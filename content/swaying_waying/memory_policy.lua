local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local math = _tl_compat and _tl_compat.math or math
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local budgets = {
	Low = {
		carriages = math.max(1, math.floor(constants.MAX_RUNTIME_VEHICLE_STATES / 4)),
		retention = 10000,
		sharedWaves = false,
	},
	Standard = { carriages = constants.MAX_RUNTIME_VEHICLE_STATES, retention = 60000, sharedWaves = true },
	High = { carriages = constants.MAX_RUNTIME_VEHICLE_STATES * 4, retention = 300000, sharedWaves = true },
}

local function budget(mode)
	local choice = mode
	if choice == nil then
		choice = "Standard"
	end
	local selected = budgets[choice]
	assert(selected ~= nil, "Invalid memory usage preset")
	return selected
end

local module = { budget = budget }
return module
