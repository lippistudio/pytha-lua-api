-- Plugin-Assistent: file access through PYTHA path handles (PYTHA 26 or newer).
--
-- Plugins may only access folders that the user selects. Writing requires a
-- handle with "full" access from pyui.select_folder, which PYTHA confirms with
-- the user.

PA_FILES = {}

function PA_FILES.write_lines(handle, lines)
	local ok, result = pcall(pyio.write_lines, handle, lines, "utf8")
	if not ok then
		return false, tostring(result)
	end
	if result == false then
		return false, nil
	end
	return true
end

function PA_FILES.write_text(handle, text)
	text = tostring(text or ""):gsub("\r\n", "\n")
	if text:sub(-1) == "\n" then
		text = text:sub(1, -2)
	end
	return PA_FILES.write_lines(handle, PA_XML.split_lines(text))
end

function PA_FILES.read_lines(handle)
	local ok, result = pcall(pyio.parse_lines, handle)
	if not ok or type(result) ~= "table" then
		return nil, tostring(result)
	end
	return result
end

function PA_FILES.read_xml(handle)
	local ok, result = pcall(pyio.parse_xml, handle)
	if not ok or type(result) ~= "table" then
		return nil, tostring(result)
	end
	return result
end

function PA_FILES.list(folder, kind, pattern)
	local ok, entries = pcall(pyio.list_folder, folder, kind, pattern)
	if not ok or type(entries) ~= "table" then
		return nil, tostring(entries)
	end
	return entries
end

function PA_FILES.append(folder, relative)
	local ok, result = pcall(pyio.append_path, folder, relative)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

function PA_FILES.find_entry(entries, name)
	local lower = name:lower()
	for _, entry in ipairs(entries or {}) do
		if entry.name:lower() == lower then
			return entry
		end
	end
	return nil
end

function PA_FILES.name_of(handle)
	local ok, name = pcall(function() return handle:get_name() end)
	return ok and name or nil
end

-- Folder of the assistant itself; it lives in the plugins folder, so the folder
-- dialogs start there.
local function start_folder()
	local ok, handle = pcall(pyio.get_plugin_folder_path)
	if ok then
		return handle
	end
	return nil
end

local function folder_options(scope, start)
	local options = { scope = scope }
	if start ~= nil then
		options.start_at = start
	end
	return options
end

-- Opening a plugin ------------------------------------------------------------------

-- Reads a plugin folder. Returns project, or nil and an error message
-- (nil without message when the user cancelled).
function PA_FILES.load_folder(folder)
	local entries, err = PA_FILES.list(folder, "files")
	if not entries then
		return nil, string.format(pyloc "Der Ordner konnte nicht gelesen werden: %s", tostring(err))
	end

	local project
	local config = PA_FILES.find_entry(entries, "config.xml")
	if config then
		local handle = PA_FILES.append(folder, config.name)
		local document, read_err = PA_FILES.read_xml(handle)
		if not document then
			return nil, string.format(pyloc "Die config.xml konnte nicht gelesen werden: %s", tostring(read_err))
		end
		local parse_err
		project, parse_err = PA_CONFIG.from_document(document)
		if not project then
			return nil, parse_err
		end
		project.raw_config = PA_FILES.read_lines(handle) or {}
		for _, line in ipairs(project.raw_config) do
			if line:find("<!--", 1, true) then
				project.has_comments = true
			end
		end
	else
		project = PA_MODEL.new_project(PA_FILES.name_of(folder))
		project.mode = "existing"
		project.options.help = false
		project.no_config = true
	end

	project.folder_name = PA_FILES.name_of(folder) or ""
	project.folder_name_auto = false
	project.read_handle = folder
	project.existing_files = {}
	project.xlf_files = {}
	local lua_files = {}
	for _, entry in ipairs(entries) do
		if not entry.is_folder then
			local lower = entry.name:lower()
			project.existing_files[lower] = true
			if lower:match("%.lua$") then
				local lines = PA_FILES.read_lines(PA_FILES.append(folder, entry.name))
				lua_files[#lua_files + 1] = { name = entry.name, lines = lines or {} }
			elseif lower:match("%.xlf$") then
				project.xlf_files[#project.xlf_files + 1] = entry.name
			end
		end
	end
	project.scan = PA_SCAN.scan(lua_files)
	project.options.stubs = true
	return project
end

function PA_FILES.open_plugin()
	local folder = pyui.select_folder("read", pyloc "Ordner des Plugins wählen", folder_options("folder", start_folder()))
	if folder == nil then
		return nil
	end
	return PA_FILES.load_folder(folder)
end

-- Saving --------------------------------------------------------------------------------

-- Writes all files below `folder` (prefix is "" or "Name/").
local function write_all(folder, prefix, files, written)
	for _, file in ipairs(files) do
		local handle, err = PA_FILES.append(folder, prefix .. file.name)
		if not handle then
			return false, file.name, err
		end
		local ok, write_err = PA_FILES.write_text(handle, file.text)
		if not ok then
			return false, file.name, write_err
		end
		written[#written + 1] = file.name
	end
	return true
end

local function failure_message(name, err, written)
	local text = string.format(pyloc "Die Datei „%s“ konnte nicht geschrieben werden.", name)
	if err then
		text = text .. "\n" .. err
	end
	if #written > 0 then
		text = text .. "\n\n" .. pyloc "Bereits geschrieben:" .. " " .. table.concat(written, ", ")
	end
	return text
end

local function success_message(folder_name, written)
	return string.format(pyloc "Gespeichert im Ordner „%s“:", folder_name) .. "\n" .. table.concat(written, "\n")
end

-- Saves a new plugin as sub-folder of the folder that the user selects
-- (normally the PYTHA plugins folder). Returns ok, message.
function PA_FILES.save_new(project)
	local files = PA_MODEL.output_files(project)
	local plugins = pyui.select_folder("full",
		pyloc "Ordner „plugins“ von PYTHA wählen – das Plugin wird darin als Unterordner angelegt",
		folder_options("recursive", start_folder()))
	if plugins == nil then
		return false
	end

	local folder_name = project.folder_name
	local folders = PA_FILES.list(plugins, "folders")
	local existing = PA_FILES.find_entry(folders, folder_name)
	if existing then
		local question = string.format(pyloc "Der Ordner „%s“ existiert bereits. Gleichnamige Dateien darin werden überschrieben:", existing.name)
		local names = {}
		for _, file in ipairs(files) do
			names[#names + 1] = file.name
		end
		if not PA_UI.confirm(pyloc "Ordner existiert bereits", question .. "\n" .. table.concat(names, ", "), pyloc "Überschreiben") then
			return false
		end
		folder_name = existing.name
	end

	local written = {}
	local ok, failed_name, err = write_all(plugins, folder_name .. "/", files, written)
	if ok then
		return true, success_message(folder_name, written)
	end
	if #written > 0 then
		return false, failure_message(failed_name, err, written)
	end

	-- PYTHA did not create the sub-folder: let the user create and select it.
	pyui.alert(string.format(pyloc "Der Ordner „%s“ konnte nicht automatisch angelegt werden. Bitte legen Sie ihn im folgenden Dialog an („Neuer Ordner“) und wählen Sie ihn aus.", folder_name))
	local target = pyui.select_folder("full", string.format(pyloc "Ordner „%s“ anlegen und auswählen", folder_name), folder_options("folder", plugins))
	if target == nil then
		return false
	end
	written = {}
	ok, failed_name, err = write_all(target, "", files, written)
	if not ok then
		return false, failure_message(failed_name, err, written)
	end
	return true, success_message(PA_FILES.name_of(target) or folder_name, written)
end

-- Saves an opened plugin into its folder. The previous config.xml is kept as
-- config.xml.bak. Lua files of the plugin are never changed.
function PA_FILES.save_existing(project)
	local files = PA_MODEL.output_files(project)
	local folder = pyui.select_folder("full",
		string.format(pyloc "Schreibzugriff auf den Ordner „%s“ bestätigen", project.folder_name),
		folder_options("folder", project.read_handle))
	if folder == nil then
		return false
	end
	local chosen = PA_FILES.name_of(folder)
	if chosen and chosen:lower() ~= (project.folder_name or ""):lower() then
		local question = string.format(pyloc "Sie haben den Ordner „%s“ gewählt, geöffnet war „%s“. Trotzdem in „%s“ speichern?", chosen, project.folder_name, chosen)
		if not PA_UI.confirm(pyloc "Anderer Ordner", question, pyloc "Speichern") then
			return false
		end
	end

	local written = {}
	if project.raw_config and #project.raw_config > 0 then
		local backup = PA_FILES.append(folder, "config.xml.bak")
		local ok, err = false, nil
		if backup then
			ok, err = PA_FILES.write_lines(backup, project.raw_config)
		end
		if not ok then
			return false, failure_message("config.xml.bak", err, written)
		end
		written[#written + 1] = "config.xml.bak"
	end
	local ok, failed_name, err = write_all(folder, "", files, written)
	if not ok then
		return false, failure_message(failed_name, err, written)
	end
	return true, success_message(chosen or project.folder_name, written)
end
