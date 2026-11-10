local function sourceFor(settings, mode)
	return {
		schema = 2,
		revision = 1,
		modelFile = "tests::/memory.mdl",
		originalTransformator = "::/vehicle/train/shared/default_train.trf",
		carrier = "RAIL",
		profile = "DEFAULT",
		axisReversed = false,
		vehicleFactor = 1,
		wheelbase = 10,
		sections = {},
		settings = settings.resolve({ intensity = 1, memoryUsage = mode }),
	}
end

local referencePose
for _, mode in ipairs({ "Low", "Standard", "High" }) do
	local harness = dofile("tests/support/harness.lua").new()
	local constants = harness.require("apasz_swaying_waying::/swaying_waying/constants.lua")
	constants.MAX_RUNTIME_VEHICLE_STATES = 8
	local settings = harness.require("apasz_swaying_waying::/swaying_waying/settings.lua")
	local runtime = harness.require("apasz_swaying_waying::/swaying_waying/runtime_state.lua")
	local track = harness.require("apasz_swaying_waying::/swaying_waying/track_response.lua")
	local budget = harness.require("apasz_swaying_waying::/swaying_waying/memory_policy.lua").budget(mode)
	local source = sourceFor(settings, mode)
	local histories, queries = {}, 0
	local api = {
		getBaseEdgeInfo = function()
			queries = queries + 1
			return { edgeOffsetClampedToEdgesCount = 0, onBaseEdge = true, baseEdgeType = 0, streetCategories = {} }
		end,
		getVehicleEdgeInfo = function()
			return { speedLimit = 100 / 3.6 }
		end,
	}
	for entity = 1, budget.carriages do
		local state = runtime.get(source, entity, 1, 0)
		state.responseTime = 0
		histories[entity] = state
		track.response(api, entity, 1, 0, 5, 0, mode)
	end
	queries = 0
	for frame = 1, 3 do
		for entity = 1, budget.carriages + 1 do
			local state = runtime.get(source, entity, 1, frame * 16)
			if entity <= budget.carriages then
				assert(
					state == histories[entity] and state.responseTime == 0,
					"overflow must preserve active damping history"
				)
			else
				assert(not state.retained, "overflow has an explicit allocation-free fallback")
			end
			local factor = track.response(api, entity, 1, frame / 4, 5, frame * 16, mode)
			assert(
				factor == (entity <= budget.carriages and 1.25 or 1),
				"only excess carriages use neutral track response"
			)
		end
	end
	assert(queries == 0, "saturated history caches must preserve sampling budgets")
	local overflow = runtime.get(source, budget.carriages + 1, 1, 48)
	assert(runtime.get(source, budget.carriages + 2, 1, 48) == overflow, "overflow reuses scratch storage")
	collectgarbage("collect")
	collectgarbage("stop")
	for _ = 1, 20 do
		runtime.get(source, budget.carriages + 2, 1, 48)
	end
	local before = collectgarbage("count")
	for _ = 1, 1000 do
		runtime.get(source, budget.carriages + 2, 1, 48)
	end
	local allocated = collectgarbage("count") - before
	collectgarbage("restart")
	assert(allocated < 1, "warm overflow callbacks must not allocate state or warning messages")
	assert(#harness.warnings == 2, "overflow is diagnosed once per history kind")
	local replacement = runtime.get(source, 1, 2, 48)
	assert(replacement.retained and replacement ~= histories[1], "entity replacement can update a protected slot")
	local expired = runtime.get(source, 2, 1, budget.retention + 1000)
	assert(expired ~= histories[2] and expired.responseTime == nil, "inactive history expires under every preset")
	assert(runtime.get(source, 2, 1, 0) ~= expired, "clock rewinds reset timed history")
	assert(not pcall(settings.resolve, { memoryUsage = "Unlimited" }), "unknown memory presets fail explicitly")
	assert(not pcall(settings.resolve, { memoryUsage = false }), "invalid binary values cannot select a memory preset")
	getCurrentModId = function()
		return constants.MOD_ID
	end
	local _, defaults = settings.read({})
	assert(defaults.memoryUsage == "Standard", "existing saves default to Standard memory usage")
	for index, selected in ipairs({ "Low", "Standard", "High" }) do
		local _, config = settings.read({ [constants.MOD_ID] = { [constants.MEMORY_USAGE_PARAM_KEY] = index } })
		assert(config.memoryUsage == selected, "mod parameters select named memory presets")
	end
	local motion = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
	local state = runtime.get(source, 1, 1, 16)
	state.sample.phaseSeed, state.sample.sharedPhaseSeed = 1, 1
	state.sample.distance, state.sample.sharedDistance, state.sample.motionScale = 123, 123, 0.8
	for frame = 1, 2 do
		state.sample.distance, state.sample.sharedDistance = 123 + frame, 123 + frame
		for _ = 1, 3 do
			motion.prepareWaves(state, 123 + frame, 0)
		end
	end
	assert((state.sample.waves ~= nil) == budget.sharedWaves, "Low memory skips optional shared-wave coefficients")
	local pose = { motion.animationTimes(state.sample, state.model.motion, state.model.sections[1].geometry) }
	if referencePose then
		for axis, value in ipairs(pose) do
			assert(math.abs(value - referencePose[axis]) < 1e-9, "memory presets retain the same motion profile")
		end
	else
		referencePose = pose
	end
end
print("Memory budget checks passed")
