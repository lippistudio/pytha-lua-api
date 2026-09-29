-- Plugin-Assistent: validation rules.
--
-- PA_VALIDATE.run(project) returns a list of issues:
--   { level = "error" | "warning" | "info", code = "...", where = "...", text = "...", ext_index = n }
-- Errors block saving. Warnings and infos are shown but do not block.

PA_VALIDATE = {}

local trim = function(text) return PA_MODEL.trim(text) end

local function add(issues, level, code, where, text, ext_index)
	issues[#issues + 1] = { level = level, code = code, where = where, text = text, ext_index = ext_index }
end

local function is_version(text)
	if text == "" then
		return false
	end
	for part in (text .. "."):gmatch("(.-)%.") do
		if not part:match("^%d+$") then
			return false
		end
	end
	return true
end

local function major_version(text)
	return tonumber((trim(text)):match("^(%d+)"))
end

local function extension_where(ext, index)
	local entry = trim(ext.values["entry-point"])
	if entry ~= "" then
		return string.format(pyloc "Extension %d (%s „%s“)", index, PA_SCHEMA.type_label(ext.type), entry)
	end
	return string.format(pyloc "Extension %d (%s)", index, PA_SCHEMA.type_label(ext.type))
end

local function is_help_file_generatable(name)
	local lower = name:lower()
	return not name:find("[/\\]") and (lower:match("%.html$") or lower:match("%.htm$")) ~= nil
end

-- Distinct help-file values of all extensions (also undocumented ones)
function PA_VALIDATE.help_files(project)
	local names, seen = {}, {}
	for _, ext in ipairs(project.extensions) do
		local name = trim(ext.values["help-file"])
		if name ~= "" and not seen[name:lower()] then
			seen[name:lower()] = true
			names[#names + 1] = name
		end
	end
	return names
end

function PA_VALIDATE.help_file_will_exist(project, name)
	if project.existing_files and project.existing_files[name:lower()] then
		return true
	end
	return project.options.help and is_help_file_generatable(name)
end

PA_VALIDATE.is_help_file_generatable = is_help_file_generatable

-- Header and folder ------------------------------------------------------------

local function check_header(project, issues)
	local header = project.header
	local where = pyloc "Plugin"

	local guid = trim(header.guid)
	if guid == "" then
		add(issues, "error", "guid_missing", where, pyloc "Die GUID fehlt. Mit „Neu erzeugen“ eine GUID anlegen.")
	elseif not PA_MODEL.is_guid(guid) then
		add(issues, "error", "guid_format", where,
			string.format(pyloc "Die GUID „%s“ hat nicht das Format XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (hexadezimal).", guid))
	end

	local name = trim(header.name)
	if name == "" then
		add(issues, "error", "name_missing", where, pyloc "Der Name des Plugins fehlt.")
	elseif PA_SCHEMA.PLACEHOLDER_TEXTS[name] then
		add(issues, "warning", "placeholder", where, pyloc "Der Name ist noch der Platzhalter aus der Vorlage.")
	end

	local version = trim(header.version)
	if version == "" then
		add(issues, "warning", "version_missing", where, pyloc "Keine Version angegeben. PYTHA nutzt sie, um bei mehreren installierten Versionen die neueste zu laden.")
	elseif not is_version(version) then
		add(issues, "error", "version_format", where,
			string.format(pyloc "Die Version „%s“ ist ungültig. Erlaubt sind Zahlen mit Punkten, z. B. 1.0 oder 2.1.3.", version))
	end

	local pytha_version = trim(header["pytha-version"])
	if pytha_version == "" then
		add(issues, "warning", "pytha_version_missing", where, pyloc "Keine Mindestversion von PYTHA angegeben.")
	elseif not pytha_version:match("^%d+%.%d+$") then
		add(issues, "error", "pytha_version_format", where,
			string.format(pyloc "Die Mindestversion „%s“ ist ungültig. Erwartet wird z. B. 25.0 oder 26.0.", pytha_version))
	elseif (major_version(pytha_version) or 0) < 25 then
		add(issues, "warning", "pytha_version_old", where,
			string.format(pyloc "Lua-Plugins gibt es erst ab PYTHA 25. Die Mindestversion %s ist zu alt.", pytha_version))
	end

	for _, key in ipairs({ "description", "licensing" }) do
		if PA_SCHEMA.PLACEHOLDER_TEXTS[trim(header[key])] then
			local label = PA_SCHEMA.get().header_by_key[key].label
			add(issues, "warning", "placeholder", where,
				string.format(pyloc "„%s“ enthält noch den Platzhaltertext der PYTHA-Vorlage.", label))
		end
	end
end

local function check_folder(project, issues)
	if project.mode ~= "new" then
		return
	end
	local where = pyloc "Ordner"
	local folder = project.folder_name or ""
	if trim(folder) == "" then
		add(issues, "error", "folder_missing", where, pyloc "Der Ordnername fehlt.")
		return
	end
	if folder:find("[<>:\"/\\|%?%*%c]") then
		add(issues, "error", "folder_invalid", where,
			pyloc "Der Ordnername enthält unzulässige Zeichen (< > : \" / \\ | ? * oder Steuerzeichen).")
	end
	if folder:match("[%.%s]$") or folder:match("^%s") then
		add(issues, "error", "folder_invalid", where, pyloc "Der Ordnername darf nicht mit Punkt oder Leerzeichen enden oder mit einem Leerzeichen beginnen.")
	end
	if PA_MODEL.is_reserved_file_name(folder) then
		add(issues, "error", "folder_invalid", where,
			string.format(pyloc "„%s“ ist unter Windows als Ordnername reserviert.", folder))
	end
end

-- Extensions ------------------------------------------------------------------------

local function check_field(project, ext, index, field, value, issues)
	local where = extension_where(ext, index)
	if value == "" then
		if field.required then
			add(issues, "error", "field_missing", where,
				string.format(pyloc "Pflichtfeld „%s“ (<%s>) ist leer.", field.label, field.key), index)
		end
		return
	end
	local kind = field.kind
	if kind == "identifier" then
		if PA_MODEL.is_lua_keyword(value) then
			add(issues, "error", "entry_point_invalid", where,
				string.format(pyloc "„%s“ ist ein Lua-Schlüsselwort und kann keine Einstiegsfunktion sein.", value), index)
		elseif not PA_MODEL.is_identifier(value) then
			add(issues, "error", "entry_point_invalid", where,
				string.format(pyloc "Die Einstiegsfunktion „%s“ ist kein gültiger Lua-Funktionsname (nur Buchstaben, Ziffern und _, nicht mit einer Ziffer beginnend).", value), index)
		end
	elseif kind == "attribute_id" then
		if not value:match("^[%w_%-]+$") then
			add(issues, "error", "attribute_id", where,
				string.format(pyloc "Die Attribut-ID „%s“ enthält unzulässige Zeichen. Erlaubt sind nur Buchstaben, Ziffern, _ und - (keine Leerzeichen, keine Anführungszeichen).", value), index)
		end
	elseif kind == "history_id" or kind == "id" then
		if not value:match("^[%w_%-%.]+$") then
			add(issues, "warning", "id_characters", where,
				string.format(pyloc "Die ID „%s“ enthält Leerzeichen, Anführungszeichen oder Sonderzeichen. Empfohlen sind nur Buchstaben, Ziffern, _ und -.", value), index)
		end
	elseif kind == "file_filter" then
		for pattern in (value .. ";"):gmatch("(.-);") do
			pattern = trim(pattern)
			if not pattern:match("^%*%.[%w_%-%.]+$") then
				add(issues, "error", "file_filter", where,
					string.format(pyloc "Der Dateifilter „%s“ ist ungültig. Erwartet wird z. B. *.csv, mehrere Filter mit ; getrennt.", value), index)
				break
			end
		end
	elseif kind == "enum" then
		local allowed = false
		for _, option in ipairs(field.options or {}) do
			if option == value then
				allowed = true
			end
		end
		if not allowed then
			local level = ext.type == "cam-native-macro" and "warning" or "error"
			add(issues, level, "enum_value", where,
				string.format(pyloc "„%s“ ist für „%s“ nicht zulässig. Möglich: %s.", value, field.label, table.concat(field.options or {}, ", ")), index)
		end
	elseif kind == "message" then
		local guid, topic = value:match("^([^/]+)/(.+)$")
		if not guid or not PA_MODEL.is_guid(guid) or trim(topic) == "" then
			add(issues, "error", "message_format", where,
				string.format(pyloc "Das Thema „%s“ muss die Form GUID/THEMA haben, z. B. %s/PRICE-REQUEST.", value, PA_MODEL.is_guid(project.header.guid) and project.header.guid or "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"), index)
		end
	elseif kind == "help_file" then
		if value:find("[<>:\"|%?%*%c]") or value:find("%.%.") then
			add(issues, "error", "help_file_invalid", where,
				string.format(pyloc "Der Dateiname „%s“ ist ungültig.", value), index)
		elseif not (value:lower():match("%.html?$") or value:lower():match("%.pdf$") or value:lower():match("%.txt$")) then
			add(issues, "warning", "help_file_type", where,
				string.format(pyloc "Die Hilfedatei „%s“ sollte eine .html-, .pdf- oder .txt-Datei sein.", value), index)
		end
	elseif kind == "text" then
		if PA_SCHEMA.PLACEHOLDER_TEXTS[value] then
			add(issues, "warning", "placeholder", where,
				string.format(pyloc "„%s“ enthält noch den Platzhaltertext der PYTHA-Vorlage.", field.label), index)
		end
	end
end

-- Checks one extension. `index` is its position (nil for a new extension that
-- is not yet part of the project).
function PA_VALIDATE.check_extension(project, ext, index, issues)
	issues = issues or {}
	local shown_index = index or (#project.extensions + 1)
	local where = extension_where(ext, shown_index)
	local info = PA_SCHEMA.type_info(ext.type)
	if not info then
		add(issues, "warning", "unknown_type", where,
			string.format(pyloc "Unbekannter Extension-Typ „%s“. Die Angaben werden unverändert übernommen.", tostring(ext.type)), index)
		return issues
	end

	for _, field in ipairs(info.fields) do
		check_field(project, ext, shown_index, field, trim(ext.values[field.key]), issues)
	end
	for key in pairs(ext.values) do
		if not info.field_by_key[key] then
			add(issues, "info", "field_undocumented", where,
				string.format(pyloc "Das Feld <%s> ist für diesen Typ nicht dokumentiert und wird unverändert übernommen.", key), index)
		end
	end

	local minimum = major_version(project.header["pytha-version"])
	if minimum and info.min_version > minimum then
		add(issues, "error", "version_too_low", where,
			string.format(pyloc "Diesen Extension-Typ gibt es erst ab PYTHA %d. Die Mindestversion des Plugins ist %s.",info.min_version, trim(project.header["pytha-version"])), index)
	end

	-- Duplicate IDs within the same type
	local id = trim(ext.values.id)
	if id ~= "" then
		for other_index, other in ipairs(project.extensions) do
			if other ~= ext and other_index ~= index and other.type == ext.type and trim(other.values.id) == id then
				add(issues, "error", "duplicate_id", where,
					string.format(pyloc "Die ID „%s“ wird bereits von Extension %d verwendet.", id, other_index), index)
				break
			end
		end
	end
	return issues
end

-- Help files, Lua code and other files -------------------------------------------------

local function check_files(project, issues)
	local where = pyloc "Dateien"
	for _, name in ipairs(PA_VALIDATE.help_files(project)) do
		if not PA_VALIDATE.help_file_will_exist(project, name) then
			local text
			if is_help_file_generatable(name) then
				text = string.format(pyloc "Die Hilfedatei „%s“ fehlt. „Fehlende Hilfeseite erzeugen“ aktivieren oder die Datei ergänzen.", name)
			else
				text = string.format(pyloc "Die Hilfedatei „%s“ fehlt im Plugin-Ordner.", name)
			end
			add(issues, "warning", "help_missing", where, text)
		end
	end

	if project.mode == "new" then
		if not project.options.lua then
			add(issues, "info", "no_lua", where, pyloc "Es wird keine Lua-Datei erzeugt. Die Einstiegsfunktionen müssen Sie selbst anlegen.")
		elseif project.options.template == "generator" then
			local has_function = PA_MODEL.find_extension(project, "function") ~= nil
			if not has_function then
				add(issues, "warning", "template_function", where, pyloc "Die Generator-Vorlage braucht eine Funktion-Extension. Ohne sie wird nur ein Gerüst ohne Dialog erzeugt.")
			elseif not PA_MODEL.template_history_id(project) then
				add(issues, "warning", "template_history", where, pyloc "Ohne Bearbeiten-Extension mit History-ID kann das erzeugte Teil nicht per Rechtsklick bearbeitet werden.")
			end
		end
		return
	end

	-- Opened plugins: compare with the Lua code
	local scan = project.scan
	if not scan then
		return
	end
	local code_where = pyloc "Lua-Code"
	local reported = {}
	for index, ext in ipairs(project.extensions) do
		local entry = trim(ext.values["entry-point"])
		if PA_MODEL.is_identifier(entry) and not reported[entry] then
			reported[entry] = true
			if scan.globals[entry] then
				-- fine
			elseif scan.locals[entry] then
				add(issues, "warning", "entry_local", extension_where(ext, index),
					string.format(pyloc "Die Einstiegsfunktion „%s“ ist nur als local function definiert (%s, Zeile %d). PYTHA kann sie so nicht aufrufen.", entry, scan.locals[entry].file, scan.locals[entry].line), index)
			elseif project.options.stubs then
				add(issues, "info", "entry_stub", extension_where(ext, index),
					string.format(pyloc "Die Einstiegsfunktion „%s“ fehlt im Lua-Code und wird als Gerüst in %s angelegt.", entry, PA_MODEL.stub_file_name(project)), index)
			else
				add(issues, "error", "entry_missing", extension_where(ext, index),
					string.format(pyloc "Die Einstiegsfunktion „%s“ ist in keiner Lua-Datei des Plugins definiert.", entry), index)
			end
		end
	end

	local history_extensions = {}
	for _, ext in ipairs(project.extensions) do
		if ext.type == "edit" or ext.type == "update" then
			history_extensions[trim(ext.values.id)] = true
		end
	end
	local ids = {}
	for id in pairs(scan.history_set) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if not history_extensions[id] then
			local location = scan.history_set[id]
			add(issues, "warning", "history_without_edit", code_where,
				string.format(pyloc "Der Code setzt die History „%s“ (%s, Zeile %d), aber keine Bearbeiten-Extension hat diese ID. Rechtsklick → Bearbeiten funktioniert dann nicht.", id, location.file, location.line))
		end
	end
	if scan.lua_files > 0 then
		for index, ext in ipairs(project.extensions) do
			local id = trim(ext.values.id)
			if (ext.type == "edit" or ext.type == "update") and id ~= "" and not scan.history_set[id] then
				add(issues, "warning", "history_unused", extension_where(ext, index),
					string.format(pyloc "Die History-ID „%s“ wird im Lua-Code nirgends mit pytha.set_element_history gesetzt.", id), index)
			end
		end
	end

	if project.has_comments then
		add(issues, "warning", "config_comments", where, pyloc "Die config.xml enthält Kommentare. Sie gehen beim Speichern verloren. Die bisherige Datei wird als config.xml.bak gesichert.")
	end
	if project.no_config then
		add(issues, "info", "config_created", where, pyloc "Der Ordner enthält noch keine config.xml. Sie wird beim Speichern angelegt.")
	end
	if scan.pyloc_count > 0 then
		local translations = project.xlf_files or {}
		local text = string.format(pyloc "Der Code enthält %d übersetzbare Texte (pyloc).", scan.pyloc_count)
		if #translations > 0 then
			text = text .. " " .. string.format(pyloc "Übersetzungsdateien: %s", table.concat(translations, ", "))
		else
			text = text .. " " .. pyloc "Es gibt noch keine Übersetzungsdateien (.xlf)."
		end
		add(issues, "info", "translations", code_where, text)
	end
end

-- All rules ----------------------------------------------------------------------------------

function PA_VALIDATE.run(project)
	local issues = {}
	check_header(project, issues)
	check_folder(project, issues)
	if #project.extensions == 0 then
		add(issues, "warning", "no_extensions", pyloc "Extensions", pyloc "Das Plugin hat keine Extension und bietet in PYTHA daher keine Funktion an.")
	end
	for index, ext in ipairs(project.extensions) do
		PA_VALIDATE.check_extension(project, ext, index, issues)
	end
	check_files(project, issues)
	return issues
end

function PA_VALIDATE.counts(issues)
	local counts = { error = 0, warning = 0, info = 0 }
	for _, issue in ipairs(issues) do
		counts[issue.level] = counts[issue.level] + 1
	end
	return counts
end

function PA_VALIDATE.has_errors(issues)
	return PA_VALIDATE.counts(issues).error > 0
end

function PA_VALIDATE.summary(issues)
	local counts = PA_VALIDATE.counts(issues)
	if counts.error == 0 and counts.warning == 0 then
		if counts.info == 0 then
			return pyloc "Keine Fehler oder Warnungen."
		end
		return string.format(pyloc "Keine Fehler oder Warnungen, %d Hinweis(e).", counts.info)
	end
	return string.format(pyloc "%d Fehler, %d Warnung(en), %d Hinweis(e).", counts.error, counts.warning, counts.info)
end

local LEVEL_ORDER = { error = 1, warning = 2, info = 3 }

function PA_VALIDATE.format(issues)
	local labels = { error = pyloc "FEHLER", warning = pyloc "WARNUNG", info = pyloc "HINWEIS" }
	local sorted = {}
	for index, issue in ipairs(issues) do
		sorted[#sorted + 1] = { issue = issue, index = index }
	end
	table.sort(sorted, function(a, b)
		local la, lb = LEVEL_ORDER[a.issue.level], LEVEL_ORDER[b.issue.level]
		if la ~= lb then
			return la < lb
		end
		return a.index < b.index
	end)
	local lines = {}
	for _, entry in ipairs(sorted) do
		local issue = entry.issue
		lines[#lines + 1] = string.format("%s – %s: %s", labels[issue.level], issue.where, issue.text)
	end
	return table.concat(lines, "\n")
end
