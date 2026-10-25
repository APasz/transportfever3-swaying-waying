local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local math = _tl_compat and _tl_compat.math or math
local pairs = _tl_compat and _tl_compat.pairs or pairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local analysis = ug_require("apasz_swaying_waying::/swaying_waying/model_analysis.lua")
local cameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua")
local transaction = ug_require("apasz_swaying_waying::/swaying_waying/model_transaction.lua")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")

local checked = false
local logic = nil
local list = nil
local CAMERA_MOD_ID = "dome_wagon_cameras"
local LAYOUT_KEY = "domeWagonCameras"
local ROOT_NODE = constants.ROOT_NODE

local function reset()
	checked, logic, list = false, nil, nil
end

local function ensureLoaded()
	if not compatibility.isModEnabled(CAMERA_MOD_ID) then
		return false
	end
	if not checked then
		checked = true
		local loaded, candidate = pcall(ug_require, CAMERA_MOD_ID .. "::/camera_logic.lua")
		if loaded then
			local valid, failure = pcall(function()
				local module = values.asTable(candidate)
				assert(module ~= nil, "Wagon Cameras logic must be a table")
				for _, name in ipairs({
					"normalizeList",
					"nodeNames",
					"layout",
					"findModelEntries",
					"camerasFromLayout",
				}) do
					assert(type((module)[name]) == "function", "Wagon Cameras is missing " .. name)
				end
				local adapter = module
				local raw = ug_require(CAMERA_MOD_ID .. "::/camera_positions.lua")
				local settings = adapter.normalizeList(raw)
				assert(
					values.asTable(settings) ~= nil and values.asTable(settings.default) ~= nil,
					"Invalid Wagon Cameras configuration"
				)
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

local function isolated(fileName, model, stage, update)
	local changed = false
	local succeeded, failure = pcall(transaction.run, model, function(draft)
		changed = update(draft)
		return changed
	end)
	if not succeeded then
		logger.warnOnce(
			"wagon-cameras:" .. stage .. ":" .. fileName,
			"Wagon Cameras " .. stage .. " skipped for " .. fileName .. ": " .. tostring(failure)
		)
	end
	return succeeded, succeeded and changed
end

local function restPose(node, index)
	local pose = nodes.transform(node)
	local parent = index.parents[node]
	while parent ~= nil do
		pose = nodes.multiply(nodes.transform(parent), pose)
		parent = index.parents[parent]
	end
	return pose
end

local function samePose(left, right)
	for component = 1, 16 do
		if left[component] ~= right[component] then
			return false
		end
	end
	return true
end

local function repairRoots(model)
	local counts = nodes.validate(model)
	local lods = values.asArray(model.lods)
	assert(lods ~= nil and #lods > 0, "Wagon Cameras needs a LOD hierarchy")
	local missing = {}
	local referenceRoot = nil
	for _, entry in ipairs(lods) do
		local lod = values.asTable(entry)
		local root = lod ~= nil and nodes.get((lod).node) or nil
		assert(root ~= nil, "Wagon Cameras needs a root in every LOD")
		local count = counts[root][ROOT_NODE]
		if count == nil then
			missing[#missing + 1] = lod
		else
			assert(count == 1, "Ambiguous Wagon Cameras root anchor")
			referenceRoot = referenceRoot or root
		end
	end
	if #missing == 0 then
		return false
	end
	local reference = nil
	if referenceRoot ~= nil then
		local indices = analysis.index(lods, {}, {})
		local index = indices[referenceRoot]
		reference = restPose(index.names[ROOT_NODE][1], index)
	end
	local implicit = false
	for _, entry in ipairs(cameras.positions(model.metadata)) do
		local camera = values.asTable(entry)
		if camera ~= nil and ((camera).group == nil or (camera).group == "") then
			implicit = true
		end
	end
	if reference == nil and implicit then
		reference = nodes.transform((lods)[1].node)
	end
	local frame = reference or nodes.identity(0)
	local inverse = nodes.inverse(frame)
	assert(inverse ~= nil, "Wagon Cameras root frame must be invertible and affine")
	local identityFrame = samePose(frame, nodes.identity(0))
	local repaired = {}
	for _, lod in ipairs(missing) do
		local root = lod.node
		local parent = repaired[root]
		if parent == nil then
			local animated = root.animations ~= nil and next(root.animations) ~= nil
			assert(not animated or (identityFrame and not implicit), "Cannot safely rebase an animated camera root")
			assert(
				not implicit or samePose(nodes.transform(root), frame),
				"Cannot preserve implicit camera frames across LODs"
			)

			if not identityFrame then
				root.transf = nodes.multiply(inverse, nodes.transform(root))
			end
			parent = { name = ROOT_NODE, transf = frame, children = { root } }
			repaired[root] = parent
		end
		lod.node = parent
	end
	return true
end

local function finite(value)
	return type(value) == "number" and value > -math.huge and value < math.huge
end

local function layoutOf(model, candidate)
	local fields = values.asTable(candidate)
	assert(fields ~= nil, "Invalid Wagon Cameras layout: expected a table")
	local layout = fields
	local groups, extra, original =
		values.asArray(layout.groups), values.asArray(layout.extra), values.asArray(layout.original)
	local rests, default = values.asTable(layout.rests), values.asTable(layout.default)
	assert(
		groups ~= nil
			and values.arraySize(groups) ~= nil
			and extra ~= nil
			and values.arraySize(extra) ~= nil
			and original ~= nil
			and values.arraySize(original) ~= nil
			and rests ~= nil
			and default ~= nil
			and type(layout.defaults) == "boolean",
		"Invalid Wagon Cameras layout: incomplete fields or sparse arrays"
	)
	assert(
		layout.carrier == "RAIL"
			or layout.carrier == "TRAM"
			or layout.carrier == "ROAD"
			or layout.carrier == "WATER"
			or layout.carrier == "AIR",
		"Invalid Wagon Cameras layout: carrier"
	)
	local position = values.asArray((default).position)
	assert(
		position ~= nil
			and values.arraySize(position) == 3
			and finite((position)[1])
			and finite((position)[2])
			and finite((position)[3])
			and finite((default).yaw)
			and finite((default).fov),
		"Invalid Wagon Cameras layout: default viewpoint"
	)
	local positions = { { transf = nodes.identity(0), fov = (default).fov } }
	for _, group in ipairs(groups) do
		local body = values.asTable(group)
		assert(
			body ~= nil and type((body).name) == "string" and type((body).attach) == "string" and finite((body).center),
			"Invalid Wagon Cameras layout: body"
		)
		positions[#positions + 1] = { group = (body).attach, transf = (body).rest }
	end
	for name, rest in pairs(rests) do
		assert(type(name) == "string", "Invalid Wagon Cameras layout: rest anchor")
		positions[#positions + 1] = { group = name, transf = rest }
	end
	for _, entries in ipairs({ original, extra }) do
		for _, camera in ipairs(entries) do
			positions[#positions + 1] = camera
		end
	end
	if layout.driver ~= nil then
		positions[#positions + 1] = layout.driver
	end
	cameras.validate(model, positions)
	return layout
end

local function prepare(fileName, model, generate)
	local metadata = model.metadata
	local custom = values.asTable(metadata.metadata)
	local existing = custom ~= nil and (custom)[LAYOUT_KEY] or nil
	if not ensureLoaded() and existing == nil then
		return false, false
	end
	return isolated(fileName, model, "preparation", function(draft)
		local changed = repairRoots(draft)
		local fields = draft.metadata
		local payload = values.asTable(fields.metadata)
		local layout = payload ~= nil and (payload)[LAYOUT_KEY] or nil
		if layout ~= nil then
			layoutOf(draft, layout)
		elseif generate then
			local module, settings = logic, list
			local names, tree = module.nodeNames(draft)
			local prepared = layoutOf(
				draft,
				module.layout(fields, settings.default, module.findModelEntries(settings, fileName), names, tree)
			)

			prepared.extra = {}
			local generated = module.camerasFromLayout(prepared)
			cameras.validate(draft, generated)
			if #generated > 0 then
				local original = cameras.positions(fields)
				assert(#generated >= #original, "Wagon Cameras discarded existing cameras")
				for index, entry in ipairs(original) do
					local authored = entry
					local made = generated[index]
					assert(
						(authored.group or ROOT_NODE) == (made.group or ROOT_NODE)
							and authored.fov == made.fov
							and samePose(authored.transf, made.transf),
						"Wagon Cameras changed an existing camera"
					);

					(generated)[index] = entry
				end
				local config = (values.asTable(fields.cameraConfig) or {})
				fields.cameraConfig = config
				config.positions = generated
				prepared.original = original
			end
			assert(fields.metadata == nil or payload ~= nil, "Custom model metadata must be a table")
			payload = (payload or {});
			(payload)[LAYOUT_KEY] = prepared
			fields.metadata = payload
			changed = true
		end
		nodes.validate(draft)
		return changed
	end)
end

local function refresh(fileName, model, additions)
	if #additions.positions == 0 then
		return
	end
	local metadata = model.metadata
	local custom = values.asTable(metadata.metadata)
	local candidate = custom ~= nil and (custom)[LAYOUT_KEY] or nil
	if candidate == nil then
		return
	end

	isolated(fileName, candidate, "overlay update", function(draft)
		local layout = layoutOf(model, draft)
		for _, position in ipairs(additions.positions) do
			layout.extra[#layout.extra + 1] = position
			layout.rests[position.group] = additions.rests[position.group]
		end
		layoutOf(model, layout)
		return true
	end)
end

local module = { reset = reset, prepare = prepare, refresh = refresh }
return module
