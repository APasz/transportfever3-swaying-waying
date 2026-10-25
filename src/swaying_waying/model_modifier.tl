local origins = ug_require("apasz_swaying_waying::/swaying_waying/origin_loader.lua") as SwayingWaying.OriginLoader
local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua") as SwayingWaying.Settings
local runtimeConfig = ug_require("apasz_swaying_waying::/swaying_waying/runtime_config.lua") as SwayingWaying.RuntimeConfig
local bindings = ug_require("apasz_swaying_waying::/swaying_waying/animation_bindings.lua") as SwayingWaying.AnimationBindings
local analysis = ug_require("apasz_swaying_waying::/swaying_waying/model_analysis.lua") as SwayingWaying.ModelAnalysis
local activeLodRoots = analysis.activeRoots
local validateSectionGroups = analysis.validateSections
local placementBodyTargetsByLod = analysis.placementTargets
local bodyTargetsByLod = analysis.bodyTargets
local automaticSections = analysis.sections

local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua") as SwayingWaying.ModelPolicy
local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua") as SwayingWaying.ModelAuthoring
local authorOptions = policy.options
local carrierOf = policy.carrier
local vehicleMotionSettings = policy.vehicleSettings
local injectionLodCount = policy.lodCount
local hasAuthoredSwayAnimations = policy.authoredSway
local modelAxisSignFor = policy.axisSign
local pivotHeight = policy.pivot
local inferredWheelbase = policy.wheelbase
local vehiclePlacementData = policy.placement
local axleNames = policy.axles

local type MotionSection = SwayingWaying.ModelSection
local type AuthorOptions = SwayingWaying.ModelOptions
local type VehicleMotionSettings = SwayingWaying.VehicleMotionSettings

local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua") as SwayingWaying.ModelCompatibility
local wrapperFor = compatibility.wrapperFor
local defaultTransformator = compatibility.defaultFor

local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local dynamicArray = validation.asArray

local constants = ug_require(
    "apasz_swaying_waying::/swaying_waying/constants.lua"
) as SwayingWaying.Constants
local logger = ug_require(
    "apasz_swaying_waying::/swaying_waying/logger.lua"
) as SwayingWaying.Logger
local reporting = ug_require("apasz_swaying_waying::/swaying_waying/model_reporting.lua") as SwayingWaying.ModelReporting
local normalReports = reporting.create(logger, false)
local detailedReports = reporting.create(logger, true)

local transaction = ug_require(
    "apasz_swaying_waying::/swaying_waying/model_transaction.lua"
) as SwayingWaying.ModelTransaction
local references = ug_require(
    "apasz_swaying_waying::/swaying_waying/model_references.lua"
) as SwayingWaying.ModelReferences

local nodes = ug_require(
    "apasz_swaying_waying::/swaying_waying/model_nodes.lua"
) as SwayingWaying.ModelNodes

local type DynamicTable = SwayingWaying.RawTable
local type StringSet = {string: boolean}
local type NameMap = {string: string}
local type ModelNode = SwayingWaying.ModelNode
local type NodeSet = {ModelNode: boolean}

local type AnimationMap = {string: SwayingWaying.MotionAnimations}

local type ModelDiagnostics = SwayingWaying.ModelContext
local cameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua") as SwayingWaying.ModelCameras
local cameraCompatibility = ug_require("apasz_swaying_waying::/swaying_waying/camera_compatibility.lua") as SwayingWaying.CameraCompatibility

local enum SectionMode
    "shared"
    "authored"
    "inferred"
end

local record SwayInjectionResult
    added: boolean
    modelAxisSign: number
    activeLodCount: integer
    transformatorLodCount: integer | nil
    wheelbases: {number}
    sections: {MotionSection}
    report: function() | nil
    attachments: NameMap
    wrappers: SwayingWaying.WrapperRegistry | nil
end

local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH
local ROOT_NODE_NAME = constants.ROOT_NODE
local OWN_TRANSFORMATORS: StringSet = {
    [constants.TRAIN_TRANSFORMATOR] = true,
    [constants.TILTING_TRANSFORMATOR] = true,
    [constants.TRAM_TRANSFORMATOR] = true,
    [constants.ANY_TRANSFORMATOR] = true,
}
local DEFAULT_LOAD_OPTIONS: SwayingWaying.ModelLoadOptions = { swayEnabled = true, cameraMode = "Disabled" }

local function canOwnSwayChannels(name: any): boolean
    return type(name) == "string" and not compatibility.isDirect(name)
end

local function onlyGroup(groups: StringSet): string | nil
    local result: string | nil = nil
    for name in pairs(groups) do
        if result ~= nil then
            return nil
        end
        result = name
    end
    return result
end

local function onlyMappedTarget(targets: NameMap): string | nil
    local result: string | nil = nil
    for _, target in pairs(targets) do
        if result ~= nil and result ~= target then
            return nil
        end
        result = target
    end
    return result
end

local function isAxleBranch(value: any, branches: NodeSet): boolean
    local candidate = dynamicTable(value)
    return candidate ~= nil and branches[candidate as ModelNode] == true
end

local function indexFixedPlacementBranches(
    placementGroups: StringSet,
    movingTargets: StringSet,
    branches: NodeSet,
    index: SwayingWaying.NodeIndex
)
    for group in pairs(placementGroups) do
        if not movingTargets[group] then
            local entries = index.names[group]
            if entries ~= nil then
                for _, node in ipairs(entries) do
                    local current: ModelNode | nil = node
                    while current ~= nil and not branches[current as ModelNode] do
                        branches[current as ModelNode] = true
                        current = index.parents[current as ModelNode]
                    end
                end
            end
        end
    end
end

local function recordBodyGroup(groups: StringSet | nil, name: string)
    if groups ~= nil then
        (groups as StringSet)[name ~= "" and name or "<unnamed>"] = true
    end
end

local function registerTargets(
    nodeName: string,
    wrapped: SwayingWaying.WrappedNode,
    context: SwayingWaying.LodContext,
    isRoot: boolean,
    retargetPlacement: boolean
)
    if nodeName ~= "" then
        context.model.references.attachments[nodeName] = wrapped.contentName
        if retargetPlacement then
            context.model.references.placements[nodeName] = wrapped.swayName
        end
    end
    if isRoot then
        context.model.references.attachments[ROOT_NODE_NAME] = wrapped.contentName
        if retargetPlacement then
            context.model.references.placements[ROOT_NODE_NAME] = wrapped.swayName
        end
    end
end

local function wrapTargetGroups(
    node: ModelNode,
    targets: StringSet,
    animationsByGroup: AnimationMap | nil,
    defaultAnimations: SwayingWaying.MotionAnimations | nil,
    context: SwayingWaying.LodContext,
    isRoot: boolean,
    retargetPlacement: boolean
): integer
    local nodeName = nodes.name(node, "")
    if targets[nodeName] then
        local animations = animationsByGroup ~= nil
            and (animationsByGroup as AnimationMap)[nodeName]
            or defaultAnimations
        local wrapped = nodes.wrap(node, context, isRoot, animations, nil)
        if wrapped ~= nil then
            recordBodyGroup(context.bodyGroups, nodeName)
            registerTargets(nodeName, wrapped as SwayingWaying.WrappedNode, context, isRoot, retargetPlacement)
            return 1
        end
        local locator = nodes.wrapLocator(node, animations, context.model.wrappers, nil,
            nodes.wrapperNames(nodeName, isRoot, context.model.wrappers))
        if locator ~= nil then
            recordBodyGroup(context.bodyGroups, nodeName)
            registerTargets(nodeName, locator as SwayingWaying.WrappedNode, context, isRoot, retargetPlacement)
            return 1
        end
    end

    local count = 0
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            count = count + wrapTargetGroups(
                child,
                targets,
                animationsByGroup,
                defaultAnimations,
                context,
                false,
                retargetPlacement
            )
        end
    end
    return count
end

local function wrapMixedBranches(
    node: ModelNode,
    context: SwayingWaying.LodContext,
    isRoot: boolean,
    animations: SwayingWaying.MotionAnimations | nil
): integer
    local nodeName = nodes.name(node, "")
    if context.model.axleNames[nodeName] then
        return 0
    end

    local children = node.children
    if children == nil then
        return 0
    end

    local hasAxleBranch = false
    local hasFreeBranch = nodes.hasContent(node)
    for _, child in ipairs(children as {ModelNode}) do
        if isAxleBranch(child, context.fixedBranches) then
            hasAxleBranch = true
        else
            hasFreeBranch = true
        end
    end

    if hasAxleBranch and hasFreeBranch then
        local wrapped = nodes.wrap(node, context, isRoot, animations, nil)
        if wrapped ~= nil then
            recordBodyGroup(context.bodyGroups, nodeName)
            registerTargets(nodeName, wrapped as SwayingWaying.WrappedNode, context, isRoot, true)
            return 1
        end
    end

    local count = 0
    if hasAxleBranch then
        for _, child in ipairs(children as {ModelNode}) do
            if isAxleBranch(child, context.fixedBranches) then
                count = count + wrapMixedBranches(child, context, false, animations)
            end
        end
    end
    return count
end

local function singleBodyContainer(
    root: ModelNode,
    model: ModelDiagnostics,
    placementGroup: string
): ModelNode
    local placementTarget = model.references.placements[placementGroup]
    local contentTarget: string | nil = nil
    for _, wrapped in pairs(model.wrappers.names) do
        if wrapped.swayName == placementTarget then
            contentTarget = wrapped.contentName
            break
        end
    end
    local container = root
    for _ = 1, MAX_NODE_DEPTH do
        local containerName = container == root and ROOT_NODE_NAME or nodes.name(container, "")
        -- Reuse the earlier LOD's container when a later LOD omits sibling
        -- bogies. All LODs share the same retargeted placement reference.
        if contentTarget ~= nil and model.references.attachments[containerName] == contentTarget then
            break
        end
        local children = container.children
        if nodes.hasContent(container)
            or children == nil
            or #children ~= 1
        then
            break
        end
        local child = nodes.get((children as {ModelNode})[1])
        if child == nil
            or model.axleNames[nodes.name(child as ModelNode, "")]
            or nodes.hasContent(child as ModelNode)
            or dynamicArray((child as ModelNode).children) == nil
        then
            break
        end
        -- Earlier wrappers can contain the body, doors, and fixed axles together.
        container = child as ModelNode
    end
    return container
end

local function wrapSingleBodyAttachments(
    node: ModelNode,
    bodyName: string,
    context: SwayingWaying.LodContext,
    animations: SwayingWaying.MotionAnimations | nil,
    depth: integer,
    index: SwayingWaying.NodeIndex
)
    if depth > MAX_NODE_DEPTH then
        return
    end
    local children = node.children
    if children == nil then
        return
    end
    local body: ModelNode | nil = nil
    for _, child in ipairs(children as {ModelNode}) do
        if nodes.name(child, "") == bodyName then
            body = child
            break
        end
    end
    if body ~= nil then
        local bodyTransform = nodes.transform(body)
        local bodyInverse = nodes.inverse(bodyTransform)
        if bodyInverse == nil then
            logger.warnOnce(
                "attachment-frame:" .. context.model.fileName .. ":" .. bodyName,
                "Cannot align body attachments to a singular or invalid transform on " .. context.model.fileName
            )
            return
        end
        for _, child in ipairs(children as {ModelNode}) do
            if child ~= body
                and index.rigid[child] == true
            then
                local attachment = child
                local transform = nodes.transform(attachment)
                local inverse = nodes.inverse(transform)
                if inverse ~= nil then
                    -- Keep authored placement/yaw outside motion, but rotate its
                    -- visible content about the body's context.model.pivot in the body's axes.
                    local frame: SwayingWaying.MotionFrame = {
                        fromBody = nodes.multiply(inverse as {number}, bodyTransform),
                        toBody = nodes.multiply(bodyInverse as {number}, transform),
                    }
                    local wrapped = nodes.wrap(attachment, context, false, animations, frame)
                    if wrapped ~= nil then
                        context.model.references.attachments[nodes.name(attachment, "")] = (wrapped as SwayingWaying.WrappedNode).contentName
                    end
                else
                    logger.warnOnce(
                        "attachment-frame:" .. context.model.fileName .. ":" .. nodes.name(attachment, ""),
                        "Cannot align a body attachment with a singular or invalid transform on " .. context.model.fileName
                    )
                end
            end
        end
        return
    end
    for _, child in ipairs(children as {ModelNode}) do
        wrapSingleBodyAttachments(child, bodyName, context, animations, depth + 1, index)
    end
end

local function lodContext(
    root: ModelNode,
    model: SwayingWaying.ModelContext,
    bodyGroups: StringSet | nil
): SwayingWaying.LodContext
    local context: SwayingWaying.LodContext = {
        model = model,
        fixedBranches = {},
        bodyGroups = bodyGroups,
    }
    if next(model.axleNames) ~= nil then
        for node in pairs(model.indices[root].axles) do
            context.fixedBranches[node] = true
        end
    end
    return context
end

local function ensureInactiveAttachments(root: ModelNode, model: ModelDiagnostics)
    local index = model.indices[root]
    for source, target in pairs(model.references.attachments) do
        local entries = index.names[source]
        if entries ~= nil and #entries == 1 and nodes.countNamed(root, target, 0) == 0 then
            for _, wrapped in pairs(model.wrappers.names) do
                if wrapped.contentName == target then
                    nodes.ensureMotionAnchor(entries[1], model.pivot, wrapped)
                    break
                end
            end
        end
    end
end

local function wrapAutomaticLod(
    root: ModelNode,
    model: SwayingWaying.ModelContext,
    singlePlacementGroup: string | nil,
    stableTargets: StringSet | nil,
    animations: SwayingWaying.MotionAnimations | nil,
    bodyGroups: StringSet | nil
): integer
    local context = lodContext(root, model, bodyGroups)
    if stableTargets ~= nil then
        local bodyName = onlyGroup(stableTargets as StringSet)
        if bodyName ~= nil then
            wrapSingleBodyAttachments(root, bodyName as string, context, animations, 0, model.indices[root])
        end
        indexFixedPlacementBranches(
            model.placementGroups,
            stableTargets as StringSet,
            context.fixedBranches,
            model.indices[root]
        )
        return wrapTargetGroups(root, stableTargets as StringSet, nil, animations, context, true, false)
    end
    local wrappedCount = 0
    if singlePlacementGroup ~= nil then
        local container = singleBodyContainer(root, model, singlePlacementGroup as string)
        local isRoot = container == root
        local wrapped = nodes.wrap(container, context, isRoot, animations, nil)
        if wrapped ~= nil then
            recordBodyGroup(bodyGroups, nodes.name(container, ""))
            local presentWrapped = wrapped as SwayingWaying.WrappedNode
            model.references.placements[singlePlacementGroup as string] = presentWrapped.swayName
            registerTargets(nodes.name(container, ""), presentWrapped, context, isRoot, true)
            wrappedCount = 1
        end
    end
    if wrappedCount == 0 and next(model.placementGroups) ~= nil then
        wrappedCount = wrapTargetGroups(root, model.placementGroups, nil, animations, context, true, true)
    end
    if wrappedCount == 0 then
        wrappedCount = wrapMixedBranches(root, context, true, animations)
    end
    if wrappedCount == 0 then
        local wrapped = nodes.wrap(root, context, true, animations, nil)
        if wrapped ~= nil then
            recordBodyGroup(bodyGroups, nodes.name(root, ""))
            registerTargets(nodes.name(root, ""), wrapped as SwayingWaying.WrappedNode, context, true, true)
            wrappedCount = 1
        end
    end
    return wrappedCount
end

local function wrapSectionLod(
    root: ModelNode,
    model: SwayingWaying.ModelContext,
    sections: {MotionSection},
    lodIndex: integer,
    animations: AnimationMap | nil,
    retargetPlacement: boolean,
    bodyGroups: StringSet | nil
): integer
    local context = lodContext(root, model, bodyGroups)
    local index = model.indices[root]
    local targets: StringSet = {}
    for _, section in ipairs(sections) do
        targets[authoring.group(section, lodIndex - 1)] = true
    end
    if not retargetPlacement then
        indexFixedPlacementBranches(model.placementGroups, targets, context.fixedBranches, index)
    end
    local count = 0
    for _, section in ipairs(sections) do
        local previousCount = count
        local group = authoring.group(section, lodIndex - 1)
        local entries = index.names[group]
        if entries ~= nil and #entries == 1 and not model.axleNames[group] then
            local node = entries[1]
            local names = nodes.wrapperNames(section.group, section.group == ROOT_NODE_NAME, model.wrappers)
            local frame = nodes.sectionFrame(node, index, section, model.pivot, lodIndex - 1)
            local wrapped = nodes.wrap(node, context, node == root,
                animations ~= nil and (animations as AnimationMap)[section.group] or nil, frame, names)
            if wrapped ~= nil then
                registerTargets(group, wrapped as SwayingWaying.WrappedNode, context, node == root, retargetPlacement)
                recordBodyGroup(bodyGroups, group)
                count = count + 1
            else
                -- Empty locators have no nested pivot translation to compensate.
                local locatorFrame = nodes.sectionFrame(node, index, section, model.pivot, lodIndex - 1, 0.0)
                local locator = nodes.wrapLocator(node,
                    animations ~= nil and (animations as AnimationMap)[section.group] or nil,
                    model.wrappers, locatorFrame, names)
                if locator ~= nil then
                    registerTargets(group, locator as SwayingWaying.WrappedNode, context, node == root, retargetPlacement)
                    recordBodyGroup(bodyGroups, group)
                    count = count + 1
                end
            end
        end
        if animations ~= nil and count == previousCount then
            logger.warnOnce("author-section-content:" .. model.fileName .. ":" .. section.index,
                "Skipping sway for " .. model.fileName .. ": swayingWaying.sections[" .. section.index
                    .. "] group '" .. group .. "' in LOD " .. (lodIndex - 1)
                    .. " has no movable body content; select a body group outside fixed axle branches")
            return 0
        end
    end
    return count
end

local function addSwayNodes(
    fileName: string,
    model: any,
    transformatorConfig: DynamicTable | nil,
    originalTransformator: any,
    originalTransformatorName: string,
    options: AuthorOptions,
    secondaryMotionEnabled: boolean,
    detailed: boolean
): SwayInjectionResult
    local reports = detailed and detailedReports or normalReports
    local empty: SwayInjectionResult = {
        added = false,
        modelAxisSign = 1.0,
        activeLodCount = 0,
        transformatorLodCount = nil,
        wheelbases = {},
        sections = {},
        report = nil,
        attachments = {},
        wrappers = nil,
    }
    local modelCandidate = dynamicTable(model)
    if modelCandidate == nil then
        return empty
    end
    local modelTable = modelCandidate as DynamicTable
    local lodCandidate = dynamicArray(modelTable.lods)
    if lodCandidate == nil then
        return empty
    end
    local lods = lodCandidate as {any}

    local metadataCandidate = dynamicTable(modelTable.metadata)
    if metadataCandidate == nil then
        return empty
    end
    local metadata = metadataCandidate as DynamicTable
    if not options.valid or not authoring.validateLods(fileName, options, #lods) then
        return empty
    end
    local activeCount, transformatorLodCount = injectionLodCount(
        fileName,
        lods,
        transformatorConfig,
        options,
        originalTransformator
    )
    local attachmentBindings = references.collect(metadata)
    local placement = vehiclePlacementData(attachmentBindings)
    local targets = placement.groups
    local names = axleNames(metadata)
    local attachmentTargets: NameMap = {}
    local placementTargets: NameMap = {}
    local movedMeshes: NameMap = {}
    local referenceTargets: SwayingWaying.ReferenceTargets = {
        attachments = attachmentTargets,
        placements = placementTargets,
        meshes = movedMeshes,
    }
    local indices = analysis.index(lods, names, targets)
    local diagnostics: ModelDiagnostics = {
        fileName = fileName,
        originalTransformator = originalTransformatorName,
        axleNames = names,
        placementGroups = targets,
        pivot = pivotHeight(modelTable),
        references = referenceTargets,
        wrappers = nodes.registry(indices),
        indices = indices,
    }
    local activeRootsCandidate = activeLodRoots(fileName, lods, activeCount)
    if activeRootsCandidate == nil then
        reports.skipped(diagnostics, lods, activeCount, "invalid active LOD root")
        return empty
    end
    local activeRoots = activeRootsCandidate as {ModelNode}
    local sections: {MotionSection} = options.sections ~= nil
        and options.sections as {MotionSection}
        or {}
    local sectionMode: SectionMode = options.sections ~= nil and "authored" or "shared"
    if sectionMode ~= "shared"
        and not validateSectionGroups(
            fileName,
            activeRoots,
            sections,
            true,
            diagnostics.indices
        )
    then
        reports.skipped(diagnostics, lods, activeCount, "invalid section groups")
        return empty
    end

    local pivot = diagnostics.pivot
    local singlePlacementGroup = onlyGroup(targets)
    local placementBodyTargets: {StringSet} | nil = nil
    if sectionMode == "shared" then
        placementBodyTargets = placementBodyTargetsByLod(
            activeRoots,
            names,
            targets,
            diagnostics.indices
        )
        if placementBodyTargets ~= nil then
            local inferredSections = automaticSections(
                fileName,
                activeRoots,
                (placementBodyTargets as {StringSet})[1],
                placement,
                diagnostics.indices
            )
            if inferredSections ~= nil then
                sections = inferredSections as {MotionSection}
                sectionMode = "inferred"
            end
        end
    end
    local automaticBodyTargets: {StringSet} | nil = nil
    if sectionMode == "shared"
        and next(targets) ~= nil
        and singlePlacementGroup == nil
    then
        local inferredTargets = placementBodyTargets
            or bodyTargetsByLod(activeRoots, names, diagnostics.indices)
        if inferredTargets ~= nil then
            automaticBodyTargets = inferredTargets
        else
            reports.skipped(diagnostics, lods, activeCount, "body groups could not be identified")
            return empty
        end
    end
    local automaticAnimations = bindings.get(0, secondaryMotionEnabled)
    local animationsBySection: AnimationMap = {}
    local wheelbases: {number} = {}
    for _, section in ipairs(sections) do
        animationsBySection[section.group] = bindings.get(
            section.index,
            secondaryMotionEnabled
        )
        wheelbases[section.index] = section.wheelbase
            or options.wheelbase
            or inferredWheelbase(modelTable, placement, authoring.group(section, 0))
    end
    if sectionMode == "shared" then
        wheelbases[1] = options.wheelbase
            or inferredWheelbase(modelTable, placement, nil)
    end
    local added = false
    local wrappedCounts: {integer} = {}
    local reportedGroups: {integer: StringSet} = {}
    local modelAxisSign = sectionMode == "shared" and modelAxisSignFor(lods) or 1.0

    for lodIndex, root in ipairs(activeRoots) do
        local wrappedCount: integer
        local bodyGroups: StringSet | nil = detailed and {} or nil
        if sectionMode ~= "shared" then
            wrappedCount = wrapSectionLod(
                root,
                diagnostics,
                sections,
                lodIndex,
                animationsBySection,
                sectionMode == "authored",
                bodyGroups
            )
        else
            wrappedCount = wrapAutomaticLod(
                root,
                diagnostics,
                singlePlacementGroup,
                automaticBodyTargets ~= nil
                    and (automaticBodyTargets as {StringSet})[lodIndex]
                    or nil,
                automaticAnimations,
                bodyGroups
            )
        end
        if wrappedCount > 0 then
            added = true
        end
        wrappedCounts[lodIndex] = wrappedCount
        reportedGroups[lodIndex] = bodyGroups
    end
    for _, wrappedCount in ipairs(wrappedCounts) do
        if wrappedCount == 0 then
            reports.skipped(diagnostics, lods, activeCount, "no body groups wrapped")
            return empty
        end
    end

    if added then
        local rootTarget = attachmentTargets[ROOT_NODE_NAME]
        local defaultLabelTarget = rootTarget
        local defaultLabels = references.defaultLabels(metadata)
        local hasDefaultLabel = #defaultLabels > 0
        if defaultLabelTarget == nil and hasDefaultLabel then
            defaultLabelTarget = onlyMappedTarget(attachmentTargets)
        end
        local needsInactiveAnchors = activeCount < #lods
            and (
                references.hasReferences(attachmentBindings, referenceTargets)
                or (defaultLabelTarget ~= nil and hasDefaultLabel)
            )
        if needsInactiveAnchors then
            for lodIndex = activeCount + 1, #lods do
                local lod = dynamicTable(lods[lodIndex])
                local root = lod ~= nil
                    and nodes.get((lod as DynamicTable).node)
                    or nil
                if root ~= nil then
                    if sectionMode ~= "shared" then
                        wrapSectionLod(
                            root as ModelNode,
                            diagnostics,
                            sections,
                            lodIndex,
                            nil,
                            sectionMode == "authored",
                            nil
                        )
                    else
                        wrapAutomaticLod(
                            root as ModelNode,
                            diagnostics,
                            singlePlacementGroup,
                            automaticBodyTargets ~= nil
                                and (automaticBodyTargets as {StringSet})[1]
                                or nil,
                            nil,
                            nil
                        )
                    end
                    ensureInactiveAttachments(root as ModelNode, diagnostics)
                    if rootTarget ~= nil then
                        nodes.ensureRootMotionAnchor(root as ModelNode, pivot, diagnostics.wrappers)
                    elseif defaultLabelTarget ~= nil then
                        nodes.ensureAttachmentAnchor(
                            root as ModelNode,
                            defaultLabelTarget as string
                        )
                    end
                end
            end
        end
        references.retarget(attachmentBindings, referenceTargets)
        if defaultLabelTarget ~= nil then
            for _, label in ipairs(defaultLabels) do
                label.childId = defaultLabelTarget
            end
        end
    end
    references.validate(attachmentBindings, referenceTargets, indices, nodes.validate(model, indices))
    return {
        added = added,
        attachments = attachmentTargets,
        wrappers = diagnostics.wrappers,
        modelAxisSign = modelAxisSign,
        activeLodCount = activeCount,
        transformatorLodCount = transformatorLodCount,
        wheelbases = wheelbases,
        sections = sections,
        report = function()
            reports.applied(diagnostics, activeCount, #lods, #sections)
            for lodIndex, root in ipairs(activeRoots) do
                reports.active(diagnostics, lodIndex, lods[lodIndex], root,
                    reportedGroups[lodIndex], wrappedCounts[lodIndex], nil)
            end
            reports.inactive(diagnostics, lods, activeCount)
        end,
    }
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
    end)
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
                return cameraCompatibilityChanged
            end
            local added, updated = applyCameras(fileName, draftTable, cameraPlan as SwayingWaying.CameraPlan, {}, nil)
            if not updated then
                return cameraCompatibilityChanged
            end
            if cameraCompatibilityReady then
                cameraCompatibility.refresh(fileName, draftTable, added)
            end
            local params = draftTransformatorConfig ~= nil and dynamicTable((draftTransformatorConfig as DynamicTable).params) or nil
            if #added.positions > 0 and type(draftName) == "string" and params ~= nil then
                compatibility.refresh(fileName, draftTable, draftName as string, params as DynamicTable)
            end
            return true
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
        local injection = addSwayNodes(
            fileName,
            draft,
            draftTransformatorConfig,
            draftName,
            originalName,
            swayOptions,
            secondaryMotionEnabled,
            detailed
        )
        if not injection.added then
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
            configTable = { skipFromLod = injection.activeLodCount }
            draftMetadata.transformatorConfig = configTable
        end
        if injection.transformatorLodCount ~= nil then
            configTable.skipFromLod = injection.transformatorLodCount
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
                injection.attachments, injection.wrappers)
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
            axisReversed = injection.modelAxisSign < 0,
            vehicleFactor = presentVehicleSettings.swayFactor,
            wheelbase = injection.wheelbases[1] or constants.DEFAULT_WHEELBASE,
            settings = config,
            sections = {},
        }
        for index, section in ipairs(injection.sections) do
            configured.sections[index] = { lag = section.lag, wheelbase = injection.wheelbases[index] }
        end
        runtimeConfig.validate(configured)
        params[constants.RUNTIME_PARAM] = configured

        local transformator = dynamicTable(configTable.transformator)
        if transformator == nil then
            transformator = {}
            configTable.transformator = transformator
        end
        (transformator as DynamicTable).name = wrapperFor(originalName)

        committedReport = injection.report
        return true
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
