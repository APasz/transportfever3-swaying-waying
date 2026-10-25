local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pairs = _tl_compat and _tl_compat.pairs or pairs
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua")

local function read(params)
	return (params.transformatorConfigParams)[constants.RUNTIME_PARAM]
end

local function validate(value)
	assert(value.schema == constants.RUNTIME_SCHEMA, "Unsupported Swaying Waying runtime schema")
	assert(type(value.modelFile) == "string" and value.modelFile ~= "", "Missing runtime model identity")
	assert(
		type(value.originalTransformator) == "string" and value.originalTransformator ~= "",
		"Missing original transformator"
	)
	assert(validation.positiveInteger(value.revision) ~= nil, "Invalid runtime configuration revision")
	assert(value.carrier == "RAIL" or value.carrier == "TRAM", "Invalid runtime carrier")
	assert(
		value.profile == "DEFAULT" or value.profile == "QUICK" or value.profile == "SLOW",
		"Invalid runtime motion profile"
	)
	assert(type(value.axisReversed) == "boolean", "Invalid model axis orientation")
	assert(validation.nonnegative(value.vehicleFactor), "Invalid vehicle response factor")
	assert(validation.wheelbase(value.wheelbase), "Invalid runtime wheelbase")
	assert(type(value.settings) == "table", "Missing runtime settings")
	local resolved = settings.resolve(value.settings)
	for key, expected in pairs(resolved) do
		assert((value.settings)[key] == expected, "Missing runtime setting: " .. key)
	end
	local sections = validation.asTable(value.sections)
	assert(sections ~= nil, "Missing runtime sections")
	local count = validation.arraySize(sections)
	assert(count ~= nil and count <= constants.MAX_SECTION_COUNT, "Invalid runtime section array")
	for _, section in ipairs(value.sections) do
		assert(type(section) == "table" and validation.nonnegative(section.lag), "Invalid runtime section lag")
		assert(validation.wheelbase(section.wheelbase), "Invalid runtime section wheelbase")
	end
	return resolved
end

local module = { read = read, validate = validate }
return module
