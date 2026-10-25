local enabled = ug_require("apasz_swaying_waying::/swaying_waying/lod_probe_config.lua") as boolean
assert(type(enabled) == "boolean", "Invalid LOD probe switch")
local module: SwayingWaying.LodProbe = {}
if not enabled then
    return module
end

local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local MAX_SAMPLES = 48
local CALLBACK_INTERVAL = 64
local context = tostring({})
local selectedCarriage: integer | nil = nil
local callbacks = 0
local samples = 0

local function describeKeys(value: any): string
    local keys: {string} = {}
    for key, item in pairs(value as SwayingWaying.RawTable) do
        local description = type(item)
        if type(item) == "number" or type(item) == "boolean" then
            description = tostring(item)
        end
        keys[#keys + 1] = tostring(key) .. ":" .. description
    end
    table.sort(keys)
    return "[" .. table.concat(keys, ",") .. "]"
end

local function keyInventory(value: any): string
    local succeeded, result = pcall(describeKeys, value)
    return succeeded and result as string or "unavailable"
end

local function userTransformInfo(output: Transformator.TransfOutput): string
    local transforms = output:getUserTransfs()
    local counts: {integer: integer} = {}
    for _, transform in ipairs(transforms) do
        counts[transform.type] = (counts[transform.type] or 0) + 1
    end
    local kinds: {integer} = {}
    for kind in pairs(counts) do
        kinds[#kinds + 1] = kind
    end
    table.sort(kinds)
    local descriptions: {string} = {}
    for _, kind in ipairs(kinds) do
        descriptions[#descriptions + 1] = kind .. ":" .. counts[kind]
    end
    return string.format("%d[%s]", #transforms, table.concat(descriptions, ","))
end

local function animationInfo(output: Transformator.TransfOutput): string
    local names: {string} = {}
    for _, state in ipairs(output:getAnimationStates()) do
        names[#names + 1] = state.animation
    end
    table.sort(names)
    return "[" .. table.concat(names, ",") .. "]"
end

local function observe(params: TransformatorParams, output: Transformator.TransfOutput, modelFile: string): boolean
    if samples >= MAX_SAMPLES then
        return false
    end
    local current, staticInfo = params.currentInfo, params.vehicleStaticInfo
    if current == nil or current.vehicle == nil or staticInfo == nil then
        return false
    end
    if selectedCarriage == nil then
        if current.vehicle.positionInCarriageList ~= 0 then
            return false
        end
        selectedCarriage = staticInfo.carriageEntity
        logger.info(string.format(
            "LOD probe begin: context=%s vehicle=%d carriage=%d model=%s maxSamples=%d callbackInterval=%d",
            context, params.entityId, staticInfo.carriageEntity, modelFile, MAX_SAMPLES, CALLBACK_INTERVAL
        ))
        logger.info(string.format(
            "LOD probe inventory: context=%s params=%s current=%s world=%s static=%s modelInfo=%s metadata=%s",
            context, keyInventory(params), keyInventory(current), keyInventory(current.world),
            keyInventory(staticInfo), keyInventory(staticInfo.modelInfo), keyInventory(params.modelMetadataInfo)
        ))
    end
    if staticInfo.carriageEntity ~= selectedCarriage then
        return false
    end
    callbacks = callbacks + 1
    -- Callback cadence also works while the simulation is paused for zoom tests.
    if (callbacks - 1) % CALLBACK_INTERVAL ~= 0 then
        return false
    end
    local haveTransforms, transforms = pcall(userTransformInfo, output)
    local haveAnimations, animations = pcall(animationInfo, output)
    if not haveTransforms then
        logger.warnOnce("lod-probe-transforms-failed",
            "LOD probe could not inspect native transforms for " .. modelFile .. ": " .. tostring(transforms))
    end
    if not haveAnimations then
        logger.warnOnce("lod-probe-animations-failed",
            "LOD probe could not inspect native animations for " .. modelFile .. ": " .. tostring(animations))
    end
    samples = samples + 1
    logger.info(string.format(
        "LOD probe sample: context=%s vehicle=%d carriage=%d model=%s sample=%d callback=%d time=%d transforms=%s nativeAnimations=%s params=%s current=%s world=%s",
        context, params.entityId, staticInfo.carriageEntity, modelFile, samples, callbacks, current.world.gameTime,
        haveTransforms and transforms as string or "unavailable", haveAnimations and animations as string or "unavailable",
        keyInventory(params), keyInventory(current), keyInventory(current.world)
    ))
    if samples == MAX_SAMPLES then
        logger.info(string.format("LOD probe complete: context=%s carriage=%d samples=%d", context, staticInfo.carriageEntity, samples))
    end
    return true
end

module.observe = observe
return module
