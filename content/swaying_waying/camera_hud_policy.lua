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
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")

local BODY_MARGIN = 0.5
local CAMERA_MATCH_DISTANCE = 0.75

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function finitePoint(point)
	return finite(point.x) and finite(point.y) and finite(point.z)
end

local function read(value)
	if value == nil then
		return nil
	end
	local raw = values.asTable(value)
	assert(raw ~= nil, "Camera HUD metadata must be a table")
	local payload = raw
	assert(payload.schema == constants.CAMERA_HUD_SCHEMA, "Unsupported camera HUD metadata schema")
	local count = values.positiveInteger(payload.count)
	local positions = values.asArray(payload.positions)
	assert(
		count ~= nil and positions ~= nil and values.arraySize(positions) ~= nil,
		"Camera HUD metadata needs a camera count and dense positions"
	)
	local used = {}
	for _, entry in ipairs(positions) do
		local candidate = values.asTable(entry)
		assert(candidate ~= nil, "Camera HUD positions must be records")
		local camera = candidate
		local index = values.positiveInteger(camera.index)
		assert(
			index ~= nil and index <= count and not used[index],
			"Camera HUD indices must be unique and within the camera list"
		)
		used[index] = true
		assert(camera.kind == "Model" or camera.kind == "Stable" or camera.kind == "Sway", "Unknown camera HUD kind")
		assert(camera.crewSeat == nil or values.positiveInteger(camera.crewSeat) ~= nil, "Invalid camera HUD crew seat")
		assert(
			nodes.validTransform(camera.pose) and nodes.inverse(camera.pose) ~= nil,
			"Camera HUD poses must be finite, invertible affine matrices"
		)
	end
	return value
end

local function localEye(transform, eye)
	if not finitePoint(eye) then
		return nil
	end
	for i = 1, 16 do
		if not finite(transform[i]) then
			return nil
		end
	end
	if
		math.abs(transform[4]) > 0.00000001
		or math.abs(transform[8]) > 0.00000001
		or math.abs(transform[12]) > 0.00000001
		or math.abs(transform[16] - 1) > 0.00000001
	then
		return nil
	end
	local a, b, c = transform[1], transform[5], transform[9]
	local d, e, f = transform[2], transform[6], transform[10]
	local g, h, i = transform[3], transform[7], transform[11]
	local determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
	if math.abs(determinant) < 0.00000001 then
		return nil
	end
	local x, y, z = eye.x - transform[13], eye.y - transform[14], eye.z - transform[15]
	local result = {
		x = ((e * i - f * h) * x + (c * h - b * i) * y + (b * f - c * e) * z) / determinant,
		y = ((f * g - d * i) * x + (a * i - c * g) * y + (c * d - a * f) * z) / determinant,
		z = ((d * h - e * g) * x + (b * g - a * h) * y + (a * e - b * d) * z) / determinant,
	}
	return finitePoint(result) and result or nil
end

local function clip(first, last, minimum, maximum, enter, leave)
	minimum, maximum = minimum - BODY_MARGIN, maximum + BODY_MARGIN
	local delta = last - first
	if math.abs(delta) < 0.00000001 then
		if first < minimum or first > maximum then
			return 1, 0
		end
		return enter, leave
	end
	local start, finish = (minimum - first) / delta, (maximum - first) / delta
	if start > finish then
		start, finish = finish, start
	end
	return math.max(enter, start), math.min(leave, finish)
end

local function contains(first, last, minimum, maximum)
	if
		not finitePoint(first)
		or not finitePoint(last)
		or not finitePoint(minimum)
		or not finitePoint(maximum)
		or minimum.x > maximum.x
		or minimum.y > maximum.y
		or minimum.z > maximum.z
	then
		return false
	end
	local enter, leave = clip(first.x, last.x, minimum.x, maximum.x, 0, 1)
	enter, leave = clip(first.y, last.y, minimum.y, maximum.y, enter, leave)
	enter, leave = clip(first.z, last.z, minimum.z, maximum.z, enter, leave)
	return enter <= leave
end

local function distanceSquared(first, last, pose)
	local x, y, z = last.x - first.x, last.y - first.y, last.z - first.z
	local length = x * x + y * y + z * z
	local along = 0.0
	if length > 0 then
		along = values.clamp(
			((pose[13] - first.x) * x + (pose[14] - first.y) * y + (pose[15] - first.z) * z) / length,
			0,
			1
		)
	end
	x, y, z = first.x + x * along - pose[13], first.y + y * along - pose[14], first.z + z * along - pose[15]
	return x * x + y * y + z * z
end

local function cameraAt(metadata, first, last)
	if #metadata.positions ~= metadata.count or not finitePoint(first) or not finitePoint(last) then
		return nil, false
	end
	local found = nil
	for _, camera in ipairs(metadata.positions) do
		if distanceSquared(first, last, camera.pose) <= CAMERA_MATCH_DISTANCE * CAMERA_MATCH_DISTANCE then
			if found ~= nil then
				return nil, true
			end
			found = camera
		end
	end
	return found, found ~= nil
end

local module = {
	read = read,
	finitePoint = finitePoint,
	localEye = localEye,
	contains = contains,
	cameraAt = cameraAt,
}
return module
