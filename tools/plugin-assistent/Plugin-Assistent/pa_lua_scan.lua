-- Plugin-Assistent: simple static analysis of the Lua files of a plugin.
--
-- Finds function definitions (global and local), history IDs passed to
-- pytha.set_element_history / get_element_history and counts pyloc texts.
-- It works line by line and only recognises the usual ways of writing these
-- calls, so its results are only used for warnings and hints.

PA_SCAN = {}

local function new_result()
	return {
		globals = {},       -- [name] = { file = ..., line = ... }
		locals = {},        -- [name] = { file = ..., line = ... }
		history_set = {},   -- [id] = { file = ..., line = ... }
		history_get = {},   -- [id] = { file = ..., line = ... }
		pyloc_count = 0,
		lua_files = 0,
	}
end

-- Returns the line without a trailing comment and the positions of its string
-- literals (so that matches inside strings can be ignored).
local function analyse_line(line)
	local ranges = {}
	local i = 1
	local quote, start = nil, nil
	while i <= #line do
		local c = line:sub(i, i)
		if quote then
			if c == "\\" then
				i = i + 1
			elseif c == quote then
				ranges[#ranges + 1] = { start, i }
				quote = nil
			end
		elseif c == '"' or c == "'" then
			quote, start = c, i
		elseif line:sub(i, i + 1) == "--" then
			return line:sub(1, i - 1), ranges
		end
		i = i + 1
	end
	if quote then
		ranges[#ranges + 1] = { start, #line }
	end
	return line, ranges
end

local function inside_string(ranges, position)
	for _, range in ipairs(ranges) do
		if position > range[1] and position <= range[2] then
			return true
		end
	end
	return false
end

-- Calls fn(capture) for every match of pattern that does not start inside a string
local function each_match(code, ranges, pattern, fn)
	local init = 1
	while true do
		local first, _, capture = code:find(pattern, init)
		if not first then
			return
		end
		if not inside_string(ranges, first) then
			fn(capture)
		end
		init = first + 1
	end
end

local function record(map, name, file, line_number)
	if map[name] == nil then
		map[name] = { file = file, line = line_number }
	end
end

-- files: list of { name = "main.lua", lines = { ... } }
function PA_SCAN.scan(files)
	local result = new_result()
	for _, file in ipairs(files or {}) do
		result.lua_files = result.lua_files + 1
		local in_block_comment = false
		for line_number, raw in ipairs(file.lines or {}) do
			local line = raw
			if in_block_comment then
				local close = line:find("]]", 1, true)
				if close then
					in_block_comment = false
					line = line:sub(close + 2)
				else
					line = ""
				end
			end
			local code, ranges = analyse_line(line)
			local comment = line:sub(#code + 1)
			if comment:find("^%-%-%[=*%[") and not comment:find("]]", 1, true) then
				in_block_comment = true
			end

			local name = code:match("^%s*function%s+([%a_][%w_%.:]*)%s*%(")
			if name then
				record(result.globals, name, file.name, line_number)
			end
			name = code:match("^%s*local%s+function%s+([%a_][%w_]*)%s*%(")
			if name then
				record(result.locals, name, file.name, line_number)
			end
			name = code:match("^%s*local%s+([%a_][%w_]*)%s*=%s*function%s*%(")
			if name then
				record(result.locals, name, file.name, line_number)
			end
			name = code:match("^%s*([%a_][%w_%.]*)%s*=%s*function%s*%(")
			if name then
				record(result.globals, (name:gsub("^_G%.", "")), file.name, line_number)
			end
			name = code:match("^%s*_G%s*%[%s*[\"']([%a_][%w_]*)[\"']%s*%]%s*=")
			if name then
				record(result.globals, name, file.name, line_number)
			end

			each_match(code, ranges, "set_element_history%s*%([^,]+,[^,]+,%s*[\"']([^\"']+)[\"']", function(id)
				record(result.history_set, id, file.name, line_number)
			end)
			each_match(code, ranges, ":set_element_history%s*%([^,]+,%s*[\"']([^\"']+)[\"']", function(id)
				record(result.history_set, id, file.name, line_number)
			end)
			each_match(code, ranges, "get_element_history%s*%([^,%)]+,%s*[\"']([^\"']+)[\"']", function(id)
				record(result.history_get, id, file.name, line_number)
			end)
			each_match(code, ranges, "pyloc%s*[%(\"'%[]", function()
				result.pyloc_count = result.pyloc_count + 1
			end)
		end
	end
	return result
end
