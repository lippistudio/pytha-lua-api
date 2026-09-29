-- Plugin-Assistent: creates, checks and translates PYTHA plugins.
-- Entry point of the function extension (see config.xml). Requires PYTHA 26.

local function start_dialog(dialog, state)
	dialog:set_window_title(pyloc "Plugin-Assistent")
	dialog:create_label({ 1, 3 }, pyloc "Was möchten Sie tun?")
	local create = dialog:create_button({ 1, 3 }, pyloc "Neues Plugin erstellen …")
	local open = dialog:create_button({ 1, 3 }, pyloc "Bestehendes Plugin öffnen und prüfen …")
	local translate = dialog:create_button({ 1, 3 }, pyloc "Übersetzung bearbeiten (.xlf) …")
	dialog:create_align({ 1, 3 })
	dialog:create_ok_button(3, pyloc "Schließen")

	create:set_on_click_handler(PA_UI.safe(function()
		state.last = PA_UI_EDITOR.run_new()
	end))
	open:set_on_click_handler(PA_UI.safe(function()
		state.last = PA_UI_EDITOR.run_open()
	end))
	translate:set_on_click_handler(PA_UI.safe(function()
		state.last = PA_UI_TRANSLATION.run()
	end))
end

function main()
	local state = {}
	pyui.run_modal_dialog(start_dialog, state)
	return state
end
