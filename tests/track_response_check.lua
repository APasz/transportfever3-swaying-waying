local harness = dofile("tests/support/harness.lua").new()
local constants = harness.require("apasz_swaying_waying::/swaying_waying/constants.lua")
constants.MAX_RUNTIME_VEHICLE_STATES = 2
local track = harness.require("apasz_swaying_waying::/swaying_waying/track_response.lua")
local near = dofile("tests/assertions.lua").near
local normal = false
local baseCalls = 0
local structure =
	{ edgeOffsetClampedToEdgesCount = 0, onBaseEdge = true, baseEdgeType = 1, length = 1, streetCategories = {} }
local ordinary =
	{ edgeOffsetClampedToEdgesCount = 0, onBaseEdge = true, baseEdgeType = 0, length = 1, streetCategories = {} }
local api = {
	getBaseEdgeInfo = function(_, offset)
		baseCalls = baseCalls + 1
		return normal and offset == 0 and ordinary or structure
	end,
	getVehicleEdgeInfo = function()
		return { speedLimit = (normal and 100 or 160) / 3.6 }
	end,
}
track.response(api, 1, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
assert(baseCalls == 129, "a cold structure lookup has a bounded initial scan")
baseCalls = 0
track.response(api, 1, 1, 1, constants.DEFAULT_SAMPLE_DISTANCE)
track.response(api, 1, 1, constants.DEFAULT_SAMPLE_DISTANCE - 0.01, constants.DEFAULT_SAMPLE_DISTANCE)
assert(baseCalls == 0, "track queries reuse the target within the default sampling interval")
track.response(api, 1, 1, constants.DEFAULT_SAMPLE_DISTANCE, constants.DEFAULT_SAMPLE_DISTANCE)
assert(baseCalls == 1, "failed inference is cached instead of scanning again at the next sample")
baseCalls = 0
track.response(api, 1, 1, 100, constants.DEFAULT_SAMPLE_DISTANCE)
assert(baseCalls == 129, "failed inference is retried after its distance budget")
normal = true
local reachedNormal =
	track.response(api, 1, 1, 100 + constants.DEFAULT_SAMPLE_DISTANCE, constants.DEFAULT_SAMPLE_DISTANCE)
assert(reachedNormal > 1, "failed-lookup backoff does not delay detection of normal track")

track.response(api, 10, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
track.response(api, 11, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
normal = false
near(
	track.response(api, 10, 1, constants.DEFAULT_SAMPLE_DISTANCE, constants.DEFAULT_SAMPLE_DISTANCE),
	1.25,
	1e-9,
	"the active carriage retains its normal-track history on a bridge"
)
normal = true
track.response(api, 12, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
normal = false
near(
	track.response(api, 10, 1, 2 * constants.DEFAULT_SAMPLE_DISTANCE, constants.DEFAULT_SAMPLE_DISTANCE),
	1.25,
	1e-9,
	"cache pressure preserves recently used carriage history"
)

normal = true
local before = track.response(api, 20, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
normal = false
local halfway = track.response(api, 20, 1, 0.5, constants.DEFAULT_SAMPLE_DISTANCE)
near(halfway, before, 1e-9, "unchanged targets preserve their output between native queries")

local speedLimit, queries = 160 / 3.6, 0
local normalApi = {
	getBaseEdgeInfo = function()
		queries = queries + 1
		return ordinary
	end,
	getVehicleEdgeInfo = function()
		return { speedLimit = speedLimit }
	end,
}
track.response(normalApi, 30, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
speedLimit = 350 / 3.6
local boundaryDistance = constants.DEFAULT_SAMPLE_DISTANCE
local betweenDistance = boundaryDistance + 1
local boundary = track.response(normalApi, 30, 1, boundaryDistance, constants.DEFAULT_SAMPLE_DISTANCE)
local between = track.response(normalApi, 30, 1, betweenDistance, constants.DEFAULT_SAMPLE_DISTANCE)
assert(between < boundary and between > 0.7, "track smoothing continues between queries")
near(between, 0.7 + 0.3 * math.exp(-betweenDistance / 30), 1e-9, "track smoothing retains its distance response")
assert(queries == 2, "smoothing between samples does not query native geometry")
queries = 0
for frame = 0, 1200 do
	track.response(normalApi, 31, 1, frame / 4, constants.DEFAULT_SAMPLE_DISTANCE)
end
assert(queries == 61, "300 metres uses 61 track samples at the five metre default, including the initial query")

speedLimit = 160 / 3.6
track.response(normalApi, 40, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
speedLimit = 350 / 3.6
track.response(normalApi, 40, 1, boundaryDistance, constants.DEFAULT_SAMPLE_DISTANCE)
local originalExp = math.exp
local exponentials = 0
math.exp = function(value)
	exponentials = exponentials + 1
	return originalExp(value)
end
for _ = 1, 100 do
	track.response(normalApi, 40, 1, boundaryDistance, constants.DEFAULT_SAMPLE_DISTANCE)
end
math.exp = originalExp
assert(exponentials == 0, "a pending track transition does no smoothing work while stopped")

for index, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
	queries = 0
	for frame = 0, 120 do
		track.response(normalApi, 50 + index, 1, frame / 4, option.distance)
	end
	assert(queries == option.calls, "selected track interval controls the native-query budget")
end

for _, invalid in ipairs({ -1, 0 / 0, math.huge }) do
	assert(not pcall(track.response, normalApi, 100, 1, 0, invalid), "invalid track intervals fail explicitly")
end

for index, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
	local carriage = 300 + index
	speedLimit = 160 / 3.6
	track.response(normalApi, carriage, 1, 0, constants.DEFAULT_SAMPLE_DISTANCE)
	queries = 0
	assert(
		not pcall(track.response, normalApi, carriage, 1, invalid, constants.DEFAULT_SAMPLE_DISTANCE),
		"invalid track distances fail explicitly"
	)
	assert(queries == 0, "invalid distances fail before querying native geometry")
	speedLimit = 350 / 3.6
	near(
		track.response(normalApi, carriage, 1, constants.DEFAULT_SAMPLE_DISTANCE, constants.DEFAULT_SAMPLE_DISTANCE),
		0.7 + 0.3 * math.exp(-constants.DEFAULT_SAMPLE_DISTANCE / 30),
		1e-9,
		"invalid distances cannot poison subsequent track response or smoothing"
	)
end

do
	local previousWarnings = #harness.warnings
	local failingApi = {
		getBaseEdgeInfo = function()
			error("base query failed")
		end,
		getVehicleEdgeInfo = function()
			error("vehicle query failed")
		end,
	}
	for index = 1, 20 do
		local factor, weight = track.response(failingApi, 200, 1, index, 0)
		near(factor, 1, 1e-12, "native query failures retain neutral fallback motion")
		near(weight, constants.NEUTRAL_TRACK_SHORT_WEIGHT, 1e-12, "failed queries retain the neutral spectrum")
	end
	assert(#harness.warnings == previousWarnings + 2, "each failed native query logs once without per-frame spam")
	assert(
		harness.warnings[previousWarnings + 1]:find("getBaseEdgeInfo", 1, true)
			and harness.warnings[previousWarnings + 1]:find("base query failed", 1, true),
		"base query diagnostics preserve the cause"
	)
	assert(
		harness.warnings[previousWarnings + 2]:find("getVehicleEdgeInfo", 1, true)
			and harness.warnings[previousWarnings + 2]:find("vehicle query failed", 1, true),
		"vehicle query diagnostics preserve the cause"
	)
end
print("Track response checks passed")
