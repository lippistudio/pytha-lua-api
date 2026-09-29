-- Plugin-Assistent: translation editor for XLIFF files.
--
-- Starts from a base file created by PYTHA (e.g. localization.base.xlf) and
-- writes <name>.<language>.xlf into the same folder. Existing translations in
-- that file are kept.

PA_UI_TRANSLATION = {}

local function is_translated(unit)
	return unit.target ~= nil and unit.target ~= ""
end

local function item_text(unit)
	local marker = "[ ]"
	if unit.changed then
		marker = "[?]"
	elseif is_translated(unit) then
		marker = "[x]"
	end
	return marker .. " " .. PA_UI.shorten(unit.source, 70)
end

local function list_items(state)
	local items = {}
	for index, unit in ipairs(state.units) do
		items[index] = item_text(unit)
	end
	return items
end

local function update_status(state)
	local stats = PA_XLIFF.stats(state.work)
	local text = string.format(pyloc "%d von %d Texten übersetzt · Zieldatei: %s", stats.translated, stats.total, state.target_name)
	if not state.target_exists then
		text = text .. " " .. pyloc "(neu)"
	end
	if stats.changed > 0 then
		text = text .. " · " .. string.format(pyloc "%d geänderte Quelltexte prüfen [?]", stats.changed)
	end
	if stats.obsolete > 0 then
		text = text .. " · " .. string.format(pyloc "%d veraltete Übersetzungen entfallen", stats.obsolete)
	end
	if state.dirty then
		text = text .. " · " .. pyloc "nicht gespeichert"
	end
	PA_UI.set_text(state.controls.status, text)
end

local function show_current(state)
	local c = state.controls
	local unit = state.units[state.current]
	PA_UI.set_display(c.source, unit and unit.source or "")
	PA_UI.set_display(c.target, unit and unit.target or "")
	PA_UI.enable(c.target, unit ~= nil)
	update_status(state)
end

local function refresh_list(state)
	PA_UI.fill_list(state.controls.list, list_items(state), state.current)
end

local function next_open(state)
	local count = #state.units
	for step = 1, count do
		local index = (state.current - 1 + step) % count + 1
		local unit = state.units[index]
		if not is_translated(unit) or unit.changed then
			return index
		end
	end
	return nil
end

local function save(state)
	local handle, err = PA_FILES.append(state.folder, state.target_name)
	local ok = false
	if handle then
		ok, err = PA_FILES.write_lines(handle, PA_XLIFF.lines(state.work, state.src_lang, state.trg_lang))
	end
	if ok then
		state.dirty = false
		state.target_exists = true
		state.saved = true
		update_status(state)
		pyui.alert(string.format(pyloc "Die Übersetzung wurde als „%s“ gespeichert.", state.target_name))
	else
		pyui.alert(string.format(pyloc "Die Datei „%s“ konnte nicht geschrieben werden.", state.target_name) .. (err and ("\n" .. err) or ""))
	end
end

local function translation_dialog(dialog, state)
	local c = {}
	state.controls = c
	dialog:set_window_title(string.format(pyloc "Übersetzung: %s → %s", state.base_name, state.target_name))
	c.status = dialog:create_text_display({ 1, 4 }, "")
	c.list = dialog:create_list_box({ 1, 3 })
	c.next = dialog:create_button(4, pyloc "Nächster offener Text")
	c.copy = dialog:create_button(4, pyloc "Quelltext übernehmen")
	c.clear = dialog:create_button(4, pyloc "Übersetzung löschen")
	dialog:create_align({ 1, 4 })
	dialog:create_label(1, pyloc "Quelltext")
	c.source = dialog:create_text_display_area({ 2, 4 }, "")
	dialog:create_label(1, pyloc "Übersetzung")
	c.target = dialog:create_text_area({ 2, 4 }, "")
	dialog:create_align({ 1, 4 })
	c.save = dialog:create_button(3, pyloc "Speichern")
	dialog:create_cancel_button(4, pyloc "Schließen")
	dialog:equalize_column_widths({ 3, 4 })
	PA_UI.min_height(c.list, 120)

	local function set_target(text)
		local unit = state.units[state.current]
		if not unit then
			return
		end
		local was = item_text(unit)
		text = PA_UI.input_text(text)
		if text == "" then
			unit.target = nil
			unit.state = nil
		else
			unit.target = text
			unit.state = unit.state or "translated"
		end
		unit.changed = nil
		state.dirty = true
		if item_text(unit) ~= was then
			refresh_list(state)
		end
		update_status(state)
	end

	c.list:set_on_change_handler(PA_UI.safe(function(_, index)
		state.current = index
		show_current(state)
	end))
	c.target:set_on_change_handler(PA_UI.safe(set_target))
	c.next:set_on_click_handler(PA_UI.safe(function()
		local index = next_open(state)
		if index then
			state.current = index
			state.controls.list:set_control_selection(index)
			show_current(state)
		else
			pyui.alert(pyloc "Alle Texte sind übersetzt.")
		end
	end))
	c.copy:set_on_click_handler(PA_UI.safe(function()
		local unit = state.units[state.current]
		if unit then
			set_target(unit.source)
			show_current(state)
		end
	end))
	c.clear:set_on_click_handler(PA_UI.safe(function()
		set_target("")
		show_current(state)
	end))
	c.save:set_on_click_handler(PA_UI.safe(function()
		save(state)
	end))

	refresh_list(state)
	show_current(state)
end

local function language_dialog(dialog, state)
	dialog:set_window_title(pyloc "Sprachen der Übersetzung")
	local labels = {}
	for index, language in ipairs(state.languages) do
		labels[index] = string.format("%s (%s)", language.label, language.code)
	end
	dialog:create_label(1, pyloc "Sprache der Quelltexte")
	local source = dialog:create_drop_list({ 2, 3 })
	dialog:create_label(1, pyloc "Zielsprache")
	local target = dialog:create_drop_list({ 2, 3 })
	dialog:create_align({ 1, 3 })
	dialog:create_ok_button(2)
	dialog:create_cancel_button(3)
	dialog:equalize_column_widths({ 2, 3 })
	PA_UI.fill_list(source, labels, state.source)
	PA_UI.fill_list(target, labels, state.target)
	source:set_on_change_handler(function(_, index) state.source = index end)
	target:set_on_change_handler(function(_, index) state.target = index end)
end

local function language_index(languages, code)
	for index, language in ipairs(languages) do
		if language.code == code then
			return index
		end
	end
	return 1
end

function PA_UI_TRANSLATION.run()
	local files, folder = pyui.select_open_file(
		{ { name = pyloc "XLIFF-Basisdatei", filter = "*.base.xlf" }, { name = pyloc "XLIFF-Datei", filter = "*.xlf" } },
		pyloc "Basisdatei der Übersetzung wählen (z. B. localization.base.xlf)",
		{ scope = "folder", access = "full" })
	if files == nil or files[1] == nil or folder == nil then
		return nil
	end
	local base_handle = files[1]
	local base_name = PA_FILES.name_of(base_handle) or "localization.base.xlf"
	local document, err = PA_FILES.read_xml(base_handle)
	if not document then
		pyui.alert(string.format(pyloc "Die Datei „%s“ konnte nicht gelesen werden: %s", base_name, tostring(err)))
		return nil
	end
	local base, parse_err = PA_XLIFF.from_document(document)
	if not base then
		pyui.alert(parse_err)
		return nil
	end
	if #PA_XLIFF.units(base) == 0 then
		pyui.alert(string.format(pyloc "„%s“ enthält keine Texte. PYTHA füllt die Basisdatei, sobald das Plugin einmal ausgeführt wurde.", base_name))
		return nil
	end

	local languages = PA_XLIFF.languages()
	local choice = { languages = languages, source = language_index(languages, "en-US"), target = language_index(languages, "de-DE") }
	if pyui.run_modal_subdialog(language_dialog, choice) ~= "ok" then
		return nil
	end
	local src_lang = languages[choice.source].code
	local trg_lang = languages[choice.target].code

	local target_name = PA_XLIFF.target_file_name(base_name, trg_lang)
	local existing = nil
	local entry = PA_FILES.find_entry(PA_FILES.list(folder, "files"), target_name)
	if entry then
		target_name = entry.name
		local existing_document, read_err = PA_FILES.read_xml(PA_FILES.append(folder, entry.name))
		if existing_document then
			existing, read_err = PA_XLIFF.from_document(existing_document)
		end
		if not existing then
			pyui.alert(string.format(pyloc "Die vorhandene Übersetzung „%s“ konnte nicht gelesen werden und wird nicht überschrieben: %s", entry.name, tostring(read_err)))
			return nil
		end
	end

	local work = PA_XLIFF.merge(base, existing)
	local state = {
		work = work,
		units = PA_XLIFF.units(work),
		current = 1,
		folder = folder,
		base_name = base_name,
		target_name = target_name,
		target_exists = entry ~= nil,
		src_lang = src_lang,
		trg_lang = trg_lang,
	}
	state.current = 0
	state.current = next_open(state) or 1
	pyui.run_modal_subdialog(translation_dialog, state)
	return state
end
