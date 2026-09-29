-- Rules of the PYTHA Lua runtime (wiki pages "Lua Runtime" and
-- "Anatomy of a Lua Api Plugin"):
--   * all *.lua files are loaded in an undefined order,
--   * the PYTHA API is not available while the files are loaded,
--   * io, require, dofile, loadfile, print, os.execute, ... are not available,
--   * global names should not start with "py".

local tests = {}

local ALLOWED_GLOBALS = {
	main = true,
}

tests["every file loads on its own without using the API"] = function(T)
	for _, name in ipairs(T.plugin_files) do
		local env = T.sandbox()
		T.load_plugin(env, { name })
	end
end

tests["only PA_* tables and main are defined as globals"] = function(T)
	local env = T.sandbox()
	local before = {}
	for key in pairs(env) do
		before[key] = true
	end
	T.load_plugin(env)
	for key, value in pairs(env) do
		if not before[key] and not ({ pytha = 1, pyui = 1, pyio = 1, pyux = 1, pyloc = 1, pymsg = 1, pyplot = 1, pygeo = 1 })[key] then
			T.ok(ALLOWED_GLOBALS[key] or (key:match("^PA_") and type(value) == "table") or key == "PA_UI",
				"unexpected global: " .. tostring(key))
			T.ok(not key:lower():match("^py"), "global must not start with py: " .. key)
		end
	end
	T.ok(type(env.main) == "function", "main is defined")
end

tests["no forbidden functions are used in the plugin files"] = function(T)
	local forbidden = { "require%s*%(", "dofile%s*%(", "loadfile%s*%(", "[^%w_%.:]print%s*%(",
		"os%.execute", "os%.exit", "os%.getenv", "os%.remove", "os%.rename", "os%.tmpname", "[^%w_]io%.", "debug%." }
	for _, name in ipairs(T.plugin_files) do
		local text = T.read_file(T.plugin_dir .. "/" .. name)
		for line_number, line in ipairs(T.split_lines(text)) do
			local code = line:gsub("%-%-.*$", "")
			for _, pattern in ipairs(forbidden) do
				T.ok(not (" " .. code):find(pattern), string.format("%s:%d uses %s", name, line_number, pattern))
			end
		end
	end
end

tests["no unit literals (plain Lua can load the files)"] = function(T)
	for _, name in ipairs(T.plugin_files) do
		local text = T.read_file(T.plugin_dir .. "/" .. name)
		for line_number, line in ipairs(T.split_lines(text)) do
			local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
			T.ok(not code:find("%f[%w]%d+%.?%d*%s*mm%f[%W]"), string.format("%s:%d contains a unit literal", name, line_number))
		end
	end
end

local function shuffled(list, seed)
	local result = {}
	for i, v in ipairs(list) do
		result[i] = v
	end
	local state = seed
	for i = #result, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = state % i + 1
		result[i], result[j] = result[j], result[i]
	end
	return result
end

tests["load order does not matter"] = function(T)
	local reversed = {}
	for i = #T.plugin_files, 1, -1 do
		reversed[#reversed + 1] = T.plugin_files[i]
	end
	for _, order in ipairs({ T.plugin_files, reversed, shuffled(T.plugin_files, 7), shuffled(T.plugin_files, 42) }) do
		local env, fake = T.new_env({ order = order })
		fake.scripts[1] = function(dialog)
			T.eq(dialog.title, "Plugin-Assistent")
		end
		env.main()
		T.eq(#fake.alerts, 0, "no error messages")
	end
end

tests["config.xml of the assistant is valid"] = function(T)
	local env, fake = T.new_env()
	fake.fs.write("/plugins/Plugin-Assistent/config.xml", T.read_lines(T.plugin_dir .. "/config.xml"))
	for _, name in ipairs(T.plugin_files) do
		fake.fs.write("/plugins/Plugin-Assistent/" .. name, T.read_lines(T.plugin_dir .. "/" .. name))
	end
	fake.fs.write("/plugins/Plugin-Assistent/help.html", T.read_lines(T.plugin_dir .. "/help.html"))
	local project = assert(env.PA_FILES.load_folder(fake.handle("/plugins/Plugin-Assistent", "read", "folder")))
	local issues = env.PA_VALIDATE.run(project)
	for _, issue in ipairs(issues) do
		T.ok(issue.level == "info", "unexpected issue: " .. issue.code .. " " .. issue.text)
	end
	T.eq(project.header["pytha-version"], "26.0")
	T.ok(project.scan.globals.main, "main is found by the scanner")
end

return tests
