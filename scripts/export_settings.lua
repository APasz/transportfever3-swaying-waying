local modules = {}
ug_require = function(name)
	local relative = assert(name:match("^apasz_swaying_waying::/(.+%.lua)$"), "Unexpected resource: " .. name)
	if modules[name] == nil then
		modules[name] = dofile("content/" .. relative)
	end
	return modules[name]
end
local definitions = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").definitions
local function quote(value)
	return '"'
		.. value:gsub('[%z\1-\31\\"]', function(character)
			if character == '"' or character == "\\" then
				return "\\" .. character
			end
			return string.format("\\u%04x", string.byte(character))
		end)
		.. '"'
end
local entries = {}
for _, definition in ipairs(definitions) do
	assert(#definition.values == #definition.labels, "Setting labels must match their values")
	assert(definition.values[definition.defaultIndex] ~= nil, "Setting default must exist")
	local labels = {}
	for _, label in ipairs(definition.labels) do
		labels[#labels + 1] = quote(label)
	end
	entries[#entries + 1] = "{"
		.. '"defaultIndex":'
		.. (definition.defaultIndex - 1)
		.. ',"key":'
		.. quote(definition.key)
		.. ',"name":'
		.. quote(definition.name)
		.. ',"tooltip":'
		.. quote(definition.tooltip)
		.. ',"uiType":'
		.. quote(definition.uiType)
		.. ',"values":['
		.. table.concat(labels, ",")
		.. "]}"
end
io.write("[", table.concat(entries, ","), "]\n")
