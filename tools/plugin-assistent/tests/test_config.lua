local tests = {}

local xml_parser = require("support.xml_parser")

local function read_config(env, T, text)
	local project, err = env.PA_CONFIG.from_document(xml_parser.parse(text))
	T.ok(project, err)
	return project
end

tests["config.xml of a new project matches the reference file"] = function(T)
	local env = T.new_env()
	local M = env.PA_MODEL
	local project = M.new_project("Mein Regal")
	project.header.guid = "3f2d1456-960c-489c-abfd-0cab1cd5644c"
	project.header.description = "Regal mit Fachböden & Rückwand <variabel>."
	project.header.licensing = "Copyright (c) 2026. All rights reserved."
	M.set_template(project, "generator")
	local attribute = M.new_extension(project, "attribute")
	attribute.values.caption = "Regalbreite"
	M.add_extension(project, attribute)
	local expected = T.read_file(T.tests_dir .. "/expected/config_reference.xml")
	T.eq(table.concat(env.PA_XML.config_lines(project), "\n") .. "\n", expected)
end

tests["multi-line texts are written and read back"] = function(T)
	local env = T.new_env()
	local project = env.PA_MODEL.new_project("Text")
	project.header.description = "Zeile 1\nZeile 2\n  eingerückt"
	local text = table.concat(env.PA_XML.config_lines(project), "\n")
	local again = read_config(env, T, text)
	T.eq(again.header.description, "Zeile 1\nZeile 2\n  eingerückt")
end

tests["unknown elements and attributes are kept"] = function(T)
	local env = T.new_env()
	local text = [[<?xml version="1.0" encoding="UTF-8"?>
<plugin xmlns="http://xmlns.pytha.com/plugin_config/1.0">
  <header>
    <guid>3f2d1456-960c-489c-abfd-0cab1cd5644c</guid>
    <name>Test</name>
    <author>Jemand</author>
  </header>
  <extension type="function" experimental="yes">
    <entry-point>main</entry-point>
    <caption>Test</caption>
    <icon size="16">icon.png</icon>
    <options><option name="a">1</option></options>
  </extension>
  <extension type="future-type">
    <entry-point>go</entry-point>
    <speed>fast</speed>
  </extension>
  <settings enabled="true"/>
</plugin>]]
	local project = read_config(env, T, text)
	T.eq(project.header.name, "Test")
	T.eq(#project.header_extra, 1)
	T.eq(project.extensions[1].attributes.experimental, "yes")
	T.eq(project.extensions[1].values.icon, "icon.png")
	T.eq(#project.extensions[1].extra, 1, "nested element kept as extra")
	T.eq(project.extensions[2].type, "future-type")
	T.eq(project.extensions[2].values.speed, "fast")
	T.eq(#project.root_extra, 1)

	local written = table.concat(env.PA_XML.config_lines(project), "\n")
	T.contains(written, "<author>Jemand</author>")
	T.contains(written, '<extension type="function" experimental="yes">')
	T.contains(written, "<icon>icon.png</icon>")
	T.contains(written, '<option name="a">1</option>')
	T.contains(written, '<extension type="future-type">')
	T.contains(written, "<speed>fast</speed>")
	T.contains(written, '<settings enabled="true"/>')
	local again = read_config(env, T, written)
	T.eq(again.extensions[2].values, project.extensions[2].values)
end

tests["special characters are escaped"] = function(T)
	local env = T.new_env()
	local project = env.PA_MODEL.new_project("A & B <C>")
	local text = table.concat(env.PA_XML.config_lines(project), "\n")
	T.contains(text, "<name>A &amp; B &lt;C&gt;</name>")
	local again = read_config(env, T, text)
	T.eq(again.header.name, "A & B <C>")
end

tests["not a plugin config"] = function(T)
	local env = T.new_env()
	local project, err = env.PA_CONFIG.from_document(xml_parser.parse("<xliff/>"))
	T.eq(project, nil)
	T.contains(err, "<xliff>")
end

tests["all sample config.xml files survive a round trip"] = function(T)
	local env = T.new_env()
	local folders = T.sample_folders()
	T.ok(#folders >= 18, "found the sample plugins")
	for _, folder in ipairs(folders) do
		local text = T.read_file(T.samples_dir .. "/" .. folder .. "/config.xml")
		local project = read_config(env, T, text)
		local written = table.concat(env.PA_XML.config_lines(project), "\n")
		local again = read_config(env, T, written)
		T.eq(again.header, project.header, folder .. ": header")
		T.eq(#again.extensions, #project.extensions, folder .. ": number of extensions")
		for index, ext in ipairs(project.extensions) do
			T.eq(again.extensions[index].type, ext.type, folder .. ": type")
			T.eq(again.extensions[index].values, ext.values, folder .. ": values of extension " .. index)
		end
	end
end

tests["sample values are read correctly"] = function(T)
	local env = T.new_env()
	local project = read_config(env, T, T.read_file(T.samples_dir .. "/Spiral Stairs 1/config.xml"))
	T.eq(project.header.guid, "25fb669b-975b-41d3-9c15-72507fc05d67")
	T.eq(project.extensions[2].type, "edit")
	T.eq(project.extensions[2].values.id, "spiral_stairs_history")
	T.eq(project.extensions[2].values["help-file"], "help.html")

	local kitchen = read_config(env, T, T.read_file(T.samples_dir .. "/Kitchen Wizard/config.xml"))
	T.eq(#kitchen.extensions, 2, "commented extensions are not read (as in pyio.parse_xml)")
end

return tests
