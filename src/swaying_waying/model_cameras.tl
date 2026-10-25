local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua") as SwayingWaying.ModelPolicy
local references = ug_require("apasz_swaying_waying::/swaying_waying/model_references.lua") as SwayingWaying.ModelReferences
local config = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua") as SwayingWaying.CameraConfig
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local type RawTable = SwayingWaying.RawTable
local type ModelNode = SwayingWaying.ModelNode
local type CameraView = SwayingWaying.CameraView

local DEFAULT_FOV = 60.0
local SEATED_EYE_HEIGHT = 1.2
local STANDING_EYE_HEIGHT = 1.6
local AUTHORED_VIEW_DISTANCE = 1.0
local MIN_VIEW_ALIGNMENT = 0.95
local MIN_FORWARD_ALIGNMENT = math.sqrt(0.5)
local MODEL_FORWARD = nodes.identity(0)
local FREIGHT_END_INSET = 0.5
local FREIGHT_HEIGHT_CLEARANCE = 0.5
local MATCH_TOLERANCE = 0.0001
local CAMERA_SAFE_ANIMATION_FILES: {string: boolean} = {
    [constants.BASE_TILT_ANIMATION:gsub("^::", "")] = true,
    ["devers_1::/vehicle/train/devers/ani/devers_roll.ani"] = true,
}

local record Frame
    node: ModelNode
    parent: Frame | nil
    pose: {number}
    moving: boolean
    cameraSafe: boolean
    -- Rigid descendants share this ancestor's placement and animation response.
    dynamicNode: ModelNode
    inverse: {number} | nil
end

local record AuthoredView
    index: integer
    group: string
    transf: {number}
    pose: {number}
    fov: number
end

local type CameraDescriptions = {integer: SwayingWaying.CameraDescriptor}

local record FrameIndex
    root: Frame
    names: {string: Frame}
    duplicates: {string: boolean}
end

local record Bounds
    minimum: {number}
    maximum: {number}
end

local function safeAnimations(node: ModelNode, motion: {string: boolean}): boolean
    if motion[nodes.name(node, "")] or node.animations == nil then
        return true
    end
    for _, entry in pairs(node.animations as {string: any}) do
        local animation = values.asTable(entry)
        local params = animation ~= nil and values.asTable((animation as RawTable).params) or nil
        local id = params ~= nil and (params as RawTable).id or nil
        -- Authored visibility animations can collapse a node's axes to zero.
        -- Native tilt and Real Track Cant use known non-collapsing transforms.
        if animation == nil or (animation as RawTable).type ~= "FILE_REF" or type(id) ~= "string"
            or not CAMERA_SAFE_ANIMATION_FILES[(id as string):gsub("^::", "")]
        then
            return false
        end
    end
    return true
end

local function indexRoot(root: ModelNode, motion: {string: boolean}, placements: {string: boolean}): FrameIndex
    local rootFrame: Frame = {
        node = root, parent = nil, pose = nodes.transform(root), moving = false, cameraSafe = true, dynamicNode = root,
    }
    local result: FrameIndex = { root = rootFrame, names = {}, duplicates = {} }
    local function visit(frame: Frame)
        local name = nodes.name(frame.node, "")
        frame.moving = frame.moving or motion[name] == true
        frame.cameraSafe = frame.cameraSafe and safeAnimations(frame.node, motion)
        local animations = frame.node.animations
        if motion[name] or placements[name] or (animations ~= nil and next(animations as {string: any}) ~= nil) then
            frame.dynamicNode = frame.node
        end
        if name ~= "" then
            if result.names[name] ~= nil then
                result.duplicates[name] = true
            end
            result.names[name] = frame
        end
        local children = frame.node.children
        if children ~= nil then
            for _, child in ipairs(children as {ModelNode}) do
                visit({ node = child, parent = frame, pose = nodes.multiply(frame.pose, nodes.transform(child)),
                    moving = frame.moving, cameraSafe = frame.cameraSafe, dynamicNode = frame.dynamicNode })
            end
        end
    end
    visit(rootFrame)
    return result
end

local function modelRoots(model: RawTable): {ModelNode}
    local lods = values.asArray(model.lods)
    assert(lods ~= nil and #lods > 0, "Camera models need a LOD hierarchy")
    local result: {ModelNode} = {}
    for _, entry in ipairs(lods as {any}) do
        local lod = values.asTable(entry)
        local root = lod ~= nil and nodes.get((lod as RawTable).node) or nil
        assert(root ~= nil, "Camera models need a valid root in every LOD")
        result[#result + 1] = root as ModelNode
    end
    return result
end

local function modelIndices(model: RawTable, motion: {string: boolean}, placements: {string: boolean}): {FrameIndex}
    local result: {FrameIndex} = {}
    for _, root in ipairs(modelRoots(model)) do
        result[#result + 1] = indexRoot(root, motion, placements)
    end
    return result
end

local function frameInverse(frame: Frame): {number}
    if frame.inverse == nil then
        frame.inverse = nodes.inverse(frame.pose)
        assert(frame.inverse ~= nil, "Camera anchor has a singular or non-affine transform")
    end
    return frame.inverse as {number}
end

local function named(index: FrameIndex, name: string): Frame | nil
    if name == "" then
        return index.root
    end
    if index.duplicates[name] then
        return nil
    end
    return index.names[name]
end

local function cameraPositions(metadata: RawTable): {any}
    if metadata.cameraConfig == nil then
        return {}
    end
    local camera = values.asTable(metadata.cameraConfig)
    assert(camera ~= nil, "Camera configuration must be a table")
    local positions = (camera as RawTable).positions
    if positions == nil then
        return {}
    end
    local array = values.asArray(positions)
    assert(array ~= nil and values.arraySize(array as RawTable) ~= nil, "Camera positions must be a dense array")
    return array as {any}
end

local function validCameraTransform(value: any): boolean
    return nodes.validTransform(value) and nodes.inverse(value as {number}) ~= nil
end

local function cameraEntry(entry: any): RawTable
    local candidate = values.asTable(entry)
    assert(candidate ~= nil, "Camera positions must be tables")
    local camera = candidate as RawTable
    assert(camera.group == nil or type(camera.group) == "string", "Camera groups must be node names")
    assert(validCameraTransform(camera.transf), "Camera transforms must be finite, invertible affine matrices")
    local fov = camera.fov
    if fov == nil then
        fov = DEFAULT_FOV
    end
    assert(type(fov) == "number" and (fov as number) > 0 and (fov as number) < 180,
        "Camera FOV must be between 0 and 180 degrees")
    return camera
end

local function validate(model: RawTable, positions: any)
    local entries = values.asArray(positions)
    assert(entries ~= nil and values.arraySize(entries as RawTable) ~= nil, "Camera positions must be a dense array")
    nodes.validate(model)
    local indices = modelIndices(model, {}, {})
    for _, entry in ipairs(entries as {any}) do
        local camera = cameraEntry(entry)
        local group = camera.group as string or ""
        for _, index in ipairs(indices) do
            local frame = named(index, group)
            assert(frame ~= nil, "Camera anchor must occur exactly once in every LOD: " .. group)
            assert(validCameraTransform(nodes.multiply((frame as Frame).pose, camera.transf as {number})),
                "Camera world transforms must be finite, invertible affine matrices")
        end
    end
end

local function authoredViews(metadata: RawTable, index: FrameIndex): {AuthoredView}
    local result: {AuthoredView} = {}
    for cameraIndex, entry in ipairs(cameraPositions(metadata)) do
        local position = cameraEntry(entry)
        local group = position.group
        local name = group ~= nil and group as string or ""
        local frame = named(index, name)
        local fov = position.fov or DEFAULT_FOV
        if frame ~= nil then
            local pose = nodes.multiply((frame as Frame).pose, position.transf as {number})
            assert(validCameraTransform(pose), "Camera world transforms must be finite, invertible affine matrices")
            result[#result + 1] = {
                index = cameraIndex,
                group = name, transf = position.transf as {number}, fov = fov as number,
                pose = pose,
            }
        end
    end
    return result
end

local function samePose(left: {number}, right: {number}): boolean
    for component = 1, 16 do
        local difference = left[component] - right[component]
        if difference ~= difference or math.abs(difference) > MATCH_TOLERANCE then
            return false
        end
    end
    return true
end

local function aligned(left: {number}, right: {number}, column: integer, minimum: number): boolean
    local dot, leftLength, rightLength = 0.0, 0.0, 0.0
    for offset = 1, 3 do
        local a, b = left[column + offset], right[column + offset]
        dot, leftLength, rightLength = dot + a * b, leftLength + a * a, rightLength + b * b
    end
    return dot > 0 and dot * dot >= minimum * minimum * leftLength * rightLength
end

local function nearbyAuthored(pose: {number}, authored: {AuthoredView}): AuthoredView | nil
    local nearest: AuthoredView | nil = nil
    local distance = AUTHORED_VIEW_DISTANCE * AUTHORED_VIEW_DISTANCE
    for _, view in ipairs(authored) do
        local squared = 0.0
        for component = 13, 15 do
            squared = squared + (pose[component] - view.pose[component]) ^ 2
        end
        if squared <= distance and aligned(pose, view.pose, 0, MIN_VIEW_ALIGNMENT)
            and aligned(pose, view.pose, 8, MIN_VIEW_ALIGNMENT)
        then
            nearest, distance = view, squared
        end
    end
    return nearest
end

local function stableGroup(index: FrameIndex, source: Frame, pose: {number}, placement: SwayingWaying.PlacementData): string
    local ancestor: Frame | nil = source
    while ancestor ~= nil do
        local current = ancestor as Frame
        local name = nodes.name(current.node, "")
        if placement.groups[name] and named(index, name) ~= nil then
            return name
        end
        ancestor = current.parent
    end
    -- Some articulated models attach seats to the root rather than their cab section.
    local closest = math.huge
    local selected = nodes.name(index.root.node, "")
    local tied = false
    for group, extent in pairs(placement.extents) do
        if extent.count >= 2 and named(index, group) ~= nil then
            local distance = math.abs(pose[13] - (extent.minimum + extent.maximum) * 0.5)
            if distance < closest - MATCH_TOLERANCE then
                closest, selected, tied = distance, group, false
            elseif math.abs(distance - closest) <= MATCH_TOLERANCE then
                tied = true
            end
        end
    end
    return tied and nodes.name(index.root.node, "") or selected
end

local function seatView(index: FrameIndex, seat: RawTable, authored: {AuthoredView},
    placement: SwayingWaying.PlacementData): CameraView | nil
    local group = seat.group
    local frame = (group == nil or type(group) == "string") and named(index, group as string or "") or nil
    if frame == nil or not validCameraTransform(seat.transf) then
        return nil
    end
    local standing = seat.animation == "idle" or seat.animation == "walk"
    local eye = nodes.identity(standing and STANDING_EYE_HEIGHT or SEATED_EYE_HEIGHT)
    local pose = nodes.multiply((frame as Frame).pose, nodes.multiply(seat.transf as {number}, eye))
    if not validCameraTransform(pose) then
        return nil
    end
    local preferred = nearbyAuthored(pose, authored)
    if preferred ~= nil then
        pose = (preferred as AuthoredView).pose
    end
    return {
        sourceGroup = nodes.name((frame as Frame).node, ""),
        stableGroup = stableGroup(index, frame as Frame, pose, placement),
        pose = pose, fov = preferred ~= nil and (preferred as AuthoredView).fov or DEFAULT_FOV,
    }
end

local function readBounds(value: any): Bounds | nil
    local fields = values.asTable(value)
    if fields == nil then
        assert(value == nil, "Camera bounds must be a table")
        return nil
    end
    local bounds = fields as RawTable
    if bounds.bbMin == nil and bounds.bbMax == nil then
        return nil
    end
    local minimum, maximum = values.asArray(bounds.bbMin), values.asArray(bounds.bbMax)
    assert(minimum ~= nil and maximum ~= nil and #minimum == 3 and #maximum == 3,
        "Camera bounds must contain three minimum and maximum coordinates")
    local result: Bounds = { minimum = {}, maximum = {} }
    for axis = 1, 3 do
        local first, last = (minimum as {any})[axis], (maximum as {any})[axis]
        assert(type(first) == "number" and type(last) == "number"
            and (first as number) > -math.huge and (last as number) < math.huge and (first as number) <= (last as number),
            "Camera bounds must be finite and ordered")
        result.minimum[axis], result.maximum[axis] = first as number, last as number
    end
    return result
end

local function includeBounds(target: Bounds, source: Bounds, transform: {number})
    for axis = 1, 3 do
        local minimum, maximum = transform[12 + axis], transform[12 + axis]
        for coordinate = 1, 3 do
            local factor = transform[(coordinate - 1) * 4 + axis]
            local first, last = factor * source.minimum[coordinate], factor * source.maximum[coordinate]
            minimum, maximum = minimum + math.min(first, last), maximum + math.max(first, last)
        end
        target.minimum[axis] = math.min(target.minimum[axis], minimum)
        target.maximum[axis] = math.max(target.maximum[axis], maximum)
    end
end

local function freightView(fileName: string, model: RawTable, index: FrameIndex,
    placement: SwayingWaying.PlacementData): CameraView | nil
    local metadata = model.metadata as RawTable
    local bounds = readBounds(model.boundingInfo)
    local extent = readBounds(metadata.extent)
    if bounds == nil then
        bounds = extent
    elseif extent ~= nil then
        includeBounds(bounds as Bounds, extent as Bounds, MODEL_FORWARD)
    end
    if bounds == nil then
        logger.warnOnce("camera-bounds:" .. fileName, "No bounds for an exterior camera on " .. fileName)
        return nil
    end
    local present = bounds as Bounds
    local x = math.min(present.minimum[1] + FREIGHT_END_INSET, (present.minimum[1] + present.maximum[1]) * 0.5)
    local y = (present.minimum[2] + present.maximum[2]) * 0.5
    local indicator = values.asTable(metadata.loadIndicator)
    local configs = indicator ~= nil and values.asTable((indicator as RawTable).configs) or nil
    for _, entry in pairs(configs or {}) do
        local loadConfig = values.asTable(entry)
        local bay = loadConfig ~= nil and values.asTable((loadConfig as RawTable).cargoBay) or nil
        if bay ~= nil then
            local loadBounds = readBounds(bay)
            if loadBounds ~= nil then
                local group = (bay as RawTable).childId
                assert(group == nil or type(group) == "string", "Cargo camera anchors must be node names")
                local frame = named(index, group as string or "")
                assert(frame ~= nil, "Cargo camera bounds need a unique model anchor")
                includeBounds(present, loadBounds as Bounds, (frame as Frame).pose)
            end
        end
    end
    local pose = nodes.identity(present.maximum[3] + FREIGHT_HEIGHT_CLEARANCE)
    pose[13], pose[14] = x, y
    local group = stableGroup(index, index.root, pose, placement)
    return { sourceGroup = group, stableGroup = group, pose = pose, fov = DEFAULT_FOV }
end

local function capture(fileName: string, model: RawTable, mode: SwayingWaying.CameraMode,
    extra: boolean | nil): SwayingWaying.CameraPlan
    assert(extra == nil or type(extra) == "boolean", "Extra cameras switch must be a boolean")
    local plan: SwayingWaying.CameraPlan = { mode = mode, views = {}, placementGroups = {} }
    if mode == "Disabled" then
        return plan
    end
    local metadata = model.metadata as RawTable
    local placement = policy.placement(references.collect(metadata))
    plan.placementGroups = placement.groups
    local index = indexRoot(modelRoots(model)[1], {}, placement.groups)
    local authored = authoredViews(metadata, index)
    local provider = values.asTable(metadata.seatProvider)
    local seats = provider ~= nil and values.asArray((provider as RawTable).seats) or values.asArray(metadata.seats)
    assert(type(config.multipleCrewSeats) == "boolean", "Multiple crew cameras switch must be a boolean")
    local crewSeat = 0
    local preferredForward, preferredDriving = false, false
    for _, entry in ipairs(seats or {}) do
        local seat = values.asTable(entry)
        if seat ~= nil and (seat as RawTable).crew == true then
            crewSeat = crewSeat + 1
            local view = seatView(index, seat as RawTable, authored, placement)
            if view ~= nil then
                local present = view as CameraView
                present.crewSeat = crewSeat
                if config.multipleCrewSeats and extra ~= true then
                    plan.views[#plan.views + 1] = present
                else
                    local forward = aligned(present.pose, MODEL_FORWARD, 0, MIN_FORWARD_ALIGNMENT)
                    local driving = (seat as RawTable).animation == "driving"
                        or (seat as RawTable).animation == "driving_upright"
                    if #plan.views == 0 or (forward and (not preferredForward or (driving and not preferredDriving))) then
                        plan.views[1] = present
                        preferredForward, preferredDriving = forward, driving
                    end
                    if preferredForward and preferredDriving then
                        break
                    end
                end
            else
                logger.warnOnce("camera-seat:" .. fileName, "Ignoring invalid crew camera seat on " .. fileName)
            end
        end
    end
    if extra == true and #plan.views == 0 then
        for _, entry in ipairs(seats or {}) do
            local seat = values.asTable(entry)
            if seat ~= nil and (seat as RawTable).crew ~= true then
                local view = seatView(index, seat as RawTable, authored, placement)
                if view ~= nil then
                    plan.views[1] = view as CameraView
                    break
                end
            end
        end
    end
    if #plan.views == 0 and #authored > 0 then
        local view = authored[1]
        local frame = named(index, view.group) as Frame
        plan.views[1] = {
            sourceGroup = view.group, stableGroup = stableGroup(index, frame, view.pose, placement),
            pose = view.pose, fov = view.fov,
        }
    end
    if extra == true and #plan.views == 0 then
        local view = freightView(fileName, model, index, placement)
        if view ~= nil then
            plan.views[1] = view as CameraView
        end
    end
    return plan
end

local function fixedFrame(index: FrameIndex, name: string): Frame | nil
    local frame: Frame | nil = (named(index, name) or index.root) as Frame
    while frame ~= nil do
        local present = frame as Frame
        if not present.moving and present.cameraSafe then
            return present
        end
        frame = present.parent
    end
    return nil
end

local function safeMovingAncestor(frame: Frame | nil): Frame | nil
    while frame ~= nil and (frame as Frame).moving do
        local present = frame as Frame
        if present.cameraSafe then
            return present
        end
        frame = present.parent
    end
    return nil
end

local function movingFrame(index: FrameIndex, view: CameraView, attachments: {string: string}): Frame | nil
    local source = safeMovingAncestor(named(index, attachments[view.sourceGroup] or view.sourceGroup))
    if source ~= nil then
        return source
    end
    local section = safeMovingAncestor(named(index, attachments[view.stableGroup] or view.stableGroup))
    if section ~= nil then
        return section
    end
    local only: Frame | nil = nil
    for _, target in pairs(attachments) do
        local frame = named(index, target)
        if frame ~= nil and (frame as Frame).moving then
            if only ~= nil and (only as Frame).node ~= (frame as Frame).node then
                return nil
            end
            only = frame
        end
    end
    return safeMovingAncestor(only)
end

local function reusable(camera: AuthoredView, view: CameraView, indices: {FrameIndex}, parents: {Frame}): boolean
    if math.abs(camera.fov - view.fov) > MATCH_TOLERANCE or not samePose(camera.pose, view.pose) then
        return false
    end
    for lodIndex, index in ipairs(indices) do
        local frame = named(index, camera.group)
        if frame == nil then
            return false
        end
        local current = frame as Frame
        local parent = parents[lodIndex]
        if not current.cameraSafe or current.moving ~= parent.moving or current.dynamicNode ~= parent.dynamicNode
            or not samePose(nodes.multiply(current.pose, camera.transf), view.pose)
        then
            return false
        end
    end
    return true
end

local function apply(fileName: string, model: RawTable, plan: SwayingWaying.CameraPlan,
    attachments: {string: string}, wrappers: SwayingWaying.WrapperRegistry | nil): SwayingWaying.CameraAdditions, boolean
    local added: SwayingWaying.CameraAdditions = { positions = {}, rests = {} }
    if #plan.views == 0 then
        return added, false
    end
    local motion: {string: boolean} = {}
    if wrappers ~= nil then
        for _, wrapped in pairs((wrappers as SwayingWaying.WrapperRegistry).names) do
            motion[wrapped.swayName] = true
            motion[wrapped.pitchName] = true
            motion[wrapped.rollName] = true
        end
    end
    local indices = modelIndices(model, motion, plan.placementGroups)
    local metadata = model.metadata as RawTable
    local existing = authoredViews(metadata, indices[1])
    local descriptions: CameraDescriptions | nil = config.hudEnabled and {} or nil
    if descriptions ~= nil then
        for _, camera in ipairs(existing) do
            (descriptions as CameraDescriptions)[camera.index] = { index = camera.index, kind = "Model", pose = camera.pose }
        end
    end
    local positionCount = #cameraPositions(metadata)
    local function describe(camera: AuthoredView, view: CameraView, moving: boolean)
        if descriptions == nil then
            return
        end
        local description = (descriptions as CameraDescriptions)[camera.index]
        if description.kind == "Model" then
            description.kind = moving and "Sway" or "Stable"
            description.crewSeat = view.crewSeat
        end
    end
    local reserved: {string: boolean} = {}
    for _, index in ipairs(indices) do
        for name in pairs(index.names) do
            reserved[name] = true
        end
    end
    local function add(view: CameraView, moving: boolean)
        local target: Frame | nil = nil
        if moving then
            target = movingFrame(indices[1], view, attachments)
        else
            target = fixedFrame(indices[1], view.stableGroup)
        end
        if target == nil then
            logger.warnOnce("camera-anchor:" .. fileName .. ":" .. tostring(moving),
                "No safe " .. (moving and "moving" or "stable") .. " camera anchor outside authored animations on " .. fileName)
            return
        end
        local parents: {Frame} = {}
        for lodIndex, index in ipairs(indices) do
            local parent = lodIndex == 1 and target as Frame
                or (moving and movingFrame(index, view, attachments) or nil)
                or fixedFrame(index, view.stableGroup)
            if parent == nil then
                logger.warnOnce("camera-lod:" .. fileName, "No safe camera anchor in every LOD on " .. fileName)
                return
            end
            parents[lodIndex] = parent as Frame
        end
        for _, camera in ipairs(existing) do
            if reusable(camera, view, indices, parents) then
                describe(camera, view, moving)
                return
            end
        end
        local base = "swaying_waying_camera_" .. (moving and "sway" or "stable")
        local suffix = 1
        while reserved[base .. "_" .. suffix] do
            suffix = suffix + 1
        end
        local name = base .. "_" .. suffix
        reserved[name] = true
        local transforms: {{number}} = {}
        for lodIndex, parent in ipairs(parents) do
            transforms[lodIndex] = nodes.multiply(frameInverse(parent), view.pose)
        end
        -- A camera group must exist even on distant LODs of other consist members.
        local inserted: {ModelNode: ModelNode} = {}
        for lodIndex, parent in ipairs(parents) do
            local anchor = inserted[parent.node]
            if anchor ~= nil then
                assert(samePose(nodes.transform(anchor as ModelNode), transforms[lodIndex]),
                    "Shared LOD camera anchor has conflicting coordinate frames")
            else
                anchor = { name = name, transf = transforms[lodIndex] }
                local children = (parent.node.children or {}) as {ModelNode}
                parent.node.children = children
                children[#children + 1] = anchor
                inserted[parent.node] = anchor
            end
            indices[lodIndex].names[name] = {
                node = anchor as ModelNode, parent = parent, pose = view.pose, moving = parent.moving,
                cameraSafe = parent.cameraSafe, dynamicNode = parent.dynamicNode,
            }
        end
        local camera: SwayingWaying.CameraPosition = { group = name, transf = nodes.identity(0), fov = view.fov }
        added.positions[#added.positions + 1] = camera
        added.rests[name] = view.pose
        local authored: AuthoredView = {
            index = positionCount + #added.positions,
            group = name, transf = camera.transf, pose = view.pose, fov = view.fov,
        }
        existing[#existing + 1] = authored
        if descriptions ~= nil then
            (descriptions as CameraDescriptions)[authored.index] = { index = authored.index, kind = "Model", pose = view.pose }
            describe(authored, view, moving)
        end
    end
    for _, view in ipairs(plan.views) do
        if plan.mode == "Stable" or plan.mode == "Both" then
            add(view, false)
        end
        if plan.mode == "Sway" or plan.mode == "Both" then
            add(view, true)
        end
    end
    if #added.positions > 0 then
        local camera = (values.asTable(metadata.cameraConfig) or {}) as RawTable
        metadata.cameraConfig = camera
        local positions = cameraPositions(metadata)
        camera.positions = positions
        for _, position in ipairs(added.positions) do
            positions[#positions + 1] = position
        end
    end
    if descriptions == nil or positionCount + #added.positions == 0 then
        return added, #added.positions > 0
    end
    local custom = values.asTable(metadata.metadata)
    assert(metadata.metadata == nil or custom ~= nil, "Custom model metadata must be a table")
    local hud: SwayingWaying.CameraHudMetadata = {
        schema = constants.CAMERA_HUD_SCHEMA, count = positionCount + #added.positions, positions = {},
    }
    for _, camera in ipairs(existing) do
        hud.positions[#hud.positions + 1] = (descriptions as CameraDescriptions)[camera.index]
    end
    local payload = (custom or {}) as RawTable
    local previous = values.asTable(payload[constants.CAMERA_HUD_METADATA_KEY])
    assert(payload[constants.CAMERA_HUD_METADATA_KEY] == nil
        or (previous ~= nil and (previous as RawTable).schema == constants.CAMERA_HUD_SCHEMA),
        "Camera HUD metadata namespace is already occupied")
    payload[constants.CAMERA_HUD_METADATA_KEY] = hud
    metadata.metadata = payload
    return added, true
end

local module: SwayingWaying.ModelCameras = {
    positions = cameraPositions, validate = validate, capture = capture, apply = apply,
}
return module
