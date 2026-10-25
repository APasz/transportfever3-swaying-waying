local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local clamp = validation.clamp
local cache = ug_require("apasz_swaying_waying::/swaying_waying/bounded_cache.lua") as SwayingWaying.Cache
local constants = ug_require(
    "apasz_swaying_waying::/swaying_waying/constants.lua"
) as SwayingWaying.Constants
local logger = ug_require(
    "apasz_swaying_waying::/swaying_waying/logger.lua"
) as SwayingWaying.Logger

local record TrackState
    purchaseTime: integer
    hasNormal: boolean
    normalSpeedLimit: number
    normalFactor: number
    hasOutput: boolean
    outputFactor: number
    outputShortWeight: number
    distance: number
    sampleDistance: number
    hasTarget: boolean
    targetFactor: number
    targetShortWeight: number
    inferenceFailed: boolean
    inferenceDistance: number
end

local record NormalTrackCandidate
    speedLimit: number
    categories: {string}
end

local SLOW_TRACK_SPEED = 100.0 / 3.6
local STANDARD_TRACK_SPEED = 160.0 / 3.6
local HIGH_SPEED_TRACK_SPEED = 350.0 / 3.6
local MIN_COMBINED_FACTOR = 0.35
local MAX_COMBINED_FACTOR = 2.0
local TRANSITION_DISTANCE = 30.0
local FAILED_INFERENCE_RETRY_DISTANCE = 100.0
local MAX_EDGE_SCAN_COUNT = 64
local MAX_EDGE_SCAN_DISTANCE = 2000.0
local NORMAL_EDGE_SAMPLE_INSET = 5.0
local ROUGH_SHORT_WEIGHT = 0.80
local NEUTRAL_SHORT_WEIGHT = constants.NEUTRAL_TRACK_SHORT_WEIGHT
local SMOOTH_SHORT_WEIGHT = 0.45
local MAX_TRACK_INFLUENCE = constants.MAX_TRACK_INFLUENCE

-- Transformator scripts can run in multiple isolated Lua contexts. Each context
-- keeps a bounded hint cache; cold structure loads still use adjacent-edge data.
local trackStates: SwayingWaying.BoundedCache<integer, TrackState> = cache.create(constants.MAX_RUNTIME_VEHICLE_STATES)

local function smoothStep(value: number): number
    local ratio = clamp(value, 0.0, 1.0)
    return ratio * ratio * (3.0 - 2.0 * ratio)
end

local function interpolate(
    value: number,
    lowerValue: number,
    upperValue: number,
    lowerFactor: number,
    upperFactor: number
): number
    local ratio = smoothStep(
        (value - lowerValue) / (upperValue - lowerValue)
    )
    return lowerFactor + (upperFactor - lowerFactor) * ratio
end

local function speedLimitFactor(speedLimit: number): number
    if speedLimit ~= speedLimit or speedLimit <= 0.0 or speedLimit == math.huge then
        return 1.0
    elseif speedLimit <= SLOW_TRACK_SPEED then
        return constants.ROUGH_FACTOR
    elseif speedLimit < STANDARD_TRACK_SPEED then
        return interpolate(
            speedLimit,
            SLOW_TRACK_SPEED,
            STANDARD_TRACK_SPEED,
            constants.ROUGH_FACTOR,
            1.0
        )
    elseif speedLimit < HIGH_SPEED_TRACK_SPEED then
        return interpolate(
            speedLimit,
            STANDARD_TRACK_SPEED,
            HIGH_SPEED_TRACK_SPEED,
            1.0,
            constants.SMOOTH_FACTOR
        )
    end
    return constants.SMOOTH_FACTOR
end

local function shortWeightForFactor(factor: number): number
    if factor >= constants.ROUGH_FACTOR then
        return ROUGH_SHORT_WEIGHT
    elseif factor > 1.0 then
        local ratio = (factor - 1.0) / (constants.ROUGH_FACTOR - 1.0)
        return NEUTRAL_SHORT_WEIGHT
            + (ROUGH_SHORT_WEIGHT - NEUTRAL_SHORT_WEIGHT) * ratio
    elseif factor > constants.SMOOTH_FACTOR then
        local ratio = (factor - constants.SMOOTH_FACTOR)
            / (1.0 - constants.SMOOTH_FACTOR)
        return SMOOTH_SHORT_WEIGHT
            + (NEUTRAL_SHORT_WEIGHT - SMOOTH_SHORT_WEIGHT) * ratio
    end
    return SMOOTH_SHORT_WEIGHT
end

local function categoryFactor(
    categories: {string} | nil,
    automaticFactor: number
): number, boolean
    if categories == nil then
        return automaticFactor, false
    end

    local rough = false
    local smooth = false
    local rougher = false
    local smoother = false
    for _, category in ipairs(categories as {string}) do
        if category == constants.TRACK_ROUGH_TAG then
            rough = true
        elseif category == constants.TRACK_SMOOTH_TAG then
            smooth = true
        elseif category == constants.ROUGHER_TAG then
            rougher = true
        elseif category == constants.SMOOTHER_TAG then
            smoother = true
        end
    end

    if rough and smooth then
        logger.warnOnce(
            "track-profile-conflict",
            "Ignoring conflicting swaying_waying_rough and "
                .. "swaying_waying_smooth track categories"
        )
        return automaticFactor, false
    elseif rough then
        return constants.ROUGH_FACTOR, true
    elseif smooth then
        return constants.SMOOTH_FACTOR, true
    end

    if rougher and smoother then
        logger.warnOnce(
            "track-modifier-conflict",
            "Ignoring conflicting swaying_waying_rougher and "
                .. "swaying_waying_smoother track categories"
        )
        return automaticFactor, false
    elseif rougher then
        return automaticFactor * constants.ROUGH_FACTOR, true
    elseif smoother then
        return automaticFactor * constants.SMOOTH_FACTOR, true
    end
    return automaticFactor, false
end

local function baseEdgeInfo(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    edgeOffset: integer
): Transformator.BaseEdgeInfo | nil
    local succeeded, result = pcall(
        landVehicleApi.getBaseEdgeInfo,
        landVehicleApi,
        edgeOffset
    )
    if not succeeded then
        logger.warnOnce("track-base-query-failed",
            "Using fallback track response after getBaseEdgeInfo failed at offset "
                .. edgeOffset .. ": " .. tostring(result))
        return nil
    end
    if result == nil then
        return nil
    end
    return result as Transformator.BaseEdgeInfo
end

local function vehicleEdgeInfo(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    offset: number
): Transformator.VehicleEdgeInfo | nil
    local succeeded, result = pcall(
        landVehicleApi.getVehicleEdgeInfo,
        landVehicleApi,
        offset
    )
    if not succeeded then
        logger.warnOnce("track-vehicle-query-failed",
            "Using fallback track response after getVehicleEdgeInfo failed at offset "
                .. offset .. ": " .. tostring(result))
        return nil
    end
    if result == nil then
        return nil
    end
    return result as Transformator.VehicleEdgeInfo
end

local function isValidBaseEdge(info: Transformator.BaseEdgeInfo): boolean
    return info.edgeOffsetClampedToEdgesCount >= 0
end

local function isNormalWay(info: Transformator.BaseEdgeInfo): boolean
    return isValidBaseEdge(info) and info.onBaseEdge and info.baseEdgeType == 0
end

local function sampledSpeedLimit(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    direction: integer,
    lowerDistance: number,
    upperDistance: number
): number
    -- The API exposes the current base-edge length, but not the vehicle's offset
    -- along it. Sampling the possible boundary interval and taking its highest
    -- limit recovers the surrounding line speed from a restricted structure.
    local best = 0.0
    for sampleIndex = 0, 2 do
        local ratio = sampleIndex / 2.0
        local distance = lowerDistance
            + (upperDistance - lowerDistance) * ratio
        local info = vehicleEdgeInfo(landVehicleApi, direction * distance)
        if info ~= nil then
            best = math.max(best, (info as Transformator.VehicleEdgeInfo).speedLimit)
        end
    end
    return best
end

local function adjacentNormalTrack(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    current: Transformator.BaseEdgeInfo,
    direction: integer
): NormalTrackCandidate | nil
    local currentLength = math.max(current.length, 0.0)
    local interveningLength = 0.0
    for edgeDistance = 1, MAX_EDGE_SCAN_COUNT do
        local edgeOffset = direction * edgeDistance
        local candidate = baseEdgeInfo(landVehicleApi, edgeOffset)
        if candidate == nil then
            return nil
        end
        local present = candidate as Transformator.BaseEdgeInfo
        if not isValidBaseEdge(present) then
            return nil
        end
        if isNormalWay(present) then
            local lowerDistance = interveningLength
                + math.min(NORMAL_EDGE_SAMPLE_INSET, present.length * 0.5)
            local upperDistance = interveningLength
                + currentLength
                + math.min(NORMAL_EDGE_SAMPLE_INSET, present.length * 0.5)
            local speedLimit = sampledSpeedLimit(
                landVehicleApi,
                direction,
                lowerDistance,
                upperDistance
            )
            if speedLimit ~= speedLimit or speedLimit <= 0.0 or speedLimit == math.huge then
                return nil
            end
            return {
                speedLimit = speedLimit,
                categories = present.streetCategories or {},
            }
        end
        interveningLength = interveningLength + math.max(present.length, 0.0)
        if interveningLength > MAX_EDGE_SCAN_DISTANCE then
            return nil
        end
    end
    return nil
end

local function inferredNormalTrack(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    current: Transformator.BaseEdgeInfo
): NormalTrackCandidate | nil
    local behind = adjacentNormalTrack(landVehicleApi, current, -1)
    local ahead = adjacentNormalTrack(landVehicleApi, current, 1)
    if behind == nil then
        return ahead
    elseif ahead == nil then
        return behind
    elseif (ahead as NormalTrackCandidate).speedLimit
        > (behind as NormalTrackCandidate).speedLimit
    then
        return ahead
    end
    return behind
end

local function newTrackState(purchaseTime: integer): TrackState
    return {
        purchaseTime = purchaseTime,
        hasNormal = false,
        normalSpeedLimit = 0.0,
        normalFactor = 1.0,
        hasOutput = false,
        outputFactor = 1.0,
        outputShortWeight = NEUTRAL_SHORT_WEIGHT,
        distance = 0.0,
        sampleDistance = 0.0,
        hasTarget = false,
        targetFactor = 1.0,
        targetShortWeight = NEUTRAL_SHORT_WEIGHT,
        inferenceFailed = false,
        inferenceDistance = 0.0,
    }
end

local function stateFor(
    carriageEntity: integer,
    purchaseTime: integer
): TrackState
    local state = cache.get(trackStates, carriageEntity)
    if state ~= nil and (state as TrackState).purchaseTime == purchaseTime then
        return state as TrackState
    end
    local created = newTrackState(purchaseTime)
    cache.put(trackStates, carriageEntity, created)
    return created
end

local function targetFactor(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    state: TrackState,
    distance: number
): number
    local currentBase = baseEdgeInfo(landVehicleApi, 0)
    local currentVehicle: Transformator.VehicleEdgeInfo | nil = nil
    if currentBase ~= nil and isNormalWay(currentBase as Transformator.BaseEdgeInfo)
    then
        currentVehicle = vehicleEdgeInfo(landVehicleApi, 0.0)
        if currentVehicle ~= nil
            and (currentVehicle as Transformator.VehicleEdgeInfo).speedLimit > 0.0
        then
            local speedLimit = (currentVehicle as Transformator.VehicleEdgeInfo).speedLimit
            local resolved = categoryFactor(
                (currentBase as Transformator.BaseEdgeInfo).streetCategories,
                speedLimitFactor(speedLimit)
            )
            state.hasNormal = true
            state.normalSpeedLimit = speedLimit
            state.normalFactor = resolved
            return resolved
        end
    end

    local currentCategories: {string} | nil = nil
    if currentBase ~= nil
        and isValidBaseEdge(currentBase as Transformator.BaseEdgeInfo)
    then
        currentCategories = (currentBase as Transformator.BaseEdgeInfo).streetCategories
    end
    if state.hasNormal then
        local resolved, hasOverride = categoryFactor(
            currentCategories,
            speedLimitFactor(state.normalSpeedLimit)
        )
        if hasOverride then
            return resolved
        end
        return state.normalFactor
    end

    if currentBase ~= nil
        and isValidBaseEdge(currentBase as Transformator.BaseEdgeInfo)
        and (not state.inferenceFailed
            or math.abs(distance - state.inferenceDistance) >= FAILED_INFERENCE_RETRY_DISTANCE)
    then
        state.inferenceDistance = distance
        local inferred = inferredNormalTrack(
            landVehicleApi,
            currentBase as Transformator.BaseEdgeInfo
        )
        state.inferenceFailed = inferred == nil
        if inferred ~= nil then
            local present = inferred as NormalTrackCandidate
            local inferredFactor = categoryFactor(
                present.categories,
                speedLimitFactor(present.speedLimit)
            )
            state.hasNormal = true
            state.normalSpeedLimit = present.speedLimit
            state.normalFactor = inferredFactor
            local resolved, hasOverride = categoryFactor(
                currentCategories,
                speedLimitFactor(present.speedLimit)
            )
            if hasOverride then
                return resolved
            end
            return inferredFactor
        end
    end

    if currentVehicle == nil then
        currentVehicle = vehicleEdgeInfo(landVehicleApi, 0.0)
    end
    if currentVehicle ~= nil then
        local speedLimit = (currentVehicle as Transformator.VehicleEdgeInfo).speedLimit
        local resolved = categoryFactor(
            currentCategories,
            speedLimitFactor(speedLimit)
        )
        return resolved
    end
    return 1.0
end

local function response(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    carriageEntity: integer,
    purchaseTime: integer,
    distance: number,
    samplingDistance: number
): number, number
    assert(distance > -math.huge and distance < math.huge, "Invalid track sampling distance")
    assert(samplingDistance >= 0.0 and samplingDistance < math.huge, "Invalid track sampling interval")
    local state = stateFor(carriageEntity, purchaseTime)
    if not state.hasTarget or math.abs(distance - state.sampleDistance) >= samplingDistance then
        state.targetFactor = targetFactor(landVehicleApi, state, distance)
        state.targetShortWeight = shortWeightForFactor(state.targetFactor)
        state.sampleDistance = distance
        state.hasTarget = true
    end
    local target = state.targetFactor
    local targetShortWeight = state.targetShortWeight
    if not state.hasOutput then
        state.hasOutput = true
        state.outputFactor = target
        state.outputShortWeight = targetShortWeight
    elseif distance ~= state.distance
        and (target ~= state.outputFactor or targetShortWeight ~= state.outputShortWeight)
    then
        local distanceDelta = math.abs(distance - state.distance)
        local blend = 1.0 - math.exp(-distanceDelta / TRANSITION_DISTANCE)
        state.outputFactor = state.outputFactor
            + (target - state.outputFactor) * blend
        state.outputShortWeight = state.outputShortWeight
            + (targetShortWeight - state.outputShortWeight) * blend
    end
    state.distance = distance
    return state.outputFactor, state.outputShortWeight
end

local function factor(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    carriageEntity: integer,
    purchaseTime: integer,
    distance: number,
    samplingDistance: number
): number
    local outputFactor = response(
        landVehicleApi,
        carriageEntity,
        purchaseTime,
        distance,
        samplingDistance
    )
    return outputFactor
end

local function combinedFactor(
    trackFactor: number,
    vehicleFactor: number
): number
    return clamp(
        trackFactor * vehicleFactor,
        MIN_COMBINED_FACTOR,
        MAX_COMBINED_FACTOR
    )
end

local function applyInfluence(
    responseFactor: number,
    shortWeight: number,
    influence: number
): number, number
    local presentInfluence = clamp(
        influence,
        0.0,
        MAX_TRACK_INFLUENCE
    )
    return 1.0 + (responseFactor - 1.0) * presentInfluence,
        NEUTRAL_SHORT_WEIGHT
            + (shortWeight - NEUTRAL_SHORT_WEIGHT) * presentInfluence
end

local module: SwayingWaying.TrackResponse = {
    speedLimitFactor = speedLimitFactor,
    shortWeightForFactor = shortWeightForFactor,
    combinedFactor = combinedFactor,
    applyInfluence = applyInfluence,
    factor = factor,
    response = response,
}

return module
