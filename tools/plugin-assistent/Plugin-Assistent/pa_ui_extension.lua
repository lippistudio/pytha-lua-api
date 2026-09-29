-- Plugin-Assistent: dialog for one extension. The fields are generated from PA_SCHEMA.

PA_UI_EXTENSION = {}

local function sorted_keys(map)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function refresh(state)
	local issues = PA_VALIDATE.check_extension(state.project, state.ext, state.index, {})
	if #issues == 0 then
		PA_UI.set_display(state.check, pyloc "Keine Fehler.")
	else
		PA_UI.set_display(state.check, PA_VALIDATE.format(issues))
	end
end

local function add_enum_field(dialog, state, field)
	local ext = state.ext
	local options = {}
	for _, option in ipairs(field.options or {}) do
		options[#options + 1] = option
	end
	local current = PA_MODEL.trim(ext.values[field.key])
	if current == "" then
		current = field.default or options[1] or ""
		ext.values[field.key] = current
	end
	local selection = nil
	for index, option in ipairs(options) do
		if option == current then
			selection = index
		end
	end
	if not selection then
		options[#options + 1] = current
		selection = #options
	end
	local control = dialog:create_drop_list({ 2, 4 })
	PA_UI.fill_list(control, options, selection)
	control:set_on_change_handler(PA_UI.safe(function(_, index)
		ext.values[field.key] = options[index] or ext.values[field.key]
		refresh(state)
	end))
	return control
end

local function add_text_field(dialog, state, field)
	local ext = state.ext
	local control = dialog:create_text_box({ 2, 4 }, ext.values[field.key] or "")
	control:set_on_change_handler(PA_UI.safe(function(text)
		ext.values[field.key] = text
		refresh(state)
	end))
	return control
end

local function extension_dialog(dialog, state)
	local ext = state.ext
	local info = PA_SCHEMA.type_info(ext.type)
	dialog:set_window_title(string.format(pyloc "Extension: %s", info and info.title or tostring(ext.type)))

	local doc
	if info then
		doc = info.doc .. "\n" .. pyloc "Aufruf der Einstiegsfunktion:" .. " " .. info.signature
		if info.min_version > 25 then
			doc = doc .. "\n" .. string.format(pyloc "Verfügbar ab PYTHA %d.", info.min_version)
		end
	else
		doc = pyloc "Unbekannter Extension-Typ. Die Felder werden unverändert übernommen."
	end
	dialog:create_text_display_area({ 1, 4 }, PA_UI.display_text(doc))
	dialog:create_align({ 1, 4 })

	local fields = {}
	if info then
		for _, field in ipairs(info.fields) do
			fields[#fields + 1] = field
		end
	end
	for _, key in ipairs(sorted_keys(ext.values)) do
		if not (info and info.field_by_key[key]) then
			fields[#fields + 1] = { key = key, label = "<" .. key .. ">", kind = "text",
				help = pyloc "Nicht dokumentiertes Feld, wird unverändert übernommen." }
		end
	end

	state.fields = {}
	for _, field in ipairs(fields) do
		dialog:create_label(1, field.label .. (field.required and " *" or ""))
		if field.kind == "enum" then
			state.fields[field.key] = add_enum_field(dialog, state, field)
		else
			state.fields[field.key] = add_text_field(dialog, state, field)
		end
		if field.help then
			dialog:create_label({ 2, 4 }, field.help)
		end
		dialog:create_align({ 1, 4 })
	end

	dialog:create_label(1, pyloc "Prüfung")
	state.check = dialog:create_text_display_area({ 2, 4 }, "")
	dialog:create_align({ 1, 4 })
	dialog:create_ok_button(3)
	dialog:create_cancel_button(4)
	dialog:equalize_column_widths({ 3, 4 })
	refresh(state)
end

-- Shows the dialog for `ext` (index = position in the project or nil for a new
-- extension). On OK the values are copied into `ext` and true is returned.
function PA_UI_EXTENSION.edit(project, ext, index)
	-- Only the field values are edited. Elements kept from the original
	-- config.xml (ext.extra) are XML trees and are not copied.
	local work = { type = ext.type, values = PA_MODEL.copy(ext.values) }
	local state = { project = project, ext = work, index = index }
	if pyui.run_modal_subdialog(extension_dialog, state) ~= "ok" then
		return false
	end
	for key, value in pairs(work.values) do
		ext.values[key] = PA_MODEL.trim(value)
	end
	return true
end
