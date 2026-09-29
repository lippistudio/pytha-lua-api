local tests = {}

tests["new_guid creates valid, different version 4 GUIDs"] = function(T)
	local env = T.new_env()
	local seen = {}
	for _ = 1, 50 do
		local guid = env.PA_MODEL.new_guid()
		T.ok(env.PA_MODEL.is_guid(guid), "valid format: " .. guid)
		T.eq(guid:sub(15, 15), "4", "version nibble")
		T.ok(("89ab"):find(guid:sub(20, 20), 1, true), "variant nibble")
		T.ok(not seen[guid], "unique")
		seen[guid] = true
	end
	T.ok(env.PA_MODEL.is_guid("3F0FFA7C-D802-4E5E-B439-0A798FEC8639"), "upper case is accepted")
	T.ok(not env.PA_MODEL.is_guid("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"), "placeholder is rejected")
	T.ok(not env.PA_MODEL.is_guid("{3f2d1456-960c-489c-abfd-0cab1cd5644c}"), "braces are rejected")
end

tests["snake_case and folder names"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	T.eq(M.snake_case("Mein Türgriff 2"), "mein_tuergriff_2")
	T.eq(M.snake_case("Spiral Stairs"), "spiral_stairs")
	T.eq(M.snake_case("KitchenWizard"), "kitchen_wizard")
	T.eq(M.snake_case("3D Regal"), "plugin_3d_regal")
	T.eq(M.snake_case("  "), "plugin")
	T.eq(M.snake_case("end"), "end_plugin")
	T.eq(M.folder_name_from("Treppe: gerade/gewendelt?"), "Treppe_ gerade_gewendelt_")
	T.eq(M.folder_name_from("Regal."), "Regal")
	T.eq(M.folder_name_from("con"), "con_Plugin")
	T.ok(M.is_identifier("edit_block") and not M.is_identifier("2x") and not M.is_identifier("end"))
end

tests["new project has a function extension and valid defaults"] = function(T)
	local env = T.new_env()
	local project = env.PA_MODEL.new_project("Mein Regal")
	T.eq(project.mode, "new")
	T.eq(project.folder_name, "Mein Regal")
	T.eq(project.header.version, "1.0")
	T.eq(project.header["pytha-version"], "26.0")
	T.eq(#project.extensions, 1)
	T.eq(project.extensions[1].type, "function")
	T.eq(project.extensions[1].values["entry-point"], "main")
	T.eq(project.extensions[1].values.caption, "Mein Regal")
	T.eq(env.PA_VALIDATE.counts(env.PA_VALIDATE.run(project)).error, 0, "no errors")
end

tests["defaults from the last session are used"] = function(T)
	local env = T.new_env()
	local project = env.PA_MODEL.new_project("X", { pytha_version = "25.0", licensing = "MIT", help_language = "en", template = "generator" })
	T.eq(project.header["pytha-version"], "25.0")
	T.eq(project.header.licensing, "MIT")
	T.eq(project.options.help_language, "en")
	T.eq(project.options.template, "generator")
	T.ok(env.PA_MODEL.find_extension(project, "edit"), "generator adds an edit extension")
end

tests["new extensions get unique entry points and ids"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Regal")
	M.add_extension(project, M.new_extension(project, "function"))
	T.eq(project.extensions[2].values["entry-point"], "main_2")
	local first = M.new_extension(project, "attribute")
	M.add_extension(project, first)
	local second = M.new_extension(project, "attribute")
	T.eq(first.values.id, "regal_attribute")
	T.eq(second.values.id, "regal_attribute_2")
	T.eq(second.values["entry-point"], "eval_regal_attribute_2")
	local handler = M.new_extension(project, "message-handler")
	T.eq(handler.values.message, project.header.guid .. "/REGAL")
	for _, type_name in ipairs(env.PA_SCHEMA.type_names()) do
		local ext = M.new_extension(project, type_name)
		T.ok(M.is_identifier(ext.values["entry-point"]), type_name .. " has an entry point")
	end
end

tests["generator template adds and removes the edit extension"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Block")
	M.set_template(project, "generator")
	local edit = M.find_extension(project, "edit")
	T.ok(edit, "edit extension added")
	T.eq(edit.values.id, "block_history")
	T.eq(edit.values["entry-point"], "edit_block")
	T.eq(M.template_history_id(project), "block_history")
	M.set_template(project, "empty")
	T.eq(M.find_extension(project, "edit"), nil, "unchanged automatic extension is removed")

	M.set_template(project, "generator")
	M.find_extension(project, "edit").values.id = "my_history"
	M.set_template(project, "empty")
	T.ok(M.find_extension(project, "edit"), "changed extension is kept")
end

tests["extension summary for the list"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Treppe")
	T.eq(M.extension_summary(project.extensions[1]), "Funktion · main · Treppe")
	local edit = M.new_extension(project, "edit")
	T.eq(M.extension_summary(edit), "Bearbeiten · edit_treppe · treppe_history")
end

tests["output files of a new project"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Regal")
	local names = {}
	for _, file in ipairs(M.output_files(project)) do
		names[#names + 1] = file.name
	end
	T.eq(names, { "config.xml", "main.lua", "help.html" })
	project.options.lua = false
	project.options.help = false
	T.eq(#M.output_files(project), 1)
end

return tests
