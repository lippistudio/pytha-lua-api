-- Complete workflows through the dialogs, driven by the pyui fake.

local tests = {}

local function list_with_item(dialog, item)
	for _, control in ipairs(dialog.controls) do
		if control.kind == "drop_list" or control.kind == "list_box" then
			for _, text in ipairs(control.items) do
				if text == item then
					return control
				end
			end
		end
	end
	error("no list with item " .. item)
end

tests["create a new plugin with the generator template"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	fake.fs.mkdirs("/plugins")
	fake.folder_answers[1] = "/plugins"
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Neues Plugin erstellen …"))
		end,
		function(editor)
			T.eq(editor.title, "Plugin-Assistent – neues Plugin")
			F.type_text(editor:find_after_label("Name *", "text_box"), "Treppe")
			T.eq(editor:find_after_label("Ordnername *", "text_box").text, "Treppe", "folder follows the name")
			F.select_text(list_with_item(editor, "Generator mit Dialog und Bearbeiten"), "Generator mit Dialog und Bearbeiten")
			local list = editor:find("list_box")
			T.eq(list.items, { "Funktion · main · Treppe", "Bearbeiten · edit_treppe · treppe_history" })

			F.select_text(list_with_item(editor, "Attribut (berechneter Wert)"), "Attribut (berechneter Wert)")
			F.click(editor:find("button", "Hinzufügen …"))
			T.eq(#list.items, 3)
			T.eq(list.items[3], "Attribut · eval_treppe_attribute · Stufenzahl")
			T.eq(list.selection, 3)

			local displays = editor:find_all("text_display")
			local summary = displays[#displays]
			T.eq(summary.group, "Prüfung")
			T.eq(summary.text, "Keine Fehler oder Warnungen.")
			T.ok(editor:find("button", "Speichern …").enabled)
			F.click(editor:find("button", "Speichern …"))
			T.ok(editor.ended, "editor closes after saving")
		end,
		function(extension)
			T.eq(extension.title, "Extension: Attribut (berechneter Wert)")
			F.type_text(extension:find_after_label("Name des Attributs", "text_box"), "Stufenzahl")
			return "ok"
		end,
	}
	T.main(env, fake)

	local config = fake.fs.text("/plugins/Treppe/config.xml")
	T.contains(config, "<name>Treppe</name>")
	T.contains(config, "<id>treppe_history</id>")
	T.contains(config, "<caption>Stufenzahl</caption>")
	local main_lua = fake.fs.text("/plugins/Treppe/main.lua")
	T.contains(main_lua, 'local HISTORY_ID = "treppe_history"')
	T.contains(main_lua, "function edit_treppe(element, selected_element)")
	T.contains(main_lua, "function eval_treppe_attribute(element)")
	T.ok(fake.fs.read("/plugins/Treppe/help.html"))
	T.eq(#fake.alerts, 1)
	T.contains(fake.alerts[1], "Gespeichert im Ordner „Treppe“")
	T.eq(fake.values.pa_defaults.template, "generator", "defaults remembered")
end

tests["errors block saving and are listed"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Neues Plugin erstellen …"))
		end,
		function(editor)
			local save = editor:find("button", "Speichern …")
			T.ok(save.enabled)
			F.type_text(editor:find_after_label("Version", "text_box"), "1.0 beta")
			T.eq(save.enabled, false)
			local issues = editor:find("text_display_area")
			T.contains(issues.text, "FEHLER – Plugin: Die Version „1.0 beta“ ist ungültig.")
			F.type_text(editor:find_after_label("Version", "text_box"), "1.1")
			T.ok(save.enabled)
			F.type_text(editor:find_after_label("Ordnername *", "text_box"), "Regal?")
			T.eq(save.enabled, false)
			return "cancel"
		end,
	}
	T.main(env, fake)
	T.eq(fake.write_calls, nil, "nothing written")
end

tests["open Waveboards, fix the missing edit extension and save"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	T.mount_samples(fake)
	fake.folder_answers = { "/samples/Waveboards", "/samples/Waveboards" }
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Bestehendes Plugin öffnen und prüfen …"))
		end,
		function(editor)
			T.eq(editor.title, "Plugin-Assistent – Waveboards")
			local issues = editor:find("text_display_area")
			T.contains(issues.text, "„wave_shape_history“")
			T.eq(editor:find("button", "Neu erzeugen").enabled, false, "GUID of an existing plugin stays")
			F.select_text(list_with_item(editor, "Bearbeiten (Rechtsklick → Bearbeiten)"), "Bearbeiten (Rechtsklick → Bearbeiten)")
			F.click(editor:find("button", "Hinzufügen …"))
			T.not_contains(issues.text, "„wave_shape_history“ (")
			F.click(editor:find("button", "Speichern …"))
		end,
		function(extension)
			F.type_text(extension:find_after_label("History-ID", "text_box"), "wave_shape_history")
			F.type_text(extension:find_after_label("Einstiegsfunktion *", "text_box"), "edit_block")
			local check = extension:find_all("text_display_area")[2]
			T.eq(check.text, "Keine Fehler.")
			return "ok"
		end,
	}
	T.main(env, fake)
	T.eq(fake.folder_requests[1].access, "read")
	T.eq(fake.folder_requests[2].access, "full")
	T.ok(fake.fs.read("/samples/Waveboards/config.xml.bak"))
	T.contains(fake.fs.text("/samples/Waveboards/config.xml"), "<entry-point>edit_block</entry-point>")
	T.eq(fake.fs.read("/samples/Waveboards/plugin_assistent_stubs.lua"), nil, "no stubs needed")
end

tests["open a plugin with a missing entry point creates a stub file"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	fake.fs.write("/plugins/Test/config.xml", {
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<plugin xmlns="http://xmlns.pytha.com/plugin_config/1.0">',
		"  <header><guid>3f2d1456-960c-489c-abfd-0cab1cd5644c</guid><version>1.0</version><pytha-version>26.0</pytha-version><name>Test</name></header>",
		'  <extension type="function"><entry-point>main</entry-point><caption>Test</caption></extension>',
		'  <extension type="attribute"><id>laenge</id><entry-point>eval_laenge</entry-point><caption>Länge</caption></extension>',
		"</plugin>",
	})
	fake.fs.write("/plugins/Test/main.lua", { "function main()", "end" })
	fake.folder_answers = { "/plugins/Test", "/plugins/Test" }
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Bestehendes Plugin öffnen und prüfen …"))
		end,
		function(editor)
			local issues = editor:find("text_display_area")
			T.contains(issues.text, "HINWEIS – Extension 2 (Attribut „eval_laenge“): Die Einstiegsfunktion „eval_laenge“ fehlt im Lua-Code")
			F.check(editor:find("check_box", "Fehlende Einstiegsfunktionen als Lua-Gerüst anlegen"), false)
			T.contains(issues.text, "FEHLER – Extension 2 (Attribut „eval_laenge“): Die Einstiegsfunktion „eval_laenge“ ist in keiner Lua-Datei")
			T.eq(editor:find("button", "Speichern …").enabled, false)
			F.check(editor:find("check_box", "Fehlende Einstiegsfunktionen als Lua-Gerüst anlegen"), true)
			F.click(editor:find("button", "Speichern …"))
		end,
	}
	T.main(env, fake)
	T.eq(fake.fs.text("/plugins/Test/main.lua"), "function main()\nend", "Lua files are not changed")
	T.contains(fake.fs.text("/plugins/Test/plugin_assistent_stubs.lua"), "function eval_laenge(element)")
end

tests["preview, remove and reorder extensions"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Neues Plugin erstellen …"))
		end,
		function(editor)
			F.select_text(list_with_item(editor, "Teileauswahl (Filter)"), "Teileauswahl (Filter)")
			F.click(editor:find("button", "Hinzufügen …"))
			local list = editor:find("list_box")
			T.eq(list.selection, 2)
			T.eq(editor:find("button", "Nach unten").enabled, false)
			F.click(editor:find("button", "Nach oben"))
			T.eq(list.items[1]:sub(1, 12), "Teileauswahl")
			T.eq(list.selection, 1)
			F.click(editor:find("button", "Vorschau …"))
			F.select(list, 1)
			F.click(editor:find("button", "Entfernen"))
			T.eq(#list.items, 1)
			T.eq(list.items[1]:sub(1, 8), "Funktion")
			return "cancel"
		end,
		function(extension) return "ok" end,
		function(preview)
			T.eq(preview.title, "Vorschau der Dateien")
			local files = preview:find("drop_list")
			T.eq(files.items, { "config.xml", "main.lua", "help.html" })
			local text = preview:find("text_display_area")
			T.contains(text.text, '<extension type="part-selector">')
			T.contains(text.text, "\r\n", "Windows line breaks in multi-line controls")
			F.select(files, 2)
			T.contains(text.text, "function select_neues_plugin(selection)")
		end,
		function(confirm)
			T.eq(confirm.title, "Extension entfernen")
			return "ok"
		end,
	}
	T.main(env, fake)
end

tests["translate the Block sample into French"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	T.mount_samples(fake)
	fake.open_answers[1] = "/samples/Block/localization.base.xlf"
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Übersetzung bearbeiten (.xlf) …"))
		end,
		function(languages)
			T.eq(languages.title, "Sprachen der Übersetzung")
			local lists = languages:find_all("drop_list")
			T.eq(lists[1].items[lists[1].selection], "Englisch (en-US)")
			F.select_text(lists[2], "Französisch (fr-FR)")
			return "ok"
		end,
		function(editor)
			local status = editor:find("text_display")
			T.contains(status.text, "0 von 10 Texten übersetzt · Zieldatei: localization.fr-FR.xlf (neu)")
			local list = editor:find("list_box")
			T.eq(list.items[1], "[ ] No data found")
			T.eq(list.selection, 1)
			F.type_text(editor:find_after_label("Übersetzung", "text_area"), "Aucune donnée trouvée")
			T.eq(list.items[1], "[x] No data found")
			F.click(editor:find("button", "Nächster offener Text"))
			T.eq(list.selection, 2)
			T.eq(editor:find_after_label("Quelltext", "text_display_area").text, "Block")
			F.click(editor:find("button", "Quelltext übernehmen"))
			T.contains(status.text, "2 von 10 Texten übersetzt")
			T.contains(status.text, "nicht gespeichert")
			F.click(editor:find("button", "Speichern"))
			T.not_contains(status.text, "nicht gespeichert")
		end,
	}
	T.main(env, fake)
	T.eq(fake.open_requests[1].options.access, "full")
	local text = fake.fs.text("/samples/Block/localization.fr-FR.xlf")
	T.contains(text, 'srcLang="en-US"')
	T.contains(text, 'trgLang="fr-FR"')
	T.contains(text, "<target>Aucune donnée trouvée</target>")
	T.contains(text, "<target>Block</target>")
	T.contains(fake.alerts[1], "localization.fr-FR.xlf")
end

tests["existing German translation is loaded"] = function(T)
	local env, fake = T.new_env()
	local F = T.fake
	T.mount_samples(fake)
	fake.open_answers[1] = "/samples/Block/localization.base.xlf"
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Übersetzung bearbeiten (.xlf) …"))
		end,
		function(languages) return "ok" end,
		function(editor)
			T.contains(editor:find("text_display").text, "10 von 10 Texten übersetzt · Zieldatei: localization.de-DE.xlf")
			T.not_contains(editor:find("text_display").text, "(neu)")
			T.eq(editor:find_after_label("Übersetzung", "text_area").text, "Keine History gefunden")
			F.click(editor:find("button", "Nächster offener Text"))
		end,
	}
	T.main(env, fake)
	T.eq(fake.alerts[1], "Alle Texte sind übersetzt.")
end

tests["unexpected errors in handlers are reported instead of ending the plugin"] = function(T)
	local env, fake = T.new_env()
	local handler = env.PA_UI.safe(function() error("boom") end)
	handler()
	T.eq(#fake.alerts, 1)
	T.contains(fake.alerts[1], "Unerwarteter Fehler")
	T.contains(fake.alerts[1], "boom")
end

tests["larger controls with PYTHA 27"] = function(T)
	local env, fake = T.new_env({ fake = { v27 = true } })
	local F = T.fake
	fake.scripts = {
		function(start)
			F.click(start:find("button", "Neues Plugin erstellen …"))
		end,
		function(editor)
			T.eq(editor:find("list_box").min_height, 64)
			return "cancel"
		end,
	}
	T.main(env, fake)
end

return tests
