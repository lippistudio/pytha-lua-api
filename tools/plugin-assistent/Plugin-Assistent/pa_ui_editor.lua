-- Plugin-Assistent: main editor dialog for new and opened plugins.

PA_UI_EDITOR = {}

local DEFAULTS_NAME = "pa_defaults"

local function load_defaults()
	local ok, values = pcall(pyio.load_values, DEFAULTS_NAME)
	if ok and type(values) == "table" then
		return values
	end
	return {}
end

local function save_defaults(project)
	pcall(pyio.save_values, DEFAULTS_NAME, PA_MODEL.defaults_from(project))
end

local function current_year()
	local ok, year = pcall(os.date, "%Y")
	if ok and year then
		return year
	end
	return ""
end

local function license_presets()
	local year = current_year()
	return {
		{ label = pyloc "Eigener Text", text = nil },
		{ label = pyloc "MIT-Lizenz", text = string.format("Copyright (c) %s. This plugin is distributed under the terms of the MIT license.", year) },
		{ label = pyloc "Alle Rechte vorbehalten", text = string.format("Copyright (c) %s. All rights reserved.", year) },
	}
end

local function template_options()
	return {
		{ value = "empty", label = pyloc "Einfaches Gerüst (Hello World)" },
		{ value = "generator", label = pyloc "Generator mit Dialog und Bearbeiten" },
	}
end

local function help_languages()
	return {
		{ value = "de", label = pyloc "Hilfeseite auf Deutsch" },
		{ value = "en", label = pyloc "Hilfeseite auf Englisch" },
	}
end

local function index_of(options, value, key)
	for index, option in ipairs(options) do
		if (key and option[key] or option) == value then
			return index
		end
	end
	return nil
end

local function labels_of(options)
	local labels = {}
	for index, option in ipairs(options) do
		labels[index] = option.label
	end
	return labels
end

-- Refresh ------------------------------------------------------------------------------

local function update_buttons(state)
	local c = state.controls
	local project = state.project
	local count = #project.extensions
	local has_selection = state.selected >= 1 and state.selected <= count
	PA_UI.enable(c.edit, has_selection)
	PA_UI.enable(c.remove, has_selection)
	PA_UI.enable(c.up, has_selection and state.selected > 1)
	PA_UI.enable(c.down, has_selection and state.selected < count)
	PA_UI.enable(c.new_guid, project.mode == "new" or not PA_MODEL.is_guid(PA_MODEL.trim(project.header.guid)))
	if c.template then
		PA_UI.enable(c.template, project.options.lua)
	end
	PA_UI.enable(c.help_language, project.options.help)
end

function PA_UI_EDITOR.refresh(state, update_list)
	local c = state.controls
	local project = state.project
	state.issues = PA_VALIDATE.run(project)
	PA_UI.set_text(c.summary, PA_VALIDATE.summary(state.issues))
	PA_UI.set_display(c.issues, PA_VALIDATE.format(state.issues))
	PA_UI.enable(c.save, not PA_VALIDATE.has_errors(state.issues))
	if update_list then
		local items = {}
		for index, ext in ipairs(project.extensions) do
			items[index] = PA_MODEL.extension_summary(ext)
		end
		if state.selected > #items then
			state.selected = #items
		end
		if state.selected < 1 and #items > 0 then
			state.selected = 1
		end
		PA_UI.fill_list(c.list, items, state.selected)
	end
	update_buttons(state)
end

-- Preview -------------------------------------------------------------------------------

local function preview_dialog(dialog, state)
	dialog:set_window_title(pyloc "Vorschau der Dateien")
	dialog:create_label(1, pyloc "Datei")
	local list = dialog:create_drop_list({ 2, 4 })
	local text = dialog:create_text_display_area({ 1, 4 }, "")
	PA_UI.min_height(text, 240)
	dialog:create_align({ 1, 4 })
	dialog:create_ok_button(4, pyloc "Schließen")
	local names = {}
	for index, file in ipairs(state.files) do
		names[index] = file.name
	end
	PA_UI.fill_list(list, names, 1)
	PA_UI.set_display(text, state.files[1] and state.files[1].text or "")
	list:set_on_change_handler(PA_UI.safe(function(_, index)
		local file = state.files[index]
		PA_UI.set_display(text, file and file.text or "")
	end))
end

function PA_UI_EDITOR.preview(project)
	pyui.run_modal_subdialog(preview_dialog, { files = PA_MODEL.output_files(project) })
end

-- Saving --------------------------------------------------------------------------------

local function save(state)
	local project = state.project
	local issues = PA_VALIDATE.run(project)
	if PA_VALIDATE.has_errors(issues) then
		pyui.alert(pyloc "Bitte zuerst die Fehler beheben (siehe „Prüfung“).")
		return
	end
	local ok, message
	if project.mode == "new" then
		ok, message = PA_FILES.save_new(project)
	else
		ok, message = PA_FILES.save_existing(project)
	end
	if ok then
		if project.mode == "new" then
			save_defaults(project)
			message = message .. "\n\n" .. pyloc "Das Plugin erscheint im Menü der Generatoren. Falls nicht, PYTHA neu starten."
		end
		state.saved = true
		pyui.alert(message)
		pyui.end_modal_ok()
	elseif message then
		pyui.alert(message)
	end
end

-- Dialog ----------------------------------------------------------------------------------

local function editor_dialog(dialog, state)
	local project = state.project
	local header = project.header
	local options = project.options
	local is_new = project.mode == "new"
	local c = {}
	state.controls = c

	if is_new then
		dialog:set_window_title(pyloc "Plugin-Assistent – neues Plugin")
	else
		dialog:set_window_title(string.format(pyloc "Plugin-Assistent – %s", project.folder_name))
	end

	-- Plugin ---------------------------------------------------------------------------
	dialog:create_group_box({ 1, 4 }, pyloc "Plugin")
	dialog:create_label(1, pyloc "Name *")
	c.name = dialog:create_text_box({ 2, 4 }, header.name)
	dialog:create_label(1, pyloc "Ordnername *")
	if is_new then
		c.folder = dialog:create_text_box({ 2, 4 }, project.folder_name)
	else
		c.folder = dialog:create_text_display({ 2, 4 }, project.folder_name)
	end
	dialog:create_label(1, pyloc "GUID *")
	c.guid = dialog:create_text_display({ 2, 3 }, header.guid)
	c.new_guid = dialog:create_button(4, pyloc "Neu erzeugen")
	dialog:create_label(1, pyloc "Version")
	c.version = dialog:create_text_box(2, header.version)
	dialog:create_label(3, pyloc "Ab PYTHA")
	c.pytha_version = dialog:create_drop_list(4)
	dialog:create_label(1, pyloc "Beschreibung")
	c.description = dialog:create_text_area({ 2, 4 }, PA_UI.display_text(header.description))
	dialog:create_label(1, pyloc "Lizenz")
	c.license = dialog:create_drop_list({ 2, 4 })
	dialog:create_empty(1)
	c.licensing = dialog:create_text_area({ 2, 4 }, PA_UI.display_text(header.licensing))
	dialog:end_group_box()

	-- Extensions -------------------------------------------------------------------------
	dialog:create_group_box({ 1, 4 }, pyloc "Extensions (Funktionen des Plugins)")
	dialog:create_label(1, pyloc "Neuer Typ")
	c.new_type = dialog:create_drop_list({ 2, 3 })
	c.add = dialog:create_button(4, pyloc "Hinzufügen …")
	c.list = dialog:create_list_box({ 1, 3 })
	c.edit = dialog:create_button(4, pyloc "Bearbeiten …")
	c.remove = dialog:create_button(4, pyloc "Entfernen")
	c.up = dialog:create_button(4, pyloc "Nach oben")
	c.down = dialog:create_button(4, pyloc "Nach unten")
	dialog:create_align({ 1, 4 })
	dialog:end_group_box()
	PA_UI.min_height(c.list, 64)

	-- Files --------------------------------------------------------------------------------
	dialog:create_group_box({ 1, 4 }, pyloc "Zusätzliche Dateien")
	if is_new then
		c.lua = dialog:create_check_box({ 1, 2 }, pyloc "Lua-Datei main.lua erzeugen")
		c.template = dialog:create_drop_list({ 3, 4 })
	else
		c.stubs = dialog:create_check_box({ 1, 4 }, pyloc "Fehlende Einstiegsfunktionen als Lua-Gerüst anlegen")
	end
	c.help = dialog:create_check_box({ 1, 2 }, pyloc "Fehlende Hilfeseite erzeugen")
	c.help_language = dialog:create_drop_list({ 3, 4 })
	dialog:end_group_box()

	-- Check ---------------------------------------------------------------------------------
	dialog:create_group_box({ 1, 4 }, pyloc "Prüfung")
	c.summary = dialog:create_text_display({ 1, 4 }, "")
	c.issues = dialog:create_text_display_area({ 1, 4 }, "")
	dialog:end_group_box()
	PA_UI.min_height(c.issues, 96)

	dialog:create_align({ 1, 4 })
	c.preview = dialog:create_button(1, pyloc "Vorschau …")
	c.save = dialog:create_button(3, pyloc "Speichern …")
	dialog:create_cancel_button(4, pyloc "Schließen")
	dialog:equalize_column_widths({ 3, 4 })

	-- Initial values -------------------------------------------------------------------
	local versions = {}
	for _, version in ipairs(PA_SCHEMA.PYTHA_VERSIONS) do
		versions[#versions + 1] = version
	end
	local current_version = PA_MODEL.trim(header["pytha-version"])
	if current_version ~= "" and not index_of(versions, current_version) then
		table.insert(versions, 1, current_version)
	end
	PA_UI.fill_list(c.pytha_version, versions, index_of(versions, current_version))

	local presets = license_presets()
	local preset_index = 1
	for index, preset in ipairs(presets) do
		if preset.text and preset.text == PA_MODEL.trim(header.licensing) then
			preset_index = index
		end
	end
	PA_UI.fill_list(c.license, labels_of(presets), preset_index)

	local types = PA_SCHEMA.get().types
	local type_labels = {}
	for index, info in ipairs(types) do
		type_labels[index] = info.title
	end
	PA_UI.fill_list(c.new_type, type_labels, state.new_type)

	local templates = template_options()
	if c.template then
		c.lua:set_control_checked(options.lua)
		PA_UI.fill_list(c.template, labels_of(templates), index_of(templates, options.template, "value") or 1)
	end
	if c.stubs then
		c.stubs:set_control_checked(options.stubs)
	end
	c.help:set_control_checked(options.help)
	local languages = help_languages()
	PA_UI.fill_list(c.help_language, labels_of(languages), index_of(languages, options.help_language, "value") or 1)

	-- Handlers -----------------------------------------------------------------------------
	c.name:set_on_change_handler(PA_UI.safe(function(text)
		local old_name = PA_MODEL.trim(header.name)
		header.name = text
		for _, ext in ipairs(project.extensions) do
			if ext.values.caption ~= nil and PA_MODEL.trim(ext.values.caption) == old_name then
				ext.values.caption = PA_MODEL.trim(text)
			end
		end
		if is_new and project.folder_name_auto then
			project.folder_name = PA_MODEL.folder_name_from(text)
			PA_UI.set_text(c.folder, project.folder_name)
		end
		PA_UI_EDITOR.refresh(state, true)
	end))

	if is_new then
		c.folder:set_on_change_handler(PA_UI.safe(function(text)
			project.folder_name = text
			project.folder_name_auto = (text == PA_MODEL.folder_name_from(header.name))
			PA_UI_EDITOR.refresh(state)
		end))
	end

	c.new_guid:set_on_click_handler(PA_UI.safe(function()
		header.guid = PA_MODEL.new_guid()
		PA_UI.set_text(c.guid, header.guid)
		PA_UI_EDITOR.refresh(state)
	end))

	c.version:set_on_change_handler(PA_UI.safe(function(text)
		header.version = text
		PA_UI_EDITOR.refresh(state)
	end))

	c.pytha_version:set_on_change_handler(PA_UI.safe(function(_, index)
		header["pytha-version"] = versions[index] or header["pytha-version"]
		PA_UI_EDITOR.refresh(state)
	end))

	c.description:set_on_change_handler(PA_UI.safe(function(text)
		header.description = PA_UI.input_text(text)
		PA_UI_EDITOR.refresh(state)
	end))

	c.license:set_on_change_handler(PA_UI.safe(function(_, index)
		local preset = presets[index]
		if preset and preset.text then
			header.licensing = preset.text
			PA_UI.set_display(c.licensing, preset.text)
		end
		PA_UI_EDITOR.refresh(state)
	end))

	c.licensing:set_on_change_handler(PA_UI.safe(function(text)
		header.licensing = PA_UI.input_text(text)
		c.license:set_control_selection(1)
		PA_UI_EDITOR.refresh(state)
	end))

	c.new_type:set_on_change_handler(PA_UI.safe(function(_, index)
		state.new_type = index
	end))

	c.add:set_on_click_handler(PA_UI.safe(function()
		local info = types[state.new_type] or types[1]
		local ext = PA_MODEL.new_extension(project, info.type)
		if PA_UI_EXTENSION.edit(project, ext, nil) then
			state.selected = PA_MODEL.add_extension(project, ext)
			PA_UI_EDITOR.refresh(state, true)
		end
	end))

	c.list:set_on_change_handler(PA_UI.safe(function(_, index)
		state.selected = index
		update_buttons(state)
	end))

	c.edit:set_on_click_handler(PA_UI.safe(function()
		local ext = project.extensions[state.selected]
		if ext and PA_UI_EXTENSION.edit(project, ext, state.selected) then
			ext.auto_added = nil
			PA_UI_EDITOR.refresh(state, true)
		end
	end))

	c.remove:set_on_click_handler(PA_UI.safe(function()
		local ext = project.extensions[state.selected]
		if not ext then
			return
		end
		local question = string.format(pyloc "Extension „%s“ entfernen?", PA_MODEL.extension_summary(ext))
		if PA_UI.confirm(pyloc "Extension entfernen", question, pyloc "Entfernen") then
			table.remove(project.extensions, state.selected)
			PA_UI_EDITOR.refresh(state, true)
		end
	end))

	local function move(delta)
		local i, j = state.selected, state.selected + delta
		local list = project.extensions
		if list[i] and list[j] then
			list[i], list[j] = list[j], list[i]
			state.selected = j
			PA_UI_EDITOR.refresh(state, true)
		end
	end
	c.up:set_on_click_handler(PA_UI.safe(function() move(-1) end))
	c.down:set_on_click_handler(PA_UI.safe(function() move(1) end))

	if c.lua then
		c.lua:set_on_click_handler(PA_UI.safe(function(checked)
			options.lua = checked and true or false
			PA_UI_EDITOR.refresh(state)
		end))
		c.template:set_on_change_handler(PA_UI.safe(function(_, index)
			local template = templates[index]
			if template then
				PA_MODEL.set_template(project, template.value)
				PA_UI_EDITOR.refresh(state, true)
			end
		end))
	end
	if c.stubs then
		c.stubs:set_on_click_handler(PA_UI.safe(function(checked)
			options.stubs = checked and true or false
			PA_UI_EDITOR.refresh(state)
		end))
	end
	c.help:set_on_click_handler(PA_UI.safe(function(checked)
		options.help = checked and true or false
		PA_UI_EDITOR.refresh(state)
	end))
	c.help_language:set_on_change_handler(PA_UI.safe(function(_, index)
		local language = languages[index]
		if language then
			options.help_language = language.value
		end
	end))

	c.preview:set_on_click_handler(PA_UI.safe(function()
		PA_UI_EDITOR.preview(project)
	end))
	c.save:set_on_click_handler(PA_UI.safe(function()
		save(state)
	end))

	PA_UI_EDITOR.refresh(state, true)
end

function PA_UI_EDITOR.run(project)
	local state = { project = project, selected = #project.extensions > 0 and 1 or 0, new_type = 1 }
	pyui.run_modal_subdialog(editor_dialog, state)
	return state
end

function PA_UI_EDITOR.run_new()
	local project = PA_MODEL.new_project(nil, load_defaults())
	return PA_UI_EDITOR.run(project)
end

function PA_UI_EDITOR.run_open()
	local project, err = PA_FILES.open_plugin()
	if not project then
		if err then
			pyui.alert(err)
		end
		return nil
	end
	return PA_UI_EDITOR.run(project)
end
