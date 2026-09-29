-- Plugin-Assistent: description of the config.xml format.
-- Source: PYTHA Lua API wiki (pages "config.xml" and "config.xml ... Extension").
-- This table is the single source of truth for the editor, the validation and
-- the Lua templates.

PA_SCHEMA = {}

PA_SCHEMA.NAMESPACE = "http://xmlns.pytha.com/plugin_config/1.0"

-- Texts of the bare-bones config.xml that PYTHA generates and of the wiki examples
PA_SCHEMA.PLACEHOLDER_TEXTS = {
	["The description of your plugin goes here."] = true,
	["Information about the licensing terms goes here."] = true,
	["A short description of the function goes here."] = true,
	["A short description what this button does."] = true,
	["A short description of the attribute"] = true,
	["Button Caption"] = true,
	["Text of the Button"] = true,
	["Plugin Name"] = true,
	["Attribute-Name"] = true,
}

PA_SCHEMA.PYTHA_VERSIONS = { "25.0", "26.0", "27.0" }

PA_SCHEMA.CAM_SYSTEMS = { "bsolid_cix" }

PA_SCHEMA.IMPORT_SCOPES = { "file", "folder", "recursive" }

local cache = nil

-- The schema is built on first use because pyloc is not available while
-- PYTHA loads the plugin files.
local function build()
	local entry_point_help = pyloc "Name der Lua-Funktion, die PYTHA aufruft. Nur Buchstaben, Ziffern und _, nicht mit einer Ziffer beginnend."
	local caption_help = pyloc "Text in der PYTHA-Oberfläche. Wird über die .xlf-Dateien übersetzt."
	local description_help = pyloc "Kurzer Hilfetext (Tooltip). Wird über die .xlf-Dateien übersetzt."
	local help_file_help = pyloc "Hilfedatei im Plugin-Ordner (.html, .pdf oder .txt), die per Rechtsklick geöffnet wird."
	local history_id_help = pyloc "Muss mit der ID übereinstimmen, die der Code bei pytha.set_element_history übergibt."

	local schema = {}

	schema.header_fields = {
		{ key = "guid", label = pyloc "GUID", required = true, kind = "guid",
			help = pyloc "Eindeutige Kennung des Plugins. Für jedes neue Plugin eine neue GUID erzeugen." },
		{ key = "version", label = pyloc "Version", kind = "version",
			help = pyloc "Version des Plugins. Sind mehrere Versionen installiert, lädt PYTHA die neueste." },
		{ key = "pytha-version", label = pyloc "Min. PYTHA-Version", kind = "pytha_version",
			help = pyloc "Ältere PYTHA-Versionen laden das Plugin nicht." },
		{ key = "name", label = pyloc "Name", required = true, kind = "text",
			help = pyloc "Lesbarer Name des Plugins. Wird über die .xlf-Dateien übersetzt." },
		{ key = "description", label = pyloc "Beschreibung", kind = "multiline",
			help = pyloc "Längere Beschreibung des Plugins. Wird über die .xlf-Dateien übersetzt." },
		{ key = "licensing", label = pyloc "Lizenz", kind = "multiline",
			help = pyloc "Lizenzbedingungen als lesbarer Text. PYTHA setzt sie nicht durch." },
	}

	schema.types = {
		{
			type = "function",
			label = pyloc "Funktion",
			title = pyloc "Funktion (Button im Menü)",
			min_version = 25,
			signature = "main()",
			doc = pyloc "Erzeugt einen Button in der PYTHA-Oberfläche. Beim Klick wird die Einstiegsfunktion ohne Parameter aufgerufen.",
			fields = {
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
				{ key = "caption", label = pyloc "Beschriftung", required = true, kind = "text", help = caption_help },
				{ key = "description", label = pyloc "Beschreibung", kind = "text", help = description_help },
				{ key = "help-file", label = pyloc "Hilfedatei", kind = "help_file", help = help_file_help },
			},
		},
		{
			type = "edit",
			label = pyloc "Bearbeiten",
			title = pyloc "Bearbeiten (Rechtsklick → Bearbeiten)",
			min_version = 25,
			signature = "edit(element, selected_element)",
			doc = pyloc "Wird aufgerufen, wenn der Benutzer ein Teil per Rechtsklick bearbeitet, dessen History dieses Plugin mit derselben ID gesetzt hat.",
			fields = {
				{ key = "id", label = pyloc "History-ID", kind = "history_id", help = history_id_help },
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
			},
		},
		{
			type = "update",
			label = pyloc "Aktualisieren",
			title = pyloc "Aktualisieren (aus Variablen)",
			min_version = 25,
			signature = "update(element)",
			doc = pyloc "Wird bei „Parametric → Update from variables“ für Gruppen aufgerufen, deren History dieses Plugin mit derselben ID gesetzt hat.",
			fields = {
				{ key = "id", label = pyloc "History-ID", kind = "history_id", help = history_id_help },
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
			},
		},
		{
			type = "attribute",
			label = pyloc "Attribut",
			title = pyloc "Attribut (berechneter Wert)",
			min_version = 25,
			signature = "eval(element) → Text",
			doc = pyloc "Berechnet ein Attribut, z. B. für die Stückliste. Ohne Einstiegsfunktion ist das Attribut ein reiner Datenspeicher.",
			fields = {
				{ key = "id", label = pyloc "Attribut-ID", required = true, kind = "attribute_id",
					help = pyloc "Nur Buchstaben, Ziffern, _ und -. Keine Leerzeichen, keine Anführungszeichen." },
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", kind = "identifier", help = entry_point_help },
				{ key = "caption", label = pyloc "Name des Attributs", kind = "text", help = caption_help },
				{ key = "description", label = pyloc "Beschreibung", kind = "text", help = description_help },
			},
		},
		{
			type = "part-selector",
			label = pyloc "Teileauswahl",
			title = pyloc "Teileauswahl (Filter)",
			min_version = 25,
			signature = "change_selection(selection)",
			doc = pyloc "Erzeugt einen Button in der Teileauswahl. Die Funktion verändert die Tabelle selection mit den ausgewählten Teilen.",
			fields = {
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
				{ key = "caption", label = pyloc "Beschriftung", required = true, kind = "text", help = caption_help },
				{ key = "description", label = pyloc "Beschreibung", kind = "text", help = description_help },
			},
		},
		{
			type = "cam-native-macro",
			label = pyloc "CAM-Makro",
			title = pyloc "CAM-Makro (native macro)",
			min_version = 25,
			signature = "customize_macro(macro)",
			doc = pyloc "Passt die CAM-Ausgabe eines My-Makros an. Die Funktion ändert die Parameter in der Tabelle macro.",
			fields = {
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
				{ key = "id", label = pyloc "Makroname", required = true, kind = "text",
					help = pyloc "Exakter Name des My-Makros." },
				{ key = "cam-system", label = pyloc "CAM-System", kind = "enum", options = PA_SCHEMA.CAM_SYSTEMS,
					default = "bsolid_cix", help = pyloc "Kennung des CAM-Systems. Dokumentiert ist bsolid_cix." },
			},
		},
		{
			type = "file-import",
			label = pyloc "Datei-Import",
			title = pyloc "Datei-Import (Menü Import)",
			min_version = 26,
			signature = "import(file [, directory])",
			doc = pyloc "Erzeugt einen Eintrag im Import-Menü. Die Funktion erhält einen Path-Handle der gewählten Datei.",
			fields = {
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
				{ key = "id", label = pyloc "Extension-ID", kind = "id",
					help = pyloc "Kennung des Imports, z. B. für den Aufruf /Plugin \"guid/id\" \"datei\" von der Kommandozeile." },
				{ key = "caption", label = pyloc "Beschriftung", required = true, kind = "text", help = caption_help },
				{ key = "file-filter", label = pyloc "Dateifilter", kind = "file_filter",
					help = pyloc "Dateityp(en) mit führendem Stern, z. B. *.csv oder *.csv;*.txt" },
				{ key = "scope", label = pyloc "Dateizugriff", kind = "enum", options = PA_SCHEMA.IMPORT_SCOPES, default = "file",
					help = pyloc "file: nur die Datei. folder: zusätzlich der Ordner. recursive: Ordner mit Unterordnern." },
				{ key = "help-file", label = pyloc "Hilfedatei", kind = "help_file", help = help_file_help },
			},
		},
		{
			type = "message-handler",
			label = pyloc "Nachrichten-Service",
			title = pyloc "Nachrichten-Service (message handler)",
			min_version = 26,
			signature = "handler(subject, value) → status, value",
			doc = pyloc "Bietet anderen Plugins einen Dienst an, der über pymsg.send_message aufgerufen wird.",
			fields = {
				{ key = "id", label = pyloc "Handler-ID", required = true, kind = "id",
					help = pyloc "Eindeutig innerhalb des Plugins." },
				{ key = "message", label = pyloc "Thema (GUID/TOPIC)", required = true, kind = "message",
					help = pyloc "GUID des Plugins, das das Thema definiert, gefolgt von / und dem Thema." },
				{ key = "entry-point", label = pyloc "Einstiegsfunktion", required = true, kind = "identifier", help = entry_point_help },
				{ key = "caption", label = pyloc "Beschriftung", required = true, kind = "text", help = caption_help },
				{ key = "description", label = pyloc "Beschreibung", kind = "text", help = description_help },
			},
		},
	}

	schema.by_type = {}
	for _, info in ipairs(schema.types) do
		info.field_by_key = {}
		for _, field in ipairs(info.fields) do
			info.field_by_key[field.key] = field
		end
		schema.by_type[info.type] = info
	end
	schema.header_by_key = {}
	for _, field in ipairs(schema.header_fields) do
		schema.header_by_key[field.key] = field
	end
	return schema
end

function PA_SCHEMA.get()
	if cache == nil then
		cache = build()
	end
	return cache
end

function PA_SCHEMA.type_info(type_name)
	return PA_SCHEMA.get().by_type[type_name]
end

function PA_SCHEMA.field_info(type_name, key)
	local info = PA_SCHEMA.type_info(type_name)
	return info and info.field_by_key[key] or nil
end

function PA_SCHEMA.type_label(type_name)
	local info = PA_SCHEMA.type_info(type_name)
	return info and info.label or tostring(type_name)
end

function PA_SCHEMA.type_names()
	local names = {}
	for _, info in ipairs(PA_SCHEMA.get().types) do
		names[#names + 1] = info.type
	end
	return names
end
