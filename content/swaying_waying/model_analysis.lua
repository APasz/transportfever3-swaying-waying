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
local pairs = _tl_compat and _tl_compat.pairs or pairs
local table = _tl_compat and _tl_compat.table or table
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
local dynamicTable = validation.asTable
local validWheelbase = validation.wheelbase

local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua")

local MAX_NODE_DEPTH = constants.MAX_MODEL_NODE_DEPTH

local function visit(node, parent, index, names, placements)
	assert(not index.seen[node], "Model hierarchy reuses a node in multiple positions")
	index.seen[node] = true
	index.parents[node] = parent
	local name = nodes.name(node, "")
	local entries = index.names[name]
	if entries == nil then
		entries = {}
		index.names[name] = entries
	end
	entries[#entries + 1] = node
	local hasAxle = names[name] == true
	local swayable = not hasAxle and nodes.hasContent(node)
	local rigid = not hasAxle and node.skin == nil and node.skinMaterials == nil
	local hasContent = nodes.hasContent(node)
	if node.children ~= nil then
		for _, child in ipairs(node.children) do
			visit(child, node, index, names, placements)
			hasAxle = hasAxle or index.axles[child] == true
			swayable = swayable or index.swayable[child] == true
			rigid = rigid and index.rigid[child] == true and not placements[nodes.name(child, "")]
			hasContent = true
		end
	end
	if hasAxle then
		index.axles[node] = true
	end
	if not names[name] and swayable then
		index.swayable[node] = true
	end
	if rigid and not hasAxle and hasContent then
		index.rigid[node] = true
	end
end

local function build(lods, names, placements)
	local result = {}
	for _, value in ipairs(lods) do
		local lod = dynamicTable(value)
		local root = lod ~= nil and nodes.get((lod).node) or nil
		if root ~= nil then
			local index = { names = {}, parents = {}, axles = {}, swayable = {}, rigid = {}, seen = {} }
			visit(root, nil, index, names, placements)
			result[root] = index
		end
	end
	return result
end

local function countNamed(root, name, indices)
	local entries = indices[root].names[name]
	return entries ~= nil and #entries or 0
end

local function validateSectionGroups(fileName, roots, sections, warn, indices)
	for lodIndex, root in ipairs(roots) do
		local groups = {}
		for _, section in ipairs(sections) do
			groups[authoring.group(section, lodIndex - 1)] = section.index
		end
		local index = indices[root]
		for _, section in ipairs(sections) do
			local group = authoring.group(section, lodIndex - 1)
			local entries = index.names[group]
			if entries == nil or #entries ~= 1 then
				if warn then
					logger.warnOnce(
						"author-section-group:" .. fileName .. ":" .. group,
						"Skipping sway for "
							.. fileName
							.. ": swayingWaying.sections["
							.. section.index
							.. "] group '"
							.. group
							.. "' must occur exactly once in LOD "
							.. (lodIndex - 1)
							.. " (found "
							.. (entries ~= nil and #entries or 0)
							.. ")"
					)
				end
				return false
			end
			local parent = index.parents[entries[1]]
			while parent ~= nil do
				local parentName = nodes.name(parent, "")
				if groups[parentName] ~= nil then
					if warn then
						logger.warnOnce(
							"author-section-overlap:" .. fileName,
							"Skipping sway for "
								.. fileName
								.. ": swayingWaying.sections["
								.. section.index
								.. "] group '"
								.. group
								.. "' is inside section "
								.. groups[parentName]
								.. " group '"
								.. parentName
								.. "' in LOD "
								.. (lodIndex - 1)
						)
					end
					return false
				end
				parent = index.parents[parent]
			end
		end
	end
	return true
end

local function activeLodRoots(fileName, lods, activeCount)
	local roots = {}
	for lodIndex = 1, activeCount do
		local lod = dynamicTable(lods[lodIndex])
		local root = lod ~= nil and nodes.get((lod).node) or nil
		if root == nil then
			logger.warnOnce(
				"missing-root:" .. fileName,
				"Cannot add sway to model without usable LOD root nodes: " .. fileName
			)

			return nil
		end
		roots[lodIndex] = root
	end
	return roots
end

local function collectBodyTargets(node, names, axleBranches, targets, isRoot, depth)
	if depth > MAX_NODE_DEPTH then
		return
	end
	local nodeName = nodes.name(node, "")
	if names[nodeName] then
		return
	end

	local children = node.children
	if children == nil then
		return
	end
	local hasAxleBranch = false
	local hasFreeBranch = nodes.hasContent(node)
	for _, child in ipairs(children) do
		if axleBranches[child] == true then
			hasAxleBranch = true
		else
			hasFreeBranch = true
		end
	end
	if
		not isRoot
		and not compatibility.isBodyContainer(nodeName)
		and nodeName ~= ""
		and hasAxleBranch
		and hasFreeBranch
	then
		targets[nodeName] = true
		return
	end

	if hasAxleBranch then
		for _, child in ipairs(children) do
			if axleBranches[child] == true then
				collectBodyTargets(child, names, axleBranches, targets, false, depth + 1)
			end
		end
	end
end

local function detectedBodyTargets(root, names, indices)
	local detected = {}
	if next(names) == nil then
		return detected
	end

	local axleBranches = indices[root].axles
	collectBodyTargets(root, names, axleBranches, detected, true, 0)

	return detected
end

local function sameStringSet(left, right)
	for value in pairs(left) do
		if not right[value] then
			return false
		end
	end
	for value in pairs(right) do
		if not left[value] then
			return false
		end
	end
	return true
end

local function collectVisualPlacementTargets(node, placementGroups, axleNodeNames, targets, depth, index)
	if depth > MAX_NODE_DEPTH then
		return
	end
	local nodeName = nodes.name(node, "")
	if not compatibility.isBodyContainer(nodeName) and placementGroups[nodeName] and index.swayable[node] == true then
		targets[nodeName] = true
	end
	local children = node.children
	if children ~= nil then
		for _, child in ipairs(children) do
			collectVisualPlacementTargets(child, placementGroups, axleNodeNames, targets, depth + 1, index)
		end
	end
end

local function placementBodyTargetsByLod(roots, axleNodeNames, placementGroups, indices)
	if #roots == 0 or next(placementGroups) == nil then
		return nil
	end

	local targetsByLod = {}
	for lodIndex, root in ipairs(roots) do
		local targets = {}
		collectVisualPlacementTargets(root, placementGroups, axleNodeNames, targets, 0, indices[root])

		if next(targets) == nil then
			return nil
		end
		if lodIndex > 1 and not sameStringSet(targetsByLod[1], targets) then
			return nil
		end
		for target in pairs(targets) do
			if countNamed(root, target, indices) ~= 1 then
				return nil
			end
		end
		targetsByLod[lodIndex] = targets
	end
	return targetsByLod
end

local function bodyTargetsByLod(roots, names, indices)
	if #roots == 0 then
		return nil
	end
	local primaryTargets = detectedBodyTargets(roots[1], names, indices)
	if next(primaryTargets) == nil then
		return nil
	end

	local targetsByLod = {}
	for lodIndex, root in ipairs(roots) do
		local targets = {}
		for target in pairs(primaryTargets) do
			if countNamed(root, target, indices) == 1 then
				targets[target] = true
			end
		end
		if lodIndex > 1 then
			for target in pairs(detectedBodyTargets(root, names, indices)) do
				targets[target] = true
			end
		end
		if next(targets) == nil then
			return nil
		end
		targetsByLod[lodIndex] = targets
	end
	return targetsByLod
end

local function automaticSections(fileName, roots, targets, placement, indices)
	if #roots == 0 or next(targets) == nil then
		return nil
	end

	local supports = {}
	for group in pairs(targets) do
		local extent = placement.extents[group]
		if extent == nil then
			return nil
		end
		local present = extent
		local span = present.maximum - present.minimum
		if present.count < 2 or not validWheelbase(span) then
			return nil
		end
		supports[#supports + 1] = {
			group = group,
			center = (present.minimum + present.maximum) * 0.5,
		}
	end
	if #supports < 2 or #supports > constants.MAX_SECTION_COUNT then
		return nil
	end

	table.sort(supports, function(left, right)
		if left.center == right.center then
			return left.group < right.group
		end
		return left.center > right.center
	end)
	for index = 2, #supports do
		if supports[index - 1].center - supports[index].center < constants.MIN_WHEELBASE then
			return nil
		end
	end
	local leadCenter = supports[1].center
	local sections = {}
	for index, support in ipairs(supports) do
		sections[index] = {
			group = support.group,
			axes = "model",
			lag = math.max(0.0, leadCenter - support.center),
			wheelbase = nil,
			index = index,
		}
	end
	if not validateSectionGroups(fileName, roots, sections, false, indices) then
		return nil
	end
	return sections
end

local module = {
	index = build,
	activeRoots = activeLodRoots,
	validateSections = validateSectionGroups,
	placementTargets = placementBodyTargetsByLod,
	bodyTargets = bodyTargetsByLod,
	sections = automaticSections,
}
return module
