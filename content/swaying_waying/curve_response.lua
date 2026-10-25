local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local math = _tl_compat and _tl_compat.math or math
local pcall = _tl_compat and _tl_compat.pcall or pcall
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local CURVATURE_WINDOW = 40.0
local LATERAL_ACCELERATION_SCALE = 1.2

local function sampleCurvature(landVehicleApi)
	local succeeded, result =
		pcall(landVehicleApi.getAverageCurvature, landVehicleApi, CURVATURE_WINDOW, CURVATURE_WINDOW)
	if not succeeded then
		logger.warnOnce("curve-query-failed", "Ignoring unavailable curve lean: " .. tostring(result))
	elseif type(result) == "number" and result > -math.huge and result < math.huge then
		return result
	else
		logger.warnOnce("curve-query-invalid", "Ignoring invalid track curvature: " .. tostring(result))
	end
	return nil
end

local function tilt(landVehicleApi, speed, reversed, state, distance)
	assert(speed > -math.huge and speed < math.huge, "Invalid curve-lean speed")
	assert(distance > -math.huge and distance < math.huge, "Invalid curve sampling distance")
	if math.abs(speed) < constants.MIN_MOTION_SPEED then
		state.curveSampleDistance = nil
		return 0.5, nil
	end
	local previousDistance = state.curveSampleDistance
	local samplingDistance = state.model.curveSamplingDistance

	if
		samplingDistance == 0.0
		or previousDistance == nil
		or math.abs(distance - previousDistance) >= samplingDistance
	then
		state.curvature = sampleCurvature(landVehicleApi)
		state.curveSampleDistance = distance
	end
	local curvature = state.curvature
	if curvature == nil or curvature == 0.0 then
		return 0.5, curvature
	end

	local presentCurvature = curvature
	local signedCurvature = reversed and presentCurvature or -presentCurvature
	return (math.tanh(speed * speed * signedCurvature / LATERAL_ACCELERATION_SCALE) + 1.0) * 0.5, presentCurvature
end

local module = { tilt = tilt }
return module
