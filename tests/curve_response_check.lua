local harness = dofile("tests/support/harness.lua").new()
local curve = harness.require("apasz_swaying_waying::/swaying_waying/curve_response.lua")
local near = dofile("tests/assertions.lua").near

local function nativeTilt(curvature, speed, reversed)
	local signed = reversed and curvature or -curvature
	return (math.tanh(speed * speed * signed / 1.2) + 1) / 2
end

local function fixture(interval)
	local item = {
		calls = 0,
		curvature = 0.001,
		distance = 0,
		state = { model = { curveSamplingDistance = interval or 0 } },
	}
	item.api = {
		getAverageCurvature = function(_, front, back)
			item.calls = item.calls + 1
			assert(front == 40 and back == 40, "curvature retains the native 40 metre averaging window")
			return item.curvature
		end,
	}
	function item.tilt(speed, reversed)
		return curve.tilt(item.api, speed or 20, reversed or false, item.state, item.distance)
	end
	return item
end

do
	local item = fixture()
	for _, curvature in ipairs({ 0.001, 0.003, -0.002, 0, 0.0001 }) do
		item.curvature = curvature
		for _, speed in ipairs({ 20, 30, 5, -20, -5 / 3.6, 5 / 3.6, 5.001 / 3.6 }) do
			for _, reversed in ipairs({ false, true }) do
				local calls = item.calls
				near(
					item.tilt(speed, reversed),
					nativeTilt(curvature, speed, reversed),
					1e-12,
					"every update uses current curvature, speed, and orientation without distance lag"
				)
				assert(item.calls == calls + 1, "each moving update makes one curvature query")
			end
		end
	end
end

for _, speed in ipairs({ -4.999 / 3.6, -0.001, 0, 0.001, 4.999 / 3.6 }) do
	local item = fixture(5)
	item.tilt()
	item.curvature = -0.002
	local tilt, average = item.tilt(speed)
	assert(tilt == 0.5 and average == nil, "curve lean targets neutral below 5 km/h in either direction")
	assert(item.calls == 1, "low-speed motion makes no curvature queries")
	assert(item.state.curveSampleDistance == nil, "low-speed motion invalidates cached curve geometry")
	near(item.tilt(5 / 3.6), nativeTilt(-0.002, 5 / 3.6), 1e-12, "lean restarts at 5 km/h with fresh geometry")
	assert(item.calls == 2, "crossing the speed threshold refreshes geometry without waiting for distance")
end

do
	local item = fixture(5)
	for _ = 1, 100 do
		assert(item.tilt(0) == 0.5, "stopped carriages have neutral lean")
	end
	assert(item.calls == 0, "a carriage at rest makes no curvature queries")
	item.tilt()
	item.curvature = -0.002
	for _ = 1, 100 do
		assert(item.tilt(0) == 0.5, "stopped targets remain neutral")
	end
	assert(item.calls == 1, "stopped frames make no curvature queries")
	near(item.tilt(), nativeTilt(-0.002, 20), 1e-12, "restart uses current geometry")
	assert(item.calls == 2, "restart needs only one fresh query")
end

for _, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
	local item = fixture(option.distance)
	for frame = 0, 120 do
		item.distance = frame / 4
		item.tilt()
	end
	assert(item.calls == option.calls, "each curve interval controls the curvature-query budget")
end

do
	local item = fixture(5)
	item.distance = 100
	item.tilt()
	item.curvature = -0.002
	item.distance = 104.99
	local tilt, average = item.tilt(30, true)
	near(tilt, nativeTilt(0.001, 30, true), 1e-12, "cached geometry retains live speed and orientation")
	assert(average == 0.001 and item.calls == 1, "curvature is reused below the selected interval")
	item.distance = 105
	near(item.tilt(), nativeTilt(-0.002, 20), 1e-12, "curve geometry refreshes exactly at the interval")
	assert(item.calls == 2, "the boundary makes one fresh curvature query")
	item.curvature = 0
	item.distance = 100
	assert(item.tilt() == 0.5 and item.calls == 3, "backward distance changes also refresh curve geometry")
	item.curvature = 0.003
	item.distance = 101
	assert(item.tilt() == 0.5 and item.calls == 3, "straight track remains a cached curvature value")
	local other = fixture(5)
	other.curvature = -0.004
	near(other.tilt(), nativeTilt(-0.004, 20), 1e-12, "carriages sample curve geometry independently")
end

do
	local item = fixture()
	local previousWarnings = #harness.warnings
	for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge, "invalid" }) do
		item.curvature = invalid
		assert(item.tilt() == 0.5, "invalid geometry produces neutral lean")
	end
	assert(#harness.warnings == previousWarnings + 1, "invalid curvature is reported once")
	item.api.getAverageCurvature = function()
		item.calls = item.calls + 1
		error("unavailable native curvature")
	end
	for _ = 1, 2 do
		assert(item.tilt() == 0.5, "native failures preserve other motion")
	end
	assert(#harness.warnings == previousWarnings + 2, "native failures are reported once")
	item.api.getAverageCurvature = function()
		return 0.001
	end
	near(item.tilt(), nativeTilt(0.001, 20), 1e-12, "the next update recovers from unavailable curvature")
end

do
	local item = fixture(5)
	item.curvature = math.huge
	local previousWarnings = #harness.warnings
	assert(item.tilt() == 0.5 and item.calls == 1, "failed curve queries produce neutral lean")
	assert(#harness.warnings == previousWarnings, "repeated invalid curvature across carriages does not log again")
	item.curvature = 0.001
	item.distance = 4
	assert(item.tilt() == 0.5 and item.calls == 1, "failed queries respect the selected interval")
	item.distance = 5
	near(item.tilt(), nativeTilt(0.001, 20), 1e-12, "failed geometry is retried at the next interval")
	assert(item.calls == 2, "recovery requires one fresh query")
end

do
	local item = fixture()
	local tilt, average = item.tilt()
	near(tilt, nativeTilt(0.001, 20), 1e-12, "diagnostic data preserves the motion result")
	assert(average == 0.001, "the motion query exposes its unmodified average to diagnostics")
	local _, stoppedAverage = item.tilt(0)
	assert(stoppedAverage == nil, "skipped stationary queries are distinguishable from straight track")
	item.curvature = 0
	local _, straightAverage = item.tilt()
	assert(straightAverage == 0, "straight track remains a valid sampled average")
	item.curvature = math.huge
	local _, unavailableAverage = item.tilt()
	assert(unavailableAverage == nil, "invalid geometry is distinguishable from straight track")
end

do
	local item = fixture()
	item.curvature = 0
	local originalTanh, evaluations = math.tanh, 0
	math.tanh = function(value)
		evaluations = evaluations + 1
		return originalTanh(value)
	end
	for _ = 1, 100 do
		assert(item.tilt() == 0.5, "straight track has neutral lean while moving")
	end
	math.tanh = originalTanh
	assert(evaluations == 0, "straight track skips the lean response calculation")
end

for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
	local item = fixture()
	assert(not pcall(item.tilt, invalid), "invalid speeds fail explicitly")
	assert(item.calls == 0, "invalid speeds fail before querying native geometry")
	item.distance = invalid
	assert(not pcall(item.tilt), "invalid sampling distances fail explicitly")
	assert(item.calls == 0, "invalid distances fail before querying native geometry")
end

print("Curve response checks passed")
