-- Plugin-Assistent: Lua code templates for the entry points of each extension type.
--
-- The generated code follows the style of the samples (English comments, tabs)
-- and avoids unit literals such as 18mm so that it also loads in plain Lua.

PA_TEMPLATES = {}

local function quote(text)
	return string.format("%q", tostring(text or ""))
end

local function comment(text)
	return (tostring(text or ""):gsub("[\r\n]+", " "))
end

local function add(lines, ...)
	for _, line in ipairs({ ... }) do
		lines[#lines + 1] = line
	end
end

local function value(ext, key)
	return PA_MODEL.trim(ext.values[key])
end

-- Stubs per extension type ------------------------------------------------------

local STUBS = {}

STUBS["function"] = function(lines, ext, entry)
	add(lines,
		"-- Function extension " .. quote(comment(value(ext, "caption"))) .. ": called without arguments when the user clicks the button.",
		"function " .. entry .. "()",
		"\tpyui.alert(pyloc \"Hello World!\")",
		"end")
end

STUBS["edit"] = function(lines, ext, entry)
	add(lines,
		"-- Edit extension (history id " .. quote(comment(value(ext, "id"))) .. "): called when the user edits an element",
		"-- whose history was set with pytha.set_element_history(element, data, " .. quote(comment(value(ext, "id"))) .. ").",
		"function " .. entry .. "(element, selected_element)",
		"\tlocal data = pytha.get_element_history(element)",
		"\tif data == nil then",
		"\t\tpyui.alert(pyloc \"No data found\")",
		"\t\treturn",
		"\tend",
		"\t-- TODO: show a dialog and recreate the geometry from 'data'",
		"end")
end

STUBS["update"] = function(lines, ext, entry)
	add(lines,
		"-- Update extension (history id " .. quote(comment(value(ext, "id"))) .. "): called by \"Update from variables\".",
		"function " .. entry .. "(element)",
		"\tlocal data = pytha.get_element_history(element)",
		"\tif data == nil then",
		"\t\treturn",
		"\tend",
		"\t-- TODO: recreate the geometry from 'data'",
		"end")
end

STUBS["attribute"] = function(lines, ext, entry)
	add(lines,
		"-- Attribute extension " .. quote(comment(value(ext, "id"))) .. ": returns the attribute value as text.",
		"function " .. entry .. "(element)",
		"\tif element:get_element_type() ~= \"part\" then",
		"\t\treturn \"\"",
		"\tend",
		"\t-- Attribute values are texts. Convert lengths before calculating, e.g.:",
		"\t-- local thickness = pyui.parse_length(element:get_element_attribute(\"3005\") or \"\") or 0",
		"\tlocal material = element:get_element_attribute(\"material-name\") or \"\"",
		"\treturn material",
		"end")
end

STUBS["part-selector"] = function(lines, ext, entry)
	add(lines,
		"-- Part selector " .. quote(comment(value(ext, "caption"))) .. ": change the table 'selection' (handles of the selected parts).",
		"function " .. entry .. "(selection)",
		"\t-- Example: remove parts without material. Iterate backwards when removing entries.",
		"\tfor i = #selection, 1, -1 do",
		"\t\tlocal material = selection[i]:get_element_attribute(\"material-name\") or \"\"",
		"\t\tif material == \"\" then",
		"\t\t\ttable.remove(selection, i)",
		"\t\tend",
		"\tend",
		"\t-- To add parts, enumerate all parts of the model:",
		"\t-- for part in pytha.enumerate_parts() do",
		"\t--\tif <condition> then table.insert(selection, part) end",
		"\t-- end",
		"end")
end

STUBS["cam-native-macro"] = function(lines, ext, entry)
	add(lines,
		"-- CAM native macro " .. quote(comment(value(ext, "id"))) .. " (" .. comment(value(ext, "cam-system")) .. "): change the exported macro parameters.",
		"function " .. entry .. "(macro)",
		"\t-- Parameters may be changed, added or removed (set to nil), e.g.:",
		"\t-- macro.TOOL = \"S29\"",
		"end")
end

STUBS["file-import"] = function(lines, ext, entry)
	local scope = value(ext, "scope")
	local with_directory = scope == "folder" or scope == "recursive"
	add(lines,
		"-- File import " .. quote(comment(value(ext, "caption"))) .. " (" .. comment(value(ext, "file-filter")) .. "): 'file' is a path handle of the selected file.",
		"function " .. entry .. (with_directory and "(file, directory)" or "(file)"),
		"\tlocal lines = pyio.parse_lines(file)",
		"\tif lines == nil or #lines == 0 then",
		"\t\tpyui.alert(pyloc \"The file is empty or could not be read.\")",
		"\t\treturn",
		"\tend",
		"\t-- TODO: create geometry from the file content (see also pyio.parse_csv, pyio.parse_xml)",
		"\tpyui.alert(string.format(pyloc \"%d lines read.\", #lines))",
		"end")
end

STUBS["message-handler"] = function(lines, ext, entry)
	add(lines,
		"-- Message handler for the topic " .. quote(comment(value(ext, "message"))) .. ".",
		"-- Other plugins send messages with pymsg.send_message; see the wiki page \"pymsg\".",
		"function " .. entry .. "(subject, value)",
		"\t-- Return a status (true on success) and a result value.",
		"\treturn true, {}",
		"end")
end

local function stub_for(lines, ext, entry)
	local stub = STUBS[ext.type]
	if stub then
		stub(lines, ext, entry)
	else
		add(lines,
			"-- Extension of type " .. quote(comment(ext.type)) .. ".",
			"function " .. entry .. "(...)",
			"end")
	end
end

-- Generator template (dialog, geometry, history, edit) ------------------------------

local function generator_code(lines, project, main_ext, history_id, handled)
	local name = PA_MODEL.trim(project.header.name)
	add(lines,
		"local DEFAULTS_NAME = \"default_values\"",
		"")
	if history_id then
		add(lines, "local HISTORY_ID = " .. quote(history_id) .. "  -- must match the id of the edit extension in config.xml", "")
	end
	add(lines,
		"local function default_values()",
		"\treturn {",
		"\t\tname = pyloc \"Block\",",
		"\t\tlength = 600,",
		"\t\twidth = 400,",
		"\t\theight = 300,",
		"\t\torigin = {0, 0, 0},",
		"\t}",
		"end",
		"",
		"-- Only plain values are stored as defaults for the next start (no element handles).",
		"local function values_to_save(data)",
		"\treturn {name = data.name, length = data.length, width = data.width, height = data.height}",
		"end",
		"",
		"local function recreate_geometry(data)",
		"\tif data.current_element ~= nil then",
		"\t\tpytha.delete_element(data.current_element)",
		"\t\tdata.current_element = nil",
		"\tend",
		"\tdata.current_element = pytha.create_block(data.length, data.width, data.height, data.origin)",
		"\tpytha.set_element_name(data.current_element, data.name)")
	if history_id then
		add(lines, "\tpytha.set_element_history(data.current_element, data, HISTORY_ID)")
	end
	add(lines,
		"end",
		"",
		"-- Handler for text boxes with a length: only accept valid positive values.",
		"local function length_handler(data, key)",
		"\treturn function(text)",
		"\t\tlocal value = pyui.parse_length(text)",
		"\t\tif value ~= nil and value > 0 then",
		"\t\t\tdata[key] = value",
		"\t\t\trecreate_geometry(data)",
		"\t\tend",
		"\tend",
		"end",
		"",
		"local function main_dialog(dialog, data)",
		"\tdialog:set_window_title(pyloc(" .. quote(name) .. "))",
		"",
		"\tdialog:create_label(1, pyloc \"Name\")",
		"\tlocal name = dialog:create_text_box({2, 3}, data.name)",
		"\tdialog:create_label(1, pyloc \"Length\")",
		"\tlocal length = dialog:create_text_box({2, 3}, pyui.format_length(data.length))",
		"\tdialog:create_label(1, pyloc \"Width\")",
		"\tlocal width = dialog:create_text_box({2, 3}, pyui.format_length(data.width))",
		"\tdialog:create_label(1, pyloc \"Height\")",
		"\tlocal height = dialog:create_text_box({2, 3}, pyui.format_length(data.height))",
		"\tdialog:create_label(1, pyloc \"Origin\")",
		"\tlocal pick = dialog:create_button({2, 3}, pyloc \"Pick point\")",
		"",
		"\tdialog:create_align({1, 3})",
		"\tdialog:create_ok_button(2)",
		"\tdialog:create_cancel_button(3)",
		"\tdialog:equalize_column_widths({2, 3})",
		"",
		"\tname:set_on_change_handler(function(text)",
		"\t\tdata.name = text",
		"\t\trecreate_geometry(data)",
		"\tend)",
		"\tlength:set_on_change_handler(length_handler(data, \"length\"))",
		"\twidth:set_on_change_handler(length_handler(data, \"width\"))",
		"\theight:set_on_change_handler(length_handler(data, \"height\"))",
		"\tpick:set_on_click_handler(function()",
		"\t\tlocal point = pyux.select_coordinate()",
		"\t\tif point ~= nil then",
		"\t\t\tdata.origin = point",
		"\t\t\trecreate_geometry(data)",
		"\t\tend",
		"\tend)",
		"end",
		"",
		"-- Function extension " .. quote(comment(value(main_ext, "caption"))) .. ": called when the user clicks the button.",
		"function " .. value(main_ext, "entry-point") .. "()",
		"\tlocal data = default_values()",
		"\tlocal saved = pyio.load_values(DEFAULTS_NAME)",
		"\tif saved ~= nil then",
		"\t\tfor key, saved_value in pairs(saved) do",
		"\t\t\tdata[key] = saved_value",
		"\t\tend",
		"\tend",
		"\trecreate_geometry(data)",
		"\tpyui.run_modal_dialog(main_dialog, data)",
		"\tpyio.save_values(DEFAULTS_NAME, values_to_save(data))",
		"end")
	handled[value(main_ext, "entry-point")] = true

	for _, ext in ipairs(project.extensions) do
		local entry = value(ext, "entry-point")
		if (ext.type == "edit" or ext.type == "update") and PA_MODEL.trim(ext.values.id) == history_id
			and PA_MODEL.is_identifier(entry) and not handled[entry] then
			handled[entry] = true
			add(lines, "")
			if ext.type == "edit" then
				add(lines,
					"-- Edit extension: right click on the element -> Edit.",
					"function " .. entry .. "(element, selected_element)",
					"\tlocal data = pytha.get_element_history(element)",
					"\tif data == nil then",
					"\t\tpyui.alert(pyloc \"No data found\")",
					"\t\treturn",
					"\tend",
					"\tdata.current_element = element",
					"\trecreate_geometry(data)",
					"\tpyui.run_modal_dialog(main_dialog, data)",
					"\tpyio.save_values(DEFAULTS_NAME, values_to_save(data))",
					"end")
			else
				add(lines,
					"-- Update extension: \"Update from variables\".",
					"function " .. entry .. "(element)",
					"\tlocal data = pytha.get_element_history(element)",
					"\tif data == nil then",
					"\t\treturn",
					"\tend",
					"\tdata.current_element = element",
					"\trecreate_geometry(data)",
					"end")
			end
		end
	end
end

local function header_comment(lines, project, title)
	add(lines,
		"-- " .. comment(PA_MODEL.trim(project.header.name)),
		"-- " .. title,
		"")
end

-- main.lua of a new plugin
function PA_TEMPLATES.main_file(project)
	local lines = {}
	header_comment(lines, project, "Created with the PYTHA Plugin-Assistent.")
	local handled = {}
	if project.options.template == "generator" then
		local main_ext = PA_MODEL.find_extension(project, "function")
		if main_ext and PA_MODEL.is_identifier(value(main_ext, "entry-point")) then
			generator_code(lines, project, main_ext, PA_MODEL.template_history_id(project), handled)
		end
	end
	for _, ext in ipairs(project.extensions) do
		local entry = value(ext, "entry-point")
		if PA_MODEL.is_identifier(entry) and not handled[entry] then
			handled[entry] = true
			if #lines > 3 then
				add(lines, "")
			end
			stub_for(lines, ext, entry)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Stub file for the missing entry points of an opened plugin.
-- missing: list of { entry = ..., ext = ... } (see PA_MODEL.missing_entry_points)
function PA_TEMPLATES.stubs_file(project, missing)
	local lines = {}
	header_comment(lines, project, "Entry points added by the PYTHA Plugin-Assistent (they were missing in the Lua files).")
	for index, item in ipairs(missing) do
		if index > 1 then
			add(lines, "")
		end
		stub_for(lines, item.ext, item.entry)
	end
	return table.concat(lines, "\n") .. "\n"
end
