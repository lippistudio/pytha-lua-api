-- Plugin-Assistent: generates a simple help page (help.html) for a plugin.
-- The page is meant as a starting point that the author completes.

PA_HELP = {}

-- The page texts are for the users of the generated plugin, so they are not
-- translated with pyloc but chosen by the "Sprache der Hilfeseite" option.
local TEXTS = {
	de = {
		lang = "de",
		title_suffix = "Hilfe",
		version = "Version %s",
		requires = "ab PYTHA %s",
		functions = "Funktionen",
		usage = "Bedienung",
		usage_todo = "Beschreiben Sie hier Schritt für Schritt, wie das Plugin bedient wird.",
		requirements = "Voraussetzungen",
		requirements_text = "PYTHA %s oder neuer.",
		requirements_any = "Eine PYTHA-Version mit Lua-Plugins (ab Version 25).",
		kinds = {
			["function"] = "Button",
			["part-selector"] = "Teileauswahl",
			["file-import"] = "Import",
			["attribute"] = "Attribut",
		},
		no_description = "Noch keine Beschreibung.",
	},
	en = {
		lang = "en",
		title_suffix = "Help",
		version = "Version %s",
		requires = "requires PYTHA %s",
		functions = "Functions",
		usage = "Usage",
		usage_todo = "Describe step by step how the plugin is used.",
		requirements = "Requirements",
		requirements_text = "PYTHA %s or newer.",
		requirements_any = "A PYTHA version with Lua plugins (version 25 or newer).",
		kinds = {
			["function"] = "Button",
			["part-selector"] = "Part selection",
			["file-import"] = "Import",
			["attribute"] = "Attribute",
		},
		no_description = "No description yet.",
	},
}

local function escape(text)
	return PA_XML.escape_attribute(PA_MODEL.trim(text))
end

local function paragraph(text)
	return "<p>" .. escape(text):gsub("\r?\n", "<br>\n") .. "</p>"
end

-- Help files that "Speichern" creates: help-file values that end with .html/.htm
-- and do not exist yet.
function PA_HELP.files_to_generate(project)
	local result = {}
	for _, name in ipairs(PA_VALIDATE.help_files(project)) do
		local exists = project.existing_files and project.existing_files[name:lower()]
		if not exists and PA_VALIDATE.is_help_file_generatable(name) then
			result[#result + 1] = name
		end
	end
	return result
end

function PA_HELP.page(project, language)
	local t = TEXTS[language] or TEXTS.de
	local header = project.header
	local name = PA_MODEL.trim(header.name)
	local lines = {
		"<!DOCTYPE html>",
		'<html lang="' .. t.lang .. '">',
		"<head>",
		'<meta charset="utf-8">',
		"<title>" .. escape(name) .. " – " .. t.title_suffix .. "</title>",
		"<style>",
		"body { font-family: \"Segoe UI\", Arial, sans-serif; max-width: 46em; margin: 2em auto; padding: 0 1em; line-height: 1.5; color: #222; }",
		"h1 { font-size: 1.6em; margin-bottom: 0.2em; }",
		"h2 { font-size: 1.25em; margin-top: 1.6em; border-bottom: 1px solid #ccc; }",
		"h3 { font-size: 1.05em; margin-bottom: 0.2em; }",
		".meta { color: #666; margin-top: 0; }",
		".kind { color: #666; font-weight: normal; }",
		".todo { background: #fff6d5; border-left: 4px solid #e0b000; padding: 0.4em 0.8em; }",
		"</style>",
		"</head>",
		"<body>",
		"<h1>" .. escape(name) .. "</h1>",
	}
	local meta = {}
	if PA_MODEL.trim(header.version) ~= "" then
		meta[#meta + 1] = string.format(t.version, escape(header.version))
	end
	if PA_MODEL.trim(header["pytha-version"]) ~= "" then
		meta[#meta + 1] = string.format(t.requires, escape(header["pytha-version"]))
	end
	if #meta > 0 then
		lines[#lines + 1] = '<p class="meta">' .. table.concat(meta, " · ") .. "</p>"
	end
	if PA_MODEL.trim(header.description) ~= "" and not PA_SCHEMA.PLACEHOLDER_TEXTS[PA_MODEL.trim(header.description)] then
		lines[#lines + 1] = paragraph(header.description)
	end

	local sections = {}
	for _, ext in ipairs(project.extensions) do
		local kind = t.kinds[ext.type]
		local caption = PA_MODEL.trim(ext.values.caption)
		if kind and caption ~= "" then
			sections[#sections + 1] = "<h3>" .. escape(caption) .. ' <span class="kind">(' .. kind .. ")</span></h3>"
			local description = PA_MODEL.trim(ext.values.description)
			if description ~= "" and not PA_SCHEMA.PLACEHOLDER_TEXTS[description] then
				sections[#sections + 1] = paragraph(description)
			else
				sections[#sections + 1] = '<p class="todo">' .. t.no_description .. "</p>"
			end
		end
	end
	if #sections > 0 then
		lines[#lines + 1] = "<h2>" .. t.functions .. "</h2>"
		for _, line in ipairs(sections) do
			lines[#lines + 1] = line
		end
	end

	lines[#lines + 1] = "<h2>" .. t.usage .. "</h2>"
	lines[#lines + 1] = '<p class="todo">' .. t.usage_todo .. "</p>"
	lines[#lines + 1] = "<h2>" .. t.requirements .. "</h2>"
	if PA_MODEL.trim(header["pytha-version"]) ~= "" then
		lines[#lines + 1] = "<p>" .. string.format(t.requirements_text, escape(header["pytha-version"])) .. "</p>"
	else
		lines[#lines + 1] = "<p>" .. t.requirements_any .. "</p>"
	end
	lines[#lines + 1] = "</body>"
	lines[#lines + 1] = "</html>"
	return table.concat(lines, "\n") .. "\n"
end
