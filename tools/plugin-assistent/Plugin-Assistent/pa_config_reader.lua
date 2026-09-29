-- Plugin-Assistent: reads a config.xml (element tree of pyio.parse_xml) into a
-- project. Elements the assistant does not know are kept and written back
-- unchanged. Note: pyio.parse_xml drops comments.

PA_CONFIG = {}

-- Returns project or nil, error message
function PA_CONFIG.from_document(document)
	local root = document and (document.root or document)
	if not PA_XML.is_element(root) then
		return nil, pyloc "Die Datei enthält kein XML-Element."
	end
	if root.local_name ~= "plugin" then
		return nil, string.format(pyloc "Keine PYTHA-config.xml: Das Wurzelelement heißt <%s> statt <plugin>.", root.local_name)
	end

	local project = PA_MODEL.empty_project()
	project.mode = "existing"
	project.options.help = false
	project.header_order = {}

	local schema = PA_SCHEMA.get()
	for _, element in ipairs(PA_XML.child_elements(root)) do
		if element.local_name == "header" then
			for _, field in ipairs(PA_XML.child_elements(element)) do
				if schema.header_by_key[field.local_name] and not PA_XML.has_child_elements(field) then
					project.header[field.local_name] = PA_MODEL.trim(PA_XML.text(field))
				else
					project.header_extra[#project.header_extra + 1] = field
				end
			end
		elseif element.local_name == "extension" then
			local ext = { type = PA_XML.attribute(element, "type") or "", values = {}, order = {}, extra = {}, attributes = {} }
			for key, value in pairs(element.attributes or {}) do
				if key ~= "type" then
					ext.attributes[key] = value
				end
			end
			for _, field in ipairs(PA_XML.child_elements(element)) do
				local key = field.local_name
				if ext.values[key] == nil and not PA_XML.has_child_elements(field) then
					ext.values[key] = PA_MODEL.trim(PA_XML.text(field))
					ext.order[#ext.order + 1] = key
				else
					ext.extra[#ext.extra + 1] = field
				end
			end
			project.extensions[#project.extensions + 1] = ext
		else
			project.root_extra[#project.root_extra + 1] = element
		end
	end
	return project
end
