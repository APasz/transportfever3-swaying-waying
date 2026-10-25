local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local math = _tl_compat and _tl_compat.math or math
local pairs = _tl_compat and _tl_compat.pairs or pairs
local string = _tl_compat and _tl_compat.string or string
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local function dynamicTable(value)
	if type(value) == "table" then
		return value
	end
	return nil
end

local function dynamicArray(value)
	if type(value) == "table" then
		return value
	end
	return nil
end

local function safeNodeSuffix(name)
	return (name:gsub("[^%w_]", "_"))
end

local function validLag(value)
	return type(value) == "number" and value >= 0.0 and value < math.huge
end

local function validWheelbase(value)
	return type(value) == "number" and value >= constants.MIN_WHEELBASE and value <= constants.MAX_WHEELBASE
end

local function positiveInteger(value)
	if type(value) == "number" and value >= 1.0 and value < math.huge and value == math.floor(value) then
		return value
	end
	return nil
end

local function denseArraySize(value)
	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1.0 or key ~= math.floor(key) then
			return nil
		end
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil then
			return nil
		end
	end
	return count
end

local function clamp(value, minimum, maximum)
	if value ~= value or value <= minimum then
		return minimum
	elseif value >= maximum then
		return maximum
	end
	return value
end

local module = {
	asTable = dynamicTable,
	clamp = clamp,
	asArray = dynamicArray,
	nodeSuffix = safeNodeSuffix,
	nonnegative = validLag,
	wheelbase = validWheelbase,
	positiveInteger = positiveInteger,
	arraySize = denseArraySize,
}
return module
