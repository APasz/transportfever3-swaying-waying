local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local clamp = validation.clamp
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local NEUTRAL_FACTOR = 1.0
local LOWEST_COMFORT_FACTOR = 1.10
local HIGHEST_COMFORT_FACTOR = 0.90
local WORST_MAINTENANCE_FACTOR = 1.10
local MAX_VARIATION = constants.MAX_VEHICLE_VARIATION

local function comfortFactor(value, carriesPassengers)
	if not carriesPassengers or type(value) ~= "number" then
		return NEUTRAL_FACTOR
	end
	local comfort = value
	if comfort ~= comfort or comfort < 0.0 or comfort > 1.0 then
		return NEUTRAL_FACTOR
	end
	return LOWEST_COMFORT_FACTOR + (HIGHEST_COMFORT_FACTOR - LOWEST_COMFORT_FACTOR) * comfort
end

local function maintenanceFactor(value)
	if type(value) ~= "number" or value ~= value then
		return NEUTRAL_FACTOR
	end
	local condition = clamp(value, 0.0, 1.0)
	return NEUTRAL_FACTOR + (WORST_MAINTENANCE_FACTOR - NEUTRAL_FACTOR) * condition
end

local function scaleFromNeutral(factor, variation)
	if factor ~= factor then
		return NEUTRAL_FACTOR
	end
	local presentVariation = clamp(variation, 0.0, MAX_VARIATION)

	return NEUTRAL_FACTOR + (factor - NEUTRAL_FACTOR) * presentVariation
end

local module = {
	comfortFactor = comfortFactor,
	maintenanceFactor = maintenanceFactor,
	scaleFromNeutral = scaleFromNeutral,
}

return module
