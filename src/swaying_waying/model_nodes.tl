local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local dynamicTable = validation.asTable
local dynamicArray = validation.asArray
local safeNodeSuffix = validation.nodeSuffix
local constants = ug_require(
    "apasz_swaying_waying::/swaying_waying/constants.lua"
) as SwayingWaying.Constants
local type DynamicTable = SwayingWaying.RawTable
local type ModelNode = SwayingWaying.ModelNode
local type NameMap = {string: string}
local type StringSet = {string: boolean}
local TRANSFORM_SIZE = 16
local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH
local ROOT_NODE_NAME = constants.ROOT_NODE
local MOVED_MESH_SUFFIX = "_swaying_waying_mesh"

local function nodeTable(value: any): ModelNode | nil
    if type(value) == "table" then
        return value as ModelNode
    end
    return nil
end

local ROOT_CONTENT_KEYS: StringSet = {
    mesh = true,
    materials = true,
    skin = true,
    skinMaterials = true,
    meshes = true,
}

local function identityTransform(z: number): {number}
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, z, 1,
    }
end

local function transformOf(node: ModelNode | nil): {number}
    if node ~= nil and (node as ModelNode).transf ~= nil then
        return (node as ModelNode).transf as {number}
    end
    return identityTransform(0.0)
end

local function countNamedNodes(
    value: any,
    target: string,
    depth: integer
): integer
    local candidate = dynamicTable(value)
    if candidate == nil or depth > MAX_NODE_DEPTH then
        return 0
    end
    local node = candidate as ModelNode
    local count = node.name == target and 1 or 0
    local children = node.children
    if children ~= nil then
        for _, child in ipairs(children as {ModelNode}) do
            count = count + countNamedNodes(child, target, depth + 1)
        end
    end
    return count
end

local function multiplyTransforms(left: {number}, right: {number}): {number}
    local result: {number} = {}
    for column = 0, 3 do
        for row = 0, 3 do
            local value = 0.0
            for index = 0, 3 do
                value = value
                    + left[index * 4 + row + 1]
                        * right[column * 4 + index + 1]
            end
            result[column * 4 + row + 1] = value
        end
    end
    return result
end

local function inverseAffineTransform(transform: {number}): {number} | nil
    if transform[4] ~= 0 or transform[8] ~= 0
        or transform[12] ~= 0 or transform[16] ~= 1
    then
        return nil
    end
    local a, b, c = transform[1], transform[5], transform[9]
    local d, e, f = transform[2], transform[6], transform[10]
    local g, h, i = transform[3], transform[7], transform[11]
    local determinant = a * (e * i - f * h)
        - b * (d * i - f * g) + c * (d * h - e * g)
    if determinant == 0 or determinant ~= determinant
        or math.abs(determinant) == math.huge
    then
        return nil
    end
    local inverse: {number} = {
        (e * i - f * h) / determinant,
        (f * g - d * i) / determinant,
        (d * h - e * g) / determinant,
        0,
        (c * h - b * i) / determinant,
        (a * i - c * g) / determinant,
        (b * g - a * h) / determinant,
        0,
        (b * f - c * e) / determinant,
        (c * d - a * f) / determinant,
        (a * e - b * d) / determinant,
        0,
        0, 0, 0, 1,
    }
    for row = 1, 3 do
        inverse[12 + row] = -(
            inverse[row] * transform[13]
                + inverse[4 + row] * transform[14]
                + inverse[8 + row] * transform[15]
        )
    end
    for _, value in ipairs(inverse) do
        if value ~= value or math.abs(value) == math.huge then
            return nil
        end
    end
    return inverse
end

local function nameOf(node: ModelNode, fallback: string): string
    return node.name or fallback
end

local function sectionFrame(
    node: ModelNode,
    index: SwayingWaying.NodeIndex,
    section: SwayingWaying.ModelSection,
    pivotHeight: number,
    lod: integer,
    motionPivot: number | nil
): SwayingWaying.MotionFrame
    local label = "swayingWaying.sections[" .. section.index .. "] group '" .. nameOf(node, section.group)
        .. "' in LOD " .. lod
    local world = transformOf(node)
    local parent = index.parents[node]
    while parent ~= nil do
        world = multiplyTransforms(transformOf(parent), world)
        parent = index.parents[parent]
    end
    local inverse = inverseAffineTransform(world)
    assert(inverse ~= nil, label .. " has a singular or non-affine coordinate frame")
    local frame = identityTransform(0.0)
    if section.axes == "group" then
        for column = 0, 2 do
            local offset = column * 4
            local length = math.sqrt(world[offset + 1] ^ 2 + world[offset + 2] ^ 2 + world[offset + 3] ^ 2)
            assert(length > 0 and length < math.huge, label .. " has an invalid axis")
            for row = 1, 3 do
                frame[offset + row] = world[offset + row] / length
            end
        end
        for first = 0, 1 do
            for second = first + 1, 2 do
                local dot = 0.0
                for row = 1, 3 do
                    dot = dot + frame[first * 4 + row] * frame[second * 4 + row]
                end
                assert(math.abs(dot) < 0.000001,
                    label .. " has sheared group axes; use axes = 'model'")
            end
        end
    end
    local pivot = section.pivot
    local offset = motionPivot or pivotHeight
    frame[13] = (pivot ~= nil and (pivot as SwayingWaying.Vector3).x or world[13]) - frame[9] * offset
    frame[14] = (pivot ~= nil and (pivot as SwayingWaying.Vector3).y or world[14]) - frame[10] * offset
    frame[15] = (pivot ~= nil and (pivot as SwayingWaying.Vector3).z or pivotHeight) - frame[11] * offset
    local frameInverse = inverseAffineTransform(frame)
    assert(frameInverse ~= nil, label .. " has an invalid motion frame")
    return {
        fromBody = multiplyTransforms(inverse as {number}, frame),
        toBody = multiplyTransforms(frameInverse as {number}, world),
    }
end

local function hasNodeContent(node: ModelNode): boolean
    for key in pairs(ROOT_CONTENT_KEYS) do
        if (node as DynamicTable)[key] ~= nil then
            return true
        end
    end
    return false
end

local function moveNodeContent(
    node: ModelNode,
    movedMeshes: NameMap,
    names: SwayingWaying.WrapperRegistry
): ModelNode | nil
    local moved: ModelNode | nil = nil
    for key in pairs(ROOT_CONTENT_KEYS) do
        if (node as DynamicTable)[key] ~= nil then
            if moved == nil then
                local nodeName = nameOf(node, "node")
                local meshName = node.name ~= nil and movedMeshes[nodeName] or nil
                if meshName == nil then
                    local baseName = nodeName .. MOVED_MESH_SUFFIX
                    meshName = baseName
                    local suffix = 1
                    while names.reserved[meshName] do
                        suffix = suffix + 1
                        meshName = baseName .. "_" .. suffix
                    end
                    names.reserved[meshName] = true
                    if node.name ~= nil then
                        movedMeshes[nodeName] = meshName
                    end
                end
                moved = {
                    name = meshName,
                    transf = identityTransform(0.0),
                }
            end
            local movedTable = moved as ModelNode
            (movedTable as DynamicTable)[key] = (node as DynamicTable)[key]
            (node as DynamicTable)[key] = nil
        end
    end
    return moved
end

local function registry(indices: {ModelNode: SwayingWaying.NodeIndex}): SwayingWaying.WrapperRegistry
    local result: SwayingWaying.WrapperRegistry = { names = {}, reserved = {} }
    for _, index in pairs(indices) do
        for name in pairs(index.names) do
            result.reserved[name] = true
        end
    end
    return result
end

local function wrapperNames(nodeName: string, isRoot: boolean, names: SwayingWaying.WrapperRegistry): SwayingWaying.WrappedNode
    local key = isRoot and "root" or "node:" .. nodeName
    local cached = names.names[key]
    if cached ~= nil then
        return cached
    end
    local baseSuffix = isRoot and "" or "_" .. safeNodeSuffix(nodeName)
    local suffix = baseSuffix
    local index = 1
    while true do
        local wrapped: SwayingWaying.WrappedNode = {
            swayName = constants.SWAY_NODE .. suffix,
            pitchName = constants.PITCH_NODE .. suffix,
            rollName = constants.ROLL_NODE .. suffix,
            contentName = constants.SWAY_CONTENT_NODE .. suffix,
        }
        if not names.reserved[wrapped.swayName] and not names.reserved[wrapped.pitchName]
            and not names.reserved[wrapped.rollName] and not names.reserved[wrapped.contentName]
        then
            names.names[key] = wrapped
            names.reserved[wrapped.swayName] = true
            names.reserved[wrapped.pitchName] = true
            names.reserved[wrapped.rollName] = true
            names.reserved[wrapped.contentName] = true
            return wrapped
        end
        index = index + 1
        suffix = baseSuffix .. "_" .. index
    end
end

local function fileAnimation(
    animationName: string,
    fileName: string
): {string: SwayingWaying.FileAnimation}
    return {
        [animationName] = {
            params = { id = fileName },
            type = "FILE_REF",
        },
    }
end

local function wrappedMotionNode(
    wrapped: SwayingWaying.WrappedNode,
    content: ModelNode,
    pivot: number,
    animations: SwayingWaying.MotionAnimations | nil
): ModelNode
    if animations ~= nil
        and (animations as SwayingWaying.MotionAnimations).pitch ~= nil
        and (animations as SwayingWaying.MotionAnimations).heave ~= nil
    then
        local present = animations as SwayingWaying.MotionAnimations
        return {
            name = wrapped.swayName,
            transf = identityTransform(0.0),
            animations = fileAnimation(
                present.heave as string,
                constants.HEAVE_ANIMATION_FILE
            ),
            children = {
                {
                    name = wrapped.pitchName,
                    transf = identityTransform(pivot),
                    animations = fileAnimation(
                        present.pitch as string,
                        constants.PITCH_ANIMATION_FILE
                    ),
                    children = {
                        {
                            name = wrapped.rollName,
                            transf = identityTransform(0.0),
                            animations = fileAnimation(
                                present.roll,
                                constants.BASE_TILT_ANIMATION
                            ),
                            children = { content },
                        },
                    },
                },
            },
        }
    end

    local swayNode: ModelNode = {
        name = wrapped.swayName,
        transf = identityTransform(pivot),
        children = { content },
    }
    if animations ~= nil then
        swayNode.animations = fileAnimation(
            (animations as SwayingWaying.MotionAnimations).roll,
            constants.BASE_TILT_ANIMATION
        )
    end
    return swayNode
end

local function writableChildren(root: ModelNode): {ModelNode}
    local children = root.children
    if children ~= nil then
        return children as {ModelNode}
    end
    local result: {ModelNode} = {}
    root.children = result
    return result
end

local function ensureAttachmentAnchor(
    root: ModelNode,
    target: string
)
    if countNamedNodes(root, target, 0) > 0 then
        return
    end
    local children = writableChildren(root)
    children[#children + 1] = {
        name = target,
        transf = identityTransform(0.0),
    }
end

local function ensureMotionAnchor(
    node: ModelNode,
    pivot: number,
    wrapped: SwayingWaying.WrappedNode
)
    if countNamedNodes(node, wrapped.contentName, 0) > 0 then
        return
    end

    local content: ModelNode = {
        name = wrapped.contentName,
        transf = identityTransform(-pivot),
        children = {},
    }
    local children = writableChildren(node)
    children[#children + 1] = wrappedMotionNode(
        wrapped,
        content,
        pivot,
        nil
    )
end

local function ensureRootMotionAnchor(root: ModelNode, pivot: number, names: SwayingWaying.WrapperRegistry)
    ensureMotionAnchor(root, pivot, wrapperNames(ROOT_NODE_NAME, true, names))
end

local function wrapNode(
    node: ModelNode,
    context: SwayingWaying.LodContext,
    isRoot: boolean,
    animations: SwayingWaying.MotionAnimations | nil,
    frame: SwayingWaying.MotionFrame | nil,
    sectionNames: SwayingWaying.WrappedNode | nil
): SwayingWaying.WrappedNode | nil
    local nodeName = nameOf(node, "node")
    local wrapped = sectionNames or wrapperNames(nodeName, isRoot, context.model.wrappers)
    local childrenCandidate = node.children
    local children: {ModelNode} = childrenCandidate ~= nil
        and childrenCandidate as {ModelNode}
        or {}
    for _, child in ipairs(children) do
        if child.name == wrapped.swayName then
            return wrapped
        end
    end

    local fixedChildren: {ModelNode} = {}
    local swayingChildren: {ModelNode} = {}
    local movedContent = moveNodeContent(node, context.model.references.meshes, context.model.wrappers)
    if movedContent ~= nil then
        swayingChildren[#swayingChildren + 1] = movedContent
    end
    for _, child in ipairs(children) do
        if context.fixedBranches[child] then
            fixedChildren[#fixedChildren + 1] = child
        else
            swayingChildren[#swayingChildren + 1] = child
        end
    end
    if #swayingChildren == 0 then
        return nil
    end

    local content: ModelNode = {
        name = wrapped.contentName,
        transf = identityTransform(-context.model.pivot),
        children = swayingChildren,
    }
    local swayNode = wrappedMotionNode(wrapped, content, context.model.pivot, animations)
    if frame ~= nil then
        local present = frame as SwayingWaying.MotionFrame
        swayNode.transf = multiplyTransforms(
            present.fromBody,
            transformOf(swayNode)
        )
        content.transf = multiplyTransforms(
            transformOf(content),
            present.toBody
        )
    end
    fixedChildren[#fixedChildren + 1] = swayNode
    node.children = fixedChildren
    return wrapped
end

local function wrapPlacementLocator(
    node: ModelNode,
    animations: SwayingWaying.MotionAnimations | nil,
    names: SwayingWaying.WrapperRegistry,
    frame: SwayingWaying.MotionFrame | nil,
    sectionNames: SwayingWaying.WrappedNode | nil
): SwayingWaying.WrappedNode | nil
    local nodeName = nameOf(node, "")
    local children = node.children
    if nodeName == ""
        or hasNodeContent(node)
        or node.animations ~= nil
        or (children ~= nil and #children > 0)
    then
        return nil
    end
    local wrapped = sectionNames or wrapperNames(nodeName, false, names)

    local originalLocator: ModelNode = {}
    local originalKeys: {any} = {}
    for key, value in pairs(node as DynamicTable) do
        (originalLocator as DynamicTable)[key] = value
        originalKeys[#originalKeys + 1] = key
    end
    for _, key in ipairs(originalKeys) do
        (node as DynamicTable)[key] = nil
    end

    local locatorTransform = transformOf(originalLocator)
    originalLocator.transf = identityTransform(0.0)
    local contentTransform: {number}
    if frame ~= nil then
        contentTransform = (frame as SwayingWaying.MotionFrame).toBody
    else
        contentTransform = identityTransform(0.0)
    end
    -- Keep the same attachment anchor when another LOD has visible body content.
    local content: ModelNode = {
        name = wrapped.contentName,
        transf = contentTransform,
        children = { originalLocator },
    }
    local motionNode = wrappedMotionNode(
        wrapped,
        content,
        0.0,
        animations
    )
    for key, value in pairs(motionNode as DynamicTable) do
        (node as DynamicTable)[key] = value
    end
    node.transf = locatorTransform
    if frame ~= nil then
        node.transf = multiplyTransforms(locatorTransform, (frame as SwayingWaying.MotionFrame).fromBody)
    end
    return wrapped
end

local function validTransform(value: any): boolean
    local transform = dynamicArray(value)
    if transform == nil or #transform ~= TRANSFORM_SIZE then
        return false
    end
    for index = 1, TRANSFORM_SIZE do
        local component = (transform as {any})[index]
        if type(component) ~= "number" or (component as number) <= -math.huge or (component as number) >= math.huge or component ~= component then
            return false
        end
    end
    return true
end

local function validateNode(value: any, visiting: {ModelNode: boolean}, validated: {ModelNode: boolean}, names: {string: integer}, depth: integer)
    if type(value) ~= "table" then
        error("Model children must be node tables")
    end
    local node = value as ModelNode
    if depth > MAX_NODE_DEPTH then
        error("Model hierarchy exceeds the supported depth")
    end
    if visiting[node] then
        error("Model hierarchy contains a cycle")
    end
    if validated[node] then
        return
    end
    if node.name ~= nil and type(node.name) ~= "string" then
        error("Model node names must be strings")
    end
    if node.name ~= nil and node.name ~= "" then
        local name = node.name as string
        names[name] = (names[name] or 0) + 1
    end
    if node.transf ~= nil then
        assert(validTransform(node.transf), "Model node transforms must contain 16 finite numbers")
    end
    if node.animations ~= nil and type(node.animations) ~= "table" then
        error("Model node animations must be a table")
    end
    if node.children ~= nil then
        if type(node.children) ~= "table" then
            error("Model node children must be an array")
        end
        local count = validation.arraySize(node.children as DynamicTable)
        if count == nil then
            error("Model node children must be a dense array")
        end
        visiting[node] = true
        for index = 1, count as integer do
            validateNode((node.children as {ModelNode})[index], visiting, validated, names, depth + 1)
        end
        visiting[node] = nil
    end
    validated[node] = true
end

local function validate(model: any, original: {ModelNode: SwayingWaying.NodeIndex} | nil): {ModelNode: {string: integer}}
    local result: {ModelNode: {string: integer}} = {}
    local candidate = dynamicTable(model)
    local lods = candidate ~= nil and dynamicArray((candidate as DynamicTable).lods) or nil
    if lods == nil then
        return result
    end
    assert(validation.arraySize(lods as DynamicTable) ~= nil, "Model LODs must be a dense array")
    for _, value in ipairs(lods as {any}) do
        local lod = dynamicTable(value)
        if lod ~= nil and type((lod as DynamicTable).node) == "table" then
            local root = (lod as DynamicTable).node as ModelNode
            local names: {string: integer} = {}
            validateNode(root, {}, {}, names, 0)
            if original ~= nil then
                local previous = (original as {ModelNode: SwayingWaying.NodeIndex})[root]
                assert(previous ~= nil, "Prepared LOD root identity changed")
                for name, count in pairs(names) do
                    local entries = previous.names[name]
                    assert(count <= 1 or (entries ~= nil and count <= #entries),
                        "Adaptation introduced a duplicate node name: " .. name)
                end
            end
            result[root] = names
        end
    end
    return result
end

local module: SwayingWaying.ModelNodes = {
    get = nodeTable,
    validate = validate,
    identity = identityTransform,
    transform = transformOf,
    countNamed = countNamedNodes,
    multiply = multiplyTransforms,
    inverse = inverseAffineTransform,
    validTransform = validTransform,
    name = nameOf,
    hasContent = hasNodeContent,
    ensureAttachmentAnchor = ensureAttachmentAnchor,
    ensureMotionAnchor = ensureMotionAnchor,
    ensureRootMotionAnchor = ensureRootMotionAnchor,
    registry = registry,
    wrapperNames = wrapperNames,
    sectionFrame = sectionFrame,
    wrap = wrapNode,
    wrapLocator = wrapPlacementLocator,
}
return module
