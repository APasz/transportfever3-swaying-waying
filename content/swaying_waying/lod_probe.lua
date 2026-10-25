local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pairs = _tl_compat and _tl_compat.pairs or pairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local string = _tl_compat and _tl_compat.string or string
local table = _tl_compat and _tl_compat.table or table
local enabled = ug_require("apasz_swaying_waying::/swaying_waying/lod_probe_config.lua")
assert(type(enabled) == "boolean", "Invalid LOD probe switch")
local module = {}
if not enabled then
	return module
end

local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local MAX_SAMPLES = 48
local CALLBACK_INTERVAL = 64
local context = tostring({})
local selectedCarriage = nil
local callbacks = 0
local samples = 0

local function describeKeys(value)
	local keys = {}
	for key, item in pairs(value) do
		local description = type(item)
		if type(item) == "number" or type(item) == "boolean" then
			description = tostring(item)
		end
		keys[#keys + 1] = tostring(key) .. ":" .. description
	end
	table.sort(keys)
	return "[" .. table.concat(keys, ",") .. "]"
end

local function keyInventory(value)
	local succeeded, result = pcall(describeKeys, value)
	return succeeded and result or "unavailable"
end

local function userTransformInfo(output)
	local transforms = output:getUserTransfs()
	local counts = {}
	for _, transform in ipairs(transforms) do
		counts[transform.type] = (counts[transform.type] or 0) + 1
	end
	local kinds = {}
	for kind in pairs(counts) do
		kinds[#kinds + 1] = kind
	end
	table.sort(kinds)
	local descriptions = {}
	for _, kind in ipairs(kinds) do
		descriptions[#descriptions + 1] = kind .. ":" .. counts[kind]
	end
	return string.format("%d[%s]", #transforms, table.concat(descriptions, ","))
end

local function animationInfo(output)
	local names = {}
	for _, state in ipairs(output:getAnimationStates()) do
		names[#names + 1] = state.animation
	end
	table.sort(names)
	return "[" .. table.concat(names, ",") .. "]"
end

local function observe(params, output, modelFile)
	if samples >= MAX_SAMPLES then
		return false
	end
	local current, staticInfo = params.currentInfo, params.vehicleStaticInfo
	if current == nil or current.vehicle == nil or staticInfo == nil then
		return false
	end
	if selectedCarriage == nil then
		if current.vehicle.positionInCarriageList ~= 0 then
			return false
		end
		selectedCarriage = staticInfo.carriageEntity
		logger.info(
			string.format(
				"LOD probe begin: context=%s vehicle=%d carriage=%d model=%s maxSamples=%d callbackInterval=%d",
				context,
				params.entityId,
				staticInfo.carriageEntity,
				modelFile,
				MAX_SAMPLES,
				CALLBACK_INTERVAL
			)
		)

		logger.info(
			string.format(
				"LOD probe inventory: context=%s params=%s current=%s world=%s static=%s modelInfo=%s metadata=%s",
				context,
				keyInventory(params),
				keyInventory(current),
				keyInventory(current.world),
				keyInventory(staticInfo),
				keyInventory(staticInfo.modelInfo),
				keyInventory(params.modelMetadataInfo)
			)
		)
	end
	if staticInfo.carriageEntity ~= selectedCarriage then
		return false
	end
	callbacks = callbacks + 1

	if (callbacks - 1) % CALLBACK_INTERVAL ~= 0 then
		return false
	end
	local haveTransforms, transforms = pcall(userTransformInfo, output)
	local haveAnimations, animations = pcall(animationInfo, output)
	if not haveTransforms then
		logger.warnOnce(
			"lod-probe-transforms-failed",
			"LOD probe could not inspect native transforms for " .. modelFile .. ": " .. tostring(transforms)
		)
	end
	if not haveAnimations then
		logger.warnOnce(
			"lod-probe-animations-failed",
			"LOD probe could not inspect native animations for " .. modelFile .. ": " .. tostring(animations)
		)
	end
	samples = samples + 1
	logger.info(
		string.format(
			"LOD probe sample: context=%s vehicle=%d carriage=%d model=%s sample=%d callback=%d time=%d transforms=%s nativeAnimations=%s params=%s current=%s world=%s",
			context,
			params.entityId,
			staticInfo.carriageEntity,
			modelFile,
			samples,
			callbacks,
			current.world.gameTime,
			haveTransforms and transforms or "unavailable",
			haveAnimations and animations or "unavailable",
			keyInventory(params),
			keyInventory(current),
			keyInventory(current.world)
		)
	)

	if samples == MAX_SAMPLES then
		logger.info(
			string.format(
				"LOD probe complete: context=%s carriage=%d samples=%d",
				context,
				staticInfo.carriageEntity,
				samples
			)
		)
	end
	return true
end

module.observe = observe
return module
