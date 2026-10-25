local assertions = dofile("tests/assertions.lua")
local equal, near = assertions.equal, assertions.near
local fixture = dofile("tests/support/model_fixture.lua")
local wagonFixture = dofile("tests/support/wagon_cameras.lua")

local function environment(wagon)
	local env = dofile("tests/support/model_environment.lua").new()
	if wagon then
		env.overrides["dome_wagon_cameras::/camera_logic.lua"] = wagon.logic
		env.overrides["dome_wagon_cameras::/camera_positions.lua"] = wagon.config
		ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua").configure({
			dome_wagon_cameras = {},
		})
	end
	return env,
		ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua"),
		ug_require("apasz_swaying_waying::/swaying_waying/camera_compatibility.lua"),
		ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
end

local function modelWithRoots(renamed)
	local model = fixture.railModel(nil)
	model.metadata.cameraConfig, model.metadata.seats, model.metadata.lightSources = nil, nil, nil
	for i = 1, 3 do
		local transform = fixture.identity()
		transform[1], transform[2], transform[5], transform[6] = 0, 2, -3, 0
		transform[13], transform[14], transform[15] = i, -i, 0.5 * i
		model.lods[i] = {
			node = {
				name = renamed and ("body_lod" .. i) or "RootNode",
				transf = transform,
				mesh = "body.msh",
				children = { { name = "cab", transf = fixture.identity(), mesh = "cab.msh" } },
			},
		}
	end
	local seat = fixture.identity()
	seat[13], seat[15] = 3, 1.5
	model.metadata.seatProvider = { seats = { { crew = true, group = "cab", animation = "driving", transf = seat } } }
	return model
end

local function modify(modifier, model, mode, enabled, fileName)
	modifier.modify(fileName or "tests::/wagon_compatibility.mdl", model, { intensity = 1 }, false, {
		swayEnabled = enabled ~= false,
		cameraMode = mode or "Both",
	})
end

local function poseOf(nodes, root, name)
	local result
	local function visit(node, parent)
		local pose = nodes.multiply(parent, nodes.transform(node))
		if node.name == name then
			assert(not result, "ambiguous anchor " .. name)
			result = pose
		end
		for _, child in ipairs(node.children or {}) do
			visit(child, pose)
		end
	end
	visit(root, fixture.identity())
	return assert(result, "missing anchor " .. name)
end

local function samePose(actual, expected, message)
	for component = 1, 16 do
		near(actual[component], expected[component], 1e-7, message)
	end
end

for _, renamed in ipairs({ false, true }) do
	for _, order in ipairs({ "before", "after" }) do
		for _, mode in ipairs({ "Disabled", "Both" }) do
			for _, enabled in ipairs({ false, true }) do
				if enabled or mode ~= "Disabled" then
					local wagon = wagonFixture.new({ extras = {} })
					local env, modifier, _, nodes = environment(wagon)
					local model = modelWithRoots(renamed)
					local roots, poses = {}, {}
					for i, lod in ipairs(model.lods) do
						roots[i], poses[i] = lod.node, nodes.transform(lod.node)
					end
					if order == "before" then
						wagon.apply("tests::/wagon_compatibility.mdl", model)
					end
					modify(modifier, model, mode, enabled)
					if order == "after" then
						wagon.apply("tests::/wagon_compatibility.mdl", model)
					end
					local positions = model.metadata.cameraConfig.positions
					equal(#positions, mode == "Disabled" and 2 or (enabled and 4 or 3), "both orders retain all views")
					for i, lod in ipairs(model.lods) do
						equal(lod.node.name, "RootNode", "every LOD has a real root camera anchor")
						equal(
							nodes.countNamed(lod.node, "RootNode", 0),
							1,
							"repair does not introduce duplicate anchors"
						)
						assert(
							fixture.descendantNamed(lod.node, roots[i].name) == roots[i],
							"authored root identity survives"
						)
						samePose(
							poseOf(nodes, lod.node, roots[i].name),
							poses[i],
							"rotated/scaled authored root poses survive"
						)
						for _, camera in ipairs(positions) do
							assert(nodes.inverse(nodes.multiply(poseOf(nodes, lod.node, camera.group), camera.transf)))
						end
					end
					local layout = model.metadata.metadata.domeWagonCameras
					local displayed = wagon.logic.camerasFromLayout(layout)
					equal(
						#displayed > 0 and #displayed or #layout.original,
						#positions,
						"overlay matches final cameras"
					)
					modify(modifier, model, mode, enabled)
					equal(#model.metadata.cameraConfig.positions, #positions, "repeated preparation is idempotent")
					equal(#env.warnings, 0, "valid compatibility is quiet: " .. table.concat(env.warnings, "\n"))
				end
			end
		end
	end
end

do
	local wagon = wagonFixture.new({ extras = {} })
	local env, _, adapter, nodes = environment(wagon)
	local model = modelWithRoots(true)
	model.lods[1].node.name = "RootNode"
	local original = model.lods[2].node
	local expected = nodes.transform(original)
	local ready, changed = adapter.prepare("tests::/partial_root.mdl", model, true)
	assert(ready and changed, "missing distant root anchors are repaired")
	samePose(poseOf(nodes, model.lods[2].node, original.name), expected, "rebasing preserves distant geometry")
	equal(model.lods[2].node.children[1], original, "repair retains the original distant tree")
	equal(#env.warnings, 0, "partial LOD repair is quiet")
	model = modelWithRoots(true)
	model.lods[2].node = model.lods[1].node
	assert(adapter.prepare("tests::/shared_root.mdl", model, true))
	equal(model.lods[1].node, model.lods[2].node, "shared roots receive one shared parent")
end

do
	local wagon = wagonFixture.new()
	local _, _, adapter, nodes = environment(wagon)
	local model = modelWithRoots(false)
	local authored = { group = "cab", transf = fixture.identity(), fov = 72, custom = { preserved = true } }
	local config = { positions = { authored }, custom = "keep" }
	model.metadata.cameraConfig = config
	assert(adapter.prepare("tests::/authored_fields.mdl", model, true))
	equal(model.metadata.cameraConfig, config, "configuration identity survives generation")
	equal(config.positions[1], authored, "the complete author camera is retained at its original index")
	equal(authored.group, "cab", "the authored attachment name survives")
	assert(authored.custom.preserved and config.custom == "keep", "unknown author fields survive")
	model = modelWithRoots(true)
	model.lods[2].node.transf, model.lods[3].node.transf = model.lods[1].node.transf, model.lods[1].node.transf
	authored = { transf = fixture.identity(), fov = 72 }
	model.metadata.cameraConfig = { positions = { authored } }
	local expected = nodes.multiply(nodes.transform(model.lods[1].node), authored.transf)
	assert(adapter.prepare("tests::/implicit_camera.mdl", model, false))
	samePose(
		nodes.multiply(nodes.transform(model.lods[1].node), authored.transf),
		expected,
		"implicit cameras keep their frame"
	)
	equal(authored.group, nil, "implicit attachment fields remain implicit")
	model = modelWithRoots(true)
	local shared = model.lods[1].node
	local sharedPose = nodes.transform(shared)
	model.lods[2].node, model.lods[3].node = shared, shared
	model.metadata.cameraConfig = { positions = { { transf = fixture.identity(), fov = 72 } } }
	local ready, changed = adapter.prepare("tests::/shared_implicit_camera.mdl", model, false)
	assert(ready and changed, "shared transformed roots with implicit cameras can be repaired")
	equal(model.lods[1].node, model.lods[3].node, "shared implicit camera roots retain one parent")
	samePose(poseOf(nodes, model.lods[1].node, shared.name), sharedPose, "shared implicit roots keep their world pose")
	ready, changed = adapter.prepare("tests::/shared_implicit_camera.mdl", model, false)
	assert(ready and not changed, "shared implicit root repair is idempotent")
end

local invalidOutputs = {
	missing = function(camera)
		camera.group = "missing"
	end,
	fov = function(camera)
		camera.fov = 180
	end,
	nonfinite = function(camera)
		camera.transf[13] = 0 / 0
	end,
	singular = function(camera)
		camera.transf[1] = 0
	end,
	sparse = function(_, positions)
		positions[3] = positions[1]
	end,
}
for name, invalidate in pairs(invalidOutputs) do
	local wagon = wagonFixture.new({ extras = {} })
	wagon.logic.camerasFromLayout = function()
		local positions = { { group = "RootNode", transf = fixture.identity(), fov = 65 } }
		invalidate(positions[1], positions)
		return positions
	end
	local env, modifier = environment(wagon)
	local model = modelWithRoots(true)
	modify(modifier, model, "Both", true, "tests::/invalid_output_" .. name .. ".mdl")
	equal(#model.metadata.cameraConfig.positions, 2, "invalid foreign cameras do not suppress our safe views")
	assert(model.metadata.transformatorConfig, "invalid foreign cameras do not suppress sway")
	equal(model.lods[1].node.name, "body_lod1", "rejected generation rolls back its root repair")
	equal(model.metadata.metadata.domeWagonCameras, nil, "rejected layouts are not published")
	equal(#env.warnings, 1, "invalid generation is diagnosed once")
end

do
	local wagon = wagonFixture.new({ extras = {} })
	wagon.logic.camerasFromLayout = function()
		return { { group = "cab", transf = fixture.identity(), fov = 65 } }
	end
	local env, modifier = environment(wagon)
	local model = modelWithRoots(false)
	model.lods[3].node.children = {}
	modify(modifier, model)
	assert(model.metadata.transformatorConfig, "a missing distant foreign anchor does not disable sway")
	equal(#model.metadata.cameraConfig.positions, 2, "only independently valid cameras are added")
	assert(env.warnings[1]:find("every LOD", 1, true), "missing distant anchors are diagnosed")
end

do
	local wagon = wagonFixture.new({ extras = {} })
	local env, _, adapter, nodes = environment(wagon)
	local model = modelWithRoots(true)
	model.lods[3].node.name = "RootNode"
	model.lods[2].node.animations = { custom = {} }
	local first, second = model.lods[1].node, model.lods[2].node
	local firstTransform = first.transf
	local ready, changed = adapter.prepare("tests::/unsafe_rebase.mdl", model, false)
	equal(ready, false, "animated root rebasing is rejected explicitly")
	equal(changed, false, "failed root repair reports no committed changes")
	equal(model.lods[1].node, first, "a later repair failure restores earlier root identities")
	equal(first.transf, firstTransform, "a later repair failure restores earlier transforms")
	equal(model.lods[2].node, second, "the animated root is retained")
	equal(nodes.countNamed(first, "RootNode", 0), 0, "failed repair creates no phantom anchor")
	equal(#env.warnings, 1, "unsafe rebasing is diagnosed once")
end

do
	local wagon = wagonFixture.new({ extras = {} })
	wagon.logic.layout = function(metadata)
		metadata.foreignMutation = true
		error("injected generator failure")
	end
	local env, modifier = environment(wagon)
	local model = modelWithRoots(true)
	modify(modifier, model)
	equal(model.metadata.foreignMutation, nil, "failed generators cannot leak mutations")
	equal(#model.metadata.cameraConfig.positions, 2, "safe onboard cameras survive generator failure")
	assert(model.metadata.transformatorConfig, "sway survives generator failure")
	equal(#env.warnings, 1, "generator errors are reported")
end

do
	local wagon = wagonFixture.new({ extras = {} })
	local env, modifier = environment(wagon)
	local model = modelWithRoots(false)
	local layout = wagon.logic.layout(model.metadata)
	layout.defaults = false
	layout.extra = setmetatable({}, {
		__newindex = function()
			error("injected overlay failure")
		end,
	})
	model.metadata.metadata.domeWagonCameras = layout
	modify(modifier, model)
	equal(#model.metadata.cameraConfig.positions, 2, "overlay failures retain working onboard cameras")
	assert(model.metadata.transformatorConfig, "overlay failures retain sway")
	equal(#layout.extra, 0, "failed overlay writes are rolled back")
	equal(layout.rests.swaying_waying_camera_stable_1, nil, "failed overlay writes leave no partial rest data")
	equal(#env.warnings, 1, "overlay errors are reported once")
end

do
	local wagon = wagonFixture.new()
	wagon.logic.normalizeList = nil
	local env, modifier = environment(wagon)
	for i = 1, 2 do
		local model = modelWithRoots(false)
		modify(modifier, model, "Both", true, "tests::/changed_api_" .. i .. ".mdl")
		assert(model.metadata.transformatorConfig and #model.metadata.cameraConfig.positions == 2)
	end
	equal(#env.warnings, 1, "an incompatible API is disabled and reported once")
end

do
	local env, modifier = environment()
	local config = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua")
	local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
	config.hudEnabled = true
	local model = modelWithRoots(false)
	model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY] = { schema = -1 }
	modify(modifier, model)
	assert(model.metadata.transformatorConfig, "a late camera failure retains completed sway preparation")
	equal(model.metadata.cameraConfig, nil, "failed onboard camera writes are rolled back")
	for _, lod in ipairs(model.lods) do
		equal(
			fixture.descendantNamed(lod.node, "swaying_waying_camera_stable_1"),
			nil,
			"failed camera anchors are rolled back"
		)
	end
	equal(#env.warnings, 1, "late camera failures are diagnosed")
end

print("Camera compatibility checks passed")
