local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local paths = ug_require(
    "apasz_swaying_waying::/swaying_waying/resource_paths.lua"
) as SwayingWaying.ResourcePaths
local logger = ug_require(
    "apasz_swaying_waying::/swaying_waying/logger.lua"
) as SwayingWaying.Logger

local type DynamicTable = SwayingWaying.RawTable



local record LoadedResource
    fileName: string
    value: DynamicTable | nil
    factoryValue: DynamicTable | nil
    factoryLoaded: boolean
end

local resources: {string: LoadedResource} = {}
local origins: {string: SwayingWaying.Origin} = {}
local failed: {string: boolean} = {}
local CALLBACK_FIELDS: {string} = {
    "updateScript", "updateParticleSystemScript", "getEmittableModelsScript", "computeEmittedModelsScript",
}

local function evaluateData(loader: function(): any, fileName: string): DynamicTable | nil
    local savedData = data
    local succeeded, result = pcall(loader)
    data = savedData
    if not succeeded then
        logger.warnOnce("transformator-factory-failed:" .. fileName,
            "Original transformator resource factory failed for " .. fileName .. ": " .. tostring(result))
        return nil
    end
    return dynamicTable(result)
end

local function loadResourceOnce(fileName: string): DynamicTable | nil
    local savedData = data
    local succeeded, resource = pcall(ug_require, fileName)
    local definedData = data
    data = savedData
    if not succeeded then
        -- Missing namespace/extension candidates are normal during resolution.
        logger.debug("Could not load original transformator resource " .. fileName .. ": " .. tostring(resource))
        return nil
    end
    if type(resource) == "table" then
        return resource as DynamicTable
    end
    if type(definedData) == "function" and definedData ~= savedData then
        return evaluateData((definedData as function(): any), fileName)
    end
    return nil
end

local function loadResource(fileName: string): LoadedResource
    local cached = resources[fileName]
    if cached ~= nil then
        return cached
    end
    local resource: LoadedResource = { fileName = fileName, factoryLoaded = false }
    resources[fileName] = resource
    resource.value = loadResourceOnce(fileName)
    return resource
end

local function factoryExports(resource: LoadedResource): DynamicTable | nil
    if not resource.factoryLoaded then
        resource.factoryLoaded = true
        local value = resource.value
        if value ~= nil and type((value as DynamicTable).data) == "function" then
            resource.factoryValue = evaluateData(((value as DynamicTable).data as function(): any), resource.fileName)
        end
    end
    return resource.factoryValue
end

local function hasCallbacks(value: DynamicTable | nil): boolean
    if value ~= nil then
        for _, field in ipairs(CALLBACK_FIELDS) do
            if (value as DynamicTable)[field] ~= nil then
                return true
            end
        end
    end
    return false
end

local function transformatorConfig(resource: LoadedResource): DynamicTable | nil
    local value = resource.value
    if hasCallbacks(value) then
        return value
    end
    local exports = factoryExports(resource)
    if hasCallbacks(exports) then
        return exports
    end
    return nil
end

local function exportedFunction(exports: DynamicTable | nil, members: {string}): any
    local member: any = exports
    for _, key in ipairs(members) do
        local memberTable = dynamicTable(member)
        member = memberTable ~= nil and (memberTable as DynamicTable)[key] or nil
    end
    return type(member) == "function" and member or nil
end

local function scriptFunction(
    reference: string,
    transformatorFile: string
): any
    if reference == "" then
        return nil
    end
    local files, members = paths.scriptCandidates(reference, transformatorFile)
    for _, fileName in ipairs(files) do
        local resource = loadResource(fileName)
        local callback = exportedFunction(resource.value, members)
        if callback == nil then
            callback = exportedFunction(factoryExports(resource), members)
        end
        if callback ~= nil then
            return callback
        end
    end
    return nil
end

local function callbackFrom(
    config: DynamicTable,
    fieldName: string,
    transformatorFile: string
): any, any, boolean
    if config[fieldName] == nil then
        return nil, {}, true
    end
    local callbackConfig = dynamicTable(config[fieldName])
    if callbackConfig == nil then
        return nil, {}, false
    end
    local presentConfig = callbackConfig as DynamicTable
    local capture = type(presentConfig.params) == "table"
        and presentConfig.params
        or {}
    local reference = presentConfig.fileName
    local callback = type(reference) == "string"
        and scriptFunction(reference as string, transformatorFile)
        or nil
    if type(callback) ~= "function" then
        logger.warnOnce(
            "missing-transformator-callback:"
                .. transformatorFile
                .. ":"
                .. fieldName,
            "Could not load "
                .. fieldName
                .. " from original transformator "
                .. transformatorFile
        )
        return nil, capture, false
    end
    return callback, capture, true
end

local function get(
    name: string,
    modelFile: string,
    carrier: SwayingWayingCarrier
): SwayingWaying.Origin | nil
    local key = name .. "|" .. modelFile .. "|" .. carrier
    local cached = origins[key]
    if cached ~= nil then
        return cached
    end

    if failed[key] then
        return nil
    end
    for _, transformatorFile in ipairs(paths.trfCandidates(name, modelFile)) do
        local config = dynamicTable(transformatorConfig(loadResource(transformatorFile)))
        if config ~= nil then
            local presentConfig = config as DynamicTable
            local update, updateCapture, updateValid = callbackFrom(
                presentConfig,
                "updateScript",
                transformatorFile
            )
            if updateValid then
                local particleUpdate, particleCapture, particlesValid = callbackFrom(
                    presentConfig,
                    "updateParticleSystemScript",
                    transformatorFile
                )
                local getEmittableModels, getEmittableModelsCapture, discoveryValid = callbackFrom(
                    presentConfig,
                    "getEmittableModelsScript",
                    transformatorFile
                )
                local computeEmittedModels, computeEmittedModelsCapture, emissionValid = callbackFrom(
                    presentConfig,
                    "computeEmittedModelsScript",
                    transformatorFile
                )
                local origin: SwayingWaying.Origin = {
                    update = type(update) == "function" and update as UpdateFn or nil,
                    capture = updateCapture,
                    particles = type(particleUpdate) == "function"
                        and particleUpdate as UpdateParticleSystemFn
                        or nil,
                    particlesCapture = particleCapture,
                    getEmittableModels = type(getEmittableModels) == "function"
                        and getEmittableModels as GetEmittableModelsFn
                        or nil,
                    getEmittableModelsCapture = getEmittableModelsCapture,
                    computeEmittedModels = type(computeEmittedModels) == "function"
                        and computeEmittedModels as ComputeEmittedModelsFn
                        or nil,
                    computeEmittedModelsCapture = computeEmittedModelsCapture,
                }
                if particlesValid and discoveryValid and emissionValid then
                    origins[key] = origin
                    return origin
                end
            end
        end
    end

    failed[key] = true
    logger.warnOnce(
        "missing-transformator:" .. key,
        "Could not preserve every callback from original transformator " .. name .. " for " .. modelFile
    )
    return nil
end

local module: SwayingWaying.OriginLoader = {
    get = get,
}

return module
