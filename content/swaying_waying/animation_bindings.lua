local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local full = {}
local rollOnly = {}
for index = 0, constants.MAX_SECTION_COUNT do
	local roll = index == 0 and constants.SWAY_ANIMATION or constants.SWAY_SECTION_ANIMATION_PREFIX .. index
	full[index] = {
		roll = roll,
		pitch = index == 0 and constants.PITCH_ANIMATION or constants.PITCH_SECTION_ANIMATION_PREFIX .. index,
		heave = index == 0 and constants.HEAVE_ANIMATION or constants.HEAVE_SECTION_ANIMATION_PREFIX .. index,
	}
	rollOnly[index] = { roll = roll }
end

local function get(index, secondary)
	local names = secondary and full[index] or rollOnly[index]
	assert(names ~= nil, "Invalid motion section index")
	return names
end

local module = { get = get }
return module
