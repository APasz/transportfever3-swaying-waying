local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local dynamicArray = validation.asArray
local type DynamicTable = SwayingWaying.RawTable
local type StringSet = {string: boolean}
local type ModelNode = SwayingWaying.ModelNode

local type ModelAdapter = function(any): integer

local WEATHER_MOD_ID = "just_more_weather_1"
local SNOW_POWDER_MODULE = WEATHER_MOD_ID .. "::/jmw/neige_poudre.lua"

local REAL_TRACK_CANT_REST_PREFIX = "devers_rest"

local REAL_TRACK_CANT_CORE = "devers_1::/vehicle/train/devers/devers_core.lua"

local CAYDE_CANT_TRANSFORMATORS: StringSet = {
    ["cayde_devers_1::/cayde_devers/train/cant_train.trf"] = true,
    ["cayde_devers_1::/cayde_devers/train/cant_tilting.trf"] = true,
    ["cayde_devers_1::/cayde_devers/train/cant_any.trf"] = true,
}

local enabledMods: StringSet = {}
local snowPowderChecked = false

local snowPowderAdapter: ModelAdapter | nil = nil

local PRR_NAMESPACE = "PRR_B6sab_1::/"
local record ValveGearPart
    index: integer
end
local record ValveGearLod
    count: integer
    parts: {string: ValveGearPart}
end
local record ValveGearBuilder
    buildLodTables: function({any}, {string: string}, integer): {ValveGearLod}
end

local function indexedNodes(root: ModelNode): {ModelNode}
    local result: {ModelNode} = {}
    local function visit(node: ModelNode)
        result[#result + 1] = node
        for _, child in ipairs(node.children or {}) do
            visit(child)
        end
    end
    visit(root)
    return result
end

local function valveGear(fileName: string, model: DynamicTable): DynamicTable | nil
    if fileName:sub(1, #PRR_NAMESPACE) ~= PRR_NAMESPACE then
        return nil
    end
    local metadata = dynamicTable(model.metadata)
    local config = metadata ~= nil and dynamicTable((metadata as DynamicTable).transformatorConfig) or nil
    local params = config ~= nil and dynamicTable((config as DynamicTable).params) or nil
    if params == nil then
        return nil
    end
    local value = (params as DynamicTable).valveGear
    local gear = dynamicTable(value)
    assert(value == nil or gear ~= nil, "Invalid PRR valve-gear configuration")
    return gear
end

local function validateLodCache(model: DynamicTable, value: any): {ValveGearLod}
    local lods = model.lods as {DynamicTable}
    local cached = dynamicArray(value)
    assert(cached ~= nil and validation.arraySize(cached as DynamicTable) ~= nil,
        "Invalid PRR valve-gear LOD cache")
    for index, entryValue in ipairs(cached as {any}) do
        local entry = dynamicTable(entryValue)
        assert(entry ~= nil, "Invalid PRR valve-gear LOD entry")
        assert(lods[index] ~= nil, "PRR valve-gear cache references a missing LOD")
        local tree = indexedNodes(lods[index].node as ModelNode)
        assert((entry as DynamicTable).count == #tree, "PRR valve-gear node count does not match the prepared hierarchy")
        local parts = dynamicTable((entry as DynamicTable).parts)
        assert(parts ~= nil, "Invalid PRR valve-gear part cache")
        for key, partValue in pairs(parts as DynamicTable) do
            local part = dynamicTable(partValue)
            assert(type(key) == "string" and part ~= nil, "Invalid PRR valve-gear part cache")
            local order = (part as DynamicTable).index
            assert(validation.nonnegative(order) and (order as number) % 1 == 0
                and tree[(order as integer) + 1] ~= nil, "Invalid PRR valve-gear node index")
        end
    end
    return cached as {ValveGearLod}
end

local function validateIndexedParts(fileName: string, model: DynamicTable)
    local gear = valveGear(fileName, model)
    if gear ~= nil then
        nodes.validate(model)
        validateLodCache(model, (gear as DynamicTable).lods)
    end
end

local function captureIndexedParts(fileName: string, model: DynamicTable): function(DynamicTable) | nil
    local gear = valveGear(fileName, model)
    if gear == nil then
        return nil
    end
    nodes.validate(model)
    local cached = validateLodCache(model, (gear as DynamicTable).lods)
    local names: {string: string} = {}
    local targets: {{string: ModelNode}} = {}
    for index, entry in ipairs(cached) do
        local tree = indexedNodes((model.lods as {DynamicTable})[index].node as ModelNode)
        targets[index] = {}
        for key, part in pairs(entry.parts) do
            local target = tree[part.index + 1]
            local name = target.name
            assert(name ~= nil and name ~= "", "PRR valve-gear parts need named anchors")
            assert(names[key] == nil or names[key] == name, "PRR valve-gear part names differ across LODs")
            names[key] = name as string
            targets[index][key] = target
        end
    end
    local builder = ug_require(PRR_NAMESPACE .. "scripts/valvegear_util.lua") as ValveGearBuilder
    assert(type(builder) == "table" and type(builder.buildLodTables) == "function",
        "PRR valve-gear hierarchy adapter is unavailable")
    return function(prepared: DynamicTable)
        local refreshed = validateLodCache(prepared, builder.buildLodTables(prepared.lods as {any}, names, #cached))
        assert(#refreshed == #cached, "PRR valve-gear adapter changed the active LOD count")
        for index, original in ipairs(cached) do
            local tree = indexedNodes((prepared.lods as {DynamicTable})[index].node as ModelNode)
            for key in pairs(original.parts) do
                local part = refreshed[index].parts[key]
                assert(part ~= nil and tree[part.index + 1] == targets[index][key],
                    "PRR valve-gear adapter lost or changed a scripted part: " .. key)
            end
        end
        (valveGear(fileName, prepared) as DynamicTable).lods = refreshed
    end
end

local function isModEnabled(modId: string): boolean
    return enabledMods[modId] == true
end

local function configure(allModParams: SwayingWaying.AllModParams | nil)
    -- Installed but disabled mods can still expose Lua helpers during validation.
    enabledMods = {}
    if allModParams ~= nil then
        for modId in pairs(allModParams as SwayingWaying.AllModParams) do
            enabledMods[modId] = true
        end
    end
    snowPowderChecked = false
    snowPowderAdapter = nil
end

local function applySnowPowderCompatibility(fileName: string, model: any)
    if not isModEnabled(WEATHER_MOD_ID) then
        return
    end
    if not snowPowderChecked then
        snowPowderChecked = true
        local loaded, candidate = pcall(ug_require, SNOW_POWDER_MODULE)
        local module = loaded and dynamicTable(candidate) or nil
        local adapter = module ~= nil
            and (module as DynamicTable).addToModel
            or nil
        if type(adapter) == "function" then
            snowPowderAdapter = adapter as ModelAdapter
        elseif module ~= nil then
            logger.warnOnce("snow-powder-adapter-unavailable",
                "Realistic Environment Pro snow-powder module does not expose addToModel; compatibility adapter unavailable for " .. fileName)
        elseif not loaded then
            logger.debug("Optional Realistic Environment Pro snow-powder module unavailable: " .. tostring(candidate))
        end
    end
    if snowPowderAdapter == nil then
        return
    end
    local succeeded, failure = pcall(
        snowPowderAdapter as ModelAdapter,
        model
    )
    if not succeeded then
        error("Could not apply Realistic Environment Pro snow-powder compatibility to " .. fileName .. ": " .. tostring(failure))
    end
end

-- Cant retargets root placements to its wrapper without creating a body section.

local REAL_TRACK_CANT_TRANSFORMATORS: StringSet = {
    ["devers_1::/vehicle/train/devers/devers_train.trf"] = true,
    ["devers_1::/vehicle/train/devers/devers_tilting.trf"] = true,
    ["devers_1::/vehicle/train/devers/devers_tram.trf"] = true,
    ["devers_1::/vehicle/train/devers/devers_any.trf"] = true,
}

local DIRECT_TRANSFORMATORS: StringSet = {
    ["devers_1::/vehicle/train/devers/devers_train.trf"] = true,
    ["devers_1::/vehicle/train/devers/devers_tilting.trf"] = true,
    ["devers_1::/vehicle/train/devers/devers_tram.trf"] = true,
}

local function normalizedTransformatorName(name: string): string
    return (name:gsub("^::/", "/"))
end

local record NativeTransformator
    name: string
    wrapper: string
end
local native: {string: NativeTransformator} = {
    train = { name = "::/vehicle/train/shared/default_train.trf", wrapper = constants.TRAIN_TRANSFORMATOR },
    tilting = { name = "::/vehicle/train/shared/tilting_train.trf", wrapper = constants.TILTING_TRANSFORMATOR },
    tram = { name = "::/vehicle/tram/shared/default_tram.trf", wrapper = constants.TRAM_TRANSFORMATOR },
}
local wrappers: {string: string} = {}
for _, definition in pairs(native) do
    local normalized = normalizedTransformatorName(definition.name)
    local sharedName = "::shared/" .. assert(definition.name:match("/shared/(.+)$"))
    wrappers[normalized] = definition.wrapper
    wrappers[sharedName] = definition.wrapper
    DIRECT_TRANSFORMATORS[normalized] = true
    DIRECT_TRANSFORMATORS[sharedName] = true
end

local function wrapperFor(name: string): string
    return wrappers[normalizedTransformatorName(name)] or constants.ANY_TRANSFORMATOR
end

local function defaultFor(carrier: SwayingWayingCarrier): string
    return carrier == "TRAM" and native.tram.name or native.train.name
end

local function usesDirectTransformator(name: any): boolean
    if name == nil then
        return true
    end
    return type(name) == "string"
        and DIRECT_TRANSFORMATORS[
            normalizedTransformatorName(name as string)
        ] == true
end

local function collectRestPoses(
    node: ModelNode,
    parentTransform: {number},
    poses: {integer: {number}},
    nodeIndex: integer
): integer
    local transform = nodes.multiply(
        parentTransform,
        nodes.transform(node)
    )
    poses[nodeIndex] = transform
    local nextIndex = nodeIndex + 1
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            nextIndex = collectRestPoses(
                child,
                transform,
                poses,
                nextIndex
            )
        end
    end
    return nextIndex
end

local function clearRealTrackCantRest(params: DynamicTable)
    local keys: {any} = {}
    for key in pairs(params) do
        if type(key) == "string"
            and (key as string):match("^" .. REAL_TRACK_CANT_REST_PREFIX .. "%d+$")
        then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        params[key] = nil
    end
end

local function refreshRealTrackCantRest(
    fileName: string,
    model: DynamicTable,
    originalTransformator: string,
    params: DynamicTable
)
    if not REAL_TRACK_CANT_TRANSFORMATORS[originalTransformator] then
        return
    end

    local loaded, coreValue = pcall(ug_require, REAL_TRACK_CANT_CORE)
    local coreTable = loaded and dynamicTable(coreValue) or nil
    local encodeValue = coreTable ~= nil
        and (coreTable as DynamicTable).encodeRest
        or nil
    if type(encodeValue) ~= "function" then
        clearRealTrackCantRest(params)
        local reason = loaded and "missing encodeRest function" or tostring(coreValue)
        logger.warnOnce(
            "real-track-cant-core:" .. fileName,
            "Could not refresh Real Track Cant placement data for "
                .. fileName
                .. ": " .. reason
                .. "; absolute vehicle parts will be left to its safe fallback"
        )
        return
    end

    local encodeRest = encodeValue as function(
        integer,
        {integer: {number}}
    ): string
    local encoded: {integer: string} = {}
    local lods = dynamicArray(model.lods)
    if lods ~= nil then
        for lodIndex, lodValue in ipairs(lods as {any}) do
            local lod = dynamicTable(lodValue)
            local root = lod ~= nil
                and nodes.get((lod as DynamicTable).node)
                or nil
            if root ~= nil then
                local poses: {integer: {number}} = {}
                local nodeCount = collectRestPoses(
                    root as ModelNode,
                    nodes.identity(0.0),
                    poses,
                    0
                )
                local succeeded, result = pcall(
                    encodeRest,
                    nodeCount,
                    poses
                )
                if not succeeded or type(result) ~= "string" then
                    clearRealTrackCantRest(params)
                    logger.warnOnce(
                        "real-track-cant-rest:" .. fileName,
                        "Could not encode refreshed Real Track Cant placement data for "
                            .. fileName
                            .. ": "
                            .. tostring(result)
                    )
                    return
                end
                encoded[lodIndex] = result as string
            end
        end
    end

    clearRealTrackCantRest(params)
    for lodIndex, value in pairs(encoded) do
        params[REAL_TRACK_CANT_REST_PREFIX .. lodIndex] = value
    end
    logger.debug("Refreshed Real Track Cant placement data for " .. fileName)
end

local module: SwayingWaying.ModelCompatibility = {
    capture = captureIndexedParts,
    validate = validateIndexedParts,
    configure = configure,
    isModEnabled = isModEnabled,
    wrapperFor = wrapperFor, defaultFor = defaultFor,
    prepare = applySnowPowderCompatibility,
    refresh = function(fileName: string, model: DynamicTable, originalTransformator: string, params: DynamicTable)
        -- Cayde's modifier keeps its index builder private, so the cache cannot
        -- be refreshed through its API after changing the hierarchy.
        assert(not CAYDE_CANT_TRANSFORMATORS[originalTransformator],
            "Cayde's Track Cant is incompatible with Swaying Waying; disable one of the two mods")
        refreshRealTrackCantRest(fileName, model, originalTransformator, params)
    end,
    isDirect = usesDirectTransformator,
    isBodyContainer = function(name: string): boolean
        return name == constants.ROOT_NODE or name == "devers_roulis"
    end,
}
return module
