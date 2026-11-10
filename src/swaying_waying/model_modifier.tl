local origins = ug_require("apasz_swaying_waying::/swaying_waying/origin_loader.lua") as SwayingWaying.OriginLoader
local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua") as SwayingWaying.Settings
local runtimeConfig = ug_require("apasz_swaying_waying::/swaying_waying/runtime_config.lua") as SwayingWaying.RuntimeConfig
local injection = ug_require("apasz_swaying_waying::/swaying_waying/model_injection.lua") as SwayingWaying.ModelInjection
local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua") as SwayingWaying.ModelPolicy
local authorOptions = policy.options
local carrierOf = policy.carrier
local vehicleMotionSettings = policy.vehicleSettings
local hasAuthoredSwayAnimations = policy.authoredSway
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua") as SwayingWaying.ModelCompatibility
local wrapperFor, defaultTransformator = compatibility.wrapperFor, compatibility.defaultFor
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local transaction = ug_require("apasz_swaying_waying::/swaying_waying/model_transaction.lua") as SwayingWaying.ModelTransaction
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local cameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua") as SwayingWaying.ModelCameras
local cameraCompatibility = ug_require("apasz_swaying_waying::/swaying_waying/camera_compatibility.lua") as SwayingWaying.CameraCompatibility
local type DynamicTable = SwayingWaying.RawTable
local type NameMap = {string: string}
local type AuthorOptions = SwayingWaying.ModelOptions
local type VehicleMotionSettings = SwayingWaying.VehicleMotionSettings
local OWN_TRANSFORMATORS: {string: boolean} = {
    [constants.TRAIN_TRANSFORMATOR] = true,
    [constants.TILTING_TRANSFORMATOR] = true,
    [constants.TRAM_TRANSFORMATOR] = true,
    [constants.ANY_TRANSFORMATOR] = true,
}
local DEFAULT_LOAD_OPTIONS: SwayingWaying.ModelLoadOptions = { swayEnabled = true, cameraMode = "Disabled" }
local function canOwnSwayChannels(name: any): boolean
    return type(name) == "string" and not compatibility.isDirect(name)
end

local function transformatorName(config: DynamicTable | nil): any
    if config == nil then
        return nil
    end
    local transformator = dynamicTable((config as DynamicTable).transformator)
    if transformator == nil then
        return nil
    end
    return (transformator as DynamicTable).name
end

local function captureCameras(fileName: string, model: DynamicTable, mode: SwayingWaying.CameraMode,
    extra: boolean | nil): SwayingWaying.CameraPlan | nil
    local succeeded, plan = pcall(cameras.capture, fileName, model, mode, extra)
    if not succeeded then
        logger.warnOnce("camera-capture:" .. fileName, "Onboard cameras skipped for " .. fileName .. ": " .. tostring(plan))
        return nil
    end
    return plan as SwayingWaying.CameraPlan
end

local function applyCameras(fileName: string, model: DynamicTable, plan: SwayingWaying.CameraPlan,
    attachments: NameMap, wrappers: SwayingWaying.WrapperRegistry | nil): SwayingWaying.CameraAdditions, boolean
    local added: SwayingWaying.CameraAdditions = { positions = {}, rests = {} }
    if #plan.views == 0 then
        return added, false
    end
    local updated = false
    local succeeded, failure = pcall(transaction.run, model, function(draft: any): boolean
        added, updated = cameras.apply(fileName, draft as DynamicTable, plan, attachments, wrappers)
        nodes.validate(draft)
        return updated
    end, cameras.scope(model))
    if not succeeded then
        logger.warnOnce("camera-apply:" .. fileName, "Onboard cameras skipped for " .. fileName .. ": " .. tostring(failure))
        return { positions = {}, rests = {} }, false
    end
    return added, updated
end

local function prepareModel(
    fileName: string,
    model: any,
    config: SwayingWaying.Config,
    detailed: boolean,
    loadOptions: SwayingWaying.ModelLoadOptions | nil
): any
    local loadConfig = loadOptions or DEFAULT_LOAD_OPTIONS
    local cameraMode = settings.effectiveCameraMode(loadConfig.cameraMode, loadConfig.swayEnabled)
    if not loadConfig.swayEnabled and cameraMode == "Disabled" then
        return model
    end
    local modelCandidate = dynamicTable(model)
    if modelCandidate == nil then
        return model
    end
    local modelTable = modelCandidate as DynamicTable
    local metadataCandidate = dynamicTable(modelTable.metadata)
    if metadataCandidate == nil then
        return model
    end
    local metadata = metadataCandidate as DynamicTable
    local carrier = carrierOf(metadata)
    if carrier == nil then
        return model
    end
    local presentCarrier = carrier as SwayingWayingCarrier
    config = settings.resolve(config)
    local pitchBalance = config.pitchBalance or 1.0
    local heaveBalance = config.heaveBalance or 1.0
    local vehicleVariation = config.vehicleVariation or 1.0
    local vehicleSettings = vehicleMotionSettings(
        fileName,
        metadata,
        vehicleVariation
    )
    if vehicleSettings == nil then
        logger.info(fileName .. ": sway skipped (author opt-out)")
        return model
    end
    local presentVehicleSettings = vehicleSettings as VehicleMotionSettings
    local swayEnabled = loadConfig.swayEnabled and presentVehicleSettings.swayEnabled
    cameraMode = presentVehicleSettings.cameraEnabled
        and settings.effectiveCameraMode(loadConfig.cameraMode, swayEnabled) or "Disabled"
    if not swayEnabled and cameraMode == "Disabled" then
        return model
    end
    local secondaryMotionEnabled = pitchBalance > 0.0 or heaveBalance > 0.0
    local options: AuthorOptions | nil = nil
    if swayEnabled then
        options = authorOptions(fileName, metadata)
        if not (options as AuthorOptions).valid then
            return model
        end
    end

    local transformatorConfig = dynamicTable(metadata.transformatorConfig)
    local currentName = transformatorName(transformatorConfig)
    if type(currentName) == "string"
        and OWN_TRANSFORMATORS[currentName as string]
    then
        return model
    end

    -- Paired legacy channels belong to the model's custom transformator.
    -- Authors may explicitly allow camera additions without adopting our motion.
    if presentVehicleSettings.swayEnabled and canOwnSwayChannels(currentName)
        and hasAuthoredSwayAnimations(modelTable, transformatorConfig)
    then
        logger.info(fileName .. ": sway skipped (author-owned sway)")
        return model
    end

    local committedReport: function() | nil = nil
    local prepared = transaction.run(model, function(draft: any): boolean
        local draftTable = draft as DynamicTable
        local refreshIndexedParts = compatibility.capture(fileName, draftTable)
        local function finish(changed: boolean): boolean
            if changed and refreshIndexedParts ~= nil then
                (refreshIndexedParts as function(DynamicTable))(draftTable)
            end
            return changed
        end
        local draftMetadata = draftTable.metadata as DynamicTable
        local draftTransformatorConfig: DynamicTable | nil = nil
        local draftName: any = nil
        -- Its own modifier intentionally skips custom transformators. Calling its
        -- idempotent adapter first keeps the particle wrapper in either mod order.
        if swayEnabled then
            compatibility.prepare(fileName, draft)
        end
        nodes.validate(draft)
        local cameraCompatibilityReady, cameraCompatibilityChanged = cameraCompatibility.prepare(
            fileName, draftTable, cameraMode ~= "Disabled")
        local cameraPlan: SwayingWaying.CameraPlan | nil = nil
        if cameraMode ~= "Disabled" then
            cameraPlan = captureCameras(fileName, draftTable, cameraMode, loadConfig.extraCameras)
        end
        draftTransformatorConfig = dynamicTable(draftMetadata.transformatorConfig)
        draftName = transformatorName(draftTransformatorConfig)

        if not swayEnabled then
            if cameraPlan == nil then
                return finish(cameraCompatibilityChanged)
            end
            local added, updated = applyCameras(fileName, draftTable, cameraPlan as SwayingWaying.CameraPlan, {}, nil)
            if not updated then
                return finish(cameraCompatibilityChanged)
            end
            if cameraCompatibilityReady then
                cameraCompatibility.refresh(fileName, draftTable, added)
            end
            local params = draftTransformatorConfig ~= nil and dynamicTable((draftTransformatorConfig as DynamicTable).params) or nil
            if #added.positions > 0 and type(draftName) == "string" and params ~= nil then
                compatibility.refresh(fileName, draftTable, draftName as string, params as DynamicTable)
            end
            return finish(true)
        end

        local swayOptions = options as AuthorOptions
        local originalName: string
        if type(draftName) == "string" and draftName ~= "" then
            originalName = draftName as string
        else
            originalName = defaultTransformator(presentCarrier)
        end
        if wrapperFor(originalName) == constants.ANY_TRANSFORMATOR then
            assert(origins.get(originalName, fileName, presentCarrier) ~= nil,
                "Cannot preserve original transformator: " .. originalName)
        end
        local result = injection.apply(
            fileName,
            draft,
            draftTransformatorConfig,
            draftName,
            originalName,
            swayOptions,
            secondaryMotionEnabled,
            detailed
        )
        if not result.added then
            if swayOptions.sections == nil then
                logger.warnOnce(
                    "missing-root:" .. fileName,
                    "Cannot safely add sway to model hierarchy: " .. fileName
                )
            end
            return false
        end

        local configTable: DynamicTable
        if draftTransformatorConfig ~= nil then
            configTable = draftTransformatorConfig as DynamicTable
        else
            configTable = { skipFromLod = result.activeLodCount }
            draftMetadata.transformatorConfig = configTable
        end
        if result.transformatorLodCount ~= nil then
            configTable.skipFromLod = result.transformatorLodCount
        end
        local params: DynamicTable
        local existingParams = dynamicTable(configTable.params)
        if existingParams ~= nil then
            params = existingParams as DynamicTable
        else
            params = {}
            configTable.params = params
        end
        assert(params[constants.RUNTIME_PARAM] == nil,
            "Model already contains the reserved swayingWaying runtime parameter")
        if cameraPlan ~= nil then
            local addedCameras = applyCameras(fileName, draftTable, cameraPlan as SwayingWaying.CameraPlan,
                result.attachments, result.wrappers)
            if cameraCompatibilityReady then
                cameraCompatibility.refresh(fileName, draftTable, addedCameras)
            end
        end
        compatibility.refresh(fileName, draftTable, originalName, params)
        local configured: SwayingWaying.ModelRuntimeConfig = {
            schema = constants.RUNTIME_SCHEMA,
            revision = 1,
            modelFile = fileName,
            originalTransformator = originalName,
            carrier = presentCarrier,
            profile = presentVehicleSettings.profile,
            axisReversed = result.modelAxisSign < 0,
            vehicleFactor = presentVehicleSettings.swayFactor,
            wheelbase = result.wheelbases[1] or constants.DEFAULT_WHEELBASE,
            settings = config,
            sections = {},
        }
        for index, section in ipairs(result.sections) do
            configured.sections[index] = { lag = section.lag, wheelbase = result.wheelbases[index] }
        end
        runtimeConfig.validate(configured)
        params[constants.RUNTIME_PARAM] = configured

        local transformator = dynamicTable(configTable.transformator)
        if transformator == nil then
            transformator = {}
            configTable.transformator = transformator
        end
        (transformator as DynamicTable).name = wrapperFor(originalName)

        committedReport = result.report
        return finish(true)
    end)
    if committedReport ~= nil then
        local reported, failure = pcall(committedReport as function(): any)
        if not reported then
            logger.warnOnce("model-report:" .. fileName, "Could not report prepared model " .. fileName .. ": " .. tostring(failure))
        end
    end
    return prepared
end

local module: SwayingWaying.ModelModifier = {
    configure = function(allModParams: SwayingWaying.AllModParams | nil)
        compatibility.configure(allModParams)
        cameraCompatibility.reset()
    end,
    modify = function(fileName: string, model: any, config: SwayingWaying.Config, detailed: boolean | nil,
        options: SwayingWaying.ModelLoadOptions | nil): any
        assert(detailed == nil or type(detailed) == "boolean", "Model diagnostics switch must be a boolean")
        local succeeded, prepared = pcall(prepareModel, fileName, model, config, detailed == true, options)
        if not succeeded then
            logger.warnOnce("model:" .. fileName, "Skipping unsafe model " .. fileName .. ": " .. tostring(prepared))
            return model
        end
        return prepared
    end,
}

return module
