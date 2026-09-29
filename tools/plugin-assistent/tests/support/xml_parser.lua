-- Test support only: a small XML parser that returns the same table structure
-- as pyio.parse_xml in PYTHA (see the wiki page "pyio.parse_xml").
--
--   document = { root = element }
--   element  = { local_name, prefix, namespace_uri, qualified_name,
--                attributes, namespaces, children, parent, text,
--                [1], [2], ... = child nodes (strings or elements) }
--
-- Comments and processing instructions are dropped, like in PYTHA.

local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function decode(s)
	return (s:gsub("&(#?x?)(%w+);", function(kind, name)
		if kind == "" then
			return ENTITIES[name] or ("&" .. name .. ";")
		elseif kind == "#" then
			return utf8.char(tonumber(name))
		elseif kind == "#x" then
			return utf8.char(tonumber(name, 16))
		end
		return "&" .. kind .. name .. ";"
	end))
end

local function split_name(qname)
	local prefix, local_name = qname:match("^([^:]+):(.+)$")
	if prefix then
		return prefix, local_name
	end
	return "", qname
end

local function lookup_namespace(element, prefix)
	local current = element
	while current do
		if current.namespaces and current.namespaces[prefix] then
			return current.namespaces[prefix]
		end
		current = current.parent
	end
	return ""
end

local function parse_attributes(source)
	local attributes = {}
	local order = {}
	for name, quote, value in source:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do
		attributes[name] = decode(value)
		order[#order + 1] = name
	end
	return attributes, order
end

local function finish_text(element)
	local parts = {}
	for _, child in ipairs(element) do
		if type(child) == "table" then
			break
		end
		parts[#parts + 1] = child
	end
	element.text = table.concat(parts)
end

function M.parse(text)
	if text:sub(1, 3) == "\239\187\191" then
		text = text:sub(4)
	end
	local document = {}
	local stack = {}
	local position = 1
	local length = #text

	local function add_node(node)
		local top = stack[#stack]
		if top then
			top[#top + 1] = node
		elseif type(node) == "table" then
			if document.root then
				error("more than one root element")
			end
			document.root = node
		elseif node:match("%S") then
			error("text outside of the root element")
		end
	end

	while position <= length do
		local lt = text:find("<", position, true)
		if not lt then
			add_node(decode(text:sub(position)))
			break
		end
		if lt > position then
			add_node(decode(text:sub(position, lt - 1)))
		end
		if text:sub(lt, lt + 3) == "<!--" then
			local close = text:find("-->", lt + 4, true)
			if not close then error("unterminated comment") end
			position = close + 3
		elseif text:sub(lt, lt + 8) == "<![CDATA[" then
			local close = text:find("]]>", lt + 9, true)
			if not close then error("unterminated CDATA section") end
			add_node(text:sub(lt + 9, close - 1))
			position = close + 3
		elseif text:sub(lt, lt + 1) == "<?" then
			local close = text:find("?>", lt + 2, true)
			if not close then error("unterminated processing instruction") end
			position = close + 2
		elseif text:sub(lt, lt + 1) == "<!" then
			local close = text:find(">", lt + 2, true)
			if not close then error("unterminated declaration") end
			position = close + 1
		elseif text:sub(lt, lt + 1) == "</" then
			local close = text:find(">", lt + 2, true)
			if not close then error("unterminated end tag") end
			local name = text:sub(lt + 2, close - 1):match("^%s*(.-)%s*$")
			local top = table.remove(stack)
			if not top then
				error("unexpected end tag </" .. name .. ">")
			end
			if top.qualified_name ~= name then
				error("end tag </" .. name .. "> does not match <" .. top.qualified_name .. ">")
			end
			finish_text(top)
			position = close + 1
		else
			-- start tag: find the closing ">" outside of quoted attribute values
			local i = lt + 1
			local quote = nil
			while i <= length do
				local c = text:sub(i, i)
				if quote then
					if c == quote then quote = nil end
				elseif c == '"' or c == "'" then
					quote = c
				elseif c == ">" then
					break
				end
				i = i + 1
			end
			if i > length then error("unterminated start tag") end
			local inner = text:sub(lt + 1, i - 1)
			local self_closing = inner:sub(-1) == "/"
			if self_closing then
				inner = inner:sub(1, -2)
			end
			local qname, rest = inner:match("^%s*([^%s/>]+)(.*)$")
			if not qname then error("invalid start tag") end
			local raw_attributes, order = parse_attributes(rest)
			local element = { attributes = {}, namespaces = {} }
			element.children = element
			element.parent = stack[#stack]
			for _, name in ipairs(order) do
				local value = raw_attributes[name]
				if name == "xmlns" then
					element.namespaces[""] = value
				elseif name:sub(1, 6) == "xmlns:" then
					element.namespaces[name:sub(7)] = value
				else
					element.attributes[name] = value
				end
			end
			element.prefix, element.local_name = split_name(qname)
			element.qualified_name = qname
			element.namespace_uri = lookup_namespace(element, element.prefix)
			add_node(element)
			if self_closing then
				element.text = ""
			else
				stack[#stack + 1] = element
			end
			position = i + 1
		end
	end
	if #stack > 0 then
		error("unclosed element <" .. stack[#stack].qualified_name .. ">")
	end
	if not document.root then
		error("no root element")
	end
	return document
end

return M
