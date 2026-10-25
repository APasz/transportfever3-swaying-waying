local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua") as SwayingWaying.ModelCompatibility
local dynamicTable = validation.asTable
local validWheelbase = validation.wheelbase
local type DynamicTable = SwayingWaying.RawTable
local type ModelNode = SwayingWaying.ModelNode
local type StringSet = {string: boolean}
local type NodeSet = {ModelNode: boolean}
local type Indices = {ModelNode: SwayingWaying.NodeIndex}
local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua") as SwayingWaying.ModelAuthoring
local type MotionSection = SwayingWaying.ModelSection
local type PlacementData = SwayingWaying.PlacementData
local type PlacementExtent = SwayingWaying.PlacementExtent
local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH

local record SectionSupport
    group: string
    center: number
end

local function visit(node: ModelNode, parent: ModelNode | nil, index: SwayingWaying.NodeIndex, names: StringSet, placements: StringSet)
    assert(not index.seen[node], "Model hierarchy reuses a node in multiple positions")
    index.seen[node] = true
    index.parents[node] = parent
    local name = nodes.name(node, "")
    local entries = index.names[name]
    if entries == nil then
        entries = {}
        index.names[name] = entries
    end
    entries[#entries + 1] = node
    local hasAxle = names[name] == true
    local swayable = not hasAxle and nodes.hasContent(node)
    local rigid = not hasAxle and node.skin == nil and node.skinMaterials == nil
    local hasContent = nodes.hasContent(node)
    if node.children ~= nil then
        for _, child in ipairs(node.children as {ModelNode}) do
            visit(child, node, index, names, placements)
            hasAxle = hasAxle or index.axles[child] == true
            swayable = swayable or index.swayable[child] == true
            rigid = rigid and index.rigid[child] == true and not placements[nodes.name(child, "")]
            hasContent = true
        end
    end
    if hasAxle then
        index.axles[node] = true
    end
    if not names[name] and swayable then
        index.swayable[node] = true
    end
    if rigid and not hasAxle and hasContent then
        index.rigid[node] = true
    end
end

local function build(lods: {any}, names: StringSet, placements: StringSet): Indices
    local result: Indices = {}
    for _, value in ipairs(lods) do
        local lod = dynamicTable(value)
        local root = lod ~= nil and nodes.get((lod as DynamicTable).node) or nil
        if root ~= nil then
            local index: SwayingWaying.NodeIndex = { names = {}, parents = {}, axles = {}, swayable = {}, rigid = {}, seen = {} }
            visit(root as ModelNode, nil, index, names, placements)
            result[root as ModelNode] = index
        end
    end
    return result
end

local function countNamed(root: ModelNode, name: string, indices: Indices): integer
    local entries = indices[root].names[name]
    return entries ~= nil and #entries or 0
end

local function validateSectionGroups(fileName: string, roots: {ModelNode}, sections: {MotionSection}, warn: boolean, indices: Indices): boolean
    for lodIndex, root in ipairs(roots) do
        local groups: {string: integer} = {}
        for _, section in ipairs(sections) do
            groups[authoring.group(section, lodIndex - 1)] = section.index
        end
        local index = indices[root]
        for _, section in ipairs(sections) do
            local group = authoring.group(section, lodIndex - 1)
            local entries = index.names[group]
            if entries == nil or #entries ~= 1 then
                if warn then
                    logger.warnOnce("author-section-group:" .. fileName .. ":" .. group,
                        "Skipping sway for " .. fileName .. ": swayingWaying.sections[" .. section.index
                            .. "] group '" .. group .. "' must occur exactly once in LOD " .. (lodIndex - 1)
                            .. " (found " .. (entries ~= nil and #entries or 0) .. ")")
                end
                return false
            end
            local parent: ModelNode | nil = index.parents[entries[1]]
            while parent ~= nil do
                local parentName = nodes.name(parent as ModelNode, "")
                if groups[parentName] ~= nil then
                    if warn then
                        logger.warnOnce("author-section-overlap:" .. fileName,
                            "Skipping sway for " .. fileName .. ": swayingWaying.sections[" .. section.index
                                .. "] group '" .. group .. "' is inside section " .. groups[parentName]
                                .. " group '" .. parentName .. "' in LOD " .. (lodIndex - 1))
                    end
                    return false
                end
                parent = index.parents[parent as ModelNode]
            end
        end
    end
    return true
end

local function activeLodRoots(
    fileName: string,
    lods: {any},
    activeCount: integer
): {ModelNode} | nil
    local roots: {ModelNode} = {}
    for lodIndex = 1, activeCount do
        local lod = dynamicTable(lods[lodIndex])
        local root = lod ~= nil
            and nodes.get((lod as DynamicTable).node)
            or nil
        if root == nil then
            logger.warnOnce(
                "missing-root:" .. fileName,
                "Cannot add sway to model without usable LOD root nodes: "
                    .. fileName
            )
            return nil
        end
        roots[lodIndex] = root as ModelNode
    end
    return roots
end

local function collectBodyTargets(
    node: ModelNode,
    names: StringSet,
    axleBranches: NodeSet,
    targets: StringSet,
    isRoot: boolean,
    depth: integer
)
    if depth > MAX_NODE_DEPTH then
        return
    end
    local nodeName = nodes.name(node, "")
    if names[nodeName] then
        return
    end

    local children = node.children
    if children == nil then
        return
    end
    local hasAxleBranch = false
    local hasFreeBranch = nodes.hasContent(node)
    for _, child in ipairs(children as {ModelNode}) do
        if axleBranches[child] == true then
            hasAxleBranch = true
        else
            hasFreeBranch = true
        end
    end
    if not isRoot
        and not compatibility.isBodyContainer(nodeName)
        and nodeName ~= ""
        and hasAxleBranch
        and hasFreeBranch
    then
        targets[nodeName] = true
        return
    end

    if hasAxleBranch then
        for _, child in ipairs(children as {ModelNode}) do
            if axleBranches[child] == true then
                collectBodyTargets(
                    child,
                    names,
                    axleBranches,
                    targets,
                    false,
                    depth + 1
                )
            end
        end
    end
end

local function detectedBodyTargets(
    root: ModelNode,
    names: StringSet,
    indices: Indices
): StringSet
    local detected: StringSet = {}
    if next(names) == nil then
        return detected
    end

    local axleBranches = indices[root].axles
    collectBodyTargets(
        root,
        names,
        axleBranches,
        detected,
        true,
        0
    )
    return detected
end

local function sameStringSet(left: StringSet, right: StringSet): boolean
    for value in pairs(left) do
        if not right[value] then
            return false
        end
    end
    for value in pairs(right) do
        if not left[value] then
            return false
        end
    end
    return true
end

local function collectVisualPlacementTargets(
    node: ModelNode,
    placementGroups: StringSet,
    axleNodeNames: StringSet,
    targets: StringSet,
    depth: integer,
    index: SwayingWaying.NodeIndex
)
    if depth > MAX_NODE_DEPTH then
        return
    end
    local nodeName = nodes.name(node, "")
    if not compatibility.isBodyContainer(nodeName)
        and placementGroups[nodeName]
        and index.swayable[node] == true
    then
        targets[nodeName] = true
    end
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            collectVisualPlacementTargets(
                child,
                placementGroups,
                axleNodeNames,
                targets,
                depth + 1,
                index
            )
        end
    end
end

local function placementBodyTargetsByLod(
    roots: {ModelNode},
    axleNodeNames: StringSet,
    placementGroups: StringSet,
    indices: Indices
): {StringSet} | nil
    if #roots == 0 or next(placementGroups) == nil then
        return nil
    end

    local targetsByLod: {StringSet} = {}
    for lodIndex, root in ipairs(roots) do
        local targets: StringSet = {}
        collectVisualPlacementTargets(
            root,
            placementGroups,
            axleNodeNames,
            targets,
            0,
            indices[root]
        )
        if next(targets) == nil then
            return nil
        end
        if lodIndex > 1
            and not sameStringSet(targetsByLod[1], targets)
        then
            return nil
        end
        for target in pairs(targets) do
            if countNamed(root, target, indices) ~= 1 then
                return nil
            end
        end
        targetsByLod[lodIndex] = targets
    end
    return targetsByLod
end

local function bodyTargetsByLod(
    roots: {ModelNode},
    names: StringSet,
    indices: Indices
): {StringSet} | nil
    if #roots == 0 then
        return nil
    end
    local primaryTargets = detectedBodyTargets(roots[1], names, indices)
    if next(primaryTargets) == nil then
        return nil
    end

    local targetsByLod: {StringSet} = {}
    for lodIndex, root in ipairs(roots) do
        local targets: StringSet = {}
        for target in pairs(primaryTargets) do
            if countNamed(root, target, indices) == 1 then
                targets[target] = true
            end
        end
        if lodIndex > 1 then
            for target in pairs(detectedBodyTargets(root, names, indices)) do
                targets[target] = true
            end
        end
        if next(targets) == nil then
            return nil
        end
        targetsByLod[lodIndex] = targets
    end
    return targetsByLod
end

local function automaticSections(
    fileName: string,
    roots: {ModelNode},
    targets: StringSet,
    placement: PlacementData,
    indices: Indices
): {MotionSection} | nil
    if #roots == 0 or next(targets) == nil then
        return nil
    end

    local supports: {SectionSupport} = {}
    for group in pairs(targets) do
        local extent = placement.extents[group]
        if extent == nil then
            return nil
        end
        local present = extent as PlacementExtent
        local span = present.maximum - present.minimum
        if present.count < 2
            or not validWheelbase(span)
        then
            return nil
        end
        supports[#supports + 1] = {
            group = group,
            center = (present.minimum + present.maximum) * 0.5,
        }
    end
    if #supports < 2 or #supports > constants.MAX_SECTION_COUNT then
        return nil
    end

    table.sort(supports, function(left: SectionSupport, right: SectionSupport): boolean
        if left.center == right.center then
            return left.group < right.group
        end
        return left.center > right.center
    end)
    for index = 2, #supports do
        if supports[index - 1].center - supports[index].center
            < constants.MIN_WHEELBASE
        then
            return nil
        end
    end
    local leadCenter = supports[1].center
    local sections: {MotionSection} = {}
    for index, support in ipairs(supports) do
        sections[index] = {
            group = support.group,
            axes = "model",
            lag = math.max(0.0, leadCenter - support.center),
            wheelbase = nil,
            index = index,
        }
    end
    if not validateSectionGroups(fileName, roots, sections, false, indices) then
        return nil
    end
    return sections
end

local module: SwayingWaying.ModelAnalysis = {
    index = build,
    activeRoots = activeLodRoots,
    validateSections = validateSectionGroups,
    placementTargets = placementBodyTargetsByLod,
    bodyTargets = bodyTargetsByLod,
    sections = automaticSections,
}
return module
