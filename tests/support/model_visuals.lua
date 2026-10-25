local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local function visualSnapshot(model)
	local lods = {}
	for index, lod in ipairs(model.lods) do
		local visuals = {}
		local function visit(node, parent)
			local world = nodes.multiply(parent, nodes.transform(node))
			local mesh = node.mesh or node.meshes
			if mesh ~= nil or node.skin ~= nil then
				visuals[#visuals + 1] = {
					mesh = mesh,
					materials = node.materials,
					skin = node.skin,
					skinMaterials = node.skinMaterials,
					world = world,
				}
			end
			for _, child in ipairs(node.children or {}) do
				visit(child, world)
			end
		end
		visit(lod.node, nodes.identity(0))
		lods[index] = visuals
	end
	return lods
end

local function sameVisual(left, right)
	if
		left.mesh ~= right.mesh
		or left.materials ~= right.materials
		or left.skin ~= right.skin
		or left.skinMaterials ~= right.skinMaterials
	then
		return false
	end
	for component = 1, 16 do
		local a, b = left.world[component], right.world[component]
		if math.abs(a - b) > 1e-7 * (1 + math.abs(a) + math.abs(b)) then
			return false
		end
	end
	return true
end

local function validateRestPose(before, after, resource)
	assert(#before == #after, "LOD count changed: " .. resource)
	for index, originals in ipairs(before) do
		local prepared = after[index]
		assert(#originals == #prepared, "Visual content count changed: " .. resource)
		local matched = {}
		for _, original in ipairs(originals) do
			local found = false
			for candidate, visual in ipairs(prepared) do
				if not matched[candidate] and sameVisual(original, visual) then
					matched[candidate], found = true, true
					break
				end
			end
			assert(found, "Rest geometry or materials changed in LOD " .. (index - 1) .. ": " .. resource)
		end
	end
end

return { snapshot = visualSnapshot, validate = validateRestPose }
