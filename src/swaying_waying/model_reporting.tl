local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua") as SwayingWaying.ModelPolicy
local dynamicTable = validation.asTable
local validLodDistance = validation.nonnegative
local referencesAnimationFile = policy.referencesAnimationFile
local type DynamicTable = SwayingWaying.RawTable
local type NameMap = {string: string}
local type StringSet = {string: boolean}
local type ModelNode = SwayingWaying.ModelNode
local type NodeSet = {ModelNode: boolean}
local type ModelDiagnostics = SwayingWaying.ModelContext
local type LodFailure = SwayingWaying.ModelFailure

local record LodMotionReport
    bodyGroups: StringSet | nil
    motionNodes: {string}
    excludedAxleGroups: StringSet | nil
    excludedPlacementGroups: StringSet | nil
    visuals: integer
    movingVisuals: integer
end

local MOTION_NODE_PREFIX = constants.SWAY_NODE .. "_"

local MOTION_NODE_ANIMATION_FILES: NameMap = {
    [constants.SWAY_ANIMATION] = constants.BASE_TILT_ANIMATION,
    [constants.HEAVE_ANIMATION] = constants.HEAVE_ANIMATION_FILE,
}
for index = 1, constants.MAX_SECTION_COUNT do
    MOTION_NODE_ANIMATION_FILES[constants.SWAY_SECTION_ANIMATION_PREFIX .. index] =
        constants.BASE_TILT_ANIMATION
    MOTION_NODE_ANIMATION_FILES[constants.HEAVE_SECTION_ANIMATION_PREFIX .. index] =
        constants.HEAVE_ANIMATION_FILE
end

local function hasMotionAnimation(node: ModelNode): boolean
    local animations = dynamicTable(node.animations)
    if animations == nil then
        return false
    end
    for name, value in pairs(animations as DynamicTable) do
        if type(name) == "string" then
            local fileName = MOTION_NODE_ANIMATION_FILES[name as string]
            local animation = dynamicTable(value)
            if fileName ~= nil and animation ~= nil
                and (animation as DynamicTable).type == "FILE_REF"
                and referencesAnimationFile(animation, fileName)
            then
                return true
            end
        end
    end
    return false
end

local function collectLodMotion(
    node: ModelNode,
    diagnostics: ModelDiagnostics,
    report: LodMotionReport,
    moving: boolean,
    seen: NodeSet
)
    if seen[node] then
        return
    end
    seen[node] = true
    local nodeName = nodes.name(node, "")
    if (nodeName == constants.SWAY_NODE
        or nodeName:sub(1, #MOTION_NODE_PREFIX) == MOTION_NODE_PREFIX)
        and hasMotionAnimation(node)
    then
        report.motionNodes[#report.motionNodes + 1] = nodeName
        moving = true
    end
    if report.excludedAxleGroups ~= nil and not moving then
        if diagnostics.axleNames[nodeName] then
            (report.excludedAxleGroups as StringSet)[nodeName] = true
        end
        if diagnostics.placementGroups[nodeName]
            and (report.bodyGroups == nil or not (report.bodyGroups as StringSet)[nodeName])
        then
            (report.excludedPlacementGroups as StringSet)[nodeName] = true
        end
    end
    local hasVisual = node.mesh ~= nil or node.skin ~= nil or node.meshes ~= nil
    if hasVisual then
        report.visuals = report.visuals + 1
        if moving then
            report.movingVisuals = report.movingVisuals + 1
        end
    end
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            collectLodMotion(
                child,
                diagnostics,
                report,
                moving,
                seen
            )
        end
    end
end

local function formatGroupNames(groups: StringSet | nil): string
    if groups == nil then
        return "[]"
    end
    local names: {string} = {}
    for name in pairs(groups as StringSet) do
        names[#names + 1] = name
    end
    table.sort(names)
    return "[" .. table.concat(names, ", ") .. "]"
end

local function formatLodDistance(value: any): string
    if value == nil then
        return "unspecified"
    end
    if not validLodDistance(value) then
        return "invalid (" .. tostring(value) .. ")"
    end
    return tostring(value) .. " m"
end

local function lodVisibility(lodValue: any): string
    local lod = dynamicTable(lodValue)
    local visibleFrom: any = nil
    local visibleTo: any = nil
    if lod ~= nil then
        visibleFrom = (lod as DynamicTable).visibleFrom
        visibleTo = (lod as DynamicTable).visibleTo
    end
    return "; visibleFrom=" .. formatLodDistance(visibleFrom)
        .. "; visibleTo=" .. formatLodDistance(visibleTo)
end

local function create(logger: SwayingWaying.Logger, detailed: boolean): SwayingWaying.ModelReports
    local function logAppliedModel(diagnostics: ModelDiagnostics, activeCount: integer, lodCount: integer, sectionCount: integer)
        logger.info(diagnostics.fileName .. ": sway applied; active LODs=" .. activeCount .. "/" .. lodCount
            .. "; sections=" .. math.max(1, sectionCount)
            .. "; original transformator=" .. diagnostics.originalTransformator)
    end

    local function logInactiveLods(
        diagnostics: ModelDiagnostics,
        lods: {any},
        activeCount: integer
    )
        if not detailed then
            return
        end
        for lodIndex = activeCount + 1, #lods do
            logger.info(
                diagnostics.fileName .. " LOD " .. (lodIndex - 1)
                    .. ": inactive (beyond sway LOD limit)"
                    .. lodVisibility(lods[lodIndex])
            )
        end
    end

    local function logActiveLod(
        diagnostics: ModelDiagnostics,
        lodIndex: integer,
        lod: any,
        root: ModelNode | nil,
        bodyGroups: StringSet | nil,
        wrappedCount: integer,
        failure: LodFailure | nil
    )
        if not detailed then
            return
        end
        local report: LodMotionReport = {
            bodyGroups = bodyGroups,
            motionNodes = {},
            excludedAxleGroups = {},
            excludedPlacementGroups = {},
            visuals = 0,
            movingVisuals = 0,
        }
        if root ~= nil then
            collectLodMotion(root, diagnostics, report, false, {})
        end
        if failure ~= nil then
            report.motionNodes = {}
            report.movingVisuals = 0
        end
        table.sort(report.motionNodes)
        local outcome = wrappedCount > 0 and "applied"
            or "not applied (" .. (failure or "no body groups wrapped") .. ")"
        local summary = diagnostics.fileName .. " LOD " .. (lodIndex - 1) .. ": " .. outcome
            .. "; body groups=" .. wrappedCount
            .. "; motion nodes=[" .. table.concat(report.motionNodes, ", ") .. "]"
            .. "; moving visuals=" .. report.movingVisuals .. "/" .. report.visuals
            .. lodVisibility(lod)
        logger.info(summary
            .. "; original transformator=" .. diagnostics.originalTransformator
            .. "; detected body groups=" .. formatGroupNames(report.bodyGroups)
            .. "; excluded axle groups=" .. formatGroupNames(report.excludedAxleGroups)
            .. "; excluded placement groups=" .. formatGroupNames(report.excludedPlacementGroups))
    end

    local function logSkippedActiveLods(
        diagnostics: ModelDiagnostics,
        lods: {any},
        activeCount: integer,
        failure: LodFailure
    )
        logger.info(diagnostics.fileName .. ": sway not applied (" .. failure .. ")")
        if not detailed then
            return
        end
        for lodIndex = 1, activeCount do
            local lod = dynamicTable(lods[lodIndex])
            local root = lod ~= nil and nodes.get((lod as DynamicTable).node) or nil
            logActiveLod(diagnostics, lodIndex, lods[lodIndex], root, nil, 0, failure)
        end
        logInactiveLods(diagnostics, lods, activeCount)
    end

    return { applied = logAppliedModel, active = logActiveLod, inactive = logInactiveLods, skipped = logSkippedActiveLods }
end
local module: SwayingWaying.ModelReporting = { create = create }
return module
