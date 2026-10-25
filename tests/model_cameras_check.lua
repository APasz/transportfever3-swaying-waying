local harness = dofile("tests/support/model_environment.lua").new()
local assertions = dofile("tests/assertions.lua")
local equal, near = assertions.equal, assertions.near
local fixture = dofile("tests/support/model_fixture.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local modifier = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
local modelCameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua")
local cameraConfig = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")

local function transform(x, y, z, yaw)
	local result = fixture.identity()
	result[1], result[2], result[5], result[6] =
		math.cos(yaw or 0), math.sin(yaw or 0), -math.sin(yaw or 0), math.cos(yaw or 0)
	result[13], result[14], result[15] = x, y, z
	return result
end

local function cameraModel()
	local model = fixture.railModel(nil)
	model.metadata.cameraConfig = nil
	model.lods[1].node.transf = transform(3, -2, 1, 0.4)
	model.lods[1].node.children[#model.lods[1].node.children + 1] = {
		name = "cab",
		transf = transform(2, 1, 0.5, 0.2),
	}
	model.metadata.seatProvider = {
		seats = { { crew = true, animation = "driving", group = "cab", transf = transform(1, -0.4, 0.8) } },
	}
	return model
end

local function articulatedModel()
	local model = cameraModel()
	local root = model.lods[1].node
	local cab = root.children[2]
	root.children[2] = { name = "front_grp", transf = transform(5, 0, 0), mesh = "front.msh", children = { cab } }
	root.children[3] = { name = "rear_grp", transf = transform(-5, 0, 0), mesh = "rear.msh" }
	model.metadata.swayingWaying = { sections = { { group = "front_grp", lag = 0 }, { group = "rear_grp", lag = 10 } } }
	model.metadata.railVehicle.config = {
		fakeBogies = {
			{ group = "front_grp", position = 3 },
			{ group = "front_grp", position = 7 },
			{ group = "rear_grp", position = -7 },
			{ group = "rear_grp", position = -3 },
		},
	}
	return model
end

local function apply(model, mode, enabled, extra, fileName)
	modifier.modify(
		fileName or "tests::/cameras.mdl",
		model,
		{ intensity = 1 },
		false,
		{ swayEnabled = enabled ~= false, cameraMode = mode, extraCameras = extra }
	)
	return model.metadata.cameraConfig and model.metadata.cameraConfig.positions or {}
end

local function poseFor(model, group, lodIndex)
	local result
	local function visit(node, parent)
		local pose = nodes.multiply(parent, nodes.transform(node))
		if node.name == group then
			assert(result == nil, "camera anchor must occur exactly once")
			result = pose
		end
		for _, child in ipairs(node.children or {}) do
			visit(child, pose)
		end
	end
	visit(model.lods[lodIndex or 1].node, fixture.identity())
	return assert(result, "missing camera anchor " .. group)
end

local function cameraPose(model, camera, lodIndex)
	return nodes.multiply(poseFor(model, camera.group, lodIndex), camera.transf)
end

local function samePose(left, right, message)
	for component = 1, 16 do
		near(left[component], right[component], 1e-7, message)
	end
end

equal(cameraConfig.multipleCrewSeats, false, "multiple crew cameras default off")
equal(cameraConfig.hudEnabled, false, "the development camera HUD defaults off")
do
	local model = cameraModel()
	local custom = model.metadata.metadata
	equal(#apply(model, "Both"), 2, "camera additions work while the development HUD is off")
	equal(model.metadata.metadata, custom, "disabled HUD preserves custom metadata identity")
	equal(custom[constants.CAMERA_HUD_METADATA_KEY], nil, "disabled HUD publishes no camera descriptors")
end
cameraConfig.hudEnabled = true
for _, enabled in ipairs({ false, true }) do
	for _, mode in ipairs({ "Disabled", "Stable", "Sway", "Both" }) do
		local model = cameraModel()
		local cameras = apply(model, mode, enabled)
		local expected = (mode == "Stable" or mode == "Both") and 1 or 0
		if enabled and (mode == "Sway" or mode == "Both") then
			expected = expected + 1
		end
		equal(#cameras, expected, mode .. " respects the sway enable switch")
		equal(model.metadata.transformatorConfig ~= nil, enabled, "camera-only mode does not install a transformator")
	end
end

for _, case in ipairs({
	{ tags = { constants.ONLY_CAMERA_TAG }, sway = false, cameras = true },
	{ tags = { constants.NO_CAMERA_TAG }, sway = true, cameras = false },
	{ tags = { constants.ONLY_CAMERA_TAG, constants.NO_CAMERA_TAG }, sway = false, cameras = false },
	{ tags = { constants.NONE_TAG, constants.ONLY_CAMERA_TAG }, sway = false, cameras = false },
	{ tags = { constants.NO_CAMERA_TAG, constants.NONE_TAG }, sway = false, cameras = false },
}) do
	for _, enabled in ipairs({ false, true }) do
		for _, mode in ipairs({ "Disabled", "Stable", "Sway", "Both" }) do
			local model = cameraModel()
			model.metadata.transportVehicle.filterTags = case.tags
			local cameras = apply(model, mode, enabled, not case.cameras)
			local activeSway = enabled and case.sway
			local expected = case.cameras and (mode == "Stable" or mode == "Both") and 1 or 0
			if case.cameras and activeSway and (mode == "Sway" or mode == "Both") then
				expected = expected + 1
			end
			equal(#cameras, expected, "author tags respect camera mode and global sway settings")
			equal(
				model.metadata.transformatorConfig ~= nil,
				activeSway,
				"author tags independently gate vehicle motion"
			)
			if not case.cameras then
				equal(
					model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY],
					nil,
					"camera opt-out adds no HUD descriptors"
				)
			end
		end
	end
end

do
	local model = cameraModel()
	model.metadata.transportVehicle.filterTags = { constants.ONLY_CAMERA_TAG, constants.QUICK_TAG, constants.SLOW_TAG }
	model.metadata.swayingWaying = { sections = "irrelevant when motion is disabled" }
	local native = { transformator = { name = "unavailable::/custom.trf" }, params = { preserved = 42 } }
	model.metadata.transformatorConfig = native
	local animations = {
		sway = { type = "FILE_REF", params = { id = constants.BASE_TILT_ANIMATION } },
		tender_sway = { type = "FILE_REF", params = { id = constants.BASE_TILT_ANIMATION } },
	}
	model.lods[1].node.animations = animations
	local warnings = #harness.warnings
	equal(#apply(model, "Both"), 1, "camera-only authors can retain their own sway animations")
	equal(model.metadata.transformatorConfig, native, "camera-only preserves the original transformator")
	equal(native.transformator.name, "unavailable::/custom.trf", "camera-only needs no original callback imports")
	equal(native.params.swayingWaying, nil, "camera-only installs no sway runtime data")
	equal(model.lods[1].node.animations, animations, "camera-only preserves author-owned animation channels")
	equal(
		fixture.descendantNamed(model.lods[1].node, constants.SWAY_NODE),
		nil,
		"camera-only installs no body motion nodes"
	)
	equal(#harness.warnings, warnings, "camera-only ignores unused sway metadata and response tags")
end

do
	local model = cameraModel()
	model.metadata.transportVehicle.filterTags = { constants.NO_CAMERA_TAG }
	local authored = { group = "cab", transf = fixture.identity(), fov = 64 }
	local config = { positions = { authored }, authorField = "preserved" }
	model.metadata.cameraConfig = config
	equal(#apply(model, "Both", true, true), 1, "no-camera leaves existing cameras available without additions")
	equal(model.metadata.cameraConfig, config, "no-camera retains the authored camera configuration")
	equal(config.positions[1], authored, "no-camera preserves the authored view")
	equal(authored.fov, 64, "no-camera preserves authored camera properties")
	assert(model.metadata.transformatorConfig.params.swayingWaying, "no-camera still installs vehicle sway")
end

do
	local model = cameraModel()
	local cab = fixture.descendantNamed(model.lods[1].node, "cab")
	cab.children = { { name = "crew_mount", transf = fixture.identity() } }
	model.metadata.seatProvider.seats[1].group = "crew_mount"
	cab.animations = {
		front_forward_parts_off = {
			type = "FILE_REF",
			params = { id = "::/vehicle/shared/ani/front_forward_parts_off.ani" },
		},
	}
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "visibility-controlled crew still receive both camera variants")
	local before = cameraPose(model, cameras[2])
	local hidden = fixture.identity()
	hidden[1], hidden[6], hidden[11] = 0, 0, 0
	cab.transf = nodes.multiply(cab.transf, hidden)
	for _, camera in ipairs(cameras) do
		local pose = cameraPose(model, camera)
		assert(nodes.inverse(pose), "hiding crew/light groups must not collapse a camera's orientation")
		samePose(pose, before, "visibility changes leave the camera's position and orientation intact")
		assert(
			not fixture.descendantNamed(cab, camera.group),
			"generated cameras stay outside authored visibility branches"
		)
	end
	local sway = fixture.descendantNamed(model.lods[1].node, constants.SWAY_NODE)
	sway.transf = transform(0, 0.2, 0, 0.1)
	assert(math.abs(cameraPose(model, cameras[2])[14] - before[14]) > 0.01, "safe cameras still follow body sway")
end

do
	local model = cameraModel()
	local cab = fixture.descendantNamed(model.lods[1].node, "cab")
	cab.animations = { tilt = { type = "FILE_REF", params = { id = constants.BASE_TILT_ANIMATION } } }
	local cameras = apply(model, "Both")
	local stable = cameraPose(model, cameras[1])
	cab.transf = transform(2, 1, 0.5, 0.4)
	samePose(cameraPose(model, cameras[1]), stable, "native tilt does not move the stable camera")
	assert(
		math.abs(cameraPose(model, cameras[2])[1] - stable[1]) > 0.01,
		"safe native tilt remains part of the Sway view"
	)
end

do
	local cantAnimation = "devers_1::/vehicle/train/devers/ani/devers_roll.ani"
	local cantCore = "devers_1::/vehicle/train/devers/devers_core.lua"
	local previousCore, previousHud = harness.overrides[cantCore], cameraConfig.hudEnabled
	harness.overrides[cantCore] = {
		encodeRest = function()
			return "refreshed cant poses"
		end,
	}
	for _, hudEnabled in ipairs({ false, true }) do
		cameraConfig.hudEnabled = hudEnabled
		for _, extra in ipairs({ false, true }) do
			for _, unsafe in ipairs({ false, true }) do
				local model = cameraModel()
				local root = model.lods[1].node
				local cant = {
					name = "devers_roulis",
					transf = fixture.identity(),
					animations = { devers_roll = { type = "FILE_REF", params = { id = cantAnimation } } },
					children = root.children,
				}
				cant.children[#cant.children + 1] = {
					name = "body_mesh",
					mesh = root.mesh,
					materials = root.materials,
					transf = fixture.identity(),
				}
				root.mesh, root.materials, root.children = nil, nil, { cant }
				model.metadata.railVehicle.config = {
					fakeBogies = {
						{ group = cant.name, position = -5 },
						{ group = cant.name, position = 5 },
					},
				}
				model.metadata.transformatorConfig = {
					transformator = { name = "devers_1::/vehicle/train/devers/devers_train.trf" },
					params = {},
				}
				if unsafe then
					cant.animations.hide = {
						type = "FILE_REF",
						params = { id = "::/vehicle/shared/ani/front_forward_parts_off.ani" },
					}
				end
				local fileName = "tests::/cant_cameras_"
					.. tostring(hudEnabled)
					.. tostring(extra)
					.. tostring(unsafe)
					.. ".mdl"
				local warningCount = #harness.warnings
				local cameras = apply(model, "Both", true, extra, fileName)
				equal(
					#cameras,
					unsafe and 1 or 2,
					"known cant motion permits Sway views while visibility motion stays unsafe"
				)
				equal(
					#harness.warnings - warningCount,
					unsafe and 1 or 0,
					"only unsafe animation branches are diagnosed"
				)
				if not unsafe then
					local neutral = cameraPose(model, cameras[1])
					samePose(cameraPose(model, cameras[2]), neutral, "cant camera pairs share their neutral viewpoint")
					cant.transf = transform(0, 0.15, 0, 0.1)
					local tilted = cameraPose(model, cameras[1])
					assert(math.abs(tilted[14] - neutral[14]) > 0.01, "Stable views retain external cant motion")
					samePose(cameraPose(model, cameras[2]), tilted, "both variants retain external cant motion")
					local sway = assert(fixture.descendantNamed(cant, constants.SWAY_NODE .. "_devers_roulis"))
					sway.transf = transform(0, 0.2, 0.1, 0.08)
					samePose(cameraPose(model, cameras[1]), tilted, "Stable views ignore procedural body sway")
					assert(
						math.abs(cameraPose(model, cameras[2])[14] - tilted[14]) > 0.01,
						"Sway views follow procedural body sway"
					)
				end
			end
		end
	end
	harness.overrides[cantCore], cameraConfig.hudEnabled = previousCore, previousHud
end

do
	local model = cameraModel()
	local seat = model.metadata.seatProvider.seats[1]
	local expected = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.2)))
	local cameras = apply(model, "Both")
	samePose(cameraPose(model, cameras[1]), expected, "stable camera resolves the full seat hierarchy")
	samePose(cameraPose(model, cameras[2]), expected, "both camera variants share a neutral viewpoint")
	equal(cameras[1].fov, cameras[2].fov, "paired cameras share a FOV")
	local hud = model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY]
	equal(hud.schema, constants.CAMERA_HUD_SCHEMA, "HUD metadata has a versioned schema")
	equal(hud.count, 2, "HUD metadata describes the actual camera list")
	equal(hud.positions[1].kind, "Stable", "generated stable cameras publish their type")
	equal(hud.positions[2].kind, "Sway", "generated moving cameras publish their type")
	equal(hud.positions[1].crewSeat, 1, "HUD metadata retains the crew seat number")
	samePose(hud.positions[1].pose, expected, "HUD viewpoints use model coordinates")
	local sway = fixture.descendantNamed(model.lods[1].node, constants.SWAY_NODE)
	sway.transf = transform(0, 0.2, 0.1, 0.08)
	samePose(cameraPose(model, cameras[1]), expected, "stable camera ignores added motion")
	assert(math.abs(cameraPose(model, cameras[2])[14] - expected[14]) > 0.01, "sway camera follows body motion")
	apply(model, "Both")
	equal(#cameras, 2, "repeated model callbacks do not duplicate cameras")
end

do
	local model = articulatedModel()
	local root = model.lods[1].node
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "an articulated cab receives a camera pair")
	local front = fixture.descendantNamed(root, "front_grp")
	assert(fixture.descendantNamed(front, cameras[1].group), "the stable camera stays with its articulated section")
	front.transf = transform(5, 0, 0, 0.25)
	samePose(
		cameraPose(model, cameras[1]),
		cameraPose(model, cameras[2]),
		"both cameras follow authored section steering"
	)
	local before = cameraPose(model, cameras[1])
	fixture.descendantNamed(front, constants.SWAY_NODE .. "_front_grp").transf = transform(0, 0.1, 0, 0.1)
	samePose(cameraPose(model, cameras[1]), before, "section sway leaves the stable section camera untouched")
end

do
	local model = cameraModel()
	local root = model.lods[1].node
	local children = root.children
	local config = { transformator = { name = "author::/vehicle.trf" }, params = { owned = true } }
	model.metadata.transformatorConfig = config
	local cameras = apply(model, "Both", false)
	equal(#cameras, 1, "Both degrades to Stable while sway is disabled")
	equal(model.metadata.transformatorConfig, config, "camera-only mode preserves the authored transformator table")
	equal(config.transformator.name, "author::/vehicle.trf", "camera-only mode preserves the authored transformator")
	equal(config.params.owned, true, "camera-only mode preserves authored parameters")
	equal(root.children, children, "camera-only mode preserves the children array")
	equal(fixture.descendantNamed(root, constants.SWAY_NODE), nil, "camera-only mode adds no sway wrappers")
	apply(model, "Stable", false)
	equal(#cameras, 1, "camera-only repeated callbacks reuse the added camera")
end

for _, hudEnabled in ipairs({ false, true }) do
	cameraConfig.hudEnabled = hudEnabled
	for _, mode in ipairs({ "Stable", "Both" }) do
		local model = cameraModel()
		local root = model.lods[1].node
		local seat = model.metadata.seatProvider.seats[1]
		local pose = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.2)))
		local authored = {
			group = root.name,
			transf = nodes.multiply(assert(nodes.inverse(root.transf)), pose),
			fov = 60,
		}
		local positions = { authored }
		model.metadata.cameraConfig = { positions = positions }
		local config = {
			transformator = { name = "devers_1::/vehicle/train/devers/devers_train.trf" },
			params = { devers_rest1 = "authored placement data" },
		}
		model.metadata.transformatorConfig = config
		local children, childCount = root.children, #root.children
		for _ = 1, 2 do
			local cameras = apply(model, mode, false)
			equal(cameras, positions, "camera-only reuse preserves the authored camera list")
			equal(#cameras, 1, "camera-only reuse adds no duplicate cameras")
			equal(cameras[1], authored, "camera-only reuse preserves the authored camera entry")
			equal(root.children, children, "camera-only reuse preserves the children array")
			equal(#root.children, childCount, "camera-only reuse adds no anchor nodes")
			equal(model.metadata.transformatorConfig, config, "camera-only reuse preserves the authored transformator")
			equal(config.params.devers_rest1, "authored placement data", "camera-only reuse preserves placement data")
			local hud = model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY]
			if hudEnabled then
				assert(hud, "camera-only reuse must publish HUD metadata")
				equal(hud.count, 1, "reused camera HUD metadata matches the camera count")
				equal(hud.positions[1].kind, "Stable", "reused camera-only views retain their Stable label")
				equal(hud.positions[1].crewSeat, 1, "reused camera-only views retain their crew seat")
				samePose(hud.positions[1].pose, pose, "reused camera-only HUD viewpoints use model coordinates")
			else
				equal(hud, nil, "camera-only reuse publishes no metadata when the HUD is disabled")
			end
		end
	end
end

do
	local model = cameraModel()
	local root = model.lods[1].node
	local cab = fixture.descendantNamed(root, "cab")
	cab.animations = { tilt = { type = "FILE_REF", params = { id = constants.BASE_TILT_ANIMATION } } }
	root.children[#root.children + 1] = { name = "untilted_body", transf = fixture.identity() }
	local seat = model.metadata.seatProvider.seats[1]
	local pose = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.2)))
	model.metadata.cameraConfig = {
		positions = {
			{
				group = "untilted_body",
				transf = nodes.multiply(assert(nodes.inverse(poseFor(model, "untilted_body"))), pose),
				fov = 60,
			},
		},
	}
	local cameras = apply(model, "Both")
	equal(#cameras, 3, "a matching rest pose cannot substitute for a camera that follows native tilt")
	local original = cameraPose(model, cameras[1])
	cab.transf = transform(2, 1, 0.5, 0.4)
	samePose(cameraPose(model, cameras[1]), original, "the authored untilted camera keeps its behaviour")
	assert(
		math.abs(cameraPose(model, cameras[3])[1] - original[1]) > 0.01,
		"the new Sway camera follows native tilt independently"
	)
end

do
	local model = articulatedModel()
	local seat = model.metadata.seatProvider.seats[1]
	local pose = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.2)))
	model.metadata.cameraConfig = {
		positions = {
			{
				group = "rear_grp",
				transf = nodes.multiply(assert(nodes.inverse(poseFor(model, "rear_grp"))), pose),
				fov = 60,
			},
		},
	}
	local cameras = apply(model, "Both")
	equal(#cameras, 3, "a camera on another articulated section is not reused for the cab")
	local original = cameraPose(model, cameras[1])
	fixture.descendantNamed(model.lods[1].node, "front_grp").transf = transform(5, 0, 0, 0.25)
	samePose(cameraPose(model, cameras[1]), original, "the authored rear-section camera keeps its behaviour")
	assert(
		math.abs(cameraPose(model, cameras[2])[1] - original[1]) > 0.01,
		"the new Stable camera follows the cab section"
	)
end

do
	local model = cameraModel()
	local seat = model.metadata.seatProvider.seats[1]
	local authored = { group = "cab", transf = nodes.multiply(seat.transf, nodes.identity(1.2)), fov = 60 }
	model.metadata.cameraConfig = { positions = { authored } }
	model.lods[2] = { node = { name = "far_root", transf = fixture.identity(), mesh = "far.msh" } }
	local cameras = apply(model, "Stable", false)
	equal(#cameras, 2, "reuse requires a valid camera anchor in every LOD")
	equal(cameras[1], authored, "incomplete authored camera metadata is preserved")
	samePose(cameraPose(model, cameras[2], 1), cameraPose(model, cameras[2], 2), "the added camera works in every LOD")
end

do
	local model = cameraModel()
	model.metadata.cameraConfig = { positions = { { group = "RootNode", transf = fixture.identity(), fov = false } } }
	modifier.modify(
		"tests::/invalid_camera_fov.mdl",
		model,
		{ intensity = 1 },
		false,
		{ swayEnabled = true, cameraMode = "Both" }
	)
	assert(model.metadata.transformatorConfig, "an invalid existing camera does not disable independently safe sway")
	equal(model.metadata.cameraConfig.positions[1].fov, false, "invalid existing FOVs are preserved and diagnosed")
	assert(harness.warnings[#harness.warnings]:find("Camera FOV", 1, true), "invalid camera FOVs are diagnosed")
	model = cameraModel()
	local cab = fixture.descendantNamed(model.lods[1].node, "cab")
	cab.transf[1], cab.transf[2], cab.transf[3] = 0, 0, 0
	model.metadata.seatProvider.seats[2] = { crew = true, group = "RootNode", transf = fixture.identity() }
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "a singular crew attachment is skipped in favour of the next valid seat")
	samePose(
		cameraPose(model, cameras[1]),
		nodes.multiply(model.lods[1].node.transf, nodes.identity(1.2)),
		"the first valid crew seat supplies the replacement viewpoint"
	)
	for _, camera in ipairs(cameras) do
		assert(nodes.inverse(cameraPose(model, camera)), "generated camera world poses stay invertible")
	end
end

for _, case in ipairs({
	{
		name = "forward standing crew outrank rear-facing drivers",
		yaws = { math.pi, 0 },
		animations = { "driving_upright", "idle" },
		expected = 2,
	},
	{
		name = "forward drivers outrank forward standing crew",
		yaws = { 0, 0 },
		animations = { "idle", "driving_upright" },
		expected = 2,
	},
	{
		name = "forward drivers retain author order",
		yaws = { 0, 0 },
		animations = { "driving", "driving_upright" },
		expected = 1,
	},
	{
		name = "forward standing crew retain author order",
		yaws = { 0, 0 },
		animations = { "idle", "walk" },
		expected = 1,
	},
	{
		name = "rear-only crew retain the first valid seat",
		yaws = { math.pi, math.pi },
		animations = { "idle", "driving" },
		expected = 1,
	},
	{
		name = "sideways-only crew retain the first valid seat",
		yaws = { math.pi / 2, -math.pi / 2 },
		animations = { "idle", "driving" },
		expected = 1,
	},
	{
		name = "oblique drivers do not outrank forward crew",
		yaws = { math.pi / 3, 0 },
		animations = { "driving", "idle" },
		expected = 2,
	},
	{
		name = "root rotation contributes to crew facing",
		yaws = { 0, math.pi },
		animations = { "driving", "driving" },
		rootYaw = math.pi,
		expected = 2,
	},
	{
		name = "cab rotation contributes to crew facing",
		yaws = { 0, math.pi },
		animations = { "driving", "driving" },
		cabYaw = math.pi,
		expected = 2,
	},
}) do
	local model = cameraModel()
	model.lods[1].node.transf = transform(3, -2, 1, case.rootYaw)
	fixture.descendantNamed(model.lods[1].node, "cab").transf = transform(2, 1, 0.5, case.cabYaw)
	local seats = {}
	for index, yaw in ipairs(case.yaws) do
		seats[index] = {
			crew = true,
			forward = index == 1,
			animation = case.animations[index],
			group = "cab",
			transf = transform(index, -0.4, 0.8, yaw),
		}
	end
	model.metadata.seatProvider.seats = seats
	local plan = modelCameras.capture("tests::/crew_selection.mdl", model, "Both")
	equal(#plan.views, 1, case.name .. ": default selection keeps one viewpoint")
	equal(plan.views[1].crewSeat, case.expected, case.name)
	local expected = plan.views[1].pose
	local cameras = apply(model, "Both")
	equal(#cameras, 2, case.name .. ": the chosen seat receives both views")
	for _, camera in ipairs(cameras) do
		samePose(cameraPose(model, camera), expected, case.name .. ": generated cameras use the chosen seat")
	end
	equal(
		model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY].positions[1].crewSeat,
		case.expected,
		case.name .. ": HUD labels retain the authored crew seat number"
	)
	for index, yaw in ipairs(case.yaws) do
		equal(seats[index].transf[1], math.cos(yaw), case.name .. ": author seat order is preserved")
	end
end

do
	local model = cameraModel()
	local seats = model.metadata.seatProvider.seats
	seats[1].transf = transform(1, 0, 0, math.pi)
	seats[2] = { crew = true, animation = "driving", group = "cab", transf = { 1 } }
	local plan = modelCameras.capture("tests::/invalid_forward_crew.mdl", model, "Both")
	equal(plan.views[1].crewSeat, 1, "invalid forward candidates cannot displace a valid rear-facing seat")
	seats[2].transf = fixture.identity()
	cameraConfig.multipleCrewSeats = true
	plan = modelCameras.capture("tests::/all_crew.mdl", model, "Both")
	equal(#plan.views, 2, "multiple crew mode retains valid seats in both directions")
	equal(plan.views[1].crewSeat, 1, "multiple crew mode keeps the rear-facing seat first in author order")
	equal(plan.views[2].crewSeat, 2, "multiple crew mode keeps the forward-facing seat second in author order")
	cameraConfig.multipleCrewSeats = false
end

for _, moving in ipairs({ false, true }) do
	local model = cameraModel()
	local seat = model.metadata.seatProvider.seats[1]
	local pose = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.2)))
	local group = moving and "cab" or "RootNode"
	local authored = {
		group = group,
		transf = nodes.multiply(assert(nodes.inverse(poseFor(model, group))), pose),
		fov = 73,
		authorField = "preserved",
	}
	local config = { authorField = true, positions = { authored } }
	model.metadata.cameraConfig = config
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "a suitable authored camera supplies one of the pair")
	equal(cameras[1], authored, "authored camera identity and ordering are preserved")
	equal(authored.group, group, "authored camera anchors remain unchanged")
	equal(authored.authorField, "preserved", "unknown authored camera fields remain unchanged")
	equal(model.metadata.cameraConfig, config, "authored camera configuration identity is preserved")
	equal(config.authorField, true, "unknown configuration fields remain unchanged")
	equal(cameras[2].fov, 73, "the counterpart inherits the authored FOV")
	local descriptions = model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY].positions
	equal(descriptions[1].kind, moving and "Sway" or "Stable", "reused authored cameras receive the correct HUD label")
	equal(descriptions[1].index, 1, "reused camera descriptors retain authored order")
	samePose(cameraPose(model, cameras[1]), cameraPose(model, cameras[2]), "the counterpart inherits the authored pose")
end

do
	local model = cameraModel()
	local seats = model.metadata.seatProvider.seats
	seats[#seats + 1] = {
		crew = true,
		forward = false,
		animation = "driving",
		group = "cab",
		transf = transform(-2, 0.4, 0.8, math.pi),
	}
	seats[#seats + 1] = seats[2]
	seats[#seats + 1] = { animation = "sitting", group = "cab", transf = fixture.identity() }
	equal(#apply(model, "Both"), 2, "the default uses only the first valid crew seat")
	cameraConfig.multipleCrewSeats = true
	model = cameraModel()
	model.metadata.seatProvider.seats = seats
	local cameras = apply(model, "Both")
	equal(#cameras, 4, "multiple crew mode includes reverse crew and suppresses exact duplicate seats")
	equal(
		model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY].positions[3].crewSeat,
		2,
		"reverse crew views retain their seat number"
	)
	samePose(cameraPose(model, cameras[3]), cameraPose(model, cameras[4]), "the reverse cab also has a matched pair")
	assert(cameraPose(model, cameras[3])[1] < 0, "reverse-facing seat rotation is preserved")
	cameraConfig.multipleCrewSeats = false
end

do
	local model = cameraModel()
	model.metadata.swayingWaying = { skipFromLod = 1 }
	model.lods[2] = { node = { name = "far_root", transf = transform(-1, 2, 0, -0.2), mesh = "far.msh" } }
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "distant LODs do not prevent camera additions")
	for _, camera in ipairs(cameras) do
		samePose(
			cameraPose(model, camera, 1),
			cameraPose(model, camera, 2),
			"every LOD has a correctly rebased camera anchor"
		)
	end
	equal(
		fixture.descendantNamed(model.lods[2].node, constants.SWAY_NODE).animations,
		nil,
		"camera anchors do not enable distant sway"
	)
end

for _, enabled in ipairs({ false, true }) do
	for _, mode in ipairs({ "Stable", "Sway", "Both" }) do
		for _, passenger in ipairs({ false, true }) do
			local model = cameraModel()
			local pose
			if passenger then
				local seats = model.metadata.seatProvider.seats
				seats[1].crew, seats[1].transf = false, { 1 }
				seats[2] = {
					animation = "sitting",
					group = "cab",
					transf = transform(2, -0.4, 0.8, math.pi),
				}
				seats[3] = { animation = "idle", group = "cab", transf = transform(3, 0, 0.8) }
				pose = nodes.multiply(poseFor(model, "cab"), nodes.multiply(seats[2].transf, nodes.identity(1.2)))
			else
				model = fixture.railModel(nil)
				model.metadata.cameraConfig, model.metadata.seats = nil, nil
				pose = transform(-4.5, 0, 5.5)
			end
			local cameras = apply(model, mode, enabled, true)
			local expected = mode ~= "Sway" and 1 or 0
			if enabled and mode ~= "Stable" then
				expected = expected + 1
			end
			equal(#cameras, expected, "Extra camera variants respect the selected mode and sway switch")
			for _, camera in ipairs(cameras) do
				samePose(cameraPose(model, camera), pose, "Extra variants share one representative viewpoint")
			end
			if not enabled then
				equal(model.metadata.transformatorConfig, nil, "stable Extra views do not enable sway")
			end
		end
	end
end

do
	local model = cameraModel()
	local seats = model.metadata.seatProvider.seats
	seats[2] = { crew = true, animation = "driving", group = "cab", transf = transform(-2, 0, 1, math.pi) }
	seats[3] = { animation = "sitting", group = "cab", transf = transform(0, 0, 1) }
	cameraConfig.multipleCrewSeats = true
	local cameras = apply(model, "Both", true, true)
	cameraConfig.multipleCrewSeats = false
	equal(#cameras, 2, "Extra keeps one crew viewpoint even with other crew and passenger seats")
	local hud = model.metadata.metadata[constants.CAMERA_HUD_METADATA_KEY]
	equal(hud.positions[1].crewSeat, 1, "Extra retains the preferred crew viewpoint")
	equal(hud.positions[2].crewSeat, 1, "both Extra variants use the same crew seat")
end

do
	local model = fixture.railModel(nil)
	model.metadata.cameraConfig, model.metadata.seats = nil, nil
	local cargo = fixture.identity()
	cargo[1], cargo[3], cargo[9], cargo[11], cargo[15] = 0, 1, -1, 0, 3
	model.lods[1].node.children[#model.lods[1].node.children + 1] = { name = "cargo", transf = cargo }
	model.metadata.extent = { bbMin = { -6, -1, 0 }, bbMax = { 6, 1, 6 } }
	model.metadata.loadIndicator = {
		configs = {
			load = { cargoBay = { childId = "cargo", bbMin = { -2, -1, 0 }, bbMax = { 7, 1, 2 } } },
		},
	}
	model.lods[2] = { node = { name = "far_root", transf = transform(3, 2, 0, 0.2), mesh = "far.msh" } }
	model.metadata.swayingWaying = { skipFromLod = 1 }
	local cameras = apply(model, "Both", true, true)
	equal(#cameras, 2, "freight fallback receives a matched camera pair")
	local expected = transform(-5.5, 0, 10.5)
	for _, camera in ipairs(cameras) do
		for lod = 1, #model.lods do
			samePose(
				cameraPose(model, camera, lod),
				expected,
				"freight cameras clear rotated cargo bounds in every LOD"
			)
		end
	end
	local root = model.lods[1].node
	fixture.descendantNamed(root, constants.SWAY_NODE).transf = transform(0, 0.1, 0.1, 0.05)
	samePose(cameraPose(model, cameras[1]), expected, "the stable freight camera stays outside body sway")
	assert(math.abs(cameraPose(model, cameras[2])[14] - expected[14]) > 0.01, "the freight Sway view follows the body")
end

do
	local model = fixture.railModel(nil)
	local authored = model.metadata.cameraConfig.positions[1]
	model.metadata.seats = nil
	equal(#apply(model, "Both", true, true), 2, "an existing view supplies the representative before freight fallback")
	equal(model.metadata.cameraConfig.positions[1], authored, "Extra preserves the authored camera entry")
	samePose(
		cameraPose(model, model.metadata.cameraConfig.positions[2]),
		fixture.identity(),
		"Extra mirrors the existing viewpoint"
	)
	model = fixture.railModel(nil)
	model.metadata.cameraConfig, model.metadata.seats, model.boundingInfo = nil, nil, nil
	equal(
		#apply(model, "Both", true, true, "tests::/missing_freight_bounds.mdl"),
		0,
		"missing bounds do not create an arbitrary freight viewpoint"
	)
	assert(model.metadata.transformatorConfig, "missing optional freight bounds do not disable safe sway")
	model = fixture.railModel(nil)
	model.metadata.cameraConfig, model.metadata.seats = nil, nil
	model.boundingInfo.bbMax[3] = 0 / 0
	equal(
		#apply(model, "Both", true, true, "tests::/invalid_freight_bounds.mdl"),
		0,
		"invalid freight bounds are rejected"
	)
	assert(model.metadata.transformatorConfig, "invalid freight bounds do not disable independently safe sway")
	assert(
		not pcall(modelCameras.capture, "tests::/invalid_extra.mdl", cameraModel(), "Both", "yes"),
		"Extra must be a boolean"
	)
end

do
	local model = cameraModel()
	model.metadata.seatProvider = nil
	equal(#apply(model, "Both"), 0, "crewless models without authored views receive no cameras")
	model = cameraModel()
	model.metadata.seatProvider = nil
	model.metadata.cameraConfig = { positions = { { group = "RootNode", transf = transform(2, 0, 2), fov = 65 } } }
	equal(#apply(model, "Both"), 2, "crewless models can derive a counterpart from an authored view")
	model = cameraModel()
	model.metadata.seatProvider.seats[1].transf = { 1 }
	equal(
		#apply(model, "Both", true, false, "tests::/invalid_crew_seat.mdl"),
		0,
		"invalid crew seats are skipped explicitly"
	)
	assert(harness.warnings[#harness.warnings]:find("invalid crew camera seat", 1, true), "invalid seats are diagnosed")
end

do
	local model = cameraModel()
	model.lods[2] = { node = model.lods[1].node }
	model.lods[1].node.children[#model.lods[1].node.children + 1] = {
		name = "swaying_waying_camera_stable_1",
		transf = fixture.identity(),
	}
	local cameras = apply(model, "Both")
	equal(#cameras, 2, "shared LOD roots do not duplicate generated camera nodes")
	equal(cameras[1].group, "swaying_waying_camera_stable_2", "camera node names respect authored name collisions")
	for _, camera in ipairs(cameras) do
		cameraPose(model, camera, 1)
		cameraPose(model, camera, 2)
	end
end

do
	local model = cameraModel()
	model.metadata.seatProvider.seats[1].animation = "idle"
	local seat = model.metadata.seatProvider.seats[1]
	local expected = nodes.multiply(poseFor(model, seat.group), nodes.multiply(seat.transf, nodes.identity(1.6)))
	samePose(
		cameraPose(model, apply(model, "Stable", false)[1]),
		expected,
		"standing crew receive a standing eye-height offset"
	)
	model = cameraModel()
	model.metadata.seatProvider.seats[1].transf[1] = 0
	equal(#apply(model, "Both"), 0, "singular crew transforms cannot produce invalid camera matrices")
end

do
	local model = cameraModel()
	model.metadata.transformatorConfig = {
		transformator = { name = "::/vehicle/train/shared/default_train.trf" },
		params = setmetatable({}, {
			__newindex = function()
				error("late camera rollback")
			end,
		}),
	}
	local root, seats = model.lods[1].node, model.metadata.seatProvider.seats
	local children = root.children
	apply(model, "Both")
	equal(model.metadata.cameraConfig, nil, "late failures roll back camera metadata")
	equal(root.children, children, "late failures roll back camera anchors and sway wrappers")
	equal(seats[1].group, "cab", "late failures preserve crew references")
end

do
	local wagon = dofile("tests/support/wagon_cameras.lua").new()
	local logic, extra = wagon.logic, wagon.extras[1]
	logic.findModelEntries = function(_, fileName)
		equal(fileName, "tests::/cameras.mdl", "compatibility forwards the model resource name")
		return {}
	end
	for _, automaticEnabled in ipairs({ false, true }) do
		for _, order in ipairs({ "before", "after" }) do
			local env = dofile("tests/support/model_environment.lua").new()
			env.overrides["dome_wagon_cameras::/camera_logic.lua"] = logic
			env.overrides["dome_wagon_cameras::/camera_positions.lua"] = { default = {} }
			ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua").configure({
				dome_wagon_cameras = {},
			})
			local prepare = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
			local model = cameraModel()
			if not automaticEnabled then
				model = fixture.railModel(nil)
				model.metadata.cameraConfig, model.metadata.seats = nil, nil
				model.metadata.noWagonCameras = true
			end
			if order == "before" then
				wagon.apply("tests::/cameras.mdl", model)
			end
			prepare.modify(
				"tests::/cameras.mdl",
				model,
				{ intensity = 1 },
				false,
				{ swayEnabled = true, cameraMode = "Both", extraCameras = not automaticEnabled }
			)
			if order == "after" then
				wagon.apply("tests::/cameras.mdl", model)
			end
			local cameras = model.metadata.cameraConfig.positions
			equal(
				#cameras,
				automaticEnabled and 5 or 2,
				"Wagon Cameras retains automatic, configured, and freight views in either order"
			)
			local count = 0
			for _, camera in ipairs(cameras) do
				if camera == extra then
					count = count + 1
				end
			end
			equal(count, automaticEnabled and 1 or 0, "configured Wagon Cameras extras are added exactly once")
			local layout =
				assert(model.metadata.metadata.domeWagonCameras, "added freight views need an overlay layout")
			local overlay = logic.camerasFromLayout(layout)
			if #overlay == 0 then
				overlay = layout.original
			end
			equal(#overlay, #cameras, "the overlay includes the final camera list")
			equal(#env.warnings, 0, "both camera-mod orders adapt cleanly: " .. table.concat(env.warnings, "\n"))
		end
	end
end

do
	local env = dofile("tests/support/model_environment.lua").new()
	local prepare = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
	local model = cameraModel()
	model.metadata.metadata.domeWagonCameras = { extra = { [2] = {} }, rests = {} }
	local children = model.lods[1].node.children
	prepare.modify(
		"tests::/sparse_camera_overlay.mdl",
		model,
		{ intensity = 1 },
		false,
		{ swayEnabled = true, cameraMode = "Both" }
	)
	equal(#model.metadata.cameraConfig.positions, 2, "invalid overlay metadata does not disable onboard cameras")
	assert(model.metadata.transformatorConfig, "invalid overlay metadata does not disable sway")
	assert(model.lods[1].node.children ~= children, "independent hierarchy changes are committed")
	assert(
		env.warnings[#env.warnings]:find("Invalid Wagon Cameras layout", 1, true),
		"invalid overlay arrays are diagnosed"
	)
end

print("Model camera checks passed")
