local tests = {}

local function new_project(env, name)
	local project = env.PA_MODEL.new_project(name or "Mein Regal")
	project.header.guid = "3f2d1456-960c-489c-abfd-0cab1cd5644c"
	return project
end

tests["save_new writes the plugin as sub-folder of the plugins folder"] = function(T)
	local env, fake = T.new_env()
	fake.fs.mkdirs("/plugins")
	fake.folder_answers[1] = "/plugins"
	local project = new_project(env)
	local ok, message = env.PA_FILES.save_new(project)
	T.ok(ok, message)
	T.eq(fake.folder_requests[1].access, "full")
	T.eq(fake.folder_requests[1].options.scope, "recursive")
	T.ok(fake.folder_requests[1].options.start_at, "dialog starts at the plugin folder")
	T.eq(fake.fs.text("/plugins/Mein Regal/config.xml"), table.concat(env.PA_XML.config_lines(project), "\n"))
	T.contains(fake.fs.text("/plugins/Mein Regal/main.lua"), "function main()")
	T.contains(fake.fs.text("/plugins/Mein Regal/help.html"), "<h1>Mein Regal</h1>")
	T.contains(message, "config.xml")
	T.contains(message, "Mein Regal")
end

tests["save_new: cancelled folder dialog writes nothing"] = function(T)
	local env, fake = T.new_env()
	local ok, message = env.PA_FILES.save_new(new_project(env))
	T.eq(ok, false)
	T.eq(message, nil)
	T.eq(fake.write_calls, nil)
end

tests["save_new: fallback when PYTHA does not create the sub-folder"] = function(T)
	local env, fake = T.new_env({ fake = { write_creates_dirs = false } })
	fake.fs.mkdirs("/plugins")
	fake.folder_answers[1] = "/plugins"
	fake.folder_answers[2] = function(access, title, options)
		T.eq(access, "full")
		T.eq(options.scope, "folder")
		T.eq(options.start_at.path, "/plugins")
		fake.fs.mkdirs("/plugins/Mein Regal")   -- the user creates the folder in the dialog
		return "/plugins/Mein Regal"
	end
	local ok, message = env.PA_FILES.save_new(new_project(env))
	T.ok(ok, message)
	T.eq(#fake.alerts, 1)
	T.contains(fake.alerts[1], "„Mein Regal“")
	T.ok(fake.fs.read("/plugins/Mein Regal/config.xml"), "config.xml written into the selected folder")
	T.ok(fake.fs.read("/plugins/Mein Regal/main.lua"))
end

tests["save_new: existing folder needs confirmation"] = function(T)
	local env, fake = T.new_env()
	fake.fs.write("/plugins/mein regal/config.xml", { "<old/>" })
	fake.folder_answers[1] = "/plugins"
	fake.scripts[1] = function(dialog)
		T.eq(dialog.title, "Ordner existiert bereits")
		return "cancel"
	end
	local ok = env.PA_FILES.save_new(new_project(env))
	T.eq(ok, false)
	T.eq(fake.fs.text("/plugins/mein regal/config.xml"), "<old/>", "nothing overwritten")

	fake.folder_answers[1] = "/plugins"
	fake.scripts[1] = function() return "ok" end
	ok = env.PA_FILES.save_new(new_project(env))
	T.ok(ok)
	T.contains(fake.fs.text("/plugins/mein regal/config.xml"), "<name>Mein Regal</name>", "existing folder name is reused")
end

tests["save_new: write errors are reported"] = function(T)
	local env, fake = T.new_env()
	fake.fs.mkdirs("/plugins")
	fake.folder_answers[1] = "/plugins"
	local calls = 0
	local write = env.pyio.write_lines
	env.pyio.write_lines = function(handle, lines, encoding)
		calls = calls + 1
		if calls == 2 then
			return false
		end
		return write(handle, lines, encoding)
	end
	local ok, message = env.PA_FILES.save_new(new_project(env))
	T.eq(ok, false)
	T.contains(message, "„main.lua“ konnte nicht geschrieben werden")
	T.contains(message, "Bereits geschrieben: config.xml")
end

tests["load_folder reads config, Lua files and translations"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local project = assert(env.PA_FILES.load_folder(fake.handle("/samples/Waveboards", "read", "folder")))
	T.eq(project.mode, "existing")
	T.eq(project.folder_name, "Waveboards")
	T.eq(project.header.name, "Waveboards")
	T.eq(project.scan.lua_files, 5)
	T.ok(project.scan.globals.main, "main found")
	T.ok(project.scan.history_set.wave_shape_history, "history found")
	T.ok(project.existing_files["help.html"])
	T.eq(#project.xlf_files, 23)
	T.ok(project.scan.pyloc_count > 50)
end

tests["load_folder without config.xml"] = function(T)
	local env, fake = T.new_env()
	fake.fs.write("/plugins/Neu/main.lua", { "function main()", "end" })
	local project = assert(env.PA_FILES.load_folder(fake.handle("/plugins/Neu", "read", "folder")))
	T.eq(project.no_config, true)
	T.eq(project.header.name, "Neu")
	T.eq(project.extensions[1].values["entry-point"], "main")
	local issues = env.PA_VALIDATE.run(project)
	T.eq(env.PA_VALIDATE.counts(issues).error, 0)
end

tests["load_folder reports invalid XML"] = function(T)
	local env, fake = T.new_env()
	fake.fs.write("/plugins/Kaputt/config.xml", { "<plugin><header>" })
	local project, err = env.PA_FILES.load_folder(fake.handle("/plugins/Kaputt", "read", "folder"))
	T.eq(project, nil)
	T.contains(err, "config.xml konnte nicht gelesen werden")
end

tests["save_existing backs up config.xml and never touches Lua files"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local original_config = fake.fs.text("/samples/Waveboards/config.xml")
	local original_lua = fake.fs.text("/samples/Waveboards/wave_main.lua")
	local project = assert(env.PA_FILES.load_folder(fake.handle("/samples/Waveboards", "read", "folder")))
	-- fix the finding: add the missing edit extension
	local edit = env.PA_MODEL.new_extension(project, "edit")
	edit.values.id = "wave_shape_history"
	edit.values["entry-point"] = "edit_block"
	env.PA_MODEL.add_extension(project, edit)
	T.eq(env.PA_VALIDATE.counts(env.PA_VALIDATE.run(project)).warning, 3, "only the placeholder warnings remain")

	fake.folder_answers[1] = "/samples/Waveboards"
	local ok, message = env.PA_FILES.save_existing(project)
	T.ok(ok, message)
	T.eq(fake.folder_requests[1].access, "full")
	T.ok(rawequal(fake.folder_requests[1].options.start_at, project.read_handle), "dialog starts at the opened folder")
	T.eq(fake.fs.text("/samples/Waveboards/config.xml.bak"), original_config)
	T.eq(fake.fs.text("/samples/Waveboards/wave_main.lua"), original_lua)
	local written = fake.fs.text("/samples/Waveboards/config.xml")
	T.contains(written, "<id>wave_shape_history</id>")
	T.contains(written, "<entry-point>edit_block</entry-point>")
	T.contains(message, "config.xml.bak")

	local reloaded = assert(env.PA_FILES.load_folder(fake.handle("/samples/Waveboards", "read", "folder")))
	local codes = {}
	for _, issue in ipairs(env.PA_VALIDATE.run(reloaded)) do
		codes[issue.code] = true
	end
	T.eq(codes.history_without_edit, nil, "finding fixed")
end

tests["save_existing: other folder needs confirmation"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local project = assert(env.PA_FILES.load_folder(fake.handle("/samples/Block", "read", "folder")))
	fake.folder_answers[1] = "/samples/Pegboard"
	fake.scripts[1] = function(dialog)
		T.eq(dialog.title, "Anderer Ordner")
		return "cancel"
	end
	local ok = env.PA_FILES.save_existing(project)
	T.eq(ok, false)
	T.eq(fake.fs.read("/samples/Pegboard/config.xml.bak"), nil)
end

return tests
