local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants

local budgets: {SwayingWaying.MemoryUsage: SwayingWaying.MemoryBudget} = {
    Low = { carriages = math.max(1, math.floor(constants.MAX_RUNTIME_VEHICLE_STATES / 4)), retention = 10000, sharedWaves = false },
    Standard = { carriages = constants.MAX_RUNTIME_VEHICLE_STATES, retention = 60000, sharedWaves = true },
    High = { carriages = constants.MAX_RUNTIME_VEHICLE_STATES * 4, retention = 300000, sharedWaves = true },
}

local function budget(mode: SwayingWaying.MemoryUsage | nil): SwayingWaying.MemoryBudget
    local choice = mode
    if choice == nil then
        choice = "Standard"
    end
    local selected = budgets[choice]
    assert(selected ~= nil, "Invalid memory usage preset")
    return selected
end

local module: SwayingWaying.MemoryPolicy = { budget = budget }
return module
