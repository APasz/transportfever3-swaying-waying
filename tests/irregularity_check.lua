local harness = dofile("tests/support/harness.lua").new()
local irregularity = harness.require("apasz_swaying_waying::/swaying_waying/irregularity.lua")
local motion = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
local config = harness.require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
local near = dofile("tests/assertions.lua").near

-- Fixed vectors catch precision loss in the game's double-only Lua 5.2 arithmetic.
for _, vector in ipairs({
	{ 0, 0, 0.63585668425910569, -0.55794751824763311 },
	{ 1, 31, -0.57487037436705291, 0.038194829796182495 },
	{ -4.25, 123456, -0.30913996907096064, 0.59461584140427448 },
	{ 123.45, -1, 0.40823883421747204, -0.138550283068054 },
	{ 4294967295, 2147483647, 0.33126174157933114, 0.28244680283974632 },
	{ -4294967296.25, 4294967295, -0.30218822121750211, 0.1621931512115849 },
}) do
	near(irregularity.lateral(vector[1], vector[2]), vector[3], 1e-12, "lateral hash is stable across Lua runtimes")
	near(irregularity.vertical(vector[1], vector[2]), vector[4], 1e-12, "vertical hash is stable across Lua runtimes")
end

for index = -100, 100 do
	local regular = index / 100
	for _, irregular in ipairs({ -1, -0.5, 0, 0.5, 1 }) do
		local result = irregularity.blend(regular, irregular)
		assert(result >= -1 and result <= 1, "irregularity preserves the existing profile bounds without clipping")
		assert(math.abs(result - regular) <= 0.100000000001, "irregularity stays within its modest contribution budget")
		if regular == -1 or regular == 1 or irregular == 0 then
			near(result, regular, 1e-12, "irregularity preserves full-strength limits and zero-input poses")
		end
	end
end

for _, evaluate in ipairs({ irregularity.lateral, irregularity.vertical, irregularity.warp }) do
	local cache = irregularity.create().lateral
	for _, seed in ipairs({ 0, 31, -1, 997, 123456, 31 }) do
		for _, coordinate in ipairs({ -1e20, -1e7, -4.001, -4, -3.999, -0.001, 0, 0.001, 123.45, 1e7, 1e20, 0.001 }) do
			local expected = evaluate(coordinate, seed)
			if evaluate == irregularity.warp then
				assert(math.abs(expected - coordinate) <= 0.08000001, "phase displacement stays bounded without drift")
			else
				assert(expected >= -1 and expected <= 1, "irregular profiles remain within their amplitude budget")
			end
			near(
				evaluate(coordinate, seed, cache),
				expected,
				1e-12,
				"cached profiles match direct sampling after jumps and seed changes"
			)
			near(evaluate(coordinate, seed, cache), expected, 1e-12, "repeated callbacks do not advance the profile")
		end
	end
	for _, cell in ipairs({ -8, -1, 0, 1, 4, 11 }) do
		local epsilon = 0.0001
		local centre = evaluate(cell, 31)
		local left, right = evaluate(cell - epsilon, 31), evaluate(cell + epsilon, 31)
		near(left, right, 0.001, "profile values join smoothly across cells")
		near((centre - left) / epsilon, (right - centre) / epsilon, 0.001, "profile slopes join smoothly across cells")
		local leftCurvature = (centre - 2 * left + evaluate(cell - 2 * epsilon, 31)) / epsilon ^ 2
		local rightCurvature = (evaluate(cell + 2 * epsilon, 31) - 2 * right + centre) / epsilon ^ 2
		near(leftCurvature, rightCurvature, 0.02, "profile curvature joins smoothly across cells")
	end
	for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
		assert(not pcall(evaluate, invalid, 31), "invalid irregularity coordinates fail explicitly")
	end
end

do
	local varied = 0
	for _, seed in ipairs({ 0, 31, -1, 997, 123456 }) do
		local cached = irregularity.create().spacingLateral
		local step = 0.01
		local previous = irregularity.warp(-20, seed, cached)
		for index = -1999, 2000 do
			local coordinate = index * step
			local current = irregularity.warp(coordinate, seed, cached)
			local rate = (current - previous) / step
			assert(rate >= 0.889375 - 1e-9 and rate <= 1.110625 + 1e-9, "spacing stays bounded and strictly forward")
			if math.abs(rate - 1) > 0.02 then
				varied = varied + 1
			end
			previous = current
		end
	end
	assert(varied > 1000, "the dominant wave's spacing changes meaningfully across distance and seeds")
	local variedPeriods = 0
	for _, seed in ipairs({ 7, 31, 257 }) do
		local previous
		for cycle = -20, 20 do
			local lower, upper = cycle - 0.08, cycle + 0.08
			for _ = 1, 32 do
				local middle = (lower + upper) * 0.5
				if irregularity.warp(middle, seed) < cycle then
					lower = middle
				else
					upper = middle
				end
			end
			local crossing = (lower + upper) * 0.5
			if previous then
				local period = crossing - previous
				assert(period >= 0.90 and period <= 1.125, "complete wave cycles retain modest spacing limits")
				if math.abs(period - 1) > 0.01 then
					variedPeriods = variedPeriods + 1
				end
			end
			previous = crossing
		end
	end
	assert(variedPeriods > 30, "irregular spacing changes cycle timing, not just the shape within fixed cycles")
end

do
	local other =
		dofile("tests/support/harness.lua").new().require("apasz_swaying_waying::/swaying_waying/irregularity.lua")
	local axisDifferences, spatialDifferences, seedDifferences = 0, 0, 0
	for index = 1, 200 do
		local coordinate = index * 0.37
		local lateral = irregularity.lateral(coordinate, 31)
		near(other.lateral(coordinate, 31), lateral, 1e-12, "isolated Lua contexts produce the same profile")
		near(
			other.warp(coordinate, 31),
			irregularity.warp(coordinate, 31),
			1e-12,
			"spacing is independent of Lua context"
		)
		if math.abs(lateral - irregularity.vertical(coordinate, 31)) > 0.01 then
			axisDifferences = axisDifferences + 1
		end
		if math.abs(lateral - irregularity.lateral(coordinate + 256, 31)) > 0.01 then
			spatialDifferences = spatialDifferences + 1
		end
		if math.abs(lateral - irregularity.lateral(coordinate, 31 + 997)) > 0.01 then
			seedDifferences = seedDifferences + 1
		end
	end
	assert(axisDifferences > 150, "vertical and lateral inputs have distinct shapes")
	assert(spatialDifferences > 150, "irregularity does not tile every 256 cells")
	assert(seedDifferences > 150, "irregularity does not inherit the regular waves' 997-seed cycle")
end

do
	local fixture = dofile("tests/support/wave_fixture.lua")
	local lateral, warp = irregularity.lateral, irregularity.warp
	for _, profile in ipairs({ "QUICK", "DEFAULT", "SLOW" }) do
		for _, shared in ipairs({ false, true }) do
			local state = fixture(motion, profile, 101, 257, 0)
			local sample, settings = state.sample, state.model.motion
			local geometry = state.model.sections[1].geometry
			if shared then
				motion.prepareWaves(state, sample.distance, 0)
				motion.prepareWaves(state, sample.distance, 0)
				sample.distance = sample.distance + 0.5
				sample.sharedDistance = sample.distance
				motion.prepareWaves(state, sample.distance, 0)
				assert(sample.waves, "disabled-roll checks exercise shared wave evaluation")
			end
			local _, expectedHeave, expectedPitch = motion.animationTimes(sample, settings, geometry)
			local expectedRawHeave, expectedRawPitch = motion.secondaryMotion(sample, profile, geometry.wheelbase)
			settings.rollIntensity = 0
			local expectedRoll = motion.animationTime(sample, settings)
			assert(expectedRoll ~= 2500, "disabled-roll checks retain active curve lean")
			irregularity.lateral = function()
				error("disabled roll must not sample lateral irregularity")
			end
			irregularity.warp = function(coordinate, seed, cached)
				assert(cached ~= sample.irregularity.spacingLateral, "disabled roll must not sample lateral spacing")
				return warp(coordinate, seed, cached)
			end
			local roll, heave, pitch = motion.animationTimes(sample, settings, geometry)
			near(roll, expectedRoll, 1e-9, "zero roll strength preserves curve lean")
			near(heave, expectedHeave, 1e-9, "zero roll strength preserves heave")
			near(pitch, expectedPitch, 1e-9, "zero roll strength preserves pitch")
			local rawHeave, rawPitch = motion.secondaryMotion(sample, profile, geometry.wheelbase)
			near(rawHeave, expectedRawHeave, 1e-12, "secondary sampling skips roll without changing heave")
			near(rawPitch, expectedRawPitch, 1e-12, "secondary sampling skips roll without changing pitch")
			irregularity.lateral, irregularity.warp = lateral, warp
		end
	end
end

do
	local fixture = dofile("tests/support/wave_fixture.lua")
	for _, profile in ipairs({ "QUICK", "DEFAULT", "SLOW" }) do
		local state = fixture(motion, profile, 101, 257, 0)
		local sample, settings = state.sample, state.model.motion
		local geometry = state.model.sections[1].geometry
		settings.curveLeanIntensity = 0
		local baseline = { motion.animationTimes(sample, settings, geometry) }
		for axis, name in ipairs({ "roll", "heave", "pitch" }) do
			config[name] = false
			local result = { motion.animationTimes(sample, settings, geometry) }
			for channel = 1, 3 do
				near(
					result[channel],
					channel == axis and 2500 or baseline[channel],
					1e-9,
					"disabling one axis preserves the other irregular axes"
				)
			end
			config[name] = true
		end
	end

	local state = fixture(motion, "DEFAULT", 101, 257, 0)
	local sample, settings = state.sample, state.model.motion
	local geometry = state.model.sections[1].geometry
	settings.curveLeanIntensity = 0
	config.shortWave, config.longWave, config.thirdWave = false, false, false
	local warp = irregularity.warp
	irregularity.warp = function()
		error("disabled short wave must not sample spacing")
	end
	assert(motion.hasProceduralMotion(settings), "irregularity is an independent procedural source")
	local roll, heave, pitch = motion.animationTimes(sample, settings, geometry)
	assert(roll ~= 2500 and heave ~= 2500 and pitch ~= 2500, "irregularity can drive each axis on its own")
	local cached = sample.irregularity
	assert(cached, "active motion creates its coefficient cache")
	for index = 1, 100 do
		sample.distance = index * 0.37
		motion.animationTimes(sample, settings, geometry)
		assert(sample.irregularity == cached, "moving frames reuse the same coefficient caches")
	end
	config.irregularity = false
	assert(not motion.hasProceduralMotion(settings), "all procedural sources can be disabled")
	roll, heave, pitch = motion.animationTimes(sample, settings, geometry)
	assert(roll == 2500 and heave == 2500 and pitch == 2500, "disabled procedural sources remain neutral")
	config.irregularity = true
	local stopped = fixture(motion, "DEFAULT", 101, 258, 0)
	stopped.sample.motionScale = 0
	stopped.model.motion.curveLeanIntensity = 0
	roll, heave, pitch = motion.animationTimes(stopped.sample, stopped.model.motion, stopped.model.sections[1].geometry)
	assert(roll == 2500 and heave == 2500 and pitch == 2500, "settled motion remains neutral with irregularity enabled")
	assert(stopped.sample.irregularity == nil, "settled motion skips irregularity allocation and sampling")
	irregularity.warp = warp
end

print("Irregularity checks passed")
