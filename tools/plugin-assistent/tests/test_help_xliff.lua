local tests = {}

local xml_parser = require("support.xml_parser")

-- help.html -----------------------------------------------------------------------------

tests["help page contains name, functions and escaped texts"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Regal <Pro> & Co")
	project.header.description = "Erste Zeile\nZweite Zeile"
	project.extensions[1].values.description = "Erzeugt ein Regal."
	local import = M.new_extension(project, "file-import")
	import.values.caption = "CSV einlesen"
	M.add_extension(project, import)
	local html = env.PA_HELP.page(project, "de")
	T.contains(html, "<title>Regal &lt;Pro&gt; &amp; Co – Hilfe</title>")
	T.contains(html, "<p>Erste Zeile<br>\nZweite Zeile</p>")
	T.contains(html, '<h3>Regal &lt;Pro&gt; &amp; Co <span class="kind">(Button)</span></h3>')
	T.contains(html, "<p>Erzeugt ein Regal.</p>")
	T.contains(html, '<h3>CSV einlesen <span class="kind">(Import)</span></h3>')
	T.contains(html, "PYTHA 26.0 oder neuer.")
	T.not_contains(html, "<Pro>")
	local english = env.PA_HELP.page(project, "en")
	T.contains(english, '<html lang="en">')
	T.contains(english, "<h2>Usage</h2>")
end

tests["only missing html help files are generated"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Hilfe")
	local import = M.new_extension(project, "file-import")
	import.values["help-file"] = "import.html"
	M.add_extension(project, import)
	local second = M.new_extension(project, "function")
	second.values["help-file"] = "manual.pdf"
	M.add_extension(project, second)
	T.eq(env.PA_HELP.files_to_generate(project), { "help.html", "import.html" })
	project.existing_files = { ["help.html"] = true }
	T.eq(env.PA_HELP.files_to_generate(project), { "import.html" })
end

-- XLIFF ---------------------------------------------------------------------------------

local function read_xliff(env, T, path)
	local result, err = env.PA_XLIFF.from_document(xml_parser.parse(T.read_file(path)))
	T.ok(result, err)
	return result
end

tests["target file names"] = function(T)
	local env = T.new_env()
	local X = env.PA_XLIFF
	T.eq(X.target_file_name("localization.base.xlf", "de-DE"), "localization.de-DE.xlf")
	T.eq(X.target_file_name("config.base.xlf", "fr-FR"), "config.fr-FR.xlf")
	T.eq(X.target_file_name("Mein Plugin.BASE.XLF", "it-IT"), "Mein Plugin.it-IT.xlf")
	T.eq(X.target_file_name("texte.xlf", "es-ES"), "texte.es-ES.xlf")
end

tests["Block sample: base and German translation are merged and written back"] = function(T)
	local env = T.new_env()
	local X = env.PA_XLIFF
	local base = read_xliff(env, T, T.samples_dir .. "/Block/localization.base.xlf")
	local german = read_xliff(env, T, T.samples_dir .. "/Block/localization.de-DE.xlf")
	T.eq(#X.units(base), 10)
	T.eq(german.trg_lang, "de-DE")

	local work, stats = X.merge(base, german)
	T.eq(stats, { total = 10, translated = 10, changed = 0, obsolete = 0 })
	local lines = X.lines(work, "en-US", "de-DE")
	T.eq(lines[2], '<xliff srcLang="en-US" version="2.0" xmlns="urn:oasis:names:tc:xliff:document:2.0" trgLang="de-DE">')
	local again = X.from_document(xml_parser.parse(table.concat(lines, "\n")))
	local targets = {}
	for _, unit in ipairs(X.units(again)) do
		targets[unit.id] = unit.target
	end
	for _, unit in ipairs(X.units(german)) do
		T.eq(targets[unit.id], unit.target, "translation of " .. unit.id)
	end
	T.eq(targets["21f4091b90960be0"], "Keine History gefunden")
end

tests["merge keeps translations, reports changed and obsolete units"] = function(T)
	local env = T.new_env()
	local X = env.PA_XLIFF
	local base = { files = { { original = "main.lua", units = {
		{ id = "1", source = "Length" },
		{ id = "2", source = "Width (new wording)" },
		{ id = "3", source = "Height" },
	} } } }
	local existing = { files = { { original = "main.lua", units = {
		{ id = "1", source = "Length", target = "Länge", state = "final" },
		{ id = "2", source = "Width", target = "Breite" },
		{ id = "9", source = "Removed", target = "Entfernt" },
	} } } }
	local work, stats = X.merge(base, existing)
	T.eq(stats, { total = 3, translated = 2, changed = 1, obsolete = 1 })
	local units = X.units(work)
	T.eq(units[1].target, "Länge")
	T.eq(units[1].state, "final")
	T.eq(units[2].changed, true)
	T.eq(units[3].target, nil)
	local text = table.concat(X.lines(work, "en-US", "de-DE"), "\n")
	T.contains(text, '<segment state="final">')
	T.contains(text, "<target>Breite</target>")
	T.not_contains(text, "Entfernt")
	T.contains(text, "      <segment>\n        <source>Height</source>\n      </segment>")
end

tests["special characters in translations"] = function(T)
	local env = T.new_env()
	local X = env.PA_XLIFF
	local work = { files = { { original = "a.lua", units = { { id = "1", source = "A & B <C>", target = "A & B <C> \"x\"" } } } } }
	local lines = X.lines(work, "en-US", "de-DE")
	local text = table.concat(lines, "\n")
	T.contains(text, "<source>A &amp; B &lt;C&gt;</source>")
	local again = X.from_document(xml_parser.parse(text))
	T.eq(X.units(again)[1].target, "A & B <C> \"x\"")
end

tests["all sample translation files can be read"] = function(T)
	local env = T.new_env()
	local count = 0
	for _, relative in ipairs(T.sample_files) do
		if relative:match("%.xlf$") then
			local result = read_xliff(env, T, T.samples_dir .. "/" .. relative)
			T.ok(#result.files >= 1, relative)
			count = count + 1
		end
	end
	T.ok(count >= 40, "found the sample translation files")
end

return tests
