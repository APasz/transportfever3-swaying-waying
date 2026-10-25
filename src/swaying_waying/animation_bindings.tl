local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants

local full: {integer: SwayingWaying.MotionAnimations} = {}
local rollOnly: {integer: SwayingWaying.MotionAnimations} = {}
for index = 0, constants.MAX_SECTION_COUNT do
    local roll = index == 0 and constants.SWAY_ANIMATION or constants.SWAY_SECTION_ANIMATION_PREFIX .. index
    full[index] = {
        roll = roll,
        pitch = index == 0 and constants.PITCH_ANIMATION or constants.PITCH_SECTION_ANIMATION_PREFIX .. index,
        heave = index == 0 and constants.HEAVE_ANIMATION or constants.HEAVE_SECTION_ANIMATION_PREFIX .. index,
    }
    rollOnly[index] = { roll = roll }
end

local function get(index: integer, secondary: boolean): SwayingWaying.MotionAnimations
    local names = secondary and full[index] or rollOnly[index]
    assert(names ~= nil, "Invalid motion section index")
    return names
end

local module: SwayingWaying.AnimationBindings = { get = get }
return module
