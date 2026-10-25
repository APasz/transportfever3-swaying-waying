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
local pcall = _tl_compat and _tl_compat.pcall or pcall
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local clamp = validation.clamp
local cache = ug_require("apasz_swaying_waying::/swaying_waying/bounded_cache.lua")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")

local SLOW_TRACK_SPEED = 100.0 / 3.6
local STANDARD_TRACK_SPEED = 160.0 / 3.6
local HIGH_SPEED_TRACK_SPEED = 350.0 / 3.6
local MIN_COMBINED_FACTOR = 0.35
local MAX_COMBINED_FACTOR = 2.0
local TRANSITION_DISTANCE = 30.0
local FAILED_INFERENCE_RETRY_DISTANCE = 100.0
local MAX_EDGE_SCAN_COUNT = 64
local MAX_EDGE_SCAN_DISTANCE = 2000.0
local NORMAL_EDGE_SAMPLE_INSET = 5.0
local ROUGH_SHORT_WEIGHT = 0.80
local NEUTRAL_SHORT_WEIGHT = constants.NEUTRAL_TRACK_SHORT_WEIGHT
local SMOOTH_SHORT_WEIGHT = 0.45
local MAX_TRACK_INFLUENCE = constants.MAX_TRACK_INFLUENCE

local trackStates = cache.create(constants.MAX_RUNTIME_VEHICLE_STATES)

local function smoothStep(value)
	local ratio = clamp(value, 0.0, 1.0)
	return ratio * ratio * (3.0 - 2.0 * ratio)
end

local function interpolate(value, lowerValue, upperValue, lowerFactor, upperFactor)
	local ratio = smoothStep((value - lowerValue) / (upperValue - lowerValue))

	return lowerFactor + (upperFactor - lowerFactor) * ratio
end

local function speedLimitFactor(speedLimit)
	if speedLimit ~= speedLimit or speedLimit <= 0.0 or speedLimit == math.huge then
		return 1.0
	elseif speedLimit <= SLOW_TRACK_SPEED then
		return constants.ROUGH_FACTOR
	elseif speedLimit < STANDARD_TRACK_SPEED then
		return interpolate(speedLimit, SLOW_TRACK_SPEED, STANDARD_TRACK_SPEED, constants.ROUGH_FACTOR, 1.0)
	elseif speedLimit < HIGH_SPEED_TRACK_SPEED then
		return interpolate(speedLimit, STANDARD_TRACK_SPEED, HIGH_SPEED_TRACK_SPEED, 1.0, constants.SMOOTH_FACTOR)
	end
	return constants.SMOOTH_FACTOR
end

local function shortWeightForFactor(factor)
	if factor >= constants.ROUGH_FACTOR then
		return ROUGH_SHORT_WEIGHT
	elseif factor > 1.0 then
		local ratio = (factor - 1.0) / (constants.ROUGH_FACTOR - 1.0)
		return NEUTRAL_SHORT_WEIGHT + (ROUGH_SHORT_WEIGHT - NEUTRAL_SHORT_WEIGHT) * ratio
	elseif factor > constants.SMOOTH_FACTOR then
		local ratio = (factor - constants.SMOOTH_FACTOR) / (1.0 - constants.SMOOTH_FACTOR)
		return SMOOTH_SHORT_WEIGHT + (NEUTRAL_SHORT_WEIGHT - SMOOTH_SHORT_WEIGHT) * ratio
	end
	return SMOOTH_SHORT_WEIGHT
end

local function categoryFactor(categories, automaticFactor)
	if categories == nil then
		return automaticFactor, false
	end

	local rough = false
	local smooth = false
	local rougher = false
	local smoother = false
	for _, category in ipairs(categories) do
		if category == constants.TRACK_ROUGH_TAG then
			rough = true
		elseif category == constants.TRACK_SMOOTH_TAG then
			smooth = true
		elseif category == constants.ROUGHER_TAG then
			rougher = true
		elseif category == constants.SMOOTHER_TAG then
			smoother = true
		end
	end

	if rough and smooth then
		logger.warnOnce(
			"track-profile-conflict",
			"Ignoring conflicting swaying_waying_rough and " .. "swaying_waying_smooth track categories"
		)

		return automaticFactor, false
	elseif rough then
		return constants.ROUGH_FACTOR, true
	elseif smooth then
		return constants.SMOOTH_FACTOR, true
	end

	if rougher and smoother then
		logger.warnOnce(
			"track-modifier-conflict",
			"Ignoring conflicting swaying_waying_rougher and " .. "swaying_waying_smoother track categories"
		)

		return automaticFactor, false
	elseif rougher then
		return automaticFactor * constants.ROUGH_FACTOR, true
	elseif smoother then
		return automaticFactor * constants.SMOOTH_FACTOR, true
	end
	return automaticFactor, false
end

local function baseEdgeInfo(landVehicleApi, edgeOffset)
	local succeeded, result = pcall(landVehicleApi.getBaseEdgeInfo, landVehicleApi, edgeOffset)

	if not succeeded then
		logger.warnOnce(
			"track-base-query-failed",
			"Using fallback track response after getBaseEdgeInfo failed at offset "
				.. edgeOffset
				.. ": "
				.. tostring(result)
		)
		return nil
	end
	if result == nil then
		return nil
	end
	return result
end

local function vehicleEdgeInfo(landVehicleApi, offset)
	local succeeded, result = pcall(landVehicleApi.getVehicleEdgeInfo, landVehicleApi, offset)

	if not succeeded then
		logger.warnOnce(
			"track-vehicle-query-failed",
			"Using fallback track response after getVehicleEdgeInfo failed at offset "
				.. offset
				.. ": "
				.. tostring(result)
		)
		return nil
	end
	if result == nil then
		return nil
	end
	return result
end

local function isValidBaseEdge(info)
	return info.edgeOffsetClampedToEdgesCount >= 0
end

local function isNormalWay(info)
	return isValidBaseEdge(info) and info.onBaseEdge and info.baseEdgeType == 0
end

local function sampledSpeedLimit(landVehicleApi, direction, lowerDistance, upperDistance)
	local best = 0.0
	for sampleIndex = 0, 2 do
		local ratio = sampleIndex / 2.0
		local distance = lowerDistance + (upperDistance - lowerDistance) * ratio
		local info = vehicleEdgeInfo(landVehicleApi, direction * distance)
		if info ~= nil then
			best = math.max(best, (info).speedLimit)
		end
	end
	return best
end

local function adjacentNormalTrack(landVehicleApi, current, direction)
	local currentLength = math.max(current.length, 0.0)
	local interveningLength = 0.0
	for edgeDistance = 1, MAX_EDGE_SCAN_COUNT do
		local edgeOffset = direction * edgeDistance
		local candidate = baseEdgeInfo(landVehicleApi, edgeOffset)
		if candidate == nil then
			return nil
		end
		local present = candidate
		if not isValidBaseEdge(present) then
			return nil
		end
		if isNormalWay(present) then
			local lowerDistance = interveningLength + math.min(NORMAL_EDGE_SAMPLE_INSET, present.length * 0.5)
			local upperDistance = interveningLength
				+ currentLength
				+ math.min(NORMAL_EDGE_SAMPLE_INSET, present.length * 0.5)
			local speedLimit = sampledSpeedLimit(landVehicleApi, direction, lowerDistance, upperDistance)

			if speedLimit ~= speedLimit or speedLimit <= 0.0 or speedLimit == math.huge then
				return nil
			end
			return {
				speedLimit = speedLimit,
				categories = present.streetCategories or {},
			}
		end
		interveningLength = interveningLength + math.max(present.length, 0.0)
		if interveningLength > MAX_EDGE_SCAN_DISTANCE then
			return nil
		end
	end
	return nil
end

local function inferredNormalTrack(landVehicleApi, current)
	local behind = adjacentNormalTrack(landVehicleApi, current, -1)
	local ahead = adjacentNormalTrack(landVehicleApi, current, 1)
	if behind == nil then
		return ahead
	elseif ahead == nil then
		return behind
	elseif (ahead).speedLimit > (behind).speedLimit then
		return ahead
	end
	return behind
end

local function newTrackState(purchaseTime)
	return {
		purchaseTime = purchaseTime,
		hasNormal = false,
		normalSpeedLimit = 0.0,
		normalFactor = 1.0,
		hasOutput = false,
		outputFactor = 1.0,
		outputShortWeight = NEUTRAL_SHORT_WEIGHT,
		distance = 0.0,
		sampleDistance = 0.0,
		hasTarget = false,
		targetFactor = 1.0,
		targetShortWeight = NEUTRAL_SHORT_WEIGHT,
		inferenceFailed = false,
		inferenceDistance = 0.0,
	}
end

local function stateFor(carriageEntity, purchaseTime)
	local state = cache.get(trackStates, carriageEntity)
	if state ~= nil and (state).purchaseTime == purchaseTime then
		return state
	end
	local created = newTrackState(purchaseTime)
	cache.put(trackStates, carriageEntity, created)
	return created
end

local function targetFactor(landVehicleApi, state, distance)
	local currentBase = baseEdgeInfo(landVehicleApi, 0)
	local currentVehicle = nil
	if currentBase ~= nil and isNormalWay(currentBase) then
		currentVehicle = vehicleEdgeInfo(landVehicleApi, 0.0)
		if currentVehicle ~= nil and (currentVehicle).speedLimit > 0.0 then
			local speedLimit = (currentVehicle).speedLimit
			local resolved = categoryFactor((currentBase).streetCategories, speedLimitFactor(speedLimit))

			state.hasNormal = true
			state.normalSpeedLimit = speedLimit
			state.normalFactor = resolved
			return resolved
		end
	end

	local currentCategories = nil
	if currentBase ~= nil and isValidBaseEdge(currentBase) then
		currentCategories = (currentBase).streetCategories
	end
	if state.hasNormal then
		local resolved, hasOverride = categoryFactor(currentCategories, speedLimitFactor(state.normalSpeedLimit))

		if hasOverride then
			return resolved
		end
		return state.normalFactor
	end

	if
		currentBase ~= nil
		and isValidBaseEdge(currentBase)
		and (
			not state.inferenceFailed
			or math.abs(distance - state.inferenceDistance) >= FAILED_INFERENCE_RETRY_DISTANCE
		)
	then
		state.inferenceDistance = distance
		local inferred = inferredNormalTrack(landVehicleApi, currentBase)

		state.inferenceFailed = inferred == nil
		if inferred ~= nil then
			local present = inferred
			local inferredFactor = categoryFactor(present.categories, speedLimitFactor(present.speedLimit))

			state.hasNormal = true
			state.normalSpeedLimit = present.speedLimit
			state.normalFactor = inferredFactor
			local resolved, hasOverride = categoryFactor(currentCategories, speedLimitFactor(present.speedLimit))

			if hasOverride then
				return resolved
			end
			return inferredFactor
		end
	end

	if currentVehicle == nil then
		currentVehicle = vehicleEdgeInfo(landVehicleApi, 0.0)
	end
	if currentVehicle ~= nil then
		local speedLimit = (currentVehicle).speedLimit
		local resolved = categoryFactor(currentCategories, speedLimitFactor(speedLimit))

		return resolved
	end
	return 1.0
end

local function response(landVehicleApi, carriageEntity, purchaseTime, distance, samplingDistance)
	assert(distance > -math.huge and distance < math.huge, "Invalid track sampling distance")
	assert(samplingDistance >= 0.0 and samplingDistance < math.huge, "Invalid track sampling interval")
	local state = stateFor(carriageEntity, purchaseTime)
	if not state.hasTarget or math.abs(distance - state.sampleDistance) >= samplingDistance then
		state.targetFactor = targetFactor(landVehicleApi, state, distance)
		state.targetShortWeight = shortWeightForFactor(state.targetFactor)
		state.sampleDistance = distance
		state.hasTarget = true
	end
	local target = state.targetFactor
	local targetShortWeight = state.targetShortWeight
	if not state.hasOutput then
		state.hasOutput = true
		state.outputFactor = target
		state.outputShortWeight = targetShortWeight
	elseif
		distance ~= state.distance
		and (target ~= state.outputFactor or targetShortWeight ~= state.outputShortWeight)
	then
		local distanceDelta = math.abs(distance - state.distance)
		local blend = 1.0 - math.exp(-distanceDelta / TRANSITION_DISTANCE)
		state.outputFactor = state.outputFactor + (target - state.outputFactor) * blend
		state.outputShortWeight = state.outputShortWeight + (targetShortWeight - state.outputShortWeight) * blend
	end
	state.distance = distance
	return state.outputFactor, state.outputShortWeight
end

local function factor(landVehicleApi, carriageEntity, purchaseTime, distance, samplingDistance)
	local outputFactor = response(landVehicleApi, carriageEntity, purchaseTime, distance, samplingDistance)

	return outputFactor
end

local function combinedFactor(trackFactor, vehicleFactor)
	return clamp(trackFactor * vehicleFactor, MIN_COMBINED_FACTOR, MAX_COMBINED_FACTOR)
end

local function applyInfluence(responseFactor, shortWeight, influence)
	local presentInfluence = clamp(influence, 0.0, MAX_TRACK_INFLUENCE)

	return 1.0 + (responseFactor - 1.0) * presentInfluence,
		NEUTRAL_SHORT_WEIGHT + (shortWeight - NEUTRAL_SHORT_WEIGHT) * presentInfluence
end

local module = {
	speedLimitFactor = speedLimitFactor,
	shortWeightForFactor = shortWeightForFactor,
	combinedFactor = combinedFactor,
	applyInfluence = applyInfluence,
	factor = factor,
	response = response,
}

return module
