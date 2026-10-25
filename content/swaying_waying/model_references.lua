local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pairs = _tl_compat and _tl_compat.pairs or pairs
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")

local MAX_PLACEMENT_DEPTH = 8

local function bind(owner, field, kind, bindings)
	local target = owner[field]
	if target == nil or target == "" then
		return
	end
	assert(type(target) == "string", "Invalid model reference: " .. field)
	bindings[#bindings + 1] = { owner = owner, field = field, target = target, kind = kind }
end

local function arrayReferences(value, field, kind, bindings)
	local entries = validation.asArray(value)
	if entries == nil then
		return
	end
	for _, entry in ipairs(entries) do
		local owner = validation.asTable(entry)
		assert(owner ~= nil, "Model attachment entries must be tables")
		bind(owner, field, kind, bindings)
	end
end

local function placements(value, bindings, depth)
	local fields = validation.asTable(value)
	if fields == nil then
		return
	end
	assert(depth <= MAX_PLACEMENT_DEPTH, "Vehicle placements exceed the supported depth")
	local present = fields
	if present.group ~= nil then
		bind(present, "group", "placement", bindings)
	end
	for key, child in pairs(present) do
		if type(key) == "number" and type(child) == "table" then
			placements(child, bindings, depth + 1)
		end
	end
end

local function collect(metadata)
	local bindings = {}
	arrayReferences(metadata.seats, "group", "attachment", bindings)
	arrayReferences(metadata.lights, "meshId", "mesh", bindings)
	arrayReferences(metadata.lightSources, "meshId", "mesh", bindings)
	local seats = validation.asTable(metadata.seatProvider)
	if seats ~= nil then
		arrayReferences((seats).seats, "group", "attachment", bindings)
	end
	local lights = validation.asTable(metadata.lightSourceList)
	if lights ~= nil then
		arrayReferences((lights).lights, "meshId", "mesh", bindings)
	end
	local labels = validation.asTable(metadata.labelList)
	if labels ~= nil then
		arrayReferences((labels).labels, "childId", "attachment", bindings)
	end
	local particles = validation.asTable(metadata.particleSystem)
	if particles ~= nil then
		arrayReferences((particles).emitters, "child", "attachment", bindings)
	end
	local rail = validation.asTable(metadata.railVehicle)
	local config = rail ~= nil and validation.asTable((rail).config) or nil
	if config ~= nil then
		placements((config).fakeBogies, bindings, 0)
	end
	local indicator = validation.asTable(metadata.loadIndicator)
	if indicator ~= nil then
		local present = indicator
		arrayReferences(present.slots, "childId", "attachment", bindings)
		local configs = validation.asTable(present.configs)
		if configs ~= nil then
			for _, entry in pairs(configs) do
				local fields = validation.asTable(entry)
				local bay = fields ~= nil and validation.asTable((fields).cargoBay) or nil
				if bay ~= nil then
					bind(bay, "childId", "attachment", bindings)
				end
			end
		end
	end
	local transport = validation.asTable(metadata.transportVehicle)
	if transport ~= nil then
		local fields = transport
		local compartments = validation.asArray(fields.compartments) or validation.asArray(fields.compartmentsList)
		for _, compartment in ipairs(compartments or {}) do
			local group = validation.asTable(compartment)
			local loads = group ~= nil and validation.asArray((group).loadConfigs) or nil
			for _, loadConfig in ipairs(loads or {}) do
				local loadFields = validation.asTable(loadConfig)
				local cargo = loadFields ~= nil and validation.asTable((loadFields).cargoEntry) or nil
				if cargo ~= nil then
					arrayReferences((cargo).seats, "group", "attachment", bindings)
				end
			end
		end
	end
	return bindings
end

local function targetFor(binding, targets)
	if binding.kind == "placement" then
		return targets.placements[binding.target]
	elseif binding.kind == "mesh" then
		return targets.meshes[binding.target]
	end
	return targets.attachments[binding.target]
end

local function hasReferences(bindings, targets)
	for _, binding in ipairs(bindings) do
		if targetFor(binding, targets) ~= nil then
			return true
		end
	end
	return false
end

local function retarget(bindings, targets)
	for _, binding in ipairs(bindings) do
		local target = targetFor(binding, targets)
		if target ~= nil then
			binding.owner[binding.field] = target
		end
	end
end

local function validate(bindings, targets, original, prepared)
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

local function defaultLabels(metadata)
	local result = {}
	local labels = validation.asTable(metadata.labelList)
	local entries = labels ~= nil and validation.asArray((labels).labels) or nil
	for _, label in ipairs(entries or {}) do
		if type(label) == "table" and (label).childId == "" then
			result[#result + 1] = label
		end
	end
	return result
end

local module = {
	collect = collect,
	hasReferences = hasReferences,
	retarget = retarget,
	validate = validate,
	defaultLabels = defaultLabels,
}
return module
