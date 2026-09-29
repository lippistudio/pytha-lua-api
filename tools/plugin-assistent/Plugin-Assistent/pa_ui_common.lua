-- Plugin-Assistent: small helpers shared by the dialogs.
-- All control access that might differ between PYTHA versions goes through
-- these functions, so adjustments stay in one place.

PA_UI = {}

-- Multi-line controls on Windows need \r\n line breaks
function PA_UI.display_text(text)
	return (tostring(text or ""):gsub("\r\n", "\n"):gsub("\n", "\r\n"))
end

function PA_UI.input_text(text)
	return (tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
end

function PA_UI.set_text(control, text)
	control:set_control_text(text or "")
end

function PA_UI.set_display(control, text)
	control:set_control_text(PA_UI.display_text(text))
end

function PA_UI.enable(control, enabled)
	if enabled then
		control:enable_control()
	else
		control:disable_control()
	end
end

function PA_UI.clear_items(control)
	-- clear_control_items is the current name, reset_content the older one
	local ok = pcall(function() control:clear_control_items() end)
	if not ok then
		control:reset_content()
	end
end

function PA_UI.fill_list(control, items, selection)
	PA_UI.clear_items(control)
	for _, item in ipairs(items) do
		control:insert_control_item(item)
	end
	if selection and selection >= 1 and selection <= #items then
		control:set_control_selection(selection)
	end
end

-- Larger list boxes and text areas where PYTHA supports it (V27 and newer)
function PA_UI.min_height(control, height)
	if pyui.set_control_min_height then
		pcall(pyui.set_control_min_height, control, height)
	end
end

-- Runs a handler and reports unexpected errors instead of ending the plugin
function PA_UI.safe(handler)
	return function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			pyui.alert(pyloc "Unerwarteter Fehler im Plugin-Assistenten:" .. "\n" .. tostring(err))
		end
	end
end

local function confirm_dialog(dialog, title, message, ok_text)
	dialog:set_window_title(title)
	dialog:create_text_display_area({ 1, 3 }, PA_UI.display_text(message))
	dialog:create_align({ 1, 3 })
	dialog:create_ok_button(2, ok_text)
	dialog:create_cancel_button(3)
	dialog:equalize_column_widths({ 2, 3 })
end

-- Yes/no question; returns true when the user confirms
function PA_UI.confirm(title, message, ok_text)
	return pyui.run_modal_subdialog(confirm_dialog, title, message, ok_text or pyloc "OK") == "ok"
end

local function choice_dialog(dialog, state)
	dialog:set_window_title(state.title)
	dialog:create_label(1, state.label)
	local list = dialog:create_drop_list({ 2, 3 })
	local labels = {}
	for index, option in ipairs(state.options) do
		labels[index] = option.label
	end
	PA_UI.fill_list(list, labels, state.selection)
	dialog:create_align({ 1, 3 })
	dialog:create_ok_button(2)
	dialog:create_cancel_button(3)
	dialog:equalize_column_widths({ 2, 3 })
	list:set_on_change_handler(function(text, index)
		state.selection = index
	end)
end

-- Lets the user pick one of several options; returns the chosen option or nil
function PA_UI.choose(title, label, options, selection)
	local state = { title = title, label = label, options = options, selection = selection or 1 }
	if pyui.run_modal_subdialog(choice_dialog, state) ~= "ok" then
		return nil
	end
	return options[state.selection]
end

-- Short form of a text for list entries
function PA_UI.shorten(text, length)
	text = PA_UI.input_text(text):gsub("\n", " ⏎ ")
	length = length or 70
	if utf8.len(text) and utf8.len(text) > length then
		return text:sub(1, utf8.offset(text, length + 1) - 1) .. "…"
	end
	return text
end
