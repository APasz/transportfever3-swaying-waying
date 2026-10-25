local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua") as SwayingWaying.ModelNodes
local analysis = ug_require("apasz_swaying_waying::/swaying_waying/model_analysis.lua") as SwayingWaying.ModelAnalysis
local cameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua") as SwayingWaying.ModelCameras
local transaction = ug_require("apasz_swaying_waying::/swaying_waying/model_transaction.lua") as SwayingWaying.ModelTransaction
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua") as SwayingWaying.ModelCompatibility
local type RawTable = SwayingWaying.RawTable
local type ModelNode = SwayingWaying.ModelNode

local record WagonCamera
    group: string | nil
    transf: {number}
    fov: number | nil
end

local record WagonBody
    name: string
    center: number
    attach: string
    rest: {number}
end

local record WagonViewpoint
    position: {number}
    yaw: number
    fov: number
end

local enum WagonCarrier
    "RAIL"
    "TRAM"
    "ROAD"
    "WATER"
    "AIR"
end

local record WagonLayout
    carrier: WagonCarrier
    groups: {WagonBody}
    rests: {string: {number}}
    defaults: boolean
    default: WagonViewpoint
    extra: {WagonCamera}
    original: {WagonCamera}
    driver: WagonCamera | nil
end

local record WagonCameraLogic
    normalizeList: function(any): RawTable
    nodeNames: function(any): any, any
    layout: function(any, any, any, any, any): RawTable
    findModelEntries: function(any, string): any
    camerasFromLayout: function(any): {SwayingWaying.CameraPosition}
end

local checked = false
local logic: WagonCameraLogic | nil = nil
local list: RawTable | nil = nil
local CAMERA_MOD_ID = "dome_wagon_cameras"
local LAYOUT_KEY = "domeWagonCameras"
local ROOT_NODE = constants.ROOT_NODE

local function reset()
    checked, logic, list = false, nil, nil
end

local function ensureLoaded(): boolean
    if not compatibility.isModEnabled(CAMERA_MOD_ID) then
        return false
    end
    if not checked then
        checked = true
        local loaded, candidate = pcall(ug_require, CAMERA_MOD_ID .. "::/camera_logic.lua")
        if loaded then
            local valid, failure = pcall(function(): boolean
                local module = values.asTable(candidate)
                assert(module ~= nil, "Wagon Cameras logic must be a table")
                for _, name in ipairs({ "normalizeList", "nodeNames", "layout", "findModelEntries", "camerasFromLayout" }) do
                    assert(type((module as RawTable)[name]) == "function", "Wagon Cameras is missing " .. name)
                end
                local adapter = module as WagonCameraLogic
                local raw = ug_require(CAMERA_MOD_ID .. "::/camera_positions.lua")
                local settings = adapter.normalizeList(raw)
                assert(values.asTable(settings) ~= nil and values.asTable(settings.default) ~= nil,
                    "Invalid Wagon Cameras configuration")
                list, logic = settings, adapter
                return true
            end)
            if not valid then
                logger.warnOnce("wagon-cameras:module", "Wagon Cameras integration unavailable: " .. tostring(failure))
            end
        end
    end
    return logic ~= nil
end

local enum CompatibilityStage
    "preparation"
    "overlay update"
end

local function isolated(fileName: string, model: RawTable, stage: CompatibilityStage,
    update: function(RawTable): boolean): boolean, boolean
    local changed = false
    local succeeded, failure = pcall(transaction.run, model, function(draft: any): boolean
        changed = update(draft as RawTable)
        return changed
    end)
    if not succeeded then
        logger.warnOnce("wagon-cameras:" .. stage .. ":" .. fileName,
            "Wagon Cameras " .. stage .. " skipped for " .. fileName .. ": " .. tostring(failure))
    end
    return succeeded, succeeded and changed
end

local function restPose(node: ModelNode, index: SwayingWaying.NodeIndex): {number}
    local pose = nodes.transform(node)
    local parent = index.parents[node]
    while parent ~= nil do
        pose = nodes.multiply(nodes.transform(parent as ModelNode), pose)
        parent = index.parents[parent as ModelNode]
    end
    return pose
end

local function samePose(left: {number}, right: {number}): boolean
    for component = 1, 16 do
        if left[component] ~= right[component] then
            return false
        end
    end
    return true
end

local function repairRoots(model: RawTable): boolean
    local counts = nodes.validate(model)
    local lods = values.asArray(model.lods)
    assert(lods ~= nil and #lods > 0, "Wagon Cameras needs a LOD hierarchy")
    local missing: {RawTable} = {}
    local referenceRoot: ModelNode | nil = nil
    for _, entry in ipairs(lods as {any}) do
        local lod = values.asTable(entry)
        local root = lod ~= nil and nodes.get((lod as RawTable).node) or nil
        assert(root ~= nil, "Wagon Cameras needs a root in every LOD")
        local count = counts[root as ModelNode][ROOT_NODE]
        if count == nil then
            missing[#missing + 1] = lod as RawTable
        else
            assert(count == 1, "Ambiguous Wagon Cameras root anchor")
            referenceRoot = referenceRoot or root
        end
    end
    if #missing == 0 then
        return false
    end
    local reference: {number} | nil = nil
    if referenceRoot ~= nil then
        local indices = analysis.index(lods as {any}, {}, {})
        local index = indices[referenceRoot as ModelNode]
        reference = restPose(index.names[ROOT_NODE][1], index)
    end
    local implicit = false
    for _, entry in ipairs(cameras.positions(model.metadata as RawTable)) do
        local camera = values.asTable(entry)
        if camera ~= nil and ((camera as RawTable).group == nil or (camera as RawTable).group == "") then
            implicit = true
        end
    end
    if reference == nil and implicit then
        reference = nodes.transform((lods as {RawTable})[1].node as ModelNode)
    end
    local frame = reference or nodes.identity(0)
    local inverse = nodes.inverse(frame)
    assert(inverse ~= nil, "Wagon Cameras root frame must be invertible and affine")
    local identityFrame = samePose(frame, nodes.identity(0))
    local repaired: {ModelNode: ModelNode} = {}
    for _, lod in ipairs(missing) do
        local root = lod.node as ModelNode
        local parent = repaired[root]
        if parent == nil then
            local animated = root.animations ~= nil and next(root.animations as RawTable) ~= nil
            assert(not animated or (identityFrame and not implicit), "Cannot safely rebase an animated camera root")
            assert(not implicit or samePose(nodes.transform(root), frame), "Cannot preserve implicit camera frames across LODs")
            -- Supply a real runtime anchor while retaining the entire authored tree and its world poses.
            if not identityFrame then
                root.transf = nodes.multiply(inverse as {number}, nodes.transform(root))
            end
            parent = { name = ROOT_NODE, transf = frame, children = { root } }
            repaired[root] = parent
        end
        lod.node = parent
    end
    return true
end

local function finite(value: any): boolean
    return type(value) == "number" and (value as number) > -math.huge and (value as number) < math.huge
end

local function layoutOf(model: RawTable, candidate: any): WagonLayout
    local fields = values.asTable(candidate)
    assert(fields ~= nil, "Invalid Wagon Cameras layout: expected a table")
    local layout = fields as RawTable
    local groups, extra, original = values.asArray(layout.groups), values.asArray(layout.extra), values.asArray(layout.original)
    local rests, default = values.asTable(layout.rests), values.asTable(layout.default)
    assert(groups ~= nil and values.arraySize(groups as RawTable) ~= nil
        and extra ~= nil and values.arraySize(extra as RawTable) ~= nil
        and original ~= nil and values.arraySize(original as RawTable) ~= nil
        and rests ~= nil and default ~= nil and type(layout.defaults) == "boolean",
        "Invalid Wagon Cameras layout: incomplete fields or sparse arrays")
    assert(layout.carrier == "RAIL" or layout.carrier == "TRAM" or layout.carrier == "ROAD"
        or layout.carrier == "WATER" or layout.carrier == "AIR", "Invalid Wagon Cameras layout: carrier")
    local position = values.asArray((default as RawTable).position)
    assert(position ~= nil and values.arraySize(position as RawTable) == 3 and finite((position as {any})[1])
        and finite((position as {any})[2]) and finite((position as {any})[3]) and finite((default as RawTable).yaw)
        and finite((default as RawTable).fov), "Invalid Wagon Cameras layout: default viewpoint")
    local positions: {any} = { { transf = nodes.identity(0), fov = (default as RawTable).fov } }
    for _, group in ipairs(groups as {any}) do
        local body = values.asTable(group)
        assert(body ~= nil and type((body as RawTable).name) == "string"
            and type((body as RawTable).attach) == "string" and finite((body as RawTable).center),
            "Invalid Wagon Cameras layout: body")
        positions[#positions + 1] = { group = (body as RawTable).attach, transf = (body as RawTable).rest }
    end
    for name, rest in pairs(rests as RawTable) do
        assert(type(name) == "string", "Invalid Wagon Cameras layout: rest anchor")
        positions[#positions + 1] = { group = name, transf = rest }
    end
    for _, entries in ipairs({ original as {any}, extra as {any} }) do
        for _, camera in ipairs(entries) do
            positions[#positions + 1] = camera
        end
    end
    if layout.driver ~= nil then
        positions[#positions + 1] = layout.driver
    end
    cameras.validate(model, positions)
    return layout as WagonLayout
end

local function prepare(fileName: string, model: RawTable, generate: boolean): boolean, boolean
    local metadata = model.metadata as RawTable
    local custom = values.asTable(metadata.metadata)
    local existing = custom ~= nil and (custom as RawTable)[LAYOUT_KEY] or nil
    if not ensureLoaded() and existing == nil then
        return false, false
    end
    return isolated(fileName, model, "preparation", function(draft: RawTable): boolean
        local changed = repairRoots(draft)
        local fields = draft.metadata as RawTable
        local payload = values.asTable(fields.metadata)
        local layout = payload ~= nil and (payload as RawTable)[LAYOUT_KEY] or nil
        if layout ~= nil then
            layoutOf(draft, layout)
        elseif generate then
            local module, settings = logic as WagonCameraLogic, list as RawTable
            local names, tree = module.nodeNames(draft)
            local prepared = layoutOf(draft,
                module.layout(fields, settings.default, module.findModelEntries(settings, fileName), names, tree))
            -- Configured extras remain its later modifier's responsibility.
            prepared.extra = {}
            local generated = module.camerasFromLayout(prepared)
            cameras.validate(draft, generated)
            if #generated > 0 then
                local original = cameras.positions(fields)
                assert(#generated >= #original, "Wagon Cameras discarded existing cameras")
                for index, entry in ipairs(original) do
                    local authored = entry as RawTable
                    local made = generated[index]
                    assert((authored.group or ROOT_NODE) == (made.group or ROOT_NODE)
                        and authored.fov == made.fov and samePose(authored.transf as {number}, made.transf),
                        "Wagon Cameras changed an existing camera")
                    -- Its generator copies only known fields; retain the complete author entry.
                    (generated as {any})[index] = entry
                end
                local config = (values.asTable(fields.cameraConfig) or {}) as RawTable
                fields.cameraConfig = config
                config.positions = generated
                prepared.original = original as {WagonCamera}
            end
            assert(fields.metadata == nil or payload ~= nil, "Custom model metadata must be a table")
            payload = (payload or {}) as RawTable
            (payload as RawTable)[LAYOUT_KEY] = prepared
            fields.metadata = payload
            changed = true
        end
        nodes.validate(draft)
        return changed
    end)
end

local function refresh(fileName: string, model: RawTable, additions: SwayingWaying.CameraAdditions)
    if #additions.positions == 0 then
        return
    end
    local metadata = model.metadata as RawTable
    local custom = values.asTable(metadata.metadata)
    local candidate = custom ~= nil and (custom as RawTable)[LAYOUT_KEY] or nil
    if candidate == nil then
        return
    end
    -- The overlay owns this layout; unrelated vehicle metadata needs no copy.
    isolated(fileName, candidate as RawTable, "overlay update", function(draft: RawTable): boolean
        local layout = layoutOf(model, draft)
        for _, position in ipairs(additions.positions) do
            layout.extra[#layout.extra + 1] = position as WagonCamera
            layout.rests[position.group] = additions.rests[position.group]
        end
        layoutOf(model, layout)
        return true
    end)
end

local module: SwayingWaying.CameraCompatibility = { reset = reset, prepare = prepare, refresh = refresh }
return module
