local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants

local CURVATURE_WINDOW = 40.0
local LATERAL_ACCELERATION_SCALE = 1.2
local FULL_CURVE_RADIUS = 1000.0

local function swayFactor(curvature: number | nil, balance: number): number
    if curvature == nil then
        return 1.0
    end
    local curved = math.min(math.abs(curvature as number) * FULL_CURVE_RADIUS, 1.0)
    local straightFactor = math.min(2.0 * (1.0 - balance), 1.0)
    local curveFactor = math.min(2.0 * balance, 1.0)
    return straightFactor + (curveFactor - straightFactor) * curved
end

local function sampleCurvature(landVehicleApi: Transformator.LandVehicleScriptingApi): number | nil
    local succeeded, result = pcall(landVehicleApi.getAverageCurvature, landVehicleApi, CURVATURE_WINDOW, CURVATURE_WINDOW)
    if not succeeded then
        logger.warnOnce("curve-query-failed", "Ignoring unavailable track curvature: " .. tostring(result))
    elseif type(result) == "number" and result > -math.huge and result < math.huge then
        return result
    else
        logger.warnOnce("curve-query-invalid", "Ignoring invalid track curvature: " .. tostring(result))
    end
    return nil
end

local function tilt(
    landVehicleApi: Transformator.LandVehicleScriptingApi,
    speed: number,
    reversed: boolean,
    state: SwayingWaying.CarriageState,
    distance: number,
    calculateLean: boolean | nil
): number, number | nil
    assert(speed > -math.huge and speed < math.huge, "Invalid curve-lean speed")
    assert(distance > -math.huge and distance < math.huge, "Invalid curve sampling distance")
    if math.abs(speed) < constants.MIN_MOTION_SPEED then
        state.curveSampleDistance = nil
        return 0.5, nil
    end
    local previousDistance = state.curveSampleDistance
    local samplingDistance = state.model.curveSamplingDistance
    -- Cache only geometry so speed and orientation remain current between queries.
    if samplingDistance == 0.0 or previousDistance == nil
        or math.abs(distance - previousDistance) >= samplingDistance
    then
        state.curvature = sampleCurvature(landVehicleApi)
        state.curveSampleDistance = distance
    end
    local curvature = state.curvature
    if curvature == nil or curvature == 0.0 or calculateLean == false then
        return 0.5, curvature
    end

    -- Preserve native calculateTilt's speed and orientation response.
    local presentCurvature = curvature as number
    local signedCurvature = reversed and presentCurvature or -presentCurvature
    return (math.tanh(speed * speed * signedCurvature / LATERAL_ACCELERATION_SCALE) + 1.0) * 0.5, presentCurvature
end

local module: SwayingWaying.CurveResponse = { tilt = tilt, swayFactor = swayFactor }
return module
