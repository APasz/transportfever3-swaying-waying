local harness = dofile("tests/support/harness.lua").new()
local response = harness.require("apasz_swaying_waying::/swaying_waying/motion_response.lua")
local near = dofile("tests/assertions.lua").near

local function state()
	return {
		sample = { motionScale = 0, curveTilt = 0.5, distance = 123, sharedDistance = 83 },
		motionVelocity = 0,
		curveVelocity = 0,
	}
end

do
	local item = state()
	response.update(item, 100, 0.7, 0.2)
	assert(item.sample.motionScale == 0.7 and item.sample.curveTilt == 0.2, "cold loads start at their current pose")
	response.update(item, 100, 1, 0.8)
	assert(
		item.sample.motionScale == 0.7 and item.sample.curveTilt == 0.2,
		"duplicate times and pause do not advance damping"
	)
	response.update(item, 116, 1, 0.8)
	assert(item.sample.motionScale > 0.7 and item.sample.motionScale < 1, "amplitude steps produce gradual movement")
	assert(item.sample.curveTilt > 0.2 and item.sample.curveTilt < 0.8, "lean steps produce gradual movement")
	local moving, velocity = item.sample.curveTilt, item.curveVelocity
	response.update(item, 116, 0, 0)
	assert(
		item.sample.curveTilt == moving and item.curveVelocity == velocity,
		"a new target preserves position and velocity at the same time"
	)
	assert(
		item.sample.distance == 123 and item.sample.sharedDistance == 83,
		"damping never changes the wave coordinates"
	)
	response.update(item, 50, 0.4, 0.6)
	assert(item.sample.motionScale == 0.4 and item.sample.curveTilt == 0.6, "clock rewinds reset stale responses")
	assert(item.motionVelocity == 0 and item.curveVelocity == 0, "clock rewinds clear velocity")
end

local function stepResponse(times)
	local item = state()
	response.update(item, 0, 0, 0.1)
	for _, time in ipairs(times) do
		response.update(item, time, 1, 0.9)
	end
	return item
end

do
	local whole = stepResponse({ 200 })
	for _, times in ipairs({
		{ 100, 200 },
		{ 20, 40, 60, 80, 100, 120, 140, 160, 180, 200 },
		{ 1, 17, 52, 52, 113, 171, 199, 200 },
	}) do
		local split = stepResponse(times)
		near(
			split.sample.motionScale,
			whole.sample.motionScale,
			1e-12,
			"equal elapsed time preserves amplitude across frame rates"
		)
		near(
			split.sample.curveTilt,
			whole.sample.curveTilt,
			1e-12,
			"equal elapsed time preserves lean across irregular frame times"
		)
		near(split.motionVelocity, whole.motionVelocity, 1e-12, "frame partitioning preserves movement rate")
	end
	local previous, curvePrevious = 0, 0.1
	for time = 10, 1000, 10 do
		local item = stepResponse({ time })
		assert(
			item.sample.motionScale >= previous and item.sample.motionScale <= 1,
			"a step from rest approaches its target without overshoot"
		)
		assert(
			item.sample.curveTilt >= curvePrevious and item.sample.curveTilt <= 0.9,
			"lean approaches a constant target without oscillation"
		)
		previous, curvePrevious = item.sample.motionScale, item.sample.curveTilt
	end
	assert(previous > 0.999 and curvePrevious > 0.899, "the short response settles promptly")
	local gap = stepResponse({ 1000000 })
	assert(gap.sample.motionScale == 1 and gap.sample.curveTilt == 0.9, "long render gaps settle without instability")
end

do
	local item = state()
	response.update(item, 0, 1, 0.1)
	response.update(item, 16, 0, 0.5)
	assert(
		item.sample.motionScale > 0 and item.sample.curveTilt < 0.5,
		"stopping settles the body instead of snapping it level"
	)
	for time = 32, 2000, 16 do
		response.update(item, time, 0, 0.5)
	end
	assert(item.sample.motionScale == 0 and item.sample.curveTilt == 0.5, "stopped responses settle exactly to neutral")
	assert(item.motionVelocity == 0 and item.curveVelocity == 0, "settled responses retain no residual velocity")
	response.update(item, 2016, 0.7, 0.2)
	assert(item.sample.motionScale > 0 and item.sample.motionScale < 0.7, "restart ramps up the speed envelope")
	assert(item.sample.curveTilt < 0.5 and item.sample.curveTilt > 0.2, "restart ramps up curve lean")
end

do
	local item = state()
	response.update(item, 0, 0, 0.5)
	for frame = 1, 1000 do
		local amplitude = frame % 4 < 2 and 0 or 1
		local tilt = frame % 7 < 3 and 0 or 1
		response.update(item, frame * 16, amplitude, tilt)
		assert(
			item.sample.motionScale >= 0 and item.sample.motionScale <= 1,
			"sustained fluctuations keep amplitude bounded"
		)
		assert(item.sample.curveTilt >= 0 and item.sample.curveTilt <= 1, "rapid curve changes keep lean bounded")
	end
end

do
	local originalExp, calls = math.exp, 0
	math.exp = function(value)
		calls = calls + 1
		return originalExp(value)
	end
	local item = state()
	response.update(item, 0, 0, 0.5)
	response.update(item, 16, 0, 0.5)
	assert(calls == 0, "cold and unchanged responses skip exponentiation")
	response.update(item, 32, 1, 0.1)
	assert(calls == 1, "both response channels share one decay calculation")
	response.update(item, 32, 1, 0.1)
	assert(calls == 1, "repeated callbacks at the same time skip damping work")
	math.exp = originalExp
end

do
	local motion = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
	local curve = harness.require("apasz_swaying_waying::/swaying_waying/curve_response.lua")
	local item = state()
	item.model = { curveSamplingDistance = 0 }
	local distance, queries = 0, 0
	local api = {
		getAverageCurvature = function()
			queries = queries + 1
			return 0.003 * math.sin(distance / 40) + 0.001 * math.sin(distance / 9)
		end,
	}
	local lastRaw, lastOutput, lastRawRate, lastOutputRate
	local rawPeak, outputPeak = 0, 0
	for frame = 0, 1000 do
		local speed = math.floor(frame / 25) % 2 == 0 and 10 or 25
		if frame > 0 then
			distance = distance + speed / 100
		end
		local target = curve.tilt(api, speed, false, item, distance)
		response.update(item, frame * 10, motion.speedFactor(speed, "DEFAULT"), target)
		if lastRaw then
			local rawRate = (target - lastRaw) * 100
			local outputRate = (item.sample.curveTilt - lastOutput) * 100
			if lastRawRate then
				rawPeak = math.max(rawPeak, math.abs(rawRate - lastRawRate))
				outputPeak = math.max(outputPeak, math.abs(outputRate - lastOutputRate))
			end
			lastRawRate, lastOutputRate = rawRate, outputRate
		end
		lastRaw, lastOutput = target, item.sample.curveTilt
	end
	assert(rawPeak > 1, "the synthetic curves and speed fluctuations exercise abrupt lean changes")
	assert(outputPeak < rawPeak * 0.1, "damping softens changes in lean rate through complex curves and speed steps")
	assert(queries == 1001, "damping uses one current curvature query per moving update")
end

for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
	assert(not pcall(response.update, state(), invalid, 0, 0.5), "invalid clocks fail explicitly")
	assert(not pcall(response.update, state(), 0, invalid, 0.5), "invalid amplitudes fail explicitly")
	assert(not pcall(response.update, state(), 0, 0, invalid), "invalid tilt targets fail explicitly")
end

print("Motion response checks passed")
