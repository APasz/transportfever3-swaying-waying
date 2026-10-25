local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local math = _tl_compat and _tl_compat.math or math
local pairs = _tl_compat and _tl_compat.pairs or pairs
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local vehicleResponse = ug_require("apasz_swaying_waying::/swaying_waying/vehicle_response.lua")
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local dynamicTable = validation.asTable
local dynamicArray = validation.asArray
local validLodDistance = validation.nonnegative
local positiveInteger = validation.positiveInteger

local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua")

local DEFAULT_PIVOT_HEIGHT = 0.85

local MIN_PIVOT_HEIGHT = 0.45

local MAX_PIVOT_HEIGHT = 1.25

local PIVOT_HEIGHT_RATIO = 0.2

local MIN_SWAY_CUTOFF_DISTANCE = 350.0

local SWAY_CUTOFF_DISTANCE = 500.0

local FALLBACK_ACTIVE_LOD_COUNT = 2

local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH

local function carrierOf(metadata)
	local authoredCarrier = nil
	local transportCandidate = dynamicTable(metadata.transportVehicle)
	if transportCandidate ~= nil then
		authoredCarrier = (transportCandidate).carrier
	end
	if type(metadata.railVehicle) == "table" then
		if authoredCarrier == "TRAM" then
			return "TRAM"
		end
		return "RAIL"
	end
	if authoredCarrier == "RAIL" or authoredCarrier == "TRAM" then
		return authoredCarrier
	end
	return nil
end

local function containsPassenger(values)
	local entries = dynamicArray(values)
	if entries == nil then
		return false
	end
	for _, entry in ipairs(entries) do
		if entry == "PASSENGERS" then
			return true
		end
	end
	return false
end

local function carriesPassengers(transportVehicle)
	local compartments = dynamicArray(transportVehicle.compartments) or dynamicArray(transportVehicle.compartmentsList)
	if compartments == nil then
		return false
	end
	for _, compartmentValue in ipairs(compartments) do
		local compartment = dynamicTable(compartmentValue)
		local loadConfigs = compartment ~= nil and dynamicArray((compartment).loadConfigs) or nil
		if loadConfigs ~= nil then
			for _, loadConfigValue in ipairs(loadConfigs) do
				local loadConfig = dynamicTable(loadConfigValue)
				local cargoEntry = loadConfig ~= nil and dynamicTable((loadConfig).cargoEntry) or nil
				local cargoTypeSet = cargoEntry ~= nil and dynamicTable((cargoEntry).cargoTypeSet) or nil
				if
					cargoTypeSet ~= nil
					and (
						containsPassenger((cargoTypeSet).cargoClassesIncluded)
						or containsPassenger((cargoTypeSet).cargoTypesIncluded)
					)
				then
					return true
				end
			end
		end
	end
	return false
end

local function vehicleTags(transportVehicle)
	local result = {
		none = false,
		onlyCamera = false,
		noCamera = false,
		rougher = false,
		smoother = false,
		quick = false,
		slow = false,
	}
	local tags = dynamicArray(transportVehicle.filterTags)
	if tags == nil then
		return result
	end
	for _, value in ipairs(tags) do
		if value == constants.NONE_TAG then
			result.none = true
		elseif value == constants.ONLY_CAMERA_TAG then
			result.onlyCamera = true
		elseif value == constants.NO_CAMERA_TAG then
			result.noCamera = true
		elseif value == constants.ROUGHER_TAG then
			result.rougher = true
		elseif value == constants.SMOOTHER_TAG then
			result.smoother = true
		elseif value == constants.QUICK_TAG then
			result.quick = true
		elseif value == constants.SLOW_TAG then
			result.slow = true
		end
	end
	return result
end

local function authoredVehicleFactor(fileName, tags)
	if tags.rougher and tags.smoother then
		logger.warnOnce(
			"vehicle-response-conflict:" .. fileName,
			"Ignoring conflicting swaying_waying_rougher and " .. "swaying_waying_smoother tags on " .. fileName
		)

		return 1.0
	elseif tags.rougher then
		return constants.ROUGH_FACTOR
	elseif tags.smoother then
		return constants.SMOOTH_FACTOR
	end
	return 1.0
end

local function authoredMotionProfile(fileName, tags)
	if tags.quick and tags.slow then
		logger.warnOnce(
			"vehicle-profile-conflict:" .. fileName,
			"Ignoring conflicting swaying_waying_quick and " .. "swaying_waying_slow tags on " .. fileName
		)

		return "DEFAULT"
	elseif tags.quick then
		return "QUICK"
	elseif tags.slow then
		return "SLOW"
	end
	return "DEFAULT"
end

local function vehicleMotionSettings(fileName, metadata, vehicleVariation)
	local transportVehicle = dynamicTable(metadata.transportVehicle)
	if transportVehicle == nil then
		return {
			swayEnabled = true,
			cameraEnabled = true,
			swayFactor = 1.0,
			profile = "DEFAULT",
		}
	end
	local presentTransportVehicle = transportVehicle
	local tags = vehicleTags(presentTransportVehicle)
	if tags.none then
		return nil
	end
	if tags.onlyCamera then
		return { swayEnabled = false, cameraEnabled = not tags.noCamera, swayFactor = 1.0, profile = "DEFAULT" }
	end
	local automaticFactor = 1.0
	if vehicleVariation > 0.0 then
		automaticFactor = vehicleResponse.comfortFactor(
			presentTransportVehicle.comfortFactor,
			carriesPassengers(presentTransportVehicle)
		)

		if vehicleVariation ~= 1.0 then
			automaticFactor = vehicleResponse.scaleFromNeutral(automaticFactor, vehicleVariation)
		end
	end
	return {
		swayEnabled = true,
		cameraEnabled = not tags.noCamera,
		swayFactor = automaticFactor * authoredVehicleFactor(fileName, tags),
		profile = authoredMotionProfile(fileName, tags),
	}
end

local function referencesAnimationFile(value, fileName)
	local animation = dynamicTable(value)
	local params = animation ~= nil and dynamicTable((animation).params) or nil
	return params ~= nil and (params).id == fileName
end

local function collectAuthoredSwayChannels(value, channels, depth)
	if channels.sway and channels.tenderSway then
		return
	end
	local candidate = dynamicTable(value)
	if candidate == nil or depth > MAX_NODE_DEPTH then
		return
	end
	local node = candidate
	local animations = dynamicTable(node.animations)
	if animations ~= nil then
		local present = animations
		channels.sway = channels.sway
			or referencesAnimationFile(present[constants.AUTHORED_SWAY_ANIMATION], constants.BASE_TILT_ANIMATION)

		channels.tenderSway = channels.tenderSway
			or referencesAnimationFile(present[constants.AUTHORED_TENDER_SWAY_ANIMATION], constants.BASE_TILT_ANIMATION)
	end
	local children = node.children
	if children ~= nil then
		for _, child in ipairs(children) do
			collectAuthoredSwayChannels(child, channels, depth + 1)
			if channels.sway and channels.tenderSway then
				break
			end
		end
	end
end

local function activeLodCount(lods, transformatorConfig)
	if transformatorConfig == nil then
		return #lods
	end
	local skipFromLod = positiveInteger((transformatorConfig).skipFromLod)

	if skipFromLod == nil then
		return #lods
	end
	return math.min(#lods, skipFromLod)
end

local function distanceLodCount(fileName, lods)
	local closestCount = #lods
	local closestDifference = math.huge
	local previousEnd = 0.0
	for lodIndex, lodValue in ipairs(lods) do
		local lod = dynamicTable(lodValue)
		local visibleTo = nil
		if lod ~= nil then
			visibleTo = (lod).visibleTo
		end
		if visibleTo == nil then
			logger.debug(
				"Using legacy sway LOD selection on " .. fileName .. ": missing visibleTo for LOD " .. (lodIndex - 1)
			)

			return nil
		end
		if not validLodDistance(visibleTo) or visibleTo < previousEnd then
			logger.warnOnce(
				"lod-distance:" .. fileName,
				"Using legacy sway LOD selection on "
					.. fileName
					.. ": invalid or unordered visibleTo for LOD "
					.. (lodIndex - 1)
			)

			return nil
		end
		local distance = visibleTo
		local difference = math.abs(distance - SWAY_CUTOFF_DISTANCE)
		if distance >= MIN_SWAY_CUTOFF_DISTANCE and difference < closestDifference then
			closestCount = lodIndex
			closestDifference = difference
		end
		previousEnd = distance
	end
	return closestCount
end

local function injectionLodCount(fileName, lods, transformatorConfig, options, originalTransformator)
	if options.skipFromLod ~= nil then
		local authored = options.skipFromLod
		local inherited = activeLodCount(lods, transformatorConfig)
		return authored, math.max(authored, inherited)
	end
	local distanceCount = distanceLodCount(fileName, lods)
	local defaultCount = distanceCount or math.min(#lods, FALLBACK_ACTIVE_LOD_COUNT)
	if transformatorConfig == nil then
		return defaultCount, nil
	end
	local rawInherited = (transformatorConfig).skipFromLod
	if rawInherited == nil then
		return distanceCount or #lods, distanceCount ~= nil and #lods or nil
	end
	local inherited = positiveInteger(rawInherited)
	if inherited == nil then
		logger.warnOnce("inherited-lod:" .. fileName, "Replacing invalid inherited skipFromLod on " .. fileName)

		return distanceCount or #lods, #lods
	end
	local inheritedCount = math.min(#lods, inherited)
	if distanceCount ~= nil then
		local swayCount = compatibility.isDirect(originalTransformator) and distanceCount
			or math.min(distanceCount, inheritedCount)
		return swayCount, swayCount > inheritedCount and swayCount or nil
	end
	if inheritedCount < defaultCount and compatibility.isDirect(originalTransformator) then
		return defaultCount, defaultCount
	end
	return inheritedCount, nil
end

local function hasAuthoredSwayAnimations(model, transformatorConfig)
	local lodsCandidate = dynamicArray(model.lods)
	if lodsCandidate == nil then
		return false
	end
	local lods = lodsCandidate
	local activeCount = activeLodCount(lods, transformatorConfig)
	if activeCount == 0 then
		return false
	end
	for lodIndex = 1, activeCount do
		local lod = dynamicTable(lods[lodIndex])
		local root = lod ~= nil and nodes.get((lod).node) or nil
		if root == nil then
			return false
		end
		local channels = {
			sway = false,
			tenderSway = false,
		}
		collectAuthoredSwayChannels(root, channels, 0)
		if not channels.sway or not channels.tenderSway then
			return false
		end
	end
	return true
end

local function modelAxisSignFor(lods)
	for _, lodValue in ipairs(lods) do
		local lod = dynamicTable(lodValue)
		local root = lod ~= nil and nodes.get((lod).node) or nil
		if root ~= nil then
			return nodes.transform(root)[1] < 0 and -1.0 or 1.0
		end
	end
	return 1.0
end

local function boundsFrom(value)
	local candidate = dynamicTable(value)
	if candidate == nil then
		return nil, nil
	end
	local bounds = candidate
	return dynamicArray(bounds.bbMin), dynamicArray(bounds.bbMax)
end

local function pivotHeight(model)
	local minimum = nil
	local maximum = nil
	local metadataCandidate = dynamicTable(model.metadata)
	if metadataCandidate ~= nil then
		local extent = (metadataCandidate).extent
		minimum, maximum = boundsFrom(extent)
	end
	if minimum == nil or maximum == nil then
		minimum, maximum = boundsFrom(model.boundingInfo)
	end
	if minimum == nil or maximum == nil then
		return DEFAULT_PIVOT_HEIGHT
	end
	local minZ = tonumber((minimum)[3])
	local maxZ = tonumber((maximum)[3])
	if minZ == nil or maxZ == nil or maxZ <= minZ then
		return DEFAULT_PIVOT_HEIGHT
	end
	return math.max(MIN_PIVOT_HEIGHT, math.min(MAX_PIVOT_HEIGHT, minZ + (maxZ - minZ) * PIVOT_HEIGHT_RATIO))
end

local function longitudinalLength(model)
	local minimum = nil
	local maximum = nil
	local metadata = dynamicTable(model.metadata)
	if metadata ~= nil then
		minimum, maximum = boundsFrom((metadata).extent)
	end
	if minimum == nil or maximum == nil then
		minimum, maximum = boundsFrom(model.boundingInfo)
	end
	if minimum == nil or maximum == nil then
		return nil
	end
	local minX = tonumber((minimum)[1])
	local maxX = tonumber((maximum)[1])
	if
		minX == nil
		or maxX == nil
		or minX ~= minX
		or maxX ~= maxX
		or minX <= -math.huge
		or maxX >= math.huge
		or maxX <= minX
	then
		return nil
	end
	return maxX - minX
end

local function railVehicleConfig(metadata)
	local railVehicle = dynamicTable(metadata.railVehicle)
	if railVehicle == nil then
		return nil
	end
	return dynamicTable((railVehicle).config)
end

local function vehiclePlacementData(bindings)
	local result = { groups = {}, extents = {} }
	for _, binding in ipairs(bindings) do
		if binding.kind == "placement" then
			local group = binding.target
			result.groups[group] = true
			local position = binding.owner.position
			if type(position) == "number" and position > -math.huge and position < math.huge then
				local extent = result.extents[group]
				if extent == nil then
					result.extents[group] = { minimum = position, maximum = position, count = 1 }
				else
					local present = extent
					present.minimum = math.min(present.minimum, position)
					present.maximum = math.max(present.maximum, position)
					present.count = present.count + 1
				end
			end
		end
	end
	return result
end

local function extentWheelbase(extent)
	if extent == nil then
		return nil
	end
	local present = extent
	local span = present.maximum - present.minimum
	if present.count < 2 or span < constants.MIN_WHEELBASE then
		return nil
	end
	return math.min(span, constants.MAX_WHEELBASE)
end

local function inferredWheelbase(model, placement, group)
	if group ~= nil then
		local grouped = extentWheelbase(placement.extents[group])
		if grouped ~= nil then
			return grouped
		end
	else
		local representative = 0.0
		for _, extent in pairs(placement.extents) do
			local wheelbase = extentWheelbase(extent)
			if wheelbase ~= nil then
				representative = math.max(representative, wheelbase)
			end
		end
		if representative > 0.0 then
			return representative
		end
	end

	local length = longitudinalLength(model)
	if length == nil then
		return constants.DEFAULT_WHEELBASE
	end
	return math.max(constants.MIN_WHEELBASE, math.min(constants.MAX_WHEELBASE, length * 0.65))
end

local function axleNames(metadata)
	local names = {}
	local config = railVehicleConfig(metadata)
	if config == nil then
		return names
	end
	local axles = dynamicArray((config).axles)
	if axles ~= nil then
		for _, name in ipairs(axles) do
			if type(name) == "string" then
				names[name] = true
			end
		end
	end
	return names
end

local module = {
	options = authoring.options,
	carrier = carrierOf,
	vehicleSettings = vehicleMotionSettings,
	lodCount = injectionLodCount,
	authoredSway = hasAuthoredSwayAnimations,
	axisSign = modelAxisSignFor,
	pivot = pivotHeight,
	wheelbase = inferredWheelbase,
	placement = vehiclePlacementData,
	axles = axleNames,
	referencesAnimationFile = referencesAnimationFile,
}
return module
