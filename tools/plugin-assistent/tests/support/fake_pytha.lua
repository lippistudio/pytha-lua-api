-- Test support only: fakes for the PYTHA Lua API (pyloc, pytha, pyui, pyio, pyux).
--
-- The fakes follow the behaviour documented in the PYTHA wiki as closely as
-- needed by the Plugin-Assistent. Dialogs are simulated: every call of
-- run_modal_dialog / run_modal_subdialog builds the dialog and then runs the
-- next "script" from fake.scripts, which plays the role of the user.

local xml_parser = require("support.xml_parser")

local M = {}

local function copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for k, v in pairs(value) do
		result[copy(k, seen)] = copy(v, seen)
	end
	return result
end

local function normalize(path)
	path = path:gsub("\\", "/"):gsub("/+", "/")
	if #path > 1 then
		path = path:gsub("/$", "")
	end
	return path
end

local function parent_of(path)
	return path:match("^(.*)/[^/]+$") or "/"
end

local function base_name(path)
	return path:match("([^/]+)$") or path
end

local function wildcard_to_pattern(wildcard)
	local pattern = wildcard:lower():gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
	pattern = pattern:gsub("%*", ".*"):gsub("%?", ".")
	return "^" .. pattern .. "$"
end

-- In-memory file system ------------------------------------------------------

local function new_fs()
	local fs = { files = {}, dirs = { ["/"] = true } }

	function fs.mkdirs(path)
		path = normalize(path)
		local current = ""
		for part in path:gmatch("[^/]+") do
			current = current .. "/" .. part
			fs.dirs[current] = true
		end
	end

	function fs.write(path, lines)
		path = normalize(path)
		fs.mkdirs(parent_of(path))
		fs.files[path] = copy(lines)
	end

	function fs.write_text(path, text)
		local lines = {}
		text = text:gsub("\r\n", "\n")
		for line in (text .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		if lines[#lines] == "" then
			lines[#lines] = nil
		end
		fs.write(path, lines)
	end

	function fs.read(path)
		return fs.files[normalize(path)]
	end

	function fs.text(path)
		local lines = fs.read(path)
		return lines and table.concat(lines, "\n") or nil
	end

	function fs.list(dir)
		dir = normalize(dir)
		local entries = {}
		local prefix = dir == "/" and "/" or dir .. "/"
		for path in pairs(fs.files) do
			if path:sub(1, #prefix) == prefix and not path:sub(#prefix + 1):find("/") then
				entries[#entries + 1] = { name = base_name(path), is_folder = false, file_size = 0, last_modified = 0, is_hidden = false }
			end
		end
		for path in pairs(fs.dirs) do
			if path ~= dir and path:sub(1, #prefix) == prefix and not path:sub(#prefix + 1):find("/") then
				entries[#entries + 1] = { name = base_name(path), is_folder = true, file_size = 0, last_modified = 0, is_hidden = false }
			end
		end
		table.sort(entries, function(a, b) return a.name < b.name end)
		return entries
	end

	return fs
end

-- Path handles --------------------------------------------------------------

local HANDLE = {}
HANDLE.__index = HANDLE

local function new_handle(fake, path, access, scope)
	return setmetatable({ fake = fake, path = normalize(path), access = access or "read", scope = scope or "file" }, HANDLE)
end

function HANDLE:get_name()
	return base_name(self.path)
end

function HANDLE:append_path(relative)
	return self.fake.pyio.append_path(self, relative)
end

function HANDLE:list_folder(kind, pattern, max)
	return self.fake.pyio.list_folder(self, kind, pattern, max)
end

-- Dialog controls -------------------------------------------------------------

local CONTROL = {}
CONTROL.__index = CONTROL

function CONTROL:set_on_change_handler(handler) self.on_change = handler; return self end
function CONTROL:set_on_click_handler(handler) self.on_click = handler; return self end
function CONTROL:set_control_text(text) self.text = text end
function CONTROL:set_control_checked(state) self.checked = state and true or false end
function CONTROL:set_control_selection(index) self.selection = index end
function CONTROL:insert_control_item(text, position)
	if position and position > 0 then
		table.insert(self.items, position, text)
	else
		self.items[#self.items + 1] = text
	end
end
function CONTROL:clear_control_items() self.items = {}; self.selection = nil end
function CONTROL:reset_content() self:clear_control_items() end
function CONTROL:enable_control(state) if state == nil then state = true end; self.enabled = state and true or false end
function CONTROL:disable_control() self.enabled = false end
function CONTROL:show_control(state) if state == nil then state = true end; self.visible = state and true or false end
function CONTROL:hide_control(state) self.visible = state and true or false end
function CONTROL:delete_control() self.deleted = true end
function CONTROL:set_control_min_height(height)
	if not self.dialog.fake.v27 then
		error("set_control_min_height is not available before V27")
	end
	self.min_height = height
end

local DIALOG = {}
DIALOG.__index = DIALOG

local function add_control(dialog, kind, col_spec, text)
	local control = setmetatable({
		dialog = dialog, kind = kind, col = col_spec, text = text or "",
		items = {}, checked = false, enabled = true, visible = true,
		label = dialog.last_label, group = dialog.group_stack[#dialog.group_stack],
	}, CONTROL)
	dialog.controls[#dialog.controls + 1] = control
	if kind == "label" then
		dialog.last_label = text
	end
	return control
end

for _, kind in ipairs({ "label", "standalone_label", "caption", "text_box", "text_area", "text_display",
	"text_display_area", "button", "check_box", "drop_list", "list_box", "combo_box", "droplist_button",
	"ok_button", "cancel_button", "empty", "text_spin" }) do
	DIALOG["create_" .. kind] = function(self, col_spec, text)
		return add_control(self, kind, col_spec, text)
	end
end

function DIALOG:create_group_box(col_spec, text)
	local control = add_control(self, "group_box", col_spec, text)
	self.group_stack[#self.group_stack + 1] = text
	return control
end
DIALOG.create_foldable_group_box = DIALOG.create_group_box
DIALOG.create_scrollable_group_box = DIALOG.create_group_box
function DIALOG:end_group_box()
	if #self.group_stack == 0 then
		error("end_group_box without group box")
	end
	table.remove(self.group_stack)
end
function DIALOG:create_align(col_spec) self.aligns = (self.aligns or 0) + 1 end
function DIALOG:equalize_column_widths(columns) end
function DIALOG:set_column_stretch(columns, stretch) end
function DIALOG:set_window_title(title) self.title = title end
function DIALOG:update_dialog_layout() end

-- Test helpers to find controls
function DIALOG:find(kind, text)
	for _, control in ipairs(self.controls) do
		if (kind == nil or control.kind == kind) and (text == nil or control.text == text) then
			return control
		end
	end
	return nil
end

function DIALOG:find_after_label(label, kind)
	for _, control in ipairs(self.controls) do
		if control.label == label and control.kind ~= "label" and (kind == nil or control.kind == kind) then
			return control
		end
	end
	return nil
end

function DIALOG:find_all(kind)
	local result = {}
	for _, control in ipairs(self.controls) do
		if control.kind == kind then
			result[#result + 1] = control
		end
	end
	return result
end

-- Simulated user actions
function M.type_text(control, text)
	assert(control, "control not found")
	assert(control.enabled, "control is disabled")
	control.text = text
	if control.on_change then control.on_change(text) end
end

function M.click(control)
	assert(control, "control not found")
	assert(control.enabled, "control is disabled: " .. tostring(control.text))
	if control.on_click then control.on_click() end
end

function M.check(control, state)
	assert(control, "control not found")
	assert(control.enabled, "control is disabled")
	control.checked = state
	if control.on_click then control.on_click(state) end
end

function M.select(control, index)
	assert(control, "control not found")
	assert(control.enabled, "control is disabled")
	assert(control.items[index] ~= nil, "no item with index " .. tostring(index))
	control.selection = index
	if control.on_change then control.on_change(control.items[index], index) end
end

function M.select_text(control, text)
	for index, item in ipairs(control.items) do
		if item == text then
			return M.select(control, index)
		end
	end
	error("item not found: " .. tostring(text))
end

-- Environment ---------------------------------------------------------------

function M.install(env, options)
	options = options or {}
	local fake = {
		fs = new_fs(),
		alerts = {},
		scripts = {},
		folder_answers = {},
		open_answers = {},
		folder_requests = {},
		open_requests = {},
		values = {},
		dialogs = {},
		dialog_stack = {},
		write_creates_dirs = options.write_creates_dirs ~= false,
		v27 = options.v27 or false,
		plugin_folder = "/plugins/Plugin-Assistent",
		elements = {},
		parts = {},
		script_errors = {},
	}
	fake.fs.mkdirs(fake.plugin_folder)

	function fake.handle(path, access, scope)
		return new_handle(fake, path, access, scope)
	end

	-- pyloc --------------------------------------------------------------
	env.pyloc = function(text, original)
		if type(text) ~= "string" then
			error("pyloc expects a literal string")
		end
		return text
	end

	-- pyio ---------------------------------------------------------------
	local pyio = {}
	fake.pyio = pyio

	function pyio.append_path(handle, relative)
		assert(getmetatable(handle) == HANDLE, "append_path expects a path handle")
		if type(relative) ~= "string" or relative == "" then
			error("append_path: relative path expected")
		end
		relative = relative:gsub("\\", "/")
		if relative:sub(1, 1) == "/" then error("append_path: leading separator") end
		for part in relative:gmatch("[^/]+") do
			if part == ".." then error("append_path: '..' is not allowed") end
		end
		if relative:find("[<>:\"|%?%*%c]") then error("append_path: invalid character") end
		if handle.scope == "file" then error("append_path: path handle is not traversable") end
		if handle.scope == "folder" and relative:find("/") then
			error("append_path: sub-folders are not accessible with a folder handle")
		end
		local scope = handle.scope == "recursive" and "recursive" or "file"
		return new_handle(fake, handle.path .. "/" .. relative, handle.access, scope)
	end

	function pyio.list_folder(handle, kind, pattern, max)
		kind = kind or "all"
		if handle.scope == "file" then error("list_folder: handle does not grant directory access") end
		if not fake.fs.dirs[handle.path] then error("list_folder: folder does not exist") end
		local result = {}
		local lua_pattern = pattern and wildcard_to_pattern(pattern)
		for _, entry in ipairs(fake.fs.list(handle.path)) do
			local allowed = not entry.is_folder or handle.scope == "recursive"
			if allowed and (kind == "all" or (kind == "files" and not entry.is_folder) or (kind == "folders" and entry.is_folder)) then
				if not lua_pattern or entry.name:lower():match(lua_pattern) then
					result[#result + 1] = copy(entry)
				end
			end
		end
		return result, true
	end

	function pyio.write_lines(handle, lines, encoding)
		if handle.access ~= "full" then error("write_lines: path handle is read-only") end
		fake.write_calls = (fake.write_calls or 0) + 1
		if fake.fail_writes then return false end
		local parent = parent_of(handle.path)
		if not fake.fs.dirs[parent] then
			if not fake.write_creates_dirs then
				return false
			end
		end
		local stored = {}
		for i = 1, #lines do
			local line = lines[i]
			stored[i] = type(line) == "string" and line or (line == nil and "" or tostring(line))
		end
		fake.fs.write(handle.path, stored)
		return true
	end

	function pyio.parse_lines(handle)
		local lines = fake.fs.read(handle.path)
		if not lines then error("parse_lines: file not found: " .. handle.path) end
		return copy(lines)
	end

	function pyio.parse_xml(handle)
		local lines = fake.fs.read(handle.path)
		if not lines then error("parse_xml: file not found: " .. handle.path) end
		return xml_parser.parse(table.concat(lines, "\n"))
	end

	function pyio.get_plugin_folder_path(relative)
		local handle = new_handle(fake, fake.plugin_folder, "read", "recursive")
		if relative then
			handle = pyio.append_path(handle, relative)
			if not fake.fs.read(handle.path) and not fake.fs.dirs[handle.path] then
				error("get_plugin_folder_path: not found")
			end
		end
		return handle
	end

	function pyio.load_values(name)
		return copy(fake.values[name])
	end

	function pyio.save_values(name, values)
		for _, value in pairs(values) do
			if type(value) == "userdata" or type(value) == "function" then
				error("save_values: unsupported value")
			end
		end
		fake.values[name] = copy(values)
		return true
	end

	env.pyio = pyio

	-- pyui ---------------------------------------------------------------
	local pyui = {}

	local function run(init, subdialog, ...)
		local dialog = setmetatable({ fake = fake, controls = {}, group_stack = {}, subdialog = subdialog }, DIALOG)
		fake.dialogs[#fake.dialogs + 1] = dialog
		fake.dialog_stack[#fake.dialog_stack + 1] = dialog
		init(dialog, ...)
		if #dialog.group_stack > 0 then
			error("group box without end_group_box")
		end
		local script = table.remove(fake.scripts, 1)
		local result = "ok"
		if script then
			-- Failed assertions inside a script must reach the test even if the
			-- plugin catches errors of its handlers (PA_UI.safe).
			local ok, script_result = xpcall(script, debug.traceback, dialog, fake)
			if not ok then
				fake.script_errors[#fake.script_errors + 1] = script_result
				error(script_result, 0)
			end
			result = script_result or dialog.result or "ok"
		elseif options.strict_scripts then
			error("no script for dialog " .. tostring(dialog.title))
		end
		table.remove(fake.dialog_stack)
		dialog.closed = true
		return result
	end

	function pyui.run_modal_dialog(init, ...)
		local result = run(init, false, ...)
		if result == "cancel" then
			error("dialog cancelled")
		end
		return result
	end

	function pyui.run_modal_subdialog(init, ...)
		return run(init, true, ...)
	end

	function pyui.end_modal_ok()
		local dialog = fake.dialog_stack[#fake.dialog_stack]
		assert(dialog, "end_modal_ok outside of a dialog")
		dialog.result = "ok"
		dialog.ended = true
	end

	function pyui.end_modal_cancel()
		local dialog = fake.dialog_stack[#fake.dialog_stack]
		assert(dialog, "end_modal_cancel outside of a dialog")
		dialog.result = "cancel"
		dialog.ended = true
	end

	function pyui.alert(message)
		fake.alerts[#fake.alerts + 1] = message
	end

	function pyui.select_folder(access, title, opts)
		fake.folder_requests[#fake.folder_requests + 1] = { access = access, title = title, options = opts }
		local answer = table.remove(fake.folder_answers, 1)
		if type(answer) == "function" then
			answer = answer(access, title, opts)
		end
		if answer == nil then
			return nil
		end
		local scope = (opts and opts.scope) or "folder"
		return new_handle(fake, answer, access, scope == "recursive" and "recursive" or "folder")
	end

	function pyui.select_open_file(types, title, opts)
		fake.open_requests[#fake.open_requests + 1] = { types = types, title = title, options = opts }
		local answer = table.remove(fake.open_answers, 1)
		if answer == nil then
			return nil
		end
		opts = opts or {}
		local access = opts.access or "read"
		local file = new_handle(fake, answer, access, "file")
		if opts.scope == "folder" or opts.scope == "recursive" then
			return { file }, new_handle(fake, parent_of(file.path), access, opts.scope)
		end
		return { file }
	end

	function pyui.format_length(value)
		return string.format("%g", value)
	end

	function pyui.parse_length(text)
		local numbers = {}
		for number in tostring(text):gmatch("[-+]?%d+%.?%d*") do
			numbers[#numbers + 1] = tonumber(number)
		end
		return table.unpack(numbers)
	end

	function pyui.format_number(value)
		return string.format("%g", value)
	end

	pyui.parse_number = pyui.parse_length

	if fake.v27 then
		function pyui.set_control_min_height(control, height)
			control:set_control_min_height(height)
		end
	end

	env.pyui = pyui

	-- pytha / pyux (only what the generated templates use) ---------------
	local ELEMENT = {}
	ELEMENT.__index = ELEMENT
	function ELEMENT:get_element_type() return self.type or "part" end
	function ELEMENT:get_element_attribute(name) return self.attributes[name] end
	function ELEMENT:get_name() return self.name end

	function fake.new_element(fields)
		local element = setmetatable({ attributes = {}, type = "part" }, ELEMENT)
		for k, v in pairs(fields or {}) do element[k] = v end
		fake.elements[#fake.elements + 1] = element
		return element
	end

	local pytha = {}
	function pytha.create_block(length, width, height, origin, opts)
		assert(type(length) == "number" and type(width) == "number" and type(height) == "number", "create_block expects numbers")
		return fake.new_element({ kind = "block", size = { length, width, height }, origin = origin })
	end
	function pytha.delete_element(element) element.deleted = true end
	function pytha.set_element_name(element, name) element.name = name end
	function pytha.set_element_history(element, history, id)
		element.history = history
		element.history_id = id
	end
	function pytha.get_element_history(element)
		return element.history, element.history_id
	end
	function pytha.get_element_attribute(element, name) return element.attributes[name] end
	function pytha.enumerate_parts()
		local i = 0
		return function()
			i = i + 1
			return fake.parts[i]
		end
	end
	env.pytha = pytha

	env.pyux = {
		select_coordinate = function() return { 10, 20, 30 } end,
	}

	return fake
end

return M
