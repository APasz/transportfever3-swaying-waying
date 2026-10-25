local enabled = ug_require("apasz_swaying_waying::/swaying_waying/curvature_probe_config.lua") as boolean
assert(type(enabled) == "boolean", "Invalid curvature probe switch")
local module: SwayingWaying.CurvatureProbe = {}
if not enabled then
    return module
end

local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger

local MAX_CARRIAGES = 4
local MAX_SAMPLES = 256
local SAMPLE_INTERVAL_MS = 100
local context = tostring({})
local selectedConsist: integer | nil = nil

local record Observation
    samples: integer
    frames: integer
    suppliedChanges: integer
    averageChanges: integer
    lastTime: integer | nil
    supplied: number | nil
    average: number | nil
end

local observations: {integer: Observation} = {}
local carriageCount = 0

local function selectedPosition(position: integer, count: integer): boolean
    if count <= MAX_CARRIAGES then
        return true
    end
    for index = 0, MAX_CARRIAGES - 1 do
        if position == math.floor(index * (count - 1) / (MAX_CARRIAGES - 1)) then
            return true
        end
    end
    return false
end

local function numberText(value: any): string
    if value == nil then
        return "unavailable"
    end
    if type(value) == "number" and (value as number) > -math.huge and (value as number) < math.huge then
        return string.format("%.9g", value as number)
    end
    return "invalid(" .. tostring(value) .. ")"
end

local function pointCurvature(landVehicleApi: Transformator.LandVehicleScriptingApi): number
    return landVehicleApi:getVehicleEdgeInfo(0.0).curvature
end

local function observe(params: TransformatorParams, average: number | nil): boolean
    local current = params.currentInfo
    local staticInfo = params.vehicleStaticInfo
    if current == nil or current.railVehicle == nil or current.vehicle == nil
        or current.landVehicle == nil or staticInfo == nil
    then
        return false
    end
    local vehicle = current.vehicle
    if selectedConsist == nil then
        if vehicle.speed == 0.0 or vehicle.carriageListLength < 2 then
            return false
        end
        selectedConsist = params.entityId
        logger.info(string.format(
            "Curvature probe begin: context=%s vehicle=%d carriages=%d maxCarriages=%d maxSamples=%d intervalMs=%d",
            context, params.entityId, vehicle.carriageListLength, MAX_CARRIAGES, MAX_SAMPLES, SAMPLE_INTERVAL_MS
        ))
    end
    if params.entityId ~= selectedConsist
        or not selectedPosition(vehicle.positionInCarriageList, vehicle.carriageListLength)
    then
        return false
    end
    local carriage = staticInfo.carriageEntity
    local observation = observations[carriage]
    if observation == nil then
        if carriageCount >= MAX_CARRIAGES then
            return false
        end
        observation = { samples = 0, frames = 0, suppliedChanges = 0, averageChanges = 0 }
        observations[carriage] = observation
        carriageCount = carriageCount + 1
    end
    local state = observation as Observation
    if state.samples >= MAX_SAMPLES then
        return false
    end
    local supplied = current.railVehicle.curvature
    state.frames = state.frames + 1
    if state.samples > 0 or state.frames > 1 then
        if supplied ~= state.supplied then
            state.suppliedChanges = state.suppliedChanges + 1
        end
        if average ~= state.average then
            state.averageChanges = state.averageChanges + 1
        end
    end
    state.supplied = supplied
    state.average = average
    local time = current.world.gameTime
    local lastTime = state.lastTime
    if lastTime ~= nil and time >= lastTime as integer and time - (lastTime as integer) < SAMPLE_INTERVAL_MS then
        return false
    end
    local succeeded, point = pcall(pointCurvature, params.landVehicleApi)
    if not succeeded then
        logger.warnOnce("curvature-probe-point-failed",
            "Curvature probe could not query point curvature for vehicle " .. params.entityId
                .. ", carriage " .. carriage .. ": " .. tostring(point))
    end
    local previous = params.previousInfo
    local previousCurvature: number | nil = nil
    local previousTime: integer | nil = nil
    if previous ~= nil then
        if previous.railVehicle ~= nil then
            previousCurvature = previous.railVehicle.curvature
        end
        if previous.world ~= nil then
            previousTime = previous.world.gameTime
        end
    end
    local facing: boolean | nil = nil
    if current.landVehicle.carriagesReversed ~= nil then
        facing = current.landVehicle.carriagesReversed[vehicle.positionInCarriageList + 1]
    end
    state.samples = state.samples + 1
    logger.info(string.format(
        "Curvature probe sample: context=%s vehicle=%d carriage=%d position=%d count=%d sample=%d time=%d previousTime=%s distance=%s speed=%s reversed=%s facing=%s supplied=%s previousSupplied=%s average40=%s point=%s frames=%d suppliedChanges=%d averageChanges=%d",
        context, params.entityId, carriage, vehicle.positionInCarriageList, vehicle.carriageListLength,
        state.samples, time, numberText(previousTime), numberText(current.landVehicle.wheelAnimationInfo.totalDist),
        numberText(vehicle.speed), tostring(current.landVehicle.reversed), tostring(facing),
        numberText(supplied), numberText(previousCurvature), numberText(average),
        succeeded and numberText(point) or "unavailable", state.frames, state.suppliedChanges, state.averageChanges
    ))
    state.lastTime = time
    state.frames = 0
    state.suppliedChanges = 0
    state.averageChanges = 0
    if state.samples == MAX_SAMPLES then
        logger.info(string.format(
            "Curvature probe complete: context=%s vehicle=%d carriage=%d samples=%d",
            context, params.entityId, carriage, state.samples
        ))
    end
    return true
end

module.observe = observe
return module
