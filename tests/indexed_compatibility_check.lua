local fixture = dofile("tests/support/model_fixture.lua")
local function flattened(root)
	local result = {}
	local function visit(node)
		result[#result + 1] = node
		for _, child in ipairs(node.children or {}) do
			visit(child)
		end
	end
	visit(root)
	return result
end

for _, options in ipairs({
	{ swayEnabled = true, cameraMode = "Disabled" },
	{ swayEnabled = true, cameraMode = "Both" },
	{ swayEnabled = false, cameraMode = "Stable" },
}) do
	local env = dofile("tests/support/model_environment.lua").new()
	local builderCalls = 0
	env.overrides["PRR_B6sab_1::/scripts/valvegear_util.lua"] = {
		buildLodTables = function(lods, names, count)
			builderCalls = builderCalls + 1
			assert(names.radiusRodL == "RadiusRodL" and count == 1, "the author's builder receives captured part names")
			local tree = flattened(lods[1].node)
			local parts = {}
			for index, node in ipairs(tree) do
				if node.name == names.radiusRodL then
					parts.radiusRodL = { index = index - 1 }
				end
			end
			return { { count = #tree, parts = parts } }
		end,
	}
	local modifier = env.require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
	local compatibility = env.require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
	local model = fixture.railModel("PRR_B6sab_1::/vehicle.trf")
	model.lods[1].node.children = { { name = "RadiusRodL", transf = fixture.identity(), mesh = "rod.msh" } }
	model.metadata.cameraConfig = nil
	model.metadata.seats = { { crew = true, group = "RootNode", animation = "driving", transf = fixture.identity() } }
	local geometry = { retained = true }
	model.metadata.transformatorConfig.params.valveGear = {
		lods = { { count = 2, parts = { radiusRodL = { index = 1 } } } },
		geo = geometry,
	}
	local file = "PRR_B6sab_1::/locomotive.mdl"
	modifier.modify(file, model, { intensity = 1 }, false, options)
	local gear = model.metadata.transformatorConfig.params.valveGear
	local tree = flattened(model.lods[1].node)
	assert(gear.lods[1].count == #tree and #tree > 2, "hierarchy changes refresh native part counts")
	assert(
		tree[gear.lods[1].parts.radiusRodL.index + 1].name == "RadiusRodL",
		"scripted part indices retain their targets"
	)
	assert(
		gear.geo == geometry and builderCalls == 1,
		"refresh retains solver geometry and delegates to the author API"
	)
	assert(#env.warnings == 0, table.concat(env.warnings, "\n"))
	compatibility.validate(file, model)
	gear.lods[1].count = 2
	assert(not pcall(compatibility.validate, file, model), "offline checking detects stale cached part counts")
end

for _, invalid in ipairs({
	{ value = false, message = "Invalid PRR valve-gear configuration" },
	{ value = { lods = false }, message = "Invalid PRR valve-gear LOD cache" },
	{ value = { lods = { false } }, message = "Invalid PRR valve-gear LOD entry" },
	{
		value = { lods = { { count = 2, parts = { rod = false } } } },
		message = "Invalid PRR valve-gear part cache",
	},
	{
		value = { lods = { { count = 2, parts = { [1] = { index = 1 } } } } },
		message = "Invalid PRR valve-gear part cache",
	},
}) do
	local env = dofile("tests/support/model_environment.lua").new()
	local compatibility = env.require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
	local model = fixture.railModel("PRR_B6sab_1::/vehicle.trf")
	model.metadata.transformatorConfig.params.valveGear = invalid.value
	local succeeded, failure = pcall(compatibility.validate, "PRR_B6sab_1::/invalid.mdl", model)
	assert(
		not succeeded and tostring(failure):find(invalid.message, 1, true),
		"invalid caches get explicit diagnostics"
	)
end

do
	local env = dofile("tests/support/model_environment.lua").new()
	env.overrides["PRR_B6sab_1::/scripts/valvegear_util.lua"] = {
		buildLodTables = function()
			return { { count = 1, parts = {} } }
		end,
	}
	local modifier = env.require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
	local model = fixture.railModel("PRR_B6sab_1::/vehicle.trf")
	model.metadata.transformatorConfig.params.valveGear = {
		lods = { { count = 2, parts = { radiusRodL = { index = 1 } } } },
	}
	local root, children = model.lods[1].node, model.lods[1].node.children
	modifier.modify("PRR_B6sab_1::/broken_adapter.mdl", model, { intensity = 1 })
	assert(root.children == children and #children == 1, "an unsafe adapter leaves the hierarchy unchanged")
	assert(model.metadata.transformatorConfig.params.swayingWaying == nil, "an unsafe adapter cannot install sway")
	assert(#env.warnings == 1, "adapter failures produce a clear model diagnostic")
end
print("Indexed compatibility checks passed")
