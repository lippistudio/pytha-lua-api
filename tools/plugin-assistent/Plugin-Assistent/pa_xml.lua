-- Plugin-Assistent: XML helpers and the config.xml writer.
--
-- Reading uses the element trees of pyio.parse_xml. Writing produces plain text
-- lines (written with pyio.write_lines), so the output keeps the layout of the
-- wiki examples and the samples.

PA_XML = {}

function PA_XML.escape_text(text)
	return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function PA_XML.escape_attribute(text)
	return (PA_XML.escape_text(text):gsub('"', "&quot;"))
end

-- Splits a text into lines (accepts \r\n and \n); a final line break is ignored.
function PA_XML.split_lines(text)
	text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if #lines > 1 and lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

-- Element trees (pyio.parse_xml) ----------------------------------------------

function PA_XML.is_element(node)
	return type(node) == "table" and type(node.local_name) == "string"
end

function PA_XML.children(element)
	return element.children or element
end

function PA_XML.child_elements(element, name)
	local result = {}
	for _, child in ipairs(PA_XML.children(element)) do
		if PA_XML.is_element(child) and (name == nil or child.local_name == name) then
			result[#result + 1] = child
		end
	end
	return result
end

function PA_XML.has_child_elements(element)
	for _, child in ipairs(PA_XML.children(element)) do
		if PA_XML.is_element(child) then
			return true
		end
	end
	return false
end

-- Concatenated text content of the direct text children (not trimmed)
function PA_XML.text(element)
	local parts = {}
	local found = false
	for _, child in ipairs(PA_XML.children(element)) do
		if type(child) == "string" then
			parts[#parts + 1] = child
			found = true
		end
	end
	if not found and type(element.text) == "string" then
		return element.text
	end
	return table.concat(parts)
end

function PA_XML.attribute(element, name)
	return element.attributes and element.attributes[name] or nil
end

local function sorted_keys(map)
	local keys = {}
	for key in pairs(map or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function qualified_name(element)
	if element.prefix and element.prefix ~= "" then
		return element.prefix .. ":" .. element.local_name
	end
	return element.local_name
end

local function attribute_text(element, skip)
	local parts = {}
	for _, prefix in ipairs(sorted_keys(element.namespaces)) do
		local name = prefix == "" and "xmlns" or ("xmlns:" .. prefix)
		parts[#parts + 1] = string.format(' %s="%s"', name, PA_XML.escape_attribute(element.namespaces[prefix]))
	end
	for _, key in ipairs(sorted_keys(element.attributes)) do
		if not (skip and skip[key]) then
			parts[#parts + 1] = string.format(' %s="%s"', key, PA_XML.escape_attribute(element.attributes[key]))
		end
	end
	return table.concat(parts)
end

-- Appends a text element, e.g. <name>value</name>; multi-line values span lines.
local function add_text_element(lines, indent, name, value)
	local text_lines = PA_XML.split_lines(PA_XML.escape_text(value))
	if #text_lines == 1 then
		lines[#lines + 1] = string.format("%s<%s>%s</%s>", indent, name, text_lines[1], name)
		return
	end
	lines[#lines + 1] = string.format("%s<%s>%s", indent, name, text_lines[1])
	for i = 2, #text_lines - 1 do
		lines[#lines + 1] = text_lines[i]
	end
	lines[#lines + 1] = string.format("%s</%s>", text_lines[#text_lines], name)
end

-- Writes an element tree that the assistant does not interpret (kept unchanged).
function PA_XML.serialize(element, indent, lines)
	lines = lines or {}
	indent = indent or ""
	local name = qualified_name(element)
	local attributes = attribute_text(element)
	if not PA_XML.has_child_elements(element) then
		local text = PA_XML.text(element)
		if text:match("^%s*$") then
			lines[#lines + 1] = string.format("%s<%s%s/>", indent, name, attributes)
		else
			local text_lines = PA_XML.split_lines(PA_XML.escape_text(text))
			if #text_lines == 1 then
				lines[#lines + 1] = string.format("%s<%s%s>%s</%s>", indent, name, attributes, text_lines[1], name)
			else
				lines[#lines + 1] = string.format("%s<%s%s>%s", indent, name, attributes, text_lines[1])
				for i = 2, #text_lines - 1 do
					lines[#lines + 1] = text_lines[i]
				end
				lines[#lines + 1] = string.format("%s</%s>", text_lines[#text_lines], name)
			end
		end
		return lines
	end
	lines[#lines + 1] = string.format("%s<%s%s>", indent, name, attributes)
	for _, child in ipairs(PA_XML.children(element)) do
		if PA_XML.is_element(child) then
			PA_XML.serialize(child, indent .. "  ", lines)
		elseif type(child) == "string" and child:match("%S") then
			lines[#lines + 1] = indent .. "  " .. PA_XML.escape_text(PA_MODEL.trim(child))
		end
	end
	lines[#lines + 1] = string.format("%s</%s>", indent, name)
	return lines
end

-- config.xml --------------------------------------------------------------------

local function ordered_value_keys(ext)
	local keys, seen = {}, {}
	local info = PA_SCHEMA.type_info(ext.type)
	if info then
		for _, field in ipairs(info.fields) do
			keys[#keys + 1] = field.key
			seen[field.key] = true
		end
	end
	for _, key in ipairs(ext.order or {}) do
		if not seen[key] then
			keys[#keys + 1] = key
			seen[key] = true
		end
	end
	for _, key in ipairs(sorted_keys(ext.values)) do
		if not seen[key] then
			keys[#keys + 1] = key
			seen[key] = true
		end
	end
	return keys
end

-- The complete config.xml as a list of lines
function PA_XML.config_lines(project)
	local lines = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		string.format('<plugin xmlns="%s">', PA_SCHEMA.NAMESPACE),
		"",
		"  <header>",
	}
	for _, field in ipairs(PA_SCHEMA.get().header_fields) do
		local value = PA_MODEL.trim(project.header[field.key])
		if value ~= "" then
			add_text_element(lines, "    ", field.key, value)
		end
	end
	for _, element in ipairs(project.header_extra or {}) do
		PA_XML.serialize(element, "    ", lines)
	end
	lines[#lines + 1] = "  </header>"

	for _, ext in ipairs(project.extensions) do
		lines[#lines + 1] = ""
		local extra_attributes = ""
		for _, key in ipairs(sorted_keys(ext.attributes)) do
			if key ~= "type" then
				extra_attributes = extra_attributes .. string.format(' %s="%s"', key, PA_XML.escape_attribute(ext.attributes[key]))
			end
		end
		lines[#lines + 1] = string.format('  <extension type="%s"%s>', PA_XML.escape_attribute(ext.type), extra_attributes)
		for _, key in ipairs(ordered_value_keys(ext)) do
			local value = PA_MODEL.trim(ext.values[key])
			if value ~= "" then
				add_text_element(lines, "    ", key, value)
			end
		end
		for _, element in ipairs(ext.extra or {}) do
			PA_XML.serialize(element, "    ", lines)
		end
		lines[#lines + 1] = "  </extension>"
	end

	for _, element in ipairs(project.root_extra or {}) do
		lines[#lines + 1] = ""
		PA_XML.serialize(element, "  ", lines)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "</plugin>"
	return lines
end
