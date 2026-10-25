local harness = dofile("tests/support/harness.lua").new()
local warnings = harness.warnings
local assertions = dofile("tests/assertions.lua")
local assertEqual, assertNear = assertions.equal, assertions.near
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local trackResponse = ug_require("apasz_swaying_waying::/swaying_waying/track_response.lua")
local vehicleResponse = ug_require("apasz_swaying_waying::/swaying_waying/vehicle_response.lua")
assertNear(trackResponse.speedLimitFactor(100 / 3.6), 1.25, 0.000001, "100 km/h track uses the rough anchor")
assertNear(trackResponse.speedLimitFactor(160 / 3.6), 1.0, 0.000001, "160 km/h track uses the standard anchor")
assertNear(trackResponse.speedLimitFactor(350 / 3.6), 0.7, 0.000001, "350 km/h track uses the smooth anchor")
for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
	assertNear(trackResponse.speedLimitFactor(invalid), 1, 0.000001, "invalid speed limits are neutral")
end
assertNear(trackResponse.shortWeightForFactor(1.25), 0.80, 0.000001, "rough track favours the short wave")
assertNear(trackResponse.shortWeightForFactor(1.0), 0.65, 0.000001, "standard track uses the default spectrum")
assertNear(trackResponse.shortWeightForFactor(0.7), 0.45, 0.000001, "smooth track favours the long wave")
assertNear(trackResponse.combinedFactor(1.25, 1.25), 1.5625, 0.000001, "track and vehicle modifiers compose")
assertNear(trackResponse.combinedFactor(2.0, 2.0), 2.0, 0.000001, "combined response is safety-clamped")
assertNear(
	trackResponse.combinedFactor(0 / 0, 1.0),
	0.35,
	0.000001,
	"invalid combined response retains the safe lower clamp"
)
local disabledTrackFactor, disabledTrackWeight = trackResponse.applyInfluence(1.25, 0.80, 0.0)
assertNear(disabledTrackFactor, 1.0, 0.000001, "disabled track influence neutralises amplitude")
assertNear(disabledTrackWeight, 0.65, 0.000001, "disabled track influence neutralises spectrum")
local enhancedTrackFactor, enhancedTrackWeight = trackResponse.applyInfluence(1.25, 0.80, 1.5)
assertNear(enhancedTrackFactor, 1.375, 0.000001, "enhanced track influence scales around neutral")
assertNear(enhancedTrackWeight, 0.875, 0.000001, "enhanced track influence scales the spectrum")

assertNear(vehicleResponse.comfortFactor(0.0, true), 1.10, 0.000001, "low passenger comfort adds sway")
assertNear(vehicleResponse.comfortFactor(0.5, true), 1.0, 0.000001, "average passenger comfort is neutral")
assertNear(vehicleResponse.comfortFactor(1.0, true), 0.90, 0.000001, "high passenger comfort reduces sway")
assertNear(vehicleResponse.comfortFactor(0.0, false), 1.0, 0.000001, "freight ignores passenger comfort")
assertNear(vehicleResponse.comfortFactor(-1.0, true), 1.0, 0.000001, "automatic comfort is neutral")
assertNear(vehicleResponse.comfortFactor(1.2, true), 1.0, 0.000001, "invalid comfort is neutral")
assertNear(vehicleResponse.maintenanceFactor(0.0), 1.0, 0.000001, "best maintenance is neutral")
assertNear(vehicleResponse.maintenanceFactor(0.5), 1.05, 0.000001, "maintenance response interpolates")
assertNear(vehicleResponse.maintenanceFactor(1.0), 1.10, 0.000001, "worst maintenance adds sway")
assertNear(vehicleResponse.maintenanceFactor(nil), 1.0, 0.000001, "missing maintenance is neutral")
assertNear(vehicleResponse.scaleFromNeutral(1.10, 0.0), 1.0, 0.000001, "disabled vehicle variation is neutral")
assertNear(vehicleResponse.scaleFromNeutral(0.90, 1.5), 0.85, 0.000001, "vehicle variation scales around neutral")

local function baseEdge(baseEdgeType, categories, edgeOffset, roadType)
	return {
		edgeOffsetClampedToEdgesCount = edgeOffset == nil and 0 or math.abs(edgeOffset),
		length = 100.0,
		onBaseEdge = true,
		roadType = roadType or 0,
		baseEdgeType = baseEdgeType,
		streetCategories = categories or {},
	}
end

local function fixedTrack(speedLimit, categories)
	return {
		getBaseEdgeInfo = function(_, edgeOffset)
			return baseEdge(0, categories, edgeOffset)
		end,
		getVehicleEdgeInfo = function()
			return { speedLimit = speedLimit }
		end,
	}
end

assertNear(
	trackResponse.factor(
		fixedTrack(350 / 3.6, { constants.TRACK_ROUGH_TAG }),
		1001,
		1,
		0.0,
		constants.DEFAULT_SAMPLE_DISTANCE
	),
	1.25,
	0.000001,
	"rough track category selects the absolute preset"
)
assertNear(
	trackResponse.factor(
		fixedTrack(350 / 3.6, { constants.ROUGHER_TAG }),
		1002,
		1,
		0.0,
		constants.DEFAULT_SAMPLE_DISTANCE
	),
	0.875,
	0.000001,
	"rougher track category modifies the automatic factor"
)
assertNear(
	trackResponse.factor(
		fixedTrack(100 / 3.6, { constants.TRACK_SMOOTH_TAG }),
		1003,
		1,
		0.0,
		constants.DEFAULT_SAMPLE_DISTANCE
	),
	0.7,
	0.000001,
	"smooth track category selects the absolute preset"
)
local roughSpectrumFactor, roughSpectrumWeight = trackResponse.response(
	fixedTrack(350 / 3.6, { constants.TRACK_ROUGH_TAG }),
	1011,
	1,
	0.0,
	constants.DEFAULT_SAMPLE_DISTANCE
)
assertNear(roughSpectrumFactor, 1.25, 0.000001, "rough spectrum retains the rough amplitude")
assertNear(roughSpectrumWeight, 0.80, 0.000001, "rough spectrum selects the short-wave weight")
local smoothSpectrumFactor, smoothSpectrumWeight = trackResponse.response(
	fixedTrack(100 / 3.6, { constants.TRACK_SMOOTH_TAG }),
	1012,
	1,
	0.0,
	constants.DEFAULT_SAMPLE_DISTANCE
)
assertNear(smoothSpectrumFactor, 0.7, 0.000001, "smooth spectrum retains the smooth amplitude")
assertNear(smoothSpectrumWeight, 0.45, 0.000001, "smooth spectrum selects the long-wave weight")
local transitionSpeedLimit = 100 / 3.6
local spectrumTransitionTrack = {
	getBaseEdgeInfo = function(_, edgeOffset)
		return baseEdge(0, {}, edgeOffset)
	end,
	getVehicleEdgeInfo = function()
		return { speedLimit = transitionSpeedLimit }
	end,
}
local _, initialSpectrumWeight =
	trackResponse.response(spectrumTransitionTrack, 1013, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE)
transitionSpeedLimit = 350 / 3.6
local _, transitioningSpectrumWeight =
	trackResponse.response(spectrumTransitionTrack, 1013, 1, 30.0, constants.DEFAULT_SAMPLE_DISTANCE)
assertNear(initialSpectrumWeight, 0.80, 0.000001, "spectrum transition starts at the rough weight")
assertEqual(
	transitioningSpectrumWeight < 0.80 and transitioningSpectrumWeight > 0.45,
	true,
	"spectrum changes smoothly over distance"
)
local trackConflictWarnings = #warnings
assertNear(
	trackResponse.factor(
		fixedTrack(160 / 3.6, { constants.TRACK_ROUGH_TAG, constants.TRACK_SMOOTH_TAG }),
		1006,
		1,
		0.0,
		constants.DEFAULT_SAMPLE_DISTANCE
	),
	1.0,
	0.000001,
	"conflicting track presets resolve automatically"
)
assertEqual(#warnings, trackConflictWarnings + 1, "conflicting track presets are logged")

local tramStreet = {
	getBaseEdgeInfo = function(_, edgeOffset)
		return baseEdge(0, {}, edgeOffset, 1)
	end,
	getVehicleEdgeInfo = function()
		return { speedLimit = 100 / 3.6 }
	end,
}
assertNear(
	trackResponse.factor(tramStreet, 1007, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.25,
	0.000001,
	"street-running trams use normal street speed"
)

local invalidBaseEdgeTrack = {
	getBaseEdgeInfo = function()
		local invalid = baseEdge(0, { constants.TRACK_ROUGH_TAG }, 0)
		invalid.edgeOffsetClampedToEdgesCount = -1
		return invalid
	end,
	getVehicleEdgeInfo = function()
		return { speedLimit = 160 / 3.6 }
	end,
}
assertNear(
	trackResponse.factor(invalidBaseEdgeTrack, 1009, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.0,
	0.000001,
	"invalid base-edge metadata is ignored"
)

assertNear(
	trackResponse.factor(fixedTrack(100 / 3.6, {}), 1010, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.25,
	0.000001,
	"first occupant initializes an entity cache entry"
)
assertNear(
	trackResponse.factor(fixedTrack(350 / 3.6, {}), 1010, 2, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	0.7,
	0.000001,
	"a recycled entity resets state for its new purchase"
)

local stableTrack = fixedTrack(160 / 3.6, {})
trackResponse.response(stableTrack, 1014, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE)
local originalExp = math.exp
local stableTrackExponentialCalls = 0
math.exp = function(value)
	stableTrackExponentialCalls = stableTrackExponentialCalls + 1
	return originalExp(value)
end
trackResponse.response(stableTrack, 1014, 1, 1.0, constants.DEFAULT_SAMPLE_DISTANCE)
math.exp = originalExp
assertEqual(stableTrackExponentialCalls, 0, "stable track response skips transition exponentiation")

local structureType = 0
local rememberedVehicleEdgeCalls = 0
local rememberedTrack = {
	getBaseEdgeInfo = function(_, edgeOffset)
		if edgeOffset == 0 then
			return baseEdge(structureType, {}, 0)
		end
		return baseEdge(0, {}, edgeOffset)
	end,
	getVehicleEdgeInfo = function(_, offset)
		rememberedVehicleEdgeCalls = rememberedVehicleEdgeCalls + 1
		return { speedLimit = structureType ~= 0 and offset == 0 and 90 / 3.6 or 160 / 3.6 }
	end,
}
assertNear(
	trackResponse.factor(rememberedTrack, 1004, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.0,
	0.000001,
	"normal track response is learned"
)
local learnedVehicleEdgeCalls = rememberedVehicleEdgeCalls
structureType = 1
assertNear(
	trackResponse.factor(rememberedTrack, 1004, 1, 10.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.0,
	0.000001,
	"bridge retains the learned track response"
)
assertEqual(
	rememberedVehicleEdgeCalls,
	learnedVehicleEdgeCalls,
	"learned bridge response avoids redundant vehicle-edge sampling"
)
assertNear(
	trackResponse.factor(rememberedTrack, 1005, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.0,
	0.000001,
	"cold bridge state infers adjacent normal track"
)
structureType = 2
assertNear(
	trackResponse.factor(rememberedTrack, 1008, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
	1.0,
	0.000001,
	"cold tunnel state infers adjacent normal track"
)

for structure = 1, 2 do
	for conflictIndex, conflicts in ipairs({
		{ constants.TRACK_ROUGH_TAG, constants.TRACK_SMOOTH_TAG },
		{ constants.ROUGHER_TAG, constants.SMOOTHER_TAG },
	}) do
		local onStructure = false
		local taggedTrack = {
			getBaseEdgeInfo = function(_, edgeOffset)
				return baseEdge(
					onStructure and structure or 0,
					onStructure and conflicts or { constants.TRACK_ROUGH_TAG },
					edgeOffset
				)
			end,
			getVehicleEdgeInfo = function()
				return { speedLimit = 160 / 3.6 }
			end,
		}
		local carriage = 1020 + structure * 2 + conflictIndex
		assertNear(
			trackResponse.factor(taggedTrack, carriage, 1, 0.0, constants.DEFAULT_SAMPLE_DISTANCE),
			1.25,
			0.000001
		)
		onStructure = true
		local factor, weight =
			trackResponse.response(taggedTrack, carriage, 1, 100.0, constants.DEFAULT_SAMPLE_DISTANCE)
		assertNear(factor, 1.25, 0.000001, "conflicting structure tags retain the learned track response")
		assertNear(weight, 0.8, 0.000001, "conflicting structure tags retain the learned spectrum")
	end
end

print("Response checks passed")
