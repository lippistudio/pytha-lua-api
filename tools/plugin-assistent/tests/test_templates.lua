local tests = {}

-- Runs generated plugin code in its own sandbox with the PYTHA fakes
local function run_generated(T, code, name)
	local env = T.sandbox()
	local fake = T.fake.install(env)
	local chunk, err = load(code, "=" .. (name or "main.lua"), "t", env)
	T.ok(chunk, "generated code must load: " .. tostring(err) .. "\n" .. code)
	chunk()
	return env, fake
end

tests["stubs for every extension type load and define the entry points"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Alle Typen")
	for _, type_name in ipairs(env.PA_SCHEMA.type_names()) do
		if type_name ~= "function" then
			M.add_extension(project, M.new_extension(project, type_name))
		end
	end
	local code = env.PA_TEMPLATES.main_file(project)
	local generated = run_generated(T, code)
	for _, ext in ipairs(project.extensions) do
		local entry = ext.values["entry-point"]
		T.eq(type(generated[entry]), "function", ext.type .. ": " .. entry)
	end
	T.contains(code, "function edit_alle_typen(element, selected_element)")
	T.contains(code, "function update_alle_typen(element)")
	T.contains(code, "function eval_alle_typen_attribute(element)")
	T.contains(code, "function select_alle_typen(selection)")
	T.contains(code, "function customize_alle_typen(macro)")
	T.contains(code, "function import_alle_typen(file)")
	T.contains(code, "function on_alle_typen_message(subject, value)")
end

tests["file import with folder scope receives the directory"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Import")
	local import = M.new_extension(project, "file-import")
	import.values.scope = "recursive"
	M.add_extension(project, import)
	T.contains(env.PA_TEMPLATES.main_file(project), "function import_import(file, directory)")
end

tests["stubs behave correctly"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Filter")
	M.add_extension(project, M.new_extension(project, "part-selector"))
	M.add_extension(project, M.new_extension(project, "attribute"))
	M.add_extension(project, M.new_extension(project, "message-handler"))
	local generated, fake = run_generated(T, env.PA_TEMPLATES.main_file(project))

	-- part selector removes parts without material (iterating backwards)
	local a = fake.new_element({ attributes = { ["material-name"] = "Eiche" } })
	local b = fake.new_element({ attributes = { ["material-name"] = "" } })
	local c = fake.new_element({ attributes = {} })
	local d = fake.new_element({ attributes = { ["material-name"] = "Buche" } })
	local selection = { a, b, c, d }
	generated.select_filter(selection)
	T.eq(#selection, 2)
	T.ok(selection[1] == a and selection[2] == d)

	-- attribute returns text, also for other element types
	T.eq(generated.eval_filter_attribute(a), "Eiche")
	T.eq(generated.eval_filter_attribute(fake.new_element({ type = "group" })), "")

	-- message handler returns status and value
	local ok, value = generated.on_filter_message("subject", {})
	T.eq(ok, true)
	T.eq(type(value), "table")
end

tests["generator template: dialog, geometry, history and edit"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Mein Block")
	M.set_template(project, "generator")
	local code = env.PA_TEMPLATES.main_file(project)
	T.contains(code, 'local HISTORY_ID = "mein_block_history"')
	T.not_contains(code, "} or ", "no {parse_length(...)} or ... pattern")

	local generated, fake = run_generated(T, code)
	local F = T.fake
	fake.scripts[1] = function(dialog)
		T.eq(dialog.title, "Mein Block")
		F.type_text(dialog:find_after_label("Length", "text_box"), "800")
		F.type_text(dialog:find_after_label("Width", "text_box"), "abc")    -- invalid: ignored
		F.type_text(dialog:find_after_label("Height", "text_box"), "-5")    -- invalid: ignored
		F.click(dialog:find("button", "Pick point"))
	end
	generated.main()

	local current = nil
	local created = 0
	for _, element in ipairs(fake.elements) do
		if element.kind == "block" then
			created = created + 1
			if not element.deleted then
				current = element
			end
		end
	end
	T.ok(created >= 3, "geometry is recreated on changes")
	T.ok(current, "one block remains")
	T.eq(current.size, { 800, 400, 300 })
	T.eq(current.origin, { 10, 20, 30 })
	T.eq(current.history_id, "mein_block_history")
	T.eq(fake.values.default_values, { name = "Block", length = 800, width = 400, height = 300 })

	-- edit: right click on the element
	fake.scripts[1] = function(dialog)
		T.fake.type_text(dialog:find_after_label("Height", "text_box"), "1000")
	end
	generated.edit_mein_block(current, current)
	T.ok(current.deleted, "old element replaced")
	local edited = fake.elements[#fake.elements]
	T.eq(edited.size, { 800, 400, 1000 })
	T.eq(edited.history_id, "mein_block_history")
end

tests["generator template without edit extension"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Ohne Edit")
	M.set_template(project, "generator")
	table.remove(project.extensions, 2)
	local code = env.PA_TEMPLATES.main_file(project)
	T.not_contains(code, "set_element_history")
	local generated, fake = run_generated(T, code)
	generated.main()
	T.eq(#fake.alerts, 0)
end

tests["unusual names produce valid code"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project('Regal "Deluxe"\n]] -- Test')
	M.set_template(project, "generator")
	project.extensions[1].values.caption = "Zeile 1\nZeile 2 ]]"
	local attribute = M.new_extension(project, "attribute")
	M.add_extension(project, attribute)
	local generated = run_generated(T, env.PA_TEMPLATES.main_file(project))
	T.eq(type(generated.main), "function")
end

tests["stub file for missing entry points of an opened plugin"] = function(T)
	local env, fake = T.new_env()
	T.mount_samples(fake)
	local project = assert(env.PA_FILES.load_folder(fake.handle("/samples/Block", "read", "folder")))
	project.extensions[2].values["entry-point"] = "edit_block_v2"
	local missing = env.PA_MODEL.missing_entry_points(project)
	T.eq(#missing, 1)
	T.eq(missing[1].entry, "edit_block_v2")
	local files = env.PA_MODEL.output_files(project)
	T.eq(files[2].name, "plugin_assistent_stubs.lua")
	local generated = run_generated(T, files[2].text, files[2].name)
	T.eq(type(generated.edit_block_v2), "function")
	T.eq(generated.main, nil, "existing functions are not duplicated")

	project.existing_files["plugin_assistent_stubs.lua"] = true
	T.eq(env.PA_MODEL.stub_file_name(project), "plugin_assistent_stubs_2.lua", "existing stub files are not overwritten")
end

return tests
