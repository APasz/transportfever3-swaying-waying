local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local vehicleResponse = ug_require("apasz_swaying_waying::/swaying_waying/vehicle_response.lua") as SwayingWaying.VehicleResponse
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua") as SwayingWaying.ModelCompatibility
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local dynamicArray = validation.asArray
local validLodDistance = validation.nonnegative
local positiveInteger = validation.positiveInteger
local type DynamicTable = SwayingWaying.RawTable
local type StringSet = {string: boolean}
local type ModelNode = SwayingWaying.ModelNode
local type PlacementExtent = SwayingWaying.PlacementExtent
local type PlacementData = SwayingWaying.PlacementData
local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua") as SwayingWaying.ModelAuthoring
local type AuthorOptions = SwayingWaying.ModelOptions
local type VehicleMotionSettings = SwayingWaying.VehicleMotionSettings

local DEFAULT_PIVOT_HEIGHT = 0.85

local MIN_PIVOT_HEIGHT = 0.45

local MAX_PIVOT_HEIGHT = 1.25

local PIVOT_HEIGHT_RATIO = 0.2


local MIN_SWAY_CUTOFF_DISTANCE = 350.0

local SWAY_CUTOFF_DISTANCE = 500.0

local FALLBACK_ACTIVE_LOD_COUNT = 2

local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH

local record VehicleTags
    none: boolean
    onlyCamera: boolean
    noCamera: boolean
    rougher: boolean
    smoother: boolean
    quick: boolean
    slow: boolean
end

local record AuthoredSwayChannels
    sway: boolean
    tenderSway: boolean
end

local function carrierOf(metadata: DynamicTable): SwayingWayingCarrier | nil
    local authoredCarrier: any = nil
    local transportCandidate = dynamicTable(metadata.transportVehicle)
    if transportCandidate ~= nil then
        authoredCarrier = (transportCandidate as DynamicTable).carrier
    end
    if type(metadata.railVehicle) == "table" then
        if authoredCarrier == "TRAM" then
            return "TRAM"
        end
        return "RAIL"
    end
    if authoredCarrier == "RAIL" or authoredCarrier == "TRAM" then
        return authoredCarrier as SwayingWayingCarrier
    end
    return nil
end

local function containsPassenger(values: any): boolean
    local entries = dynamicArray(values)
    if entries == nil then
        return false
    end
    for _, entry in ipairs(entries as {any}) do
        if entry == "PASSENGERS" then
            return true
        end
    end
    return false
end

local function carriesPassengers(transportVehicle: DynamicTable): boolean
    local compartments = dynamicArray(transportVehicle.compartments)
        or dynamicArray(transportVehicle.compartmentsList)
    if compartments == nil then
        return false
    end
    for _, compartmentValue in ipairs(compartments as {any}) do
        local compartment = dynamicTable(compartmentValue)
        local loadConfigs = compartment ~= nil
            and dynamicArray((compartment as DynamicTable).loadConfigs)
            or nil
        if loadConfigs ~= nil then
            for _, loadConfigValue in ipairs(loadConfigs as {any}) do
                local loadConfig = dynamicTable(loadConfigValue)
                local cargoEntry = loadConfig ~= nil
                    and dynamicTable((loadConfig as DynamicTable).cargoEntry)
                    or nil
                local cargoTypeSet = cargoEntry ~= nil
                    and dynamicTable((cargoEntry as DynamicTable).cargoTypeSet)
                    or nil
                if cargoTypeSet ~= nil
                    and (
                        containsPassenger(
                            (cargoTypeSet as DynamicTable).cargoClassesIncluded
                        )
                        or containsPassenger(
                            (cargoTypeSet as DynamicTable).cargoTypesIncluded
                        )
                    )
                then
                    return true
                end
            end
        end
    end
    return false
end

local function vehicleTags(transportVehicle: DynamicTable): VehicleTags
    local result: VehicleTags = {
        none = false,
        onlyCamera = false,
        noCamera = false,
        rougher = false,
        smoother = false,
        quick = false,
        slow = false,
    }
    local tags = dynamicArray(transportVehicle.filterTags)
    if tags == nil then
        return result
    end
    for _, value in ipairs(tags as {any}) do
        if value == constants.NONE_TAG then
            result.none = true
        elseif value == constants.ONLY_CAMERA_TAG then
            result.onlyCamera = true
        elseif value == constants.NO_CAMERA_TAG then
            result.noCamera = true
        elseif value == constants.ROUGHER_TAG then
            result.rougher = true
        elseif value == constants.SMOOTHER_TAG then
            result.smoother = true
        elseif value == constants.QUICK_TAG then
            result.quick = true
        elseif value == constants.SLOW_TAG then
            result.slow = true
        end
    end
    return result
end

local function authoredVehicleFactor(
    fileName: string,
    tags: VehicleTags
): number
    if tags.rougher and tags.smoother then
        logger.warnOnce(
            "vehicle-response-conflict:" .. fileName,
            "Ignoring conflicting swaying_waying_rougher and "
                .. "swaying_waying_smoother tags on "
                .. fileName
        )
        return 1.0
    elseif tags.rougher then
        return constants.ROUGH_FACTOR
    elseif tags.smoother then
        return constants.SMOOTH_FACTOR
    end
    return 1.0
end

local function authoredMotionProfile(
    fileName: string,
    tags: VehicleTags
): SwayingWayingMotionProfile
    if tags.quick and tags.slow then
        logger.warnOnce(
            "vehicle-profile-conflict:" .. fileName,
            "Ignoring conflicting swaying_waying_quick and "
                .. "swaying_waying_slow tags on "
                .. fileName
        )
        return "DEFAULT"
    elseif tags.quick then
        return "QUICK"
    elseif tags.slow then
        return "SLOW"
    end
    return "DEFAULT"
end

local function vehicleMotionSettings(
    fileName: string,
    metadata: DynamicTable,
    vehicleVariation: number
): VehicleMotionSettings | nil
    local transportVehicle = dynamicTable(metadata.transportVehicle)
    if transportVehicle == nil then
        return {
            swayEnabled = true,
            cameraEnabled = true,
            swayFactor = 1.0,
            profile = "DEFAULT",
        }
    end
    local presentTransportVehicle = transportVehicle as DynamicTable
    local tags = vehicleTags(presentTransportVehicle)
    if tags.none then
        return nil
    end
    if tags.onlyCamera then
        return { swayEnabled = false, cameraEnabled = not tags.noCamera, swayFactor = 1.0, profile = "DEFAULT" }
    end
    local automaticFactor = 1.0
    if vehicleVariation > 0.0 then
        automaticFactor = vehicleResponse.comfortFactor(
            presentTransportVehicle.comfortFactor,
            carriesPassengers(presentTransportVehicle)
        )
        if vehicleVariation ~= 1.0 then
            automaticFactor = vehicleResponse.scaleFromNeutral(
                automaticFactor,
                vehicleVariation
            )
        end
    end
    return {
        swayEnabled = true,
        cameraEnabled = not tags.noCamera,
        swayFactor = automaticFactor
            * authoredVehicleFactor(fileName, tags),
        profile = authoredMotionProfile(fileName, tags),
    }
end

local function referencesAnimationFile(value: any, fileName: string): boolean
    local animation = dynamicTable(value)
    local params = animation ~= nil
        and dynamicTable((animation as DynamicTable).params)
        or nil
    return params ~= nil
        and (params as DynamicTable).id == fileName
end

local function collectAuthoredSwayChannels(
    value: any,
    channels: AuthoredSwayChannels,
    depth: integer
)
    if channels.sway and channels.tenderSway then
        return
    end
    local candidate = dynamicTable(value)
    if candidate == nil or depth > MAX_NODE_DEPTH then
        return
    end
    local node = candidate as ModelNode
    local animations = dynamicTable(node.animations)
    if animations ~= nil then
        local present = animations as DynamicTable
        channels.sway = channels.sway
            or referencesAnimationFile(
                present[constants.AUTHORED_SWAY_ANIMATION],
                constants.BASE_TILT_ANIMATION
            )
        channels.tenderSway = channels.tenderSway
            or referencesAnimationFile(
                present[constants.AUTHORED_TENDER_SWAY_ANIMATION],
                constants.BASE_TILT_ANIMATION
            )
    end
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            collectAuthoredSwayChannels(child, channels, depth + 1)
            if channels.sway and channels.tenderSway then
                break
            end
        end
    end
end

local function activeLodCount(
    lods: {any},
    transformatorConfig: DynamicTable | nil
): integer
    if transformatorConfig == nil then
        return #lods
    end
    local skipFromLod = positiveInteger(
        (transformatorConfig as DynamicTable).skipFromLod
    )
    if skipFromLod == nil then
        return #lods
    end
    return math.min(#lods, skipFromLod)
end

local function distanceLodCount(fileName: string, lods: {any}): integer | nil
    local closestCount = #lods
    local closestDifference = math.huge
    local previousEnd = 0.0
    for lodIndex, lodValue in ipairs(lods) do
        local lod = dynamicTable(lodValue)
        local visibleTo: any = nil
        if lod ~= nil then
            visibleTo = (lod as DynamicTable).visibleTo
        end
        if visibleTo == nil then
            logger.debug(
                "Using legacy sway LOD selection on " .. fileName
                    .. ": missing visibleTo for LOD " .. (lodIndex - 1)
            )
            return nil
        end
        if not validLodDistance(visibleTo)
            or (visibleTo as number) < previousEnd
        then
            logger.warnOnce(
                "lod-distance:" .. fileName,
                "Using legacy sway LOD selection on " .. fileName
                    .. ": invalid or unordered visibleTo for LOD " .. (lodIndex - 1)
            )
            return nil
        end
        local distance = visibleTo as number
        local difference = math.abs(distance - SWAY_CUTOFF_DISTANCE)
        if distance >= MIN_SWAY_CUTOFF_DISTANCE and difference < closestDifference then
            closestCount = lodIndex
            closestDifference = difference
        end
        previousEnd = distance
    end
    return closestCount
end

local function injectionLodCount(
    fileName: string,
    lods: {any},
    transformatorConfig: DynamicTable | nil,
    options: AuthorOptions,
    originalTransformator: any
): integer, integer | nil
    if options.skipFromLod ~= nil then
        local authored = options.skipFromLod as integer
        local inherited = activeLodCount(lods, transformatorConfig)
        return authored, math.max(authored, inherited)
    end
    local distanceCount = distanceLodCount(fileName, lods)
    local defaultCount = distanceCount or math.min(#lods, FALLBACK_ACTIVE_LOD_COUNT)
    if transformatorConfig == nil then
        return defaultCount, nil
    end
    local rawInherited = (transformatorConfig as DynamicTable).skipFromLod
    if rawInherited == nil then
        return distanceCount or #lods, distanceCount ~= nil and #lods or nil
    end
    local inherited = positiveInteger(rawInherited)
    if inherited == nil then
        logger.warnOnce(
            "inherited-lod:" .. fileName,
            "Replacing invalid inherited skipFromLod on " .. fileName
        )
        return distanceCount or #lods, #lods
    end
    local inheritedCount = math.min(#lods, inherited)
    if distanceCount ~= nil then
        local swayCount = compatibility.isDirect(originalTransformator)
            and distanceCount as integer
            or math.min(distanceCount as integer, inheritedCount)
        return swayCount, swayCount > inheritedCount and swayCount or nil
    end
    if inheritedCount < defaultCount
        and compatibility.isDirect(originalTransformator)
    then
        return defaultCount, defaultCount
    end
    return inheritedCount, nil
end

local function hasAuthoredSwayAnimations(
    model: DynamicTable,
    transformatorConfig: DynamicTable | nil
): boolean
    local lodsCandidate = dynamicArray(model.lods)
    if lodsCandidate == nil then
        return false
    end
    local lods = lodsCandidate as {any}
    local activeCount = activeLodCount(lods, transformatorConfig)
    if activeCount == 0 then
        return false
    end
    for lodIndex = 1, activeCount do
        local lod = dynamicTable(lods[lodIndex])
        local root = lod ~= nil
            and nodes.get((lod as DynamicTable).node)
            or nil
        if root == nil then
            return false
        end
        local channels: AuthoredSwayChannels = {
            sway = false,
            tenderSway = false,
        }
        collectAuthoredSwayChannels(root, channels, 0)
        if not channels.sway or not channels.tenderSway then
            return false
        end
    end
    return true
end

local function modelAxisSignFor(lods: {any}): number
    for _, lodValue in ipairs(lods) do
        local lod = dynamicTable(lodValue)
        local root = lod ~= nil
            and nodes.get((lod as DynamicTable).node)
            or nil
        if root ~= nil then
            return nodes.transform(root)[1] < 0 and -1.0 or 1.0
        end
    end
    return 1.0
end

local function boundsFrom(value: any): {any} | nil, {any} | nil
    local candidate = dynamicTable(value)
    if candidate == nil then
        return nil, nil
    end
    local bounds = candidate as DynamicTable
    return dynamicArray(bounds.bbMin), dynamicArray(bounds.bbMax)
end

local function pivotHeight(model: DynamicTable): number
    local minimum: {any} | nil = nil
    local maximum: {any} | nil = nil
    local metadataCandidate = dynamicTable(model.metadata)
    if metadataCandidate ~= nil then
        local extent = (metadataCandidate as DynamicTable).extent
        minimum, maximum = boundsFrom(extent)
    end
    if minimum == nil or maximum == nil then
        minimum, maximum = boundsFrom(model.boundingInfo)
    end
    if minimum == nil or maximum == nil then
        return DEFAULT_PIVOT_HEIGHT
    end
    local minZ = tonumber((minimum as {any})[3])
    local maxZ = tonumber((maximum as {any})[3])
    if minZ == nil or maxZ == nil or maxZ <= minZ then
        return DEFAULT_PIVOT_HEIGHT
    end
    return math.max(
        MIN_PIVOT_HEIGHT,
        math.min(
            MAX_PIVOT_HEIGHT,
            minZ + (maxZ - minZ) * PIVOT_HEIGHT_RATIO
        )
    )
end

local function longitudinalLength(model: DynamicTable): number | nil
    local minimum: {any} | nil = nil
    local maximum: {any} | nil = nil
    local metadata = dynamicTable(model.metadata)
    if metadata ~= nil then
        minimum, maximum = boundsFrom((metadata as DynamicTable).extent)
    end
    if minimum == nil or maximum == nil then
        minimum, maximum = boundsFrom(model.boundingInfo)
    end
    if minimum == nil or maximum == nil then
        return nil
    end
    local minX = tonumber((minimum as {any})[1])
    local maxX = tonumber((maximum as {any})[1])
    if minX == nil
        or maxX == nil
        or minX ~= minX
        or maxX ~= maxX
        or minX <= -math.huge
        or maxX >= math.huge
        or maxX <= minX
    then
        return nil
    end
    return maxX - minX
end

local function railVehicleConfig(metadata: DynamicTable): DynamicTable | nil
    local railVehicle = dynamicTable(metadata.railVehicle)
    if railVehicle == nil then
        return nil
    end
    return dynamicTable((railVehicle as DynamicTable).config)
end

local function vehiclePlacementData(bindings: {SwayingWaying.ModelReference}): PlacementData
    local result: PlacementData = { groups = {}, extents = {} }
    for _, binding in ipairs(bindings) do
        if binding.kind == "placement" then
            local group = binding.target
            result.groups[group] = true
            local position = binding.owner.position
            if type(position) == "number" and (position as number) > -math.huge and (position as number) < math.huge then
                local extent = result.extents[group]
                if extent == nil then
                    result.extents[group] = { minimum = position as number, maximum = position as number, count = 1 }
                else
                    local present = extent as PlacementExtent
                    present.minimum = math.min(present.minimum, position as number)
                    present.maximum = math.max(present.maximum, position as number)
                    present.count = present.count + 1
                end
            end
        end
    end
    return result
end

local function extentWheelbase(extent: PlacementExtent | nil): number | nil
    if extent == nil then
        return nil
    end
    local present = extent as PlacementExtent
    local span = present.maximum - present.minimum
    if present.count < 2 or span < constants.MIN_WHEELBASE then
        return nil
    end
    return math.min(span, constants.MAX_WHEELBASE)
end

local function inferredWheelbase(
    model: DynamicTable,
    placement: PlacementData,
    group: string | nil
): number
    if group ~= nil then
        local grouped = extentWheelbase(placement.extents[group as string])
        if grouped ~= nil then
            return grouped
        end
    else
        local representative = 0.0
        for _, extent in pairs(placement.extents) do
            local wheelbase = extentWheelbase(extent)
            if wheelbase ~= nil then
                representative = math.max(representative, wheelbase)
            end
        end
        if representative > 0.0 then
            return representative
        end
    end

    local length = longitudinalLength(model)
    if length == nil then
        return constants.DEFAULT_WHEELBASE
    end
    return math.max(
        constants.MIN_WHEELBASE,
        math.min(constants.MAX_WHEELBASE, length * 0.65)
    )
end

local function axleNames(metadata: DynamicTable): StringSet
    local names: StringSet = {}
    local config = railVehicleConfig(metadata)
    if config == nil then
        return names
    end
    local axles = dynamicArray((config as DynamicTable).axles)
    if axles ~= nil then
        for _, name in ipairs(axles as {any}) do
            if type(name) == "string" then
                names[name as string] = true
            end
        end
    end
    return names
end

local module: SwayingWaying.ModelPolicy = {
    options = authoring.options,
    carrier = carrierOf,
    vehicleSettings = vehicleMotionSettings,
    lodCount = injectionLodCount,
    authoredSway = hasAuthoredSwayAnimations,
    axisSign = modelAxisSignFor,
    pivot = pivotHeight,
    wheelbase = inferredWheelbase,
    placement = vehiclePlacementData,
    axles = axleNames,
    referencesAnimationFile = referencesAnimationFile,
}
return module
