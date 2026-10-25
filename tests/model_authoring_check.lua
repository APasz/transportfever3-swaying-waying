local harness = dofile("tests/support/model_environment.lua").new()
local models = dofile("tests/support/models.lua")
local fixture = dofile("tests/support/model_fixture.lua")
local assertions = dofile("tests/assertions.lua")
local modifier = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local authoring = ug_require("apasz_swaying_waying::/swaying_waying/model_authoring.lua")
local visuals = dofile("tests/support/model_visuals.lua")
local identity, near = models.identity, assertions.near
local sequence = 0

local function authoredModel(names)
	local model = models.rail({ 100, 400, 1600 })
	model.boundingInfo = { bbMin = { -10, -2, 0 }, bbMax = { 10, 2, 5 } }
	model.metadata.seats = nil
	model.metadata.cameraConfig = nil
	model.metadata.swayingWaying = { skipFromLod = 2, sections = { { group = "body", lag = 0 } } }
	for index, lod in ipairs(model.lods) do
		lod.node.mesh = nil
		lod.node.children = {
			{ name = names and names[index] or "body", transf = identity(), mesh = "body.msh" },
			{ name = "fixed_detail", transf = identity(), mesh = "fixed.msh" },
		}
	end
	return model
end

local function check(model, expected, diagnostic)
	sequence = sequence + 1
	local resource = "review::/author_" .. sequence .. ".mdl"
	local before = visuals.snapshot(model)
	local warningStart = #harness.warnings
	modifier.modify(resource, model, { intensity = 1 })
	visuals.validate(before, visuals.snapshot(model), resource)
	local config = model.metadata.transformatorConfig
	local adapted = config.params and config.params.swayingWaying ~= nil or false
	assert(adapted == expected, resource .. ": unexpected adaptation result")
	if diagnostic then
		local warnings = table.concat(harness.warnings, "\n", warningStart + 1)
		assert(warnings:find(diagnostic, 1, true), "Missing diagnostic: " .. diagnostic .. "\n" .. warnings)
	else
		assert(#harness.warnings == warningStart, "Unexpected authoring warning")
	end
	return model
end

for _, origin in ipairs({ "::/vehicle/train/shared/default_train.trf", "example::/custom.trf" }) do
	for _, inherited in ipairs({ 1, 3 }) do
		local model = authoredModel()
		model.metadata.transformatorConfig.transformator.name = origin
		model.metadata.transformatorConfig.skipFromLod = inherited
		check(model, true)
		assert(model.metadata.transformatorConfig.skipFromLod == math.max(2, inherited))
	end
	local model = authoredModel()
	model.metadata.transformatorConfig.transformator.name = origin
	model.metadata.transformatorConfig.skipFromLod = nil
	check(model, true)
	assert(model.metadata.transformatorConfig.skipFromLod == 3, "Unbounded original animations retain all LODs")
end

local invalidCases = {
	{ { section = {} }, "swayingWaying.section is an unknown field" },
	{ { wheelbase = 1 }, "swayingWaying.wheelbase" },
	{ { skipFromLod = 0 }, "swayingWaying.skipFromLod" },
	{ { skipFromLod = 4 }, "exceeds the model's 3 LODs" },
	{ { sections = { { group = "body" } } }, "sections[1].lag" },
	{ { sections = { { group = "body", lag = -1 } } }, "sections[1].lag" },
	{ { sections = { { group = "body", lag = 0, wheelbase = math.huge } } }, "sections[1].wheelbase" },
	{ { sections = { { group = "body", lag = 0, axes = "wrong" } } }, "sections[1].axes" },
	{ { sections = { { group = "body", lag = 0, pivot = { x = 0, z = 1 } } } }, "sections[1].pivot.y" },
	{ { sections = { { group = "body", lag = 0, pivot = { x = 0, y = 0, z = 0 / 0 } } } }, "sections[1].pivot.z" },
	{ { sections = { { group = "body", lag = 0, groupsByLod = {} } } }, "sections[1].groupsByLod" },
	{ { sections = { { group = "body", lag = 0, groupsByLod = { [-1] = "body" } } } }, "groupsByLod[-1]" },
	{ { sections = { { group = "body", lag = 0, groupsByLod = { [3] = "body" } } } }, "groupsByLod[3]" },
	{
		{ sections = { { group = "body", lag = 0 }, { group = "body", lag = 1 } } },
		"shares a group name with section 1",
	},
}
for _, case in ipairs(invalidCases) do
	local model = authoredModel()
	model.metadata.swayingWaying = case[1]
	local root = model.lods[1].node
	check(model, false, case[2])
	assert(model.lods[1].node == root and root.children[1].mesh == "body.msh", "Invalid metadata rolls back completely")
end
local tooMany = {}
for index = 1, 33 do
	tooMany[index] = { group = "body_" .. index, lag = index }
end
assert(not authoring.options("review::/too_many.mdl", { swayingWaying = { sections = tooMany } }).valid)

do
	local model = authoredModel({ "near_body", "middle_body", "far_body" })
	model.metadata.swayingWaying.sections[1].groupsByLod = { [0] = "near_body", [1] = "middle_body", [2] = "far_body" }
	model.metadata.seats = { { group = "near_body" } }
	check(model, true)
	local target = model.metadata.seats[1].group
	for index, lod in ipairs(model.lods) do
		assert(fixture.descendantNamed(lod.node, target), "Mapped attachment target exists in every LOD")
		local motion = assert(fixture.descendantNamed(lod.node, "swaying_waying_pivot_body"))
		assert((motion.animations ~= nil) == (index <= 2), "Distant aliases use unanimated anchors")
		assert(lod.node.children[2].mesh == "fixed.msh", "Unlisted branches stay fixed")
	end
end
do
	local model = authoredModel({ "body", "different", "body" })
	check(model, false, "group 'body' must occur exactly once in LOD 1 (found 0)")
end
do
	local model = authoredModel()
	model.lods[2].node.children[2].name = "body"
	check(model, false, "LOD 1 (found 2)")
end
do
	local model = authoredModel()
	model.metadata.swayingWaying.sections[2] = { group = "fixed_detail", lag = 8 }
	for _, lod in ipairs(model.lods) do
		lod.node.children[2].mesh = nil
		lod.node.children[2].children = { { name = "axle", mesh = "wheel.msh", transf = identity() } }
	end
	model.metadata.railVehicle.config = { axles = { "axle" } }
	check(model, false, "sections[2] group 'fixed_detail' in LOD 0 has no movable body content")
end

local function worldOf(root, target, parent)
	local world = nodes.multiply(parent or identity(), nodes.transform(root))
	if root.name == target then
		return world
	end
	for _, child in ipairs(root.children or {}) do
		local found = worldOf(child, target, world)
		if found then
			return found
		end
	end
end

-- Equivalent geometry exported with translated, rotated, scaled and mirrored group frames.
for _, transform in ipairs({
	identity(),
	{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 3, 1 },
	{ 0, 2, 0, 0, -3, 0, 0, 0, 0, 0, 4, 0, 0, 0, 3, 1 },
	{ -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 3, 1 },
}) do
	for _, pivot in ipairs({ false, { x = 2, y = -1, z = 0.5 } }) do
		local model = authoredModel()
		model.metadata.swayingWaying.sections[1].pivot = pivot or nil
		for _, lod in ipairs(model.lods) do
			local body = lod.node.children[1]
			body.transf = transform
			body.mesh = nil
			body.children = {
				{
					name = "visual",
					mesh = "body.msh",
					transf = nodes.multiply(assert(nodes.inverse(transform)), nodes.identity(3)),
				},
			}
		end
		check(model, true)
		local root = model.lods[1].node
		local frame = worldOf(root, "swaying_waying_pitch_pivot_body")
		local expected = pivot or { x = 0, y = 0, z = 1 }
		near(frame[13], expected.x, 1e-8, "Pivot X is independent of export frame")
		near(frame[14], expected.y, 1e-8, "Pivot Y is independent of export frame")
		near(frame[15], expected.z, 1e-8, "Pivot Z is independent of export frame")
		for component = 1, 12 do
			near(frame[component], identity()[component], 1e-8, "Motion axes remain model-aligned and unscaled")
		end
		local roll = fixture.descendantNamed(root, "swaying_waying_roll_pivot_body")
		local angle = 0.1
		roll.transf =
			{ 1, 0, 0, 0, 0, math.cos(angle), math.sin(angle), 0, 0, -math.sin(angle), math.cos(angle), 0, 0, 0, 0, 1 }
		local moved = worldOf(root, "visual")
		near(
			moved[14],
			expected.y + math.cos(angle) * -expected.y - math.sin(angle) * (3 - expected.z),
			1e-8,
			"Visible roll is independent of export frame"
		)
	end
end
do
	local model = authoredModel()
	model.metadata.swayingWaying.sections[1].axes = "group"
	for _, lod in ipairs(model.lods) do
		lod.node.children[1].transf = { 0, 2, 0, 0, -3, 0, 0, 0, 0, 0, 4, 0, 0, 0, 3, 1 }
	end
	check(model, true)
	local frame = worldOf(model.lods[1].node, "swaying_waying_pitch_pivot_body")
	near(frame[2], 1, 1e-8, "Group axes retain authored orientation without scaling motion")
	near(frame[5], -1, 1e-8, "Group axes retain authored orientation")
	near(frame[15], 1, 1e-8, "Group axes still use a model-space pivot")
end
do
	local model = authoredModel({ "near_body", "body", "body" })
	model.metadata.swayingWaying.sections[1].groupsByLod = { [0] = "near_body" }
	model.metadata.railVehicle.config = {
		fakeBogies = {
			{ { group = "near_body", position = 5, offset = 0 }, { group = "near_body", position = -5, offset = 0 } },
		},
	}
	check(model, true)
	near(
		model.metadata.transformatorConfig.params.swayingWaying.sections[1].wheelbase,
		10,
		1e-8,
		"Alias supports supply section wheelbase"
	)
end
for _, axes in ipairs({ "model", "group" }) do
	local model = authoredModel()
	model.metadata.swayingWaying.sections[1].axes = axes
	model.lods[2].node.children[1].transf[1] = 0
	check(model, false, "sections[1] group 'body' in LOD 1 has a singular")
end
do
	local model = authoredModel()
	model.metadata.swayingWaying.sections[1].axes = "group"
	model.lods[2].node.children[1].transf[2] = 0.5
	check(model, false, "in LOD 1 has sheared group axes")
end
do
	local model = authoredModel()
	model.metadata.railVehicle.config = { axles = { "body" } }
	check(model, false, "has no movable body content")
end
for _, secondary in ipairs({ true, false }) do
	local model = authoredModel()
	local target = { x = 2, y = -1, z = 0.5 }
	model.metadata.swayingWaying.sections[1].pivot = target
	for _, lod in ipairs(model.lods) do
		local body = lod.node.children[1]
		lod.node.transf = { -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 3, 1 }
		lod.node.children[1] = { name = "export_parent", transf = identity(), children = { body } }
		lod.node.children[1].transf[13] = 4
		body.transf[15] = 2
	end
	sequence = sequence + 1
	local original = visuals.snapshot(model)
	modifier.modify(
		"review::/nested_" .. sequence .. ".mdl",
		model,
		{ intensity = 1, pitchBalance = secondary and 1 or 0, heaveBalance = secondary and 1 or 0 }
	)
	visuals.validate(original, visuals.snapshot(model), "nested model frame")
	assert(model.metadata.transformatorConfig.params.swayingWaying.axisReversed == false)
	local frame = assert(
		worldOf(model.lods[1].node, secondary and "swaying_waying_pitch_pivot_body" or "swaying_waying_pivot_body")
	)
	near(frame[13], target.x, 1e-8, "Nested pivot X")
	near(frame[14], target.y, 1e-8, "Nested pivot Y")
	near(frame[15], target.z, 1e-8, "Nested pivot Z")
	near(frame[1], 1, 1e-8, "Mirrored root is compensated in model axes")
end
do
	local model = authoredModel()
	for _, lod in ipairs(model.lods) do
		local body = lod.node.children[1]
		body.mesh = nil
		body.transf[15] = 3
	end
	check(model, true)
	local root = model.lods[1].node
	near(worldOf(root, "body")[15], 3, 1e-8, "Empty locator rest position is retained")
	near(
		worldOf(root, "swaying_waying_pitch_pivot_body")[15],
		1,
		1e-8,
		"Empty locators use the inferred model-space pivot"
	)
end
for _, emptyLod in ipairs({ 1, 2, 3 }) do
	local model = authoredModel()
	model.metadata.seats = { { group = "body" } }
	for _, lod in ipairs(model.lods) do
		lod.node.children[1].transf[15] = 3
	end
	model.lods[emptyLod].node.children[1].mesh = nil
	check(model, true)
	local target = model.metadata.seats[1].group
	for _, lod in ipairs(model.lods) do
		local world = assert(worldOf(lod.node, target), "Mixed locator/body LODs retain a common attachment anchor")
		near(world[15], 3, 1e-8, "Attachment rest frame survives empty LODs")
	end
end
print("Model authoring checks passed")
