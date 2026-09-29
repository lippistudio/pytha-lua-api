-- Plugin-Assistent: reading, merging and writing XLIFF 2.0 translation files.
--
-- PYTHA creates the base files itself (localization.base.xlf for the pyloc
-- texts, config.base.xlf for config.xml). The unit IDs are hashes calculated by
-- PYTHA, so the assistant always takes them from the base file.

PA_XLIFF = {}

PA_XLIFF.NAMESPACE = "urn:oasis:names:tc:xliff:document:2.0"

-- Language codes as used by the translation files of the samples
function PA_XLIFF.languages()
	return {
		{ code = "de-DE", label = pyloc "Deutsch" },
		{ code = "en-US", label = pyloc "Englisch" },
		{ code = "fr-FR", label = pyloc "Französisch" },
		{ code = "it-IT", label = pyloc "Italienisch" },
		{ code = "es-ES", label = pyloc "Spanisch" },
		{ code = "nl-NL", label = pyloc "Niederländisch" },
		{ code = "pl-PL", label = pyloc "Polnisch" },
		{ code = "pt-PT", label = pyloc "Portugiesisch" },
		{ code = "ro-RO", label = pyloc "Rumänisch" },
		{ code = "bg-BG", label = pyloc "Bulgarisch" },
		{ code = "el-EL", label = pyloc "Griechisch" },
		{ code = "sq-AL", label = pyloc "Albanisch" },
		{ code = "ar-SA", label = pyloc "Arabisch" },
		{ code = "he", label = pyloc "Hebräisch" },
		{ code = "am-ET", label = pyloc "Amharisch" },
		{ code = "zh-CN", label = pyloc "Chinesisch (vereinfacht)" },
		{ code = "zh-TW", label = pyloc "Chinesisch (traditionell)" },
		{ code = "ja-JP", label = pyloc "Japanisch" },
		{ code = "ko-KR", label = pyloc "Koreanisch" },
		{ code = "th-TH", label = pyloc "Thailändisch" },
		{ code = "vi-VN", label = pyloc "Vietnamesisch" },
		{ code = "id-ID", label = pyloc "Indonesisch" },
	}
end

-- localization.base.xlf -> localization.de-DE.xlf
function PA_XLIFF.target_file_name(base_name, language)
	local stem = base_name:match("^(.*)%.[Bb][Aa][Ss][Ee]%.[Xx][Ll][Ff]$")
		or base_name:match("^(.*)%.[Xx][Ll][Ff]$")
		or base_name
	return stem .. "." .. language .. ".xlf"
end

local function collect_units(element, units)
	for _, child in ipairs(PA_XML.child_elements(element)) do
		if child.local_name == "unit" then
			local unit = { id = PA_XML.attribute(child, "id") or "" }
			local segment = PA_XML.child_elements(child, "segment")[1]
			if segment then
				unit.state = PA_XML.attribute(segment, "state")
				local source = PA_XML.child_elements(segment, "source")[1]
				local target = PA_XML.child_elements(segment, "target")[1]
				unit.source = source and PA_XML.text(source) or ""
				if target then
					unit.target = PA_XML.text(target)
				end
			else
				unit.source = ""
			end
			units[#units + 1] = unit
		elseif child.local_name == "group" then
			collect_units(child, units)
		end
	end
end

-- Returns { src_lang, trg_lang, files = { { original, units = { { id, source, target, state } } } } }
-- or nil, error message
function PA_XLIFF.from_document(document)
	local root = document and (document.root or document)
	if not PA_XML.is_element(root) or root.local_name ~= "xliff" then
		return nil, pyloc "Die Datei ist keine XLIFF-Datei (Wurzelelement <xliff> fehlt)."
	end
	local result = {
		src_lang = PA_XML.attribute(root, "srcLang"),
		trg_lang = PA_XML.attribute(root, "trgLang"),
		files = {},
	}
	for _, file in ipairs(PA_XML.child_elements(root, "file")) do
		local entry = { original = PA_XML.attribute(file, "original") or "", units = {} }
		collect_units(file, entry.units)
		result.files[#result.files + 1] = entry
	end
	return result
end

-- Combines the base file with an existing translation (may be nil).
-- Returns the working copy and statistics.
function PA_XLIFF.merge(base, existing)
	local previous = {}
	if existing then
		for _, file in ipairs(existing.files) do
			for _, unit in ipairs(file.units) do
				previous[unit.id] = unit
			end
		end
	end
	local work = { files = {} }
	local used = {}
	for _, file in ipairs(base.files) do
		local entry = { original = file.original, units = {} }
		for _, unit in ipairs(file.units) do
			local item = { id = unit.id, source = unit.source }
			local old = previous[unit.id]
			if old and old.target ~= nil and old.target ~= "" then
				item.target = old.target
				item.state = old.state
				if old.source ~= nil and old.source ~= unit.source then
					item.changed = true
				end
			elseif unit.target ~= nil and unit.target ~= "" then
				item.target = unit.target
				item.state = unit.state
			end
			used[unit.id] = true
			entry.units[#entry.units + 1] = item
		end
		work.files[#work.files + 1] = entry
	end
	local obsolete = 0
	for id, unit in pairs(previous) do
		if not used[id] and unit.target ~= nil and unit.target ~= "" then
			obsolete = obsolete + 1
		end
	end
	work.obsolete = obsolete
	return work, PA_XLIFF.stats(work)
end

function PA_XLIFF.units(work)
	local result = {}
	for _, file in ipairs(work.files) do
		for _, unit in ipairs(file.units) do
			result[#result + 1] = unit
		end
	end
	return result
end

function PA_XLIFF.stats(work)
	local stats = { total = 0, translated = 0, changed = 0, obsolete = work.obsolete or 0 }
	for _, unit in ipairs(PA_XLIFF.units(work)) do
		stats.total = stats.total + 1
		if unit.target ~= nil and unit.target ~= "" then
			stats.translated = stats.translated + 1
		end
		if unit.changed then
			stats.changed = stats.changed + 1
		end
	end
	return stats
end

-- The translation file in the layout of the sample files
function PA_XLIFF.lines(work, src_lang, trg_lang)
	local lines = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		string.format('<xliff srcLang="%s" version="2.0" xmlns="%s" trgLang="%s">',
			PA_XML.escape_attribute(src_lang), PA_XLIFF.NAMESPACE, PA_XML.escape_attribute(trg_lang)),
	}
	local function add_element(indent, name, text)
		local text_lines = PA_XML.split_lines(PA_XML.escape_text(text))
		if #text_lines == 1 then
			lines[#lines + 1] = string.format("%s<%s>%s</%s>", indent, name, text_lines[1], name)
		else
			lines[#lines + 1] = string.format("%s<%s>%s", indent, name, text_lines[1])
			for i = 2, #text_lines - 1 do
				lines[#lines + 1] = text_lines[i]
			end
			lines[#lines + 1] = string.format("%s</%s>", text_lines[#text_lines], name)
		end
	end
	for _, file in ipairs(work.files) do
		if #file.units > 0 then
			lines[#lines + 1] = string.format('  <file original="%s">', PA_XML.escape_attribute(file.original))
			for _, unit in ipairs(file.units) do
				lines[#lines + 1] = string.format('    <unit id="%s">', PA_XML.escape_attribute(unit.id))
				local translated = unit.target ~= nil and unit.target ~= ""
				if translated then
					lines[#lines + 1] = string.format('      <segment state="%s">', PA_XML.escape_attribute(unit.state or "translated"))
				else
					lines[#lines + 1] = "      <segment>"
				end
				add_element("        ", "source", unit.source or "")
				if translated then
					add_element("        ", "target", unit.target)
				end
				lines[#lines + 1] = "      </segment>"
				lines[#lines + 1] = "    </unit>"
			end
			lines[#lines + 1] = "  </file>"
		end
	end
	lines[#lines + 1] = "</xliff>"
	return lines
end
