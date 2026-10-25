local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local type RawTable = SwayingWaying.RawTable
local type Binding = SwayingWaying.ModelReference
local MAX_PLACEMENT_DEPTH = 8

local function bind(owner: RawTable, field: string, kind: SwayingWaying.ReferenceKind, bindings: {Binding})
    local target = owner[field]
    if target == nil or target == "" then
        return
    end
    assert(type(target) == "string", "Invalid model reference: " .. field)
    bindings[#bindings + 1] = { owner = owner, field = field, target = target as string, kind = kind }
end

local function arrayReferences(value: any, field: string, kind: SwayingWaying.ReferenceKind, bindings: {Binding})
    local entries = validation.asArray(value)
    if entries == nil then
        return
    end
    for _, entry in ipairs(entries as {any}) do
        local owner = validation.asTable(entry)
        assert(owner ~= nil, "Model attachment entries must be tables")
        bind(owner as RawTable, field, kind, bindings)
    end
end

local function placements(value: any, bindings: {Binding}, depth: integer)
    local fields = validation.asTable(value)
    if fields == nil then
        return
    end
    assert(depth <= MAX_PLACEMENT_DEPTH, "Vehicle placements exceed the supported depth")
    local present = fields as RawTable
    if present.group ~= nil then
        bind(present, "group", "placement", bindings)
    end
    for key, child in pairs(present) do
        if type(key) == "number" and type(child) == "table" then
            placements(child, bindings, depth + 1)
        end
    end
end

local function collect(metadata: RawTable): {Binding}
    local bindings: {Binding} = {}
    arrayReferences(metadata.seats, "group", "attachment", bindings)
    arrayReferences(metadata.lights, "meshId", "mesh", bindings)
    arrayReferences(metadata.lightSources, "meshId", "mesh", bindings)
    local seats = validation.asTable(metadata.seatProvider)
    if seats ~= nil then
        arrayReferences((seats as RawTable).seats, "group", "attachment", bindings)
    end
    local lights = validation.asTable(metadata.lightSourceList)
    if lights ~= nil then
        arrayReferences((lights as RawTable).lights, "meshId", "mesh", bindings)
    end
    local labels = validation.asTable(metadata.labelList)
    if labels ~= nil then
        arrayReferences((labels as RawTable).labels, "childId", "attachment", bindings)
    end
    local particles = validation.asTable(metadata.particleSystem)
    if particles ~= nil then
        arrayReferences((particles as RawTable).emitters, "child", "attachment", bindings)
    end
    local rail = validation.asTable(metadata.railVehicle)
    local config = rail ~= nil and validation.asTable((rail as RawTable).config) or nil
    if config ~= nil then
        placements((config as RawTable).fakeBogies, bindings, 0)
    end
    local indicator = validation.asTable(metadata.loadIndicator)
    if indicator ~= nil then
        local present = indicator as RawTable
        arrayReferences(present.slots, "childId", "attachment", bindings)
        local configs = validation.asTable(present.configs)
        if configs ~= nil then
            for _, entry in pairs(configs as RawTable) do
                local fields = validation.asTable(entry)
                local bay = fields ~= nil and validation.asTable((fields as RawTable).cargoBay) or nil
                if bay ~= nil then
                    bind(bay as RawTable, "childId", "attachment", bindings)
                end
            end
        end
    end
    local transport = validation.asTable(metadata.transportVehicle)
    if transport ~= nil then
        local fields = transport as RawTable
        local compartments = validation.asArray(fields.compartments) or validation.asArray(fields.compartmentsList)
        for _, compartment in ipairs(compartments or {}) do
            local group = validation.asTable(compartment)
            local loads = group ~= nil and validation.asArray((group as RawTable).loadConfigs) or nil
            for _, loadConfig in ipairs(loads or {}) do
                local loadFields = validation.asTable(loadConfig)
                local cargo = loadFields ~= nil and validation.asTable((loadFields as RawTable).cargoEntry) or nil
                if cargo ~= nil then
                    arrayReferences((cargo as RawTable).seats, "group", "attachment", bindings)
                end
            end
        end
    end
    return bindings
end

local function targetFor(binding: Binding, targets: SwayingWaying.ReferenceTargets): string | nil
    if binding.kind == "placement" then
        return targets.placements[binding.target]
    elseif binding.kind == "mesh" then
        return targets.meshes[binding.target]
    end
    return targets.attachments[binding.target]
end

local function hasReferences(bindings: {Binding}, targets: SwayingWaying.ReferenceTargets): boolean
    for _, binding in ipairs(bindings) do
        if targetFor(binding, targets) ~= nil then
            return true
        end
    end
    return false
end

local function retarget(bindings: {Binding}, targets: SwayingWaying.ReferenceTargets)
    for _, binding in ipairs(bindings) do
        local target = targetFor(binding, targets)
        if target ~= nil then
            binding.owner[binding.field] = target
        end
    end
end

local function validate(bindings: {Binding}, targets: SwayingWaying.ReferenceTargets,
    original: {SwayingWaying.ModelNode: SwayingWaying.NodeIndex},
    prepared: {SwayingWaying.ModelNode: {string: integer}})
    for _, binding in ipairs(bindings) do
        local target = targetFor(binding, targets)
        if target ~= nil then
            for root, index in pairs(original) do
                if index.names[binding.target] ~= nil then
                    assert(prepared[root][target], "Prepared LOD is missing model reference: " .. target)
                end
            end
        end
    end
end

local function defaultLabels(metadata: RawTable): {RawTable}
    local result: {RawTable} = {}
    local labels = validation.asTable(metadata.labelList)
    local entries = labels ~= nil and validation.asArray((labels as RawTable).labels) or nil
    for _, label in ipairs(entries or {}) do
        if type(label) == "table" and (label as RawTable).childId == "" then
            result[#result + 1] = label as RawTable
        end
    end
    return result
end

local module: SwayingWaying.ModelReferences = {
    collect = collect, hasReferences = hasReferences, retarget = retarget, validate = validate, defaultLabels = defaultLabels,
}
return module
