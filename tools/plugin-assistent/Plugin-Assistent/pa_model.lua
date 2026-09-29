-- Plugin-Assistent: project model, defaults and helpers.
--
-- A project describes one plugin:
--   project.mode            "new" or "existing"
--   project.folder_name     name of the plugin folder (= display name in PYTHA)
--   project.header          { guid, version, ["pytha-version"], name, description, licensing }
--   project.extensions      list of { type, values = { [xml name] = text }, order, extra, attributes }
--   project.options         { lua, template, stubs, help, help_language }
-- Projects opened from disk additionally carry scan results, the list of
-- existing files and the original config.xml lines.

PA_MODEL = {}

PA_MODEL.STUB_FILE = "plugin_assistent_stubs"

local LUA_KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
	["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true,
	["then"] = true, ["true"] = true, ["until"] = true, ["while"] = true,
}

function PA_MODEL.trim(text)
	if text == nil then
		return ""
	end
	return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function PA_MODEL.is_identifier(name)
	return type(name) == "string" and name:match("^[%a_][%w_]*$") ~= nil and not LUA_KEYWORDS[name]
end

function PA_MODEL.is_lua_keyword(name)
	return LUA_KEYWORDS[name] == true
end

function PA_MODEL.copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for k, v in pairs(value) do
		result[PA_MODEL.copy(k, seen)] = PA_MODEL.copy(v, seen)
	end
	return setmetatable(result, getmetatable(value))
end

-- GUID ------------------------------------------------------------------------

local seeded = false

local function seed_random()
	if seeded then
		return
	end
	seeded = true
	local seed = 0
	local ok, now = pcall(os.time)
	if ok and type(now) == "number" then
		seed = seed + now
	end
	local ok_clock, clock = pcall(os.clock)
	if ok_clock and type(clock) == "number" then
		seed = seed + math.floor(clock * 1000000)
	end
	local address = tostring({}):match("0x(%x+)") or tostring({}):match("(%x+)$")
	if address then
		seed = seed ~ (tonumber(address:sub(-12), 16) or 0)
	end
	math.randomseed(seed)
end

-- Random GUID (UUID version 4) in lower case, e.g. 3f2d1456-960c-489c-abfd-0cab1cd5644c
function PA_MODEL.new_guid()
	seed_random()
	return string.format("%08x-%04x-%04x-%04x-%06x%06x",
		math.random(0, 0xffffffff),
		math.random(0, 0xffff),
		0x4000 | math.random(0, 0x0fff),
		0x8000 | math.random(0, 0x3fff),
		math.random(0, 0xffffff),
		math.random(0, 0xffffff))
end

function PA_MODEL.is_guid(text)
	return type(text) == "string"
		and text:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

-- Names -------------------------------------------------------------------------

local TRANSLITERATION = {
	["ä"] = "ae", ["ö"] = "oe", ["ü"] = "ue", ["Ä"] = "ae", ["Ö"] = "oe", ["Ü"] = "ue", ["ß"] = "ss",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ó"] = "o", ["ò"] = "o",
	["ô"] = "o", ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ç"] = "c",
	["ñ"] = "n",
}

-- "Mein Türgriff 2" -> "mein_tuergriff_2"
function PA_MODEL.snake_case(text)
	text = PA_MODEL.trim(text)
	text = text:gsub("[\192-\244][\128-\191]*", function(char)
		return TRANSLITERATION[char] or "_"
	end)
	text = text:gsub("(%l)(%u)", "%1_%2"):lower()
	text = text:gsub("[^%w]+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
	if text == "" then
		text = "plugin"
	end
	if text:match("^%d") then
		text = "plugin_" .. text
	end
	if LUA_KEYWORDS[text] then
		text = text .. "_plugin"
	end
	return text
end

local RESERVED_NAMES = { CON = true, PRN = true, AUX = true, NUL = true }
for i = 1, 9 do
	RESERVED_NAMES["COM" .. i] = true
	RESERVED_NAMES["LPT" .. i] = true
end

function PA_MODEL.is_reserved_file_name(name)
	local stem = tostring(name):match("^([^%.]*)") or ""
	return RESERVED_NAMES[stem:upper()] == true
end

-- Suggestion for a Windows folder name derived from the plugin name
function PA_MODEL.folder_name_from(name)
	local folder = PA_MODEL.trim(name):gsub("[<>:\"/\\|%?%*%c]", "_")
	folder = folder:gsub("[%.%s]+$", "")
	if folder == "" then
		folder = "Neues Plugin"
	end
	if PA_MODEL.is_reserved_file_name(folder) then
		folder = folder .. "_Plugin"
	end
	return folder
end

-- Projects --------------------------------------------------------------------------

function PA_MODEL.default_options()
	return { lua = true, template = "empty", stubs = true, help = true, help_language = "de" }
end

function PA_MODEL.empty_project()
	return {
		mode = "new",
		folder_name = "",
		folder_name_auto = true,
		header = { guid = "", version = "", ["pytha-version"] = "", name = "", description = "", licensing = "" },
		header_extra = {},
		root_extra = {},
		extensions = {},
		options = PA_MODEL.default_options(),
	}
end

-- defaults: values remembered from the last session (see pyio.save_values in the editor)
function PA_MODEL.new_project(name, defaults)
	defaults = defaults or {}
	name = PA_MODEL.trim(name)
	if name == "" then
		name = pyloc "Neues Plugin"
	end
	local project = PA_MODEL.empty_project()
	project.header.guid = PA_MODEL.new_guid()
	project.header.version = "1.0"
	project.header["pytha-version"] = defaults.pytha_version or "26.0"
	project.header.name = name
	project.header.licensing = defaults.licensing or ""
	project.folder_name = PA_MODEL.folder_name_from(name)
	project.options.help_language = defaults.help_language or "de"
	if defaults.template == "generator" or defaults.template == "empty" then
		project.options.template = defaults.template
	end
	PA_MODEL.add_extension(project, PA_MODEL.new_extension(project, "function"))
	if project.options.template == "generator" then
		PA_MODEL.set_template(project, "generator")
	end
	return project
end

function PA_MODEL.find_extension(project, type_name)
	for index, ext in ipairs(project.extensions) do
		if ext.type == type_name then
			return ext, index
		end
	end
	return nil
end

function PA_MODEL.entry_point_used(project, name, except)
	for _, ext in ipairs(project.extensions) do
		if ext ~= except and ext.values["entry-point"] == name then
			return true
		end
	end
	return false
end

local function unique_entry_point(project, base)
	local name = base
	local n = 2
	while PA_MODEL.entry_point_used(project, name) do
		name = base .. "_" .. n
		n = n + 1
	end
	return name
end

local function unique_id(project, type_name, base)
	local function used(id)
		for _, ext in ipairs(project.extensions) do
			if ext.type == type_name and ext.values.id == id then
				return true
			end
		end
		return false
	end
	local id = base
	local n = 2
	while used(id) do
		id = base .. "_" .. n
		n = n + 1
	end
	return id
end

-- New extension with sensible defaults (not yet added to the project)
function PA_MODEL.new_extension(project, type_name)
	local snake = PA_MODEL.snake_case(project.header.name)
	local name = PA_MODEL.trim(project.header.name)
	local ext = { type = type_name, values = {}, order = {}, extra = {}, attributes = {} }
	local v = ext.values
	if type_name == "function" then
		v["entry-point"] = unique_entry_point(project, "main")
		v.caption = name
		v.description = ""
		v["help-file"] = "help.html"
	elseif type_name == "edit" then
		local update = PA_MODEL.find_extension(project, "update")
		v.id = update and update.values.id or unique_id(project, "edit", snake .. "_history")
		v["entry-point"] = unique_entry_point(project, "edit_" .. snake)
	elseif type_name == "update" then
		local edit = PA_MODEL.find_extension(project, "edit")
		v.id = edit and edit.values.id or unique_id(project, "update", snake .. "_history")
		v["entry-point"] = unique_entry_point(project, "update_" .. snake)
	elseif type_name == "attribute" then
		v.id = unique_id(project, "attribute", snake .. "_attribute")
		v["entry-point"] = unique_entry_point(project, "eval_" .. v.id)
		v.caption = name
		v.description = ""
	elseif type_name == "part-selector" then
		v["entry-point"] = unique_entry_point(project, "select_" .. snake)
		v.caption = name
		v.description = ""
	elseif type_name == "cam-native-macro" then
		v["entry-point"] = unique_entry_point(project, "customize_" .. snake)
		v.id = ""
		v["cam-system"] = "bsolid_cix"
	elseif type_name == "file-import" then
		v["entry-point"] = unique_entry_point(project, "import_" .. snake)
		v.id = unique_id(project, "file-import", snake .. "_import")
		v.caption = name
		v["file-filter"] = "*.csv"
		v.scope = "file"
		v["help-file"] = ""
	elseif type_name == "message-handler" then
		v.id = unique_id(project, "message-handler", snake .. "_handler")
		local guid = PA_MODEL.is_guid(project.header.guid) and project.header.guid or "GUID"
		v.message = guid .. "/" .. snake:upper()
		v["entry-point"] = unique_entry_point(project, "on_" .. snake .. "_message")
		v.caption = name
		v.description = ""
	end
	return ext
end

function PA_MODEL.add_extension(project, ext)
	project.extensions[#project.extensions + 1] = ext
	return #project.extensions
end

-- Chooses the Lua template of a new project. The generator template needs an
-- edit extension whose ID is used for pytha.set_element_history, so one is added
-- automatically (and removed again if the template is switched back unchanged).
function PA_MODEL.set_template(project, template)
	project.options.template = template
	if template == "generator" then
		if not PA_MODEL.find_extension(project, "edit") then
			local ext = PA_MODEL.new_extension(project, "edit")
			ext.auto_added = PA_MODEL.copy(ext.values)
			PA_MODEL.add_extension(project, ext)
		end
	else
		for index = #project.extensions, 1, -1 do
			local ext = project.extensions[index]
			if ext.auto_added then
				local unchanged = true
				for key, value in pairs(ext.auto_added) do
					if ext.values[key] ~= value then
						unchanged = false
					end
				end
				if unchanged then
					table.remove(project.extensions, index)
				end
			end
		end
	end
end

-- History ID used by the generator template (first edit extension with an ID)
function PA_MODEL.template_history_id(project)
	for _, ext in ipairs(project.extensions) do
		if ext.type == "edit" and PA_MODEL.trim(ext.values.id) ~= "" then
			return PA_MODEL.trim(ext.values.id)
		end
	end
	return nil
end

-- One line per extension for the list box, e.g. "Funktion · main · Treppe"
function PA_MODEL.extension_summary(ext)
	local parts = { PA_SCHEMA.type_label(ext.type) }
	local entry = PA_MODEL.trim(ext.values["entry-point"])
	if entry ~= "" then
		parts[#parts + 1] = entry
	end
	local detail = PA_MODEL.trim(ext.values.caption)
	if detail == "" then
		detail = PA_MODEL.trim(ext.values.id)
	end
	if detail ~= "" then
		parts[#parts + 1] = detail
	end
	return table.concat(parts, " · ")
end

-- Entry points of an opened plugin that are not defined in its Lua files
function PA_MODEL.missing_entry_points(project)
	local result = {}
	if not project.scan then
		return result
	end
	local seen = {}
	for _, ext in ipairs(project.extensions) do
		local entry = PA_MODEL.trim(ext.values["entry-point"])
		if PA_MODEL.is_identifier(entry) and not seen[entry]
			and not project.scan.globals[entry] and not project.scan.locals[entry] then
			seen[entry] = true
			result[#result + 1] = { entry = entry, ext = ext }
		end
	end
	return result
end

function PA_MODEL.stub_file_name(project)
	local existing = project.existing_files or {}
	local name = PA_MODEL.STUB_FILE .. ".lua"
	local n = 2
	while existing[name:lower()] do
		name = PA_MODEL.STUB_FILE .. "_" .. n .. ".lua"
		n = n + 1
	end
	return name
end

-- Files that "Speichern" writes, as a list of { name = ..., text = ... }
function PA_MODEL.output_files(project)
	local files = {}
	files[#files + 1] = { name = "config.xml", text = table.concat(PA_XML.config_lines(project), "\n") }
	if project.mode == "new" then
		if project.options.lua then
			files[#files + 1] = { name = "main.lua", text = PA_TEMPLATES.main_file(project) }
		end
	elseif project.options.stubs then
		local missing = PA_MODEL.missing_entry_points(project)
		if #missing > 0 then
			files[#files + 1] = { name = PA_MODEL.stub_file_name(project), text = PA_TEMPLATES.stubs_file(project, missing) }
		end
	end
	if project.options.help then
		for _, name in ipairs(PA_HELP.files_to_generate(project)) do
			files[#files + 1] = { name = name, text = PA_HELP.page(project, project.options.help_language) }
		end
	end
	return files
end

-- Values remembered for the next new plugin
function PA_MODEL.defaults_from(project)
	return {
		pytha_version = project.header["pytha-version"],
		licensing = project.header.licensing,
		help_language = project.options.help_language,
		template = project.options.template,
	}
end
