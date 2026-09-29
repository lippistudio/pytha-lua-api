-- Test support only: assertions, sandboxed environments and sample access.

local fake_pytha = require("support.fake_pytha")

local M = {}

M.plugin_files = {
	"pa_config_reader.lua",
	"pa_files.lua",
	"pa_help.lua",
	"pa_lua_scan.lua",
	"pa_main.lua",
	"pa_model.lua",
	"pa_schema.lua",
	"pa_templates.lua",
	"pa_ui_common.lua",
	"pa_ui_editor.lua",
	"pa_ui_extension.lua",
	"pa_ui_translation.lua",
	"pa_validate.lua",
	"pa_xliff.lua",
	"pa_xml.lua",
}

function M.setup(tests_dir, samples_dir, sample_list)
	M.tests_dir = tests_dir
	M.plugin_dir = tests_dir .. "/../Plugin-Assistent"
	M.samples_dir = samples_dir
	M.sample_files = {}
	for _, path in ipairs(sample_list or {}) do
		M.sample_files[#M.sample_files + 1] = path
	end
end

-- Files ----------------------------------------------------------------------

function M.read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("a")
	file:close()
	return content
end

function M.split_lines(text)
	if text:sub(1, 3) == "\239\187\191" then
		text = text:sub(4)
	end
	text = text:gsub("\r\n", "\n")
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

function M.read_lines(path)
	local content = M.read_file(path)
	return content and M.split_lines(content) or nil
end

-- Copies all text files of samples/ into the fake file system below `target`.
function M.mount_samples(fake, target)
	target = target or "/samples"
	fake.fs.mkdirs(target)
	for _, relative in ipairs(M.sample_files) do
		local lines = M.read_lines(M.samples_dir .. "/" .. relative)
		if lines then
			fake.fs.write(target .. "/" .. relative, lines)
		end
	end
end

function M.sample_folders()
	local seen, result = {}, {}
	for _, relative in ipairs(M.sample_files) do
		local folder = relative:match("^([^/]+)/config%.xml$")
		if folder and not seen[folder] then
			seen[folder] = true
			result[#result + 1] = folder
		end
	end
	table.sort(result)
	return result
end

-- Sandboxed environment like the PYTHA Lua runtime ---------------------------

local SAFE_GLOBALS = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring",
	"type", "xpcall", "setmetatable", "getmetatable", "rawequal", "rawget", "rawset", "rawlen",
	"load", "_VERSION",
}

local function copy_library(library)
	local result = {}
	for k, v in pairs(library) do
		result[k] = v
	end
	return result
end

function M.sandbox()
	local env = {}
	for _, name in ipairs(SAFE_GLOBALS) do
		env[name] = _G[name]
	end
	env.string = copy_library(string)
	env.table = copy_library(table)
	env.math = copy_library(math)
	env.utf8 = copy_library(utf8)
	env.os = { time = os.time, clock = os.clock, date = os.date, difftime = os.difftime }
	env._G = env
	return env
end

local API_NAMES = { "pytha", "pyui", "pyio", "pyux", "pymsg", "pyplot", "pygeo" }

-- Loads the plugin files into a fresh sandbox. While the files are loaded, any
-- access to the PYTHA API raises an error (PYTHA does not provide the API at
-- file scope). Afterwards the fakes are installed.
function M.load_plugin(env, order)
	for _, name in ipairs(API_NAMES) do
		env[name] = setmetatable({}, { __index = function(_, key)
			error("PYTHA API used at file scope: " .. name .. "." .. tostring(key), 2)
		end })
	end
	env.pyloc = function()
		error("pyloc used at file scope", 2)
	end
	for _, name in ipairs(order or M.plugin_files) do
		local chunk, err = loadfile(M.plugin_dir .. "/" .. name, "t", env)
		if not chunk then
			error(err, 0)
		end
		chunk()
	end
end

function M.new_env(options)
	options = options or {}
	local env = M.sandbox()
	M.load_plugin(env, options.order)
	for _, name in ipairs(API_NAMES) do
		env[name] = nil
	end
	local fake = fake_pytha.install(env, options.fake)
	return env, fake
end

M.fake = fake_pytha

-- Runs the plugin's main() and fails if a dialog script failed or the plugin
-- reported an unexpected error.
function M.main(env, fake)
	local ok, err = pcall(env.main)
	if #fake.script_errors > 0 then
		error(fake.script_errors[1], 0)
	end
	if not ok then
		error(err, 0)
	end
	for _, alert in ipairs(fake.alerts) do
		if alert:find("Unerwarteter Fehler", 1, true) then
			error("plugin reported an error: " .. alert, 0)
		end
	end
end

-- Assertions -------------------------------------------------------------------

function M.serialize(value, indent, seen)
	indent = indent or ""
	seen = seen or {}
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	elseif seen[value] then
		return "<cycle>"
	end
	seen[value] = true
	local keys = {}
	for k in pairs(value) do
		if k ~= "parent" then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end
		return type(a) < type(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = indent .. "  [" .. M.serialize(k) .. "] = " .. M.serialize(value[k], indent .. "  ", seen)
	end
	seen[value] = nil
	if #parts == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function deep_equal(a, b, seen)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" or rawequal(a, b) then
		return a == b
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not deep_equal(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

M.deep_equal = deep_equal

function M.eq(actual, expected, message)
	if not deep_equal(actual, expected) then
		error((message and (message .. "\n") or "") .. "expected: " .. M.serialize(expected) .. "\nactual:   " .. M.serialize(actual), 2)
	end
end

function M.ok(value, message)
	if not value then
		error(message or "expected a true value", 2)
	end
	return value
end

function M.contains(haystack, needle, message)
	if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
		error((message and (message .. "\n") or "") .. "expected to find " .. string.format("%q", needle) .. " in:\n" .. tostring(haystack), 2)
	end
end

function M.not_contains(haystack, needle, message)
	if type(haystack) == "string" and haystack:find(needle, 1, true) then
		error((message and (message .. "\n") or "") .. "did not expect to find " .. string.format("%q", needle) .. " in:\n" .. haystack, 2)
	end
end

function M.raises(fn, message)
	local ok = pcall(fn)
	if ok then
		error(message or "expected an error", 2)
	end
end

return M
