local runtimeConfig = ug_require("apasz_swaying_waying::/swaying_waying/runtime_config.lua") as SwayingWaying.RuntimeConfig
local runtimeState = ug_require("apasz_swaying_waying::/swaying_waying/runtime_state.lua") as SwayingWaying.RuntimeState
local constants = ug_require(
    "apasz_swaying_waying::/swaying_waying/constants.lua"
) as SwayingWaying.Constants
local motionConfig = ug_require(
    "apasz_swaying_waying::/swaying_waying/motion_config.lua"
) as SwayingWaying.MotionConfig
local motion = ug_require(
    "apasz_swaying_waying::/swaying_waying/motion.lua"
) as SwayingWaying.Motion
local motionResponse = ug_require(
    "apasz_swaying_waying::/swaying_waying/motion_response.lua"
) as SwayingWaying.MotionResponse
local trackResponse = ug_require(
    "apasz_swaying_waying::/swaying_waying/track_response.lua"
) as SwayingWaying.TrackResponse
local curveResponse = ug_require(
    "apasz_swaying_waying::/swaying_waying/curve_response.lua"
) as SwayingWaying.CurveResponse
local curvatureProbe = ug_require(
    "apasz_swaying_waying::/swaying_waying/curvature_probe.lua"
) as SwayingWaying.CurvatureProbe
local observeCurvature = curvatureProbe.observe
local lodProbe = ug_require("apasz_swaying_waying::/swaying_waying/lod_probe.lua") as SwayingWaying.LodProbe
local observeLod = lodProbe.observe
local vehicleResponse = ug_require(
    "apasz_swaying_waying::/swaying_waying/vehicle_response.lua"
) as SwayingWaying.VehicleResponse
local origins = ug_require(
    "apasz_swaying_waying::/swaying_waying/origin_loader.lua"
) as SwayingWaying.OriginLoader
local logger = ug_require(
    "apasz_swaying_waying::/swaying_waying/logger.lua"
) as SwayingWaying.Logger
local transformatorUtil = ug_require(
    "::/scripts/transformator_util.tl"
) as TransformatorUtil

local record ScriptGroup
    updateFn: UpdateFn
    updateParticleSystemFn: UpdateParticleSystemFn
end

local record TrainScripts
    train: ScriptGroup
end

local record TiltingScripts
    tiltingTrain: ScriptGroup
end

local record TramScripts
    tram: ScriptGroup
end

local vanillaTrain = ug_require(
    "::/vehicle/train/shared/transformator_train.script.tl"
) as TrainScripts
local vanillaTilting = ug_require(
    "::/vehicle/train/shared/transformator_tiltingTrain.script.tl"
) as TiltingScripts
local vanillaTram = ug_require(
    "::/vehicle/tram/shared/transformator_tram.script.tl"
) as TramScripts

local APPROXIMATE_CARRIAGE_SPACING = 20.0
local NEUTRAL_TRACK_SHORT_WEIGHT = constants.NEUTRAL_TRACK_SHORT_WEIGHT
local NEUTRAL_ROLL_TIME, NEUTRAL_HEAVE_TIME, NEUTRAL_PITCH_TIME = motion.neutralAnimationTimes()
local type DynamicTable = SwayingWaying.RawTable

local enum RuntimeFailure
    "curvature-probe-failed"
    "lod-probe-failed"
    "runtime-sway"
    "original-resolution"
    "original-update"
    "original-particles"
    "original-emittable-models"
    "original-emitted-models"
end

local function warnRuntime(kind: RuntimeFailure, message: string, params: TransformatorParams, failure: any)
    local readable, source = pcall(runtimeConfig.read, params)
    local modelFile, original, revision = "unavailable", "unavailable", "unavailable"
    if readable and type(source) == "table" then
        modelFile = tostring((source as SwayingWaying.ModelRuntimeConfig).modelFile)
        original = tostring((source as SwayingWaying.ModelRuntimeConfig).originalTransformator)
        revision = tostring((source as SwayingWaying.ModelRuntimeConfig).revision)
    end
    local carriage = params.vehicleStaticInfo ~= nil and tostring(params.vehicleStaticInfo.carriageEntity) or "unavailable"
    local reason = tostring(failure)
    logger.warnOnce(kind .. ":" .. modelFile .. ":" .. revision,
        message .. ": " .. reason .. " [model=" .. modelFile .. ", transformator=" .. original
            .. ", revision=" .. revision .. ", vehicle=" .. tostring(params.entityId) .. ", carriage=" .. carriage .. "]")
end

local function addMotionAnimations(
    output: Transformator.TransfOutput,
    section: SwayingWaying.RuntimeSection,
    sample: SwayingWaying.MotionSample,
    settings: SwayingWaying.CompiledMotion,
    neutral: boolean
)
    local names = section.animations
    local motionSettings = settings.motion
    local secondary = settings.secondaryMotionEnabled and settings.proceduralMotionEnabled
    local rollTime, heaveTime, pitchTime = NEUTRAL_ROLL_TIME, NEUTRAL_HEAVE_TIME, NEUTRAL_PITCH_TIME
    if not neutral then
        if secondary then
            rollTime, heaveTime, pitchTime = motion.animationTimes(sample, motionSettings, section.geometry)
        elseif motionConfig.roll then
            rollTime = motion.animationTime(sample, motionSettings)
        end
    end
    if motionConfig.roll then
        output:addAnimationState(names.roll, -1, rollTime, false, false)
    end
    if secondary then
        if motionConfig.heave then
            output:addAnimationState(names.heave as string, -1, heaveTime, false, false)
        end
        if motionConfig.pitch then
            output:addAnimationState(names.pitch as string, -1, pitchTime, false, false)
        end
    end
end

local function emitMotion(
    output: Transformator.TransfOutput,
    settings: SwayingWaying.CompiledMotion,
    state: SwayingWaying.CarriageState,
    neutral: boolean
)
    local sample = state.sample
    local distance, sharedDistance = sample.distance, sample.sharedDistance
    for index = 1, #settings.sections do
        local section = settings.sections[index]
        if not neutral then
            local lag = motionConfig.sectionLag and section.lag or 0.0
            sample.distance = distance - lag
            sample.sharedDistance = sharedDistance - (sample.sharedAxisReversed and -lag or lag)
            if sample.waves ~= nil then
                motion.sectionWaves(state, index)
            end
        end
        addMotionAnimations(output, section, sample, settings, neutral)
    end
end

local function observeMotion(params: TransformatorParams, averageCurvature: number | nil)
    local observer = observeCurvature as SwayingWaying.CurvatureObserver
    local succeeded, failure = pcall(observer, params, averageCurvature)
    if not succeeded then
        observeCurvature = nil
        warnRuntime("curvature-probe-failed", "Curvature probe disabled after failure", params, failure)
    end
end

local function sharedCoordinate(
    vehicle: Transformator.VehicleScriptingInfo,
    land: Transformator.LandVehicleScriptingInfo,
    distance: number
): number, boolean, number, number
    local position = vehicle.positionInCarriageList
    assert(
        position >= 0 and position < vehicle.carriageListLength and position % 1 == 0,
        "Invalid carriage position in consist"
    )
    assert(land.carriagesReversed ~= nil, "Missing carriage orientation list")
    local facing: boolean | nil = land.carriagesReversed[position + 1]
    assert(facing ~= nil, "Missing carriage orientation in consist")
    local sharedAxisReversed = facing as boolean
    local consistReversed = land.reversed ~= sharedAxisReversed
    local coordinate = consistReversed and -distance or distance
    local lag = motionConfig.carriageLag and position * APPROXIMATE_CARRIAGE_SPACING or 0.0
    return coordinate - lag, sharedAxisReversed, coordinate, lag
end

local function addSway(
    params: TransformatorParams,
    transfsOutput: Transformator.TransfOutput
): boolean
    local current = params.currentInfo
    if current == nil
        or current.landVehicle == nil
        or current.vehicle == nil
        or params.vehicleStaticInfo == nil
    then
        return true
    end

    local configured = runtimeConfig.read(params)
    local staticInfo = params.vehicleStaticInfo
    local state = runtimeState.get(
        configured,
        staticInfo.carriageEntity,
        staticInfo.purchaseTime
    )
    if state == nil then
        return true
    end
    local presentState = state as SwayingWaying.CarriageState
    local settings = presentState.model
    if observeLod ~= nil then
        local observer = observeLod as SwayingWaying.LodObserver
        local succeeded, failure = pcall(observer, params, transfsOutput, configured.modelFile)
        if not succeeded then
            observeLod = nil
            warnRuntime("lod-probe-failed", "LOD probe disabled after failure", params, failure)
        end
    end
    local proceduralMotion = settings.proceduralMotionEnabled
    local curveLean = settings.curveLeanEnabled
    if not proceduralMotion and not curveLean then
        return true
    end
    if math.abs(current.vehicle.speed) < constants.MIN_MOTION_SPEED
        and motionResponse.neutral(presentState)
    then
        presentState.curveSampleDistance = nil
        -- Keep the clock current so a long stop does not bypass restart damping.
        motionResponse.update(presentState, current.world.gameTime, 0.0, 0.5)
        emitMotion(transfsOutput, settings, presentState, true)
        if observeCurvature ~= nil then
            observeMotion(params, nil)
        end
        return true
    end
    local travelDistance = current.landVehicle.wheelAnimationInfo.totalDist
    local curveTilt = 0.5
    local averageCurvature: number | nil = nil
    if curveLean then
        local previousTime = presentState.responseTime
        if previousTime ~= nil and current.world.gameTime < previousTime then
            presentState.curveSampleDistance = nil
        end
        curveTilt, averageCurvature = curveResponse.tilt(
            params.landVehicleApi,
            current.vehicle.speed,
            current.landVehicle.reversed,
            presentState,
            travelDistance
        )
    end
    local phaseSeed = params.entityId + staticInfo.carriageEntity
    local distance = proceduralMotion and travelDistance or 0.0
    local sharedDistance = distance
    local sharedAxisReversed = false
    local sharedBaseDistance, carriageLag = distance, 0.0
    if proceduralMotion and motionConfig.longWave then
        sharedDistance, sharedAxisReversed, sharedBaseDistance, carriageLag = sharedCoordinate(current.vehicle, current.landVehicle, distance)
    end
    local trackFactor = 1.0
    local shortWeight = NEUTRAL_TRACK_SHORT_WEIGHT
    if proceduralMotion and motionConfig.trackResponse and settings.trackInfluence > 0.0 then
        trackFactor, shortWeight = trackResponse.response(
            params.landVehicleApi,
            staticInfo.carriageEntity,
            staticInfo.purchaseTime,
            distance,
            settings.samplingDistance
        )
        if settings.trackInfluence ~= 1.0 then
            trackFactor, shortWeight = trackResponse.applyInfluence(
                trackFactor,
                shortWeight,
                settings.trackInfluence
            )
        end
    end
    local vehicleFactor = 1.0
    if proceduralMotion and motionConfig.vehicleResponse then
        local maintenanceFactor = 1.0
        if settings.vehicleVariation > 0.0 then
            maintenanceFactor = vehicleResponse.maintenanceFactor(
                current.vehicle.maintenance
            )
            if settings.vehicleVariation ~= 1.0 then
                maintenanceFactor = vehicleResponse.scaleFromNeutral(
                    maintenanceFactor,
                    settings.vehicleVariation
                )
            end
        end
        vehicleFactor = settings.vehicleFactor * maintenanceFactor
    end
    local swayFactor = trackResponse.combinedFactor(
        trackFactor,
        vehicleFactor
    )
    local sample = presentState.sample
    local motionScale = proceduralMotion
        and motion.speedFactor(current.vehicle.speed, settings.motion.profile, settings.speedDependent) or 0.0
    motionResponse.update(presentState, current.world.gameTime, motionScale, curveTilt)
    sample.phaseSeed = phaseSeed
    sample.sharedPhaseSeed = params.entityId
    sample.sharedAxisReversed = sharedAxisReversed
    sample.swayFactor = swayFactor
    sample.shortWeight = shortWeight
    sample.distance = distance
    sample.sharedDistance = sharedDistance
    sample.waves = nil
    if settings.secondaryMotionEnabled and proceduralMotion and sample.motionScale > 0.0
        and current.vehicle.carriageListLength >= constants.MIN_SHARED_WAVE_CARRIAGES
    then
        motion.prepareWaves(presentState, sharedBaseDistance, carriageLag)
    end
    emitMotion(transfsOutput, settings, presentState, false)
    if observeCurvature ~= nil then
        observeMotion(params, averageCurvature)
    end
    return true
end

local function invokeUpdate(
    update: UpdateFn,
    capture: any,
    params: TransformatorParams,
    transfsOutput: Transformator.TransfOutput
): boolean
    update(capture, params, transfsOutput)
    return true
end

local function invokeParticles(
    update: UpdateParticleSystemFn,
    capture: any,
    params: TransformatorParams,
    particleSystem: Transformator.ParticleSystem
): boolean
    update(capture, params, particleSystem)
    return true
end

local function invokeGetEmittableModels(
    callback: GetEmittableModelsFn,
    capture: any,
    params: TransformatorParams
): {string}
    return callback(capture, params)
end

local function invokeComputeEmittedModels(
    callback: ComputeEmittedModelsFn,
    capture: any,
    params: TransformatorParams,
    modelEmitter: Transformator.ModelEmitter
): boolean
    callback(capture, params, modelEmitter)
    return true
end

local function safeAddSway(
    params: TransformatorParams,
    transfsOutput: Transformator.TransfOutput
)
    local succeeded, failure = pcall(addSway, params, transfsOutput)
    if not succeeded then
        warnRuntime("runtime-sway", "Could not animate a rail vehicle", params, failure)
    end
end

local function wrap(original: UpdateFn): UpdateFn
    return function(
        captureParams: any,
        params: TransformatorParams,
        transfsOutput: Transformator.TransfOutput
    )
        original(captureParams, params, transfsOutput)
        safeAddSway(params, transfsOutput)
    end
end

local function loadOriginal(params: TransformatorParams): SwayingWaying.Origin | nil
    local source = runtimeConfig.read(params)
    local model = runtimeState.model(source)
    if not model.originLoaded then
        model.origin = origins.get(source.originalTransformator, source.modelFile, source.carrier)
        model.originLoaded = true
    end
    return model.origin
end

local function originalFor(params: TransformatorParams): SwayingWaying.Origin | nil
    local succeeded, result = pcall(loadOriginal, params)
    if not succeeded then
        warnRuntime("original-resolution", "Could not resolve original vehicle transformator; callback skipped", params, result)
        return nil
    end
    return result as SwayingWaying.Origin | nil
end

local function validatedModelResources(value: any): {string} | nil, string | nil
    if type(value) ~= "table" then
        return nil, "returned " .. type(value) .. " instead of a model list"
    end
    local entries = value as DynamicTable
    local count = 0
    for index, model in pairs(entries) do
        if type(index) ~= "number" or type(model) ~= "string" then
            return nil, "returned an invalid model-resource list"
        end
        local numericIndex = index as number
        if numericIndex < 1 or numericIndex % 1 ~= 0 then
            return nil, "returned an invalid model-resource list"
        end
        count = count + 1
    end
    for index = 1, count do
        if type(entries[index]) ~= "string" then
            return nil, "returned a sparse model-resource list"
        end
    end
    return value as {string}, nil
end

local function updateAny(
    _captureParams: any,
    params: TransformatorParams,
    transfsOutput: Transformator.TransfOutput
)
    local candidate = originalFor(params)
    if candidate == nil then
        return
    end
    local original = candidate as SwayingWaying.Origin
    local update = original.update
    if update ~= nil then
        local presentUpdate = update as UpdateFn
        local succeeded, failure = pcall(
            invokeUpdate,
            presentUpdate,
            original.capture,
            params,
            transfsOutput
        )
        if not succeeded then
            warnRuntime("original-update", "Original vehicle transformator failed", params, failure)
        end
    end
    safeAddSway(params, transfsOutput)
end

local function updateAnyParticles(
    captureParams: any,
    params: TransformatorParams,
    particleSystem: Transformator.ParticleSystem
)
    local candidate = originalFor(params)
    if candidate == nil then
        return
    end
    local original = candidate as SwayingWaying.Origin
    local particles = original.particles
    if particles ~= nil then
        local presentParticles = particles as UpdateParticleSystemFn
        local succeeded, failure = pcall(
            invokeParticles,
            presentParticles,
            original.particlesCapture,
            params,
            particleSystem
        )
        if succeeded then
            return
        end
        warnRuntime("original-particles", "Original particle transformator failed", params, failure)
    end
    transformatorUtil.updateParticleSystemFn(captureParams, params, particleSystem)
end

local function getAnyEmittableModels(
    _captureParams: any,
    params: TransformatorParams
): {string}
    local candidate = originalFor(params)
    if candidate == nil then
        return {}
    end
    local original = candidate as SwayingWaying.Origin
    local callback = original.getEmittableModels
    if callback == nil then
        return {}
    end
    local succeeded, result = pcall(
        invokeGetEmittableModels,
        callback as GetEmittableModelsFn,
        original.getEmittableModelsCapture,
        params
    )
    local failure: any = result
    if succeeded then
        local models, validationFailure = validatedModelResources(result)
        if models ~= nil then
            return models as {string}
        end
        failure = validationFailure
    end
    warnRuntime("original-emittable-models", "Original vehicle model discovery failed", params, failure)
    return {}
end

local function computeAnyEmittedModels(
    _captureParams: any,
    params: TransformatorParams,
    modelEmitter: Transformator.ModelEmitter
)
    local candidate = originalFor(params)
    if candidate == nil then
        return
    end
    local original = candidate as SwayingWaying.Origin
    local callback = original.computeEmittedModels
    if callback == nil then
        return
    end
    local succeeded, failure = pcall(
        invokeComputeEmittedModels,
        callback as ComputeEmittedModelsFn,
        original.computeEmittedModelsCapture,
        params,
        modelEmitter
    )
    if not succeeded then
        warnRuntime("original-emitted-models", "Original vehicle model emission failed", params, failure)
    end
end

local scripts: {string: SwayingWaying.TransformatorScript} = {
    train = {
        updateFn = wrap(vanillaTrain.train.updateFn),
        updateParticleSystemFn = vanillaTrain.train.updateParticleSystemFn,
    },
    tilting = {
        updateFn = wrap(vanillaTilting.tiltingTrain.updateFn),
        updateParticleSystemFn = vanillaTilting.tiltingTrain.updateParticleSystemFn,
    },
    tram = {
        updateFn = wrap(vanillaTram.tram.updateFn),
        updateParticleSystemFn = vanillaTram.tram.updateParticleSystemFn,
    },
    any = {
        updateFn = updateAny,
        updateParticleSystemFn = updateAnyParticles,
        getEmittableModelsFn = getAnyEmittableModels,
        computeEmittedModelsFn = computeAnyEmittedModels,
    },
}

function data(): any
    return scripts
end

return scripts
