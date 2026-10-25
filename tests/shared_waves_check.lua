local fixture = dofile("tests/support/wave_fixture.lua")
local near = dofile("tests/assertions.lua").near
local harness = dofile("tests/support/harness.lua").new()
local motion = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
local config = harness.require("apasz_swaying_waying::/swaying_waying/motion_config.lua")

local function compare(state, distance, reversed, facing, lag, prime)
	lag = config.carriageLag and lag or 0
	local sample = state.sample
	local sharedBase = reversed and -distance or distance
	sample.sharedAxisReversed = facing
	if prime ~= false then
		-- Prime repeated coordinates, then exercise the shared branch at a new input.
		sample.distance = distance - 1
		motion.prepareWaves(state, sharedBase - 1, lag)
		motion.prepareWaves(state, sharedBase - 1, lag)
	end
	sample.distance, sample.sharedDistance = distance, sharedBase - lag
	motion.prepareWaves(state, sharedBase, lag)
	if prime ~= false then
		motion.prepareWaves(state, sharedBase, lag)
		assert(sample.waves, "the equivalence checks exercise prepared motion")
	end
	for index, section in ipairs(state.model.sections) do
		local sectionLag = config.sectionLag and section.lag or 0
		sample.distance = distance - sectionLag
		sample.sharedDistance = sharedBase - lag - (facing and -sectionLag or sectionLag)
		if sample.waves then
			motion.sectionWaves(state, index)
		end
		local actual = { motion.animationTimes(sample, state.model.motion, section.geometry) }
		local actualRoll = motion.animationTime(sample, state.model.motion)
		local prepared = sample.waves
		sample.waves = nil
		local expected = { motion.animationTimes(sample, state.model.motion, section.geometry) }
		local expectedRoll = motion.animationTime(sample, state.model.motion)
		sample.waves = prepared
		for channel = 1, 3 do
			near(actual[channel], expected[channel], 1e-6, "shared bases preserve the independently evaluated motion")
		end
		near(actualRoll, expectedRoll, 1e-6, "roll-only evaluation stays equivalent when prepared data is present")
	end
	return sample.waves ~= nil
end

for _, carriageLag in ipairs({ true, false }) do
	config.carriageLag = carriageLag
	for _, profile in ipairs({ "QUICK", "DEFAULT", "SLOW" }) do
		local state = fixture(motion, profile, 101, 257, 3, { 0, 8, 21 })
		for _, distance in ipairs({ 0, 123, -41, 100000, 1e7, 124 }) do
			for _, reversed in ipairs({ false, true }) do
				for _, facing in ipairs({ false, true }) do
					compare(state, distance, reversed, facing, 60)
				end
			end
		end
		for _, phaseSeed in ipairs({ 0, 997, 123456 }) do
			state.sample.phaseSeed = phaseSeed
			for _, lag in ipairs({ 0, 20, 180 }) do
				compare(state, 321, false, false, lag)
			end
		end
		state.sample.sharedPhaseSeed = 205
		compare(state, 321, false, false, 20)
		config.sectionLag = false
		compare(state, 321, false, false, 20)
		config.sectionLag = true
		compare(state, 321, false, false, 20)
		compare(state, 322, false, false, 20)
		compare(state, 322, false, false, 20)
		local previous, rotations = state.waves, state.waves.rotations
		compare(state, 323, false, false, 20)
		assert(
			state.waves == previous and state.waves.rotations == rotations,
			"distance updates reuse every carriage wave object"
		)
		for _, component in ipairs({ "shortWave", "longWave", "thirdWave", "irregularity", "roll", "pitch", "heave" }) do
			config[component] = false
			compare(state, 323, true, true, 20)
			config[component] = true
			compare(state, 323, true, true, 20)
		end
		for _, weight in ipairs({ -1, 0, 0.2, 0.65, 1, 2 }) do
			state.sample.shortWeight = weight
			compare(state, 324, true, true, 20)
		end
	end

	do
		local states = {}
		local profiles = { "QUICK", "DEFAULT", "SLOW" }
		for index = 1, 24 do
			local state = fixture(
				motion,
				profiles[(index - 1) % #profiles + 1],
				300 + index % 2,
				500 + index,
				index - 1,
				{ 0, 9 }
			)
			state.model.motion.modelAxisSign = index % 2 == 0 and -1 or 1
			states[index] = state
		end
		local shared, direct = 0, 0
		for frame = 1, 120 do
			for slot = 1, #states do
				local index = (slot + frame) % #states + 1
				local state = states[index]
				if frame == 60 then
					state.sample.sharedPhaseSeed = state.sample.sharedPhaseSeed + 10
					state.sample.phaseSeed = state.sample.phaseSeed + 10
				end
				local distance = (frame % 60) * 0.4 + state.sample.sharedPhaseSeed * 20
				if frame % 7 == 0 then
					distance = distance + index * 0.0001
				end
				state.sample.shortWeight = 0.65 + 0.1 * math.exp(-frame / 40) + index * 0.001
				state.sample.swayFactor = 0.8 + index * 0.02
				local prepared = compare(state, distance, frame >= 80, index % 2 == 0, (index - 1) * 20, false)
				if prepared then
					shared = shared + 1
				else
					direct = direct + 1
				end
			end
		end
		assert(
			shared > 0 and direct > 0,
			"mixed callback ordering exercises shared and direct paths without forced warm-up"
		)
	end

	do
		local states = {}
		for index = 1, 12 do
			states[index] = fixture(motion, "DEFAULT", 901, 1000 + index, index - 1, { 0, 12 })
			compare(states[index], 123, false, index % 2 == 0, (index - 1) * 20)
		end
		for index, state in ipairs(states) do
			compare(state, 124, false, index % 2 == 0, (index - 1) * 20)
		end
		local sine, cosine, calls = math.sin, math.cos, 0
		math.sin = function(value)
			calls = calls + 1
			return sine(value)
		end
		math.cos = function(value)
			calls = calls + 1
			return cosine(value)
		end
		for mode, irregular in ipairs({ false, true }) do
			config.irregularity = irregular
			calls = 0
			local distance = 124 + mode
			for index = #states, 1, -1 do
				local state = states[index]
				state.sample.distance = distance
				motion.prepareWaves(state, distance, carriageLag and (index - 1) * 20 or 0)
				for section = 1, 2 do
					motion.sectionWaves(state, section)
					motion.animationTimes(state.sample, state.model.motion, state.model.sections[section].geometry)
				end
			end
			assert(
				calls == (irregular and 4 + 3 * 24 or 6),
				"regular waves share bases; variable spacing samples each section's centre and supports once"
			)
		end
		math.sin, math.cos = sine, cosine
		for index, state in ipairs(states) do
			compare(state, 123, false, index % 2 == 0, (index - 1) * 20)
		end
	end
end
config.carriageLag = true

do
	local state = fixture(motion, "DEFAULT", 902, 1013, 0, { 0, 8 })
	compare(state, 123, false, false, 0)
	local basis = state.waveBasis
	for _, carriageLag in ipairs({ false, true, false }) do
		config.carriageLag = carriageLag
		compare(state, 123, false, false, 0)
		assert(state.waveBasis == basis, "phase mode changes preserve the consist distance cache")
	end
	config.carriageLag = true
end

do
	local cold = dofile("tests/support/harness.lua").new()
	local constants = cold.require("apasz_swaying_waying::/swaying_waying/constants.lua")
	constants.MAX_RUNTIME_VEHICLE_STATES = 2
	local isolated = cold.require("apasz_swaying_waying::/swaying_waying/motion.lua")
	local firstGeometry = isolated.secondaryGeometry("DEFAULT", 4)
	local secondGeometry = isolated.secondaryGeometry("DEFAULT", 6)
	assert(isolated.secondaryGeometry("DEFAULT", 4) == firstGeometry, "geometry hits retain the cached object")
	isolated.secondaryGeometry("DEFAULT", 8)
	assert(
		isolated.secondaryGeometry("DEFAULT", 4) == firstGeometry,
		"geometry hits protect active entries from eviction"
	)
	assert(
		isolated.secondaryGeometry("DEFAULT", 6) ~= secondGeometry,
		"geometry caches evict the least recently used wheelbase"
	)
	local states = {}
	for consist = 1, 4 do
		local state = fixture(isolated, "DEFAULT", consist, 30, 0)
		isolated.prepareWaves(state, 123, 0)
		isolated.prepareWaves(state, 123, 0)
		state.sample.distance, state.sample.sharedDistance = 124, 124
		isolated.prepareWaves(state, 124, 0)
		isolated.prepareWaves(state, 124, 0)
		states[consist] = state
	end
	for _, state in ipairs(states) do
		state.sample.distance = -41
		state.sample.sharedDistance = -41
		isolated.prepareWaves(state, -41, 0)
		isolated.sectionWaves(state, 1)
		local a = { isolated.animationTimes(state.sample, state.model.motion, state.model.sections[1].geometry) }
		state.sample.waves = nil
		local b = { isolated.animationTimes(state.sample, state.model.motion, state.model.sections[1].geometry) }
		for channel = 1, 3 do
			near(a[channel], b[channel], 1e-6, "cache eviction and isolated contexts do not change the result")
		end
	end
end

print("Shared wave checks passed")
