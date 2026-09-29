local tests = {}

local function codes(issues, level)
	local result = {}
	for _, issue in ipairs(issues) do
		if level == nil or issue.level == level then
			result[issue.code] = (result[issue.code] or 0) + 1
		end
	end
	return result
end

local function new_project(env, name)
	local project = env.PA_MODEL.new_project(name or "Test")
	project.header.guid = "3f2d1456-960c-489c-abfd-0cab1cd5644c"
	return project
end

tests["a fresh project has no errors or warnings"] = function(T)
	local env = T.new_env()
	local issues = env.PA_VALIDATE.run(new_project(env))
	T.eq(codes(issues), {})
	T.eq(env.PA_VALIDATE.summary(issues), "Keine Fehler oder Warnungen.")
end

tests["header rules"] = function(T)
	local env = T.new_env()
	local V = env.PA_VALIDATE
	local project = new_project(env)
	project.header.guid = ""
	T.eq(codes(V.run(project)).guid_missing, 1)
	project.header.guid = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
	T.eq(codes(V.run(project)).guid_format, 1)
	project.header.guid = "3F0FFA7C-D802-4E5E-B439-0A798FEC8639"
	T.eq(codes(V.run(project)).guid_format, nil)

	project.header.version = "1.000"
	T.eq(codes(V.run(project)).version_format, nil)
	project.header.version = "1.0a"
	T.eq(codes(V.run(project), "error").version_format, 1)
	project.header.version = ""
	T.eq(codes(V.run(project), "warning").version_missing, 1)
	project.header.version = "1.0"

	project.header["pytha-version"] = "26"
	T.eq(codes(V.run(project), "error").pytha_version_format, 1)
	project.header["pytha-version"] = "24.0"
	T.eq(codes(V.run(project), "warning").pytha_version_old, 1)
	project.header["pytha-version"] = "26.0"

	project.header.name = " "
	T.eq(codes(V.run(project), "error").name_missing, 1)
	project.header.name = "Test"

	project.header.description = "The description of your plugin goes here."
	project.header.licensing = "Information about the licensing terms goes here."
	T.eq(codes(V.run(project), "warning").placeholder, 2)
end

tests["folder name rules for new plugins"] = function(T)
	local env = T.new_env()
	local V = env.PA_VALIDATE
	local project = new_project(env)
	for _, name in ipairs({ "", "a/b", "Regal?", "Regal.", " Regal", "CON", "lpt1" }) do
		project.folder_name = name
		local found = codes(V.run(project), "error")
		T.ok(found.folder_invalid or found.folder_missing, "rejected: " .. name)
	end
	project.folder_name = "Mein Regal (2)"
	T.eq(codes(V.run(project), "error"), {})
	project.mode = "existing"
	project.folder_name = "a?b"
	T.eq(codes(V.run(project), "error").folder_invalid, nil, "existing folders are not renamed")
end

tests["extension field rules"] = function(T)
	local env = T.new_env()
	local V = env.PA_VALIDATE
	local M = env.PA_MODEL
	local project = new_project(env)
	local main = project.extensions[1]

	main.values["entry-point"] = "end"
	T.eq(codes(V.run(project), "error").entry_point_invalid, 1)
	main.values["entry-point"] = "2main"
	T.eq(codes(V.run(project), "error").entry_point_invalid, 1)
	main.values["entry-point"] = "main"
	main.values.caption = ""
	T.eq(codes(V.run(project), "error").field_missing, 1)
	main.values.caption = "Test"

	local attribute = M.new_extension(project, "attribute")
	M.add_extension(project, attribute)
	attribute.values.id = '"edge_banding_l1_with_offset"'
	T.eq(codes(V.run(project), "error").attribute_id, 1)
	attribute.values.id = "edge banding"
	T.eq(codes(V.run(project), "error").attribute_id, 1)
	attribute.values.id = "edge_banding-l1"
	T.eq(codes(V.run(project), "error").attribute_id, nil)
	attribute.values["entry-point"] = ""
	T.eq(codes(V.run(project), "error"), {}, "attribute without entry point is a data store")

	local second = M.new_extension(project, "attribute")
	second.values.id = "edge_banding-l1"
	M.add_extension(project, second)
	T.eq(codes(V.run(project), "error").duplicate_id, 2)
	table.remove(project.extensions)

	local import = M.new_extension(project, "file-import")
	M.add_extension(project, import)
	import.values["file-filter"] = "csv"
	T.eq(codes(V.run(project), "error").file_filter, 1)
	import.values["file-filter"] = "*.csv; *.txt"
	T.eq(codes(V.run(project), "error").file_filter, nil)
	import.values.scope = "everything"
	T.eq(codes(V.run(project), "error").enum_value, 1)
	import.values.scope = "folder"
	project.header["pytha-version"] = "25.0"
	T.eq(codes(V.run(project), "error").version_too_low, 1)
	project.header["pytha-version"] = "26.0"

	local handler = M.new_extension(project, "message-handler")
	M.add_extension(project, handler)
	T.eq(codes(V.run(project), "error").message_format, nil)
	handler.values.message = "PRICE-REQUEST"
	T.eq(codes(V.run(project), "error").message_format, 1)

	local macro = M.new_extension(project, "cam-native-macro")
	M.add_extension(project, macro)
	T.eq(codes(V.run(project), "error").field_missing, 1, "macro name is required")
	macro.values.id = "MeinMakro"
	macro.values["cam-system"] = "other_cam"
	T.eq(codes(V.run(project), "warning").enum_value, 1, "unknown CAM systems are only a warning")

	local edit = M.new_extension(project, "edit")
	edit.values.id = "my history"
	M.add_extension(project, edit)
	T.eq(codes(V.run(project), "warning").id_characters, 1)
end

tests["help files"] = function(T)
	local env = T.new_env()
	local V = env.PA_VALIDATE
	local project = new_project(env)
	project.options.help = false
	T.eq(codes(V.run(project), "warning").help_missing, 1)
	project.options.help = true
	T.eq(codes(V.run(project), "warning").help_missing, nil)
	project.extensions[1].values["help-file"] = "manual.pdf"
	T.eq(codes(V.run(project), "warning").help_missing, 1, "PDF files cannot be generated")
	project.extensions[1].values["help-file"] = "manual.doc"
	T.eq(codes(V.run(project), "warning").help_file_type, 1)
end

tests["generator template needs an edit extension with id"] = function(T)
	local env = T.new_env()
	local project = new_project(env)
	env.PA_MODEL.set_template(project, "generator")
	T.eq(codes(env.PA_VALIDATE.run(project)), {})
	env.PA_MODEL.find_extension(project, "edit").values.id = ""
	T.eq(codes(env.PA_VALIDATE.run(project), "warning").template_history, 1)
end

tests["summary and formatted list"] = function(T)
	local env = T.new_env()
	local project = new_project(env)
	project.header.guid = "x"
	project.header.version = ""
	local issues = env.PA_VALIDATE.run(project)
	T.eq(env.PA_VALIDATE.summary(issues), "1 Fehler, 1 Warnung(en), 0 Hinweis(e).")
	local text = env.PA_VALIDATE.format(issues)
	T.ok(text:find("^FEHLER"), "errors come first")
	T.contains(text, "WARNUNG – Plugin: Keine Version angegeben.")
end

-- The 18 sample plugins as test oracle ---------------------------------------------

local function load_sample(env, fake, T, folder)
	local project, err = env.PA_FILES.load_folder(fake.handle("/samples/" .. folder, "read", "folder"))
	T.ok(project, tostring(err))
	project.options.stubs = false
	project.options.help = false
	return project
end

tests["samples: findings match the analysis of the repository"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local totals = {}
	local per_folder = {}
	for _, folder in ipairs(T.sample_folders()) do
		local project = load_sample(env, fake, T, folder)
		local issues = env.PA_VALIDATE.run(project)
		per_folder[folder] = issues
		for code, count in pairs(codes(issues)) do
			totals[code] = (totals[code] or 0) + count
		end
	end

	-- 6 attribute IDs in quotation marks (Multiple Edge Banding Attributes)
	T.eq(codes(per_folder["Multiple Edge Banding Attributes"], "error"), { attribute_id = 6 })
	-- Waveboards sets a history but has no edit extension
	T.eq(codes(per_folder["Waveboards"], "warning").history_without_edit, 1)
	T.contains(env.PA_VALIDATE.format(per_folder["Waveboards"]), "wave_shape_history")
	-- 15 plugins reference a help.html that does not exist
	T.eq(totals.help_missing, 15)
	T.eq(codes(per_folder["Waveboards"]).help_missing, nil, "Waveboards has a help.html")
	-- Kitchen Wizard contains commented-out extensions
	T.eq(codes(per_folder["Kitchen Wizard"]).config_comments, 1)
	-- No false alarms: all entry points exist, all other history IDs match
	T.eq(totals.entry_missing, nil)
	T.eq(totals.entry_local, nil)
	T.eq(totals.history_unused, nil)
	T.eq(totals.history_without_edit, 1)
	-- The only blocking errors in the samples are the attribute IDs
	local errors = 0
	for _, issues in pairs(per_folder) do
		errors = errors + env.PA_VALIDATE.counts(issues).error
	end
	T.eq(errors, 6)
end

tests["samples: a missing entry point is detected"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local project = load_sample(env, fake, T, "Block")
	project.extensions[2].values["entry-point"] = "edit_block_renamed"
	T.eq(codes(env.PA_VALIDATE.run(project), "error").entry_missing, 1)
	project.options.stubs = true
	local issues = env.PA_VALIDATE.run(project)
	T.eq(codes(issues, "error").entry_missing, nil)
	T.eq(codes(issues, "info").entry_stub, 1)
end

return tests
