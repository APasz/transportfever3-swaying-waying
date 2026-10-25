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
local string = _tl_compat and _tl_compat.string or string
local table = _tl_compat and _tl_compat.table or table
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua")
local dynamicTable = validation.asTable
local validLodDistance = validation.nonnegative
local referencesAnimationFile = policy.referencesAnimationFile

local MOTION_NODE_PREFIX = constants.SWAY_NODE .. "_"

local MOTION_NODE_ANIMATION_FILES = {
	[constants.SWAY_ANIMATION] = constants.BASE_TILT_ANIMATION,
	[constants.HEAVE_ANIMATION] = constants.HEAVE_ANIMATION_FILE,
}
for index = 1, constants.MAX_SECTION_COUNT do
	MOTION_NODE_ANIMATION_FILES[constants.SWAY_SECTION_ANIMATION_PREFIX .. index] = constants.BASE_TILT_ANIMATION
	MOTION_NODE_ANIMATION_FILES[constants.HEAVE_SECTION_ANIMATION_PREFIX .. index] = constants.HEAVE_ANIMATION_FILE
end

local function hasMotionAnimation(node)
	local animations = dynamicTable(node.animations)
	if animations == nil then
		return false
	end
	for name, value in pairs(animations) do
		if type(name) == "string" then
			local fileName = MOTION_NODE_ANIMATION_FILES[name]
			local animation = dynamicTable(value)
			if
				fileName ~= nil
				and animation ~= nil
				and (animation).type == "FILE_REF"
				and referencesAnimationFile(animation, fileName)
			then
				return true
			end
		end
	end
	return false
end

local function collectLodMotion(node, diagnostics, report, moving, seen)
	if seen[node] then
		return
	end
	seen[node] = true
	local nodeName = nodes.name(node, "")
	if
		(nodeName == constants.SWAY_NODE or nodeName:sub(1, #MOTION_NODE_PREFIX) == MOTION_NODE_PREFIX)
		and hasMotionAnimation(node)
	then
		report.motionNodes[#report.motionNodes + 1] = nodeName
		moving = true
	end
	if report.excludedAxleGroups ~= nil and not moving then
		if diagnostics.axleNames[nodeName] then
			(report.excludedAxleGroups)[nodeName] = true
		end
		if
			diagnostics.placementGroups[nodeName]
			and (report.bodyGroups == nil or not (report.bodyGroups)[nodeName])
		then
			(report.excludedPlacementGroups)[nodeName] = true
		end
	end
	local hasVisual = node.mesh ~= nil or node.skin ~= nil or node.meshes ~= nil
	if hasVisual then
		report.visuals = report.visuals + 1
		if moving then
			report.movingVisuals = report.movingVisuals + 1
		end
	end
	local children = node.children
	if children ~= nil then
		for _, child in ipairs(children) do
			collectLodMotion(child, diagnostics, report, moving, seen)
		end
	end
end

local function formatGroupNames(groups)
	if groups == nil then
		return "[]"
	end
	local names = {}
	for name in pairs(groups) do
		names[#names + 1] = name
	end
	table.sort(names)
	return "[" .. table.concat(names, ", ") .. "]"
end

local function formatLodDistance(value)
	if value == nil then
		return "unspecified"
	end
	if not validLodDistance(value) then
		return "invalid (" .. tostring(value) .. ")"
	end
	return tostring(value) .. " m"
end

local function lodVisibility(lodValue)
	local lod = dynamicTable(lodValue)
	local visibleFrom = nil
	local visibleTo = nil
	if lod ~= nil then
		visibleFrom = (lod).visibleFrom
		visibleTo = (lod).visibleTo
	end
	return "; visibleFrom=" .. formatLodDistance(visibleFrom) .. "; visibleTo=" .. formatLodDistance(visibleTo)
end

local function create(logger, detailed)
	local function logAppliedModel(diagnostics, activeCount, lodCount, sectionCount)
		logger.info(
			diagnostics.fileName
				.. ": sway applied; active LODs="
				.. activeCount
				.. "/"
				.. lodCount
				.. "; sections="
				.. math.max(1, sectionCount)
				.. "; original transformator="
				.. diagnostics.originalTransformator
		)
	end

	local function logInactiveLods(diagnostics, lods, activeCount)
		if not detailed then
			return
		end
		for lodIndex = activeCount + 1, #lods do
			logger.info(
				diagnostics.fileName
					.. " LOD "
					.. (lodIndex - 1)
					.. ": inactive (beyond sway LOD limit)"
					.. lodVisibility(lods[lodIndex])
			)
		end
	end

	local function logActiveLod(diagnostics, lodIndex, lod, root, bodyGroups, wrappedCount, failure)
		if not detailed then
			return
		end
		local report = {
			bodyGroups = bodyGroups,
			motionNodes = {},
			excludedAxleGroups = {},
			excludedPlacementGroups = {},
			visuals = 0,
			movingVisuals = 0,
		}
		if root ~= nil then
			collectLodMotion(root, diagnostics, report, false, {})
		end
		if failure ~= nil then
			report.motionNodes = {}
			report.movingVisuals = 0
		end
		table.sort(report.motionNodes)
		local outcome = wrappedCount > 0 and "applied"
			or "not applied (" .. (failure or "no body groups wrapped") .. ")"
		local summary = diagnostics.fileName
			.. " LOD "
			.. (lodIndex - 1)
			.. ": "
			.. outcome
			.. "; body groups="
			.. wrappedCount
			.. "; motion nodes=["
			.. table.concat(report.motionNodes, ", ")
			.. "]"
			.. "; moving visuals="
			.. report.movingVisuals
			.. "/"
			.. report.visuals
			.. lodVisibility(lod)
		logger.info(
			summary
				.. "; original transformator="
				.. diagnostics.originalTransformator
				.. "; detected body groups="
				.. formatGroupNames(report.bodyGroups)
				.. "; excluded axle groups="
				.. formatGroupNames(report.excludedAxleGroups)
				.. "; excluded placement groups="
				.. formatGroupNames(report.excludedPlacementGroups)
		)
	end

	local function logSkippedActiveLods(diagnostics, lods, activeCount, failure)
		logger.info(diagnostics.fileName .. ": sway not applied (" .. failure .. ")")
		if not detailed then
			return
		end
		for lodIndex = 1, activeCount do
			local lod = dynamicTable(lods[lodIndex])
			local root = lod ~= nil and nodes.get((lod).node) or nil
			logActiveLod(diagnostics, lodIndex, lods[lodIndex], root, nil, 0, failure)
		end
		logInactiveLods(diagnostics, lods, activeCount)
	end

	return {
		applied = logAppliedModel,
		active = logActiveLod,
		inactive = logInactiveLods,
		skipped = logSkippedActiveLods,
	}
end
local module = { create = create }
return module
