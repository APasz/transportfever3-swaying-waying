local harness = dofile("tests/support/harness.lua").new()
local models = dofile("tests/support/models.lua")
local assertions = dofile("tests/assertions.lua")
local modifier = harness.require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
local config = { intensity = 1, pitchBalance = 1, heaveBalance = 1 }

local partial = models.rail({ 100, 400 })
partial.lods[1].node.mesh = nil
local firstRoot, secondRoot = partial.lods[1].node, partial.lods[2].node
local originalConfig = partial.metadata.transformatorConfig
modifier.modify("tests::/partial.mdl", partial, config)
assertions.equal(partial.metadata.seats[1].group, "RootNode", "unsafe partial adaptation preserves seat references")
assertions.equal(partial.lods[1].node, firstRoot, "skipping preserves the first root identity")
assertions.equal(partial.lods[2].node, secondRoot, "skipping preserves the second root identity")
assertions.equal(secondRoot.mesh, "body.msh", "skipping preserves the complete original hierarchy")
assertions.equal(partial.metadata.transformatorConfig, originalConfig, "skipping preserves authored configuration")
assert(#harness.warnings > 0, "unsafe adaptation reports a reason")

for _, sparse in ipairs({ false, true }) do
	local malformed = models.rail({ 100, 400 })
	local lods, metadata = malformed.lods, malformed.metadata
	local firstRoot, secondLod = lods[1].node, lods[2]
	metadata.swayingWaying.skipFromLod = 1
	metadata.seats = nil
	if sparse then
		lods[3], lods[2] = secondLod, nil
	else
		lods.hidden = secondLod
	end
	modifier.modify("tests::/malformed_lods_" .. tostring(sparse) .. ".mdl", malformed, config)
	assert(
		firstRoot.mesh == "body.msh" and firstRoot.children == nil,
		"malformed LOD arrays leave the source hierarchy unchanged"
	)
	assert(metadata.transformatorConfig.params == nil, "malformed LOD arrays install no runtime configuration")
end

local function validateNames(node, names)
	assert(not names[node.name], "adaptation must never introduce duplicate node names: " .. tostring(node.name))
	names[node.name] = true
	for _, child in ipairs(node.children or {}) do
		validateNames(child, names)
	end
end

for _, authored in ipairs({ false, true }) do
	local collision = models.rail({ 400 })
	local root = collision.lods[1].node
	root.mesh = nil
	root.children = {
		{ name = "body-a", mesh = "body.msh", children = { { name = "wheel_a", mesh = "wheel.msh" } } },
		{ name = "body_a", mesh = "body.msh", children = { { name = "wheel_b", mesh = "wheel.msh" } } },
	}
	collision.metadata.railVehicle.config = {
		axles = { "wheel_a", "wheel_b" },
		fakeBogies = {
			{
				{ group = "body-a", position = 5 },
				{ group = "body-a", position = -5 },
				{ group = "body_a", position = 5 },
				{ group = "body_a", position = -5 },
			},
		},
	}

	if authored then
		collision.metadata.swayingWaying.sections = {
			{ group = "body-a", lag = 0 },
			{ group = "body_a", lag = 10 },
		}
	end
	modifier.modify("tests::/collision_" .. tostring(authored) .. ".mdl", collision, config)
	local configured = assert(collision.metadata.transformatorConfig.params.swayingWaying)
	assert(not authored or #configured.sections == 2, "authored colliding suffixes retain independent sections")
	validateNames(collision.lods[1].node, {})
end

local ordinary = models.rail({ 100, 400 })
local camera = ordinary.metadata.cameraConfig.positions[1]
local oldRoot = ordinary.lods[1].node
modifier.modify("tests::/ordinary.mdl", ordinary, config)
assertions.equal(ordinary.lods[1].node, oldRoot, "successful adaptation preserves root identity")
assertions.equal(ordinary.metadata.cameraConfig.positions[1], camera, "camera metadata remains author-owned")
assertions.equal(camera.group, "RootNode", "the stable camera frame remains available")

local meshCollision = models.rail({ 100, 400 })
meshCollision.lods[2].node.children = {
	{ name = "RootNode_swaying_waying_mesh", mesh = "authored.msh" },
	{ name = "RootNode_swaying_waying_mesh_2", mesh = "also_authored.msh" },
}
meshCollision.metadata.lights = { { meshId = "RootNode" } }
modifier.modify("tests::/mesh_collision.mdl", meshCollision, config)
assert(meshCollision.metadata.transformatorConfig.params, "generated mesh names must avoid authored names")
local meshTarget = meshCollision.metadata.lights[1].meshId
assert(meshTarget == "RootNode_swaying_waying_mesh_3", "mesh references use a free name across every LOD")
local function find(root, name)
	if root.name == name then
		return root
	end
	for _, child in ipairs(root.children or {}) do
		local found = find(child, name)
		if found then
			return found
		end
	end
end
for _, lod in ipairs(meshCollision.lods) do
	validateNames(lod.node, {})
	assert(find(lod.node, meshTarget).mesh == "body.msh", "all LODs share the generated mesh reference")
end
assert(
	find(meshCollision.lods[2].node, "RootNode_swaying_waying_mesh").mesh == "authored.msh",
	"authored mesh names remain unchanged"
)

local duplicated = models.rail({ 400 })
duplicated.lods[1].node.children = {
	{ name = "wheel", mesh = "wheel.msh" },
	{ name = "wheel", mesh = "wheel.msh" },
}
duplicated.metadata.railVehicle.config = { axles = { "wheel" } }
modifier.modify("tests::/duplicate_axles.mdl", duplicated, config)
assert(
	duplicated.metadata.transformatorConfig.params.swayingWaying,
	"valid authored duplicate axle names must not prevent adaptation"
)

local unresolved = models.rail({ 400 })
local customConfig = unresolved.metadata.transformatorConfig
customConfig.transformator.name = "missing::/authored.trf"
modifier.modify("tests::/missing_origin.mdl", unresolved, config)
assert(
	customConfig.transformator.name == "missing::/authored.trf" and customConfig.params == nil,
	"unresolved authored callbacks must leave the whole model unchanged"
)

local occupied = models.rail({ 400 })
local occupiedRoot = occupied.lods[1].node
local authorPayload = { ownedByAuthor = true }
occupied.metadata.transformatorConfig.params = { swayingWaying = authorPayload }
modifier.modify("tests::/occupied_namespace.mdl", occupied, config)
assert(
	occupied.metadata.transformatorConfig.params.swayingWaying == authorPayload,
	"an occupied private namespace must not overwrite authored parameters"
)
assert(
	occupiedRoot.mesh == "body.msh" and occupiedRoot.children == nil,
	"namespace conflicts must reject the entire prepared hierarchy"
)

local placeholder = models.rail({ 160, 470, 1410 })
placeholder.metadata.railVehicle.config = {
	axles = { "w1", "w2" },
	fakeBogies = {
		{},
		{ { group = "", position = 0 } },
		{ { group = "RootNode", position = -4.5 }, { group = "RootNode", position = 4.5 } },
	},
}
for _, lod in ipairs(placeholder.lods) do
	lod.node.children = { { name = "w1", mesh = "wheel.msh" }, { name = "w2", mesh = "wheel.msh" } }
end
placeholder.metadata.railVehicle.config.fakeBogies.foreign = { group = "foreign-layout", position = 100 }
modifier.modify("tests::/empty_placement.mdl", placeholder, config)
assert(
	placeholder.metadata.transformatorConfig.params.swayingWaying,
	"empty placement names must not create phantom body groups"
)
assert(
	placeholder.metadata.railVehicle.config.fakeBogies[2][1].group == "",
	"empty native placement placeholders remain unchanged"
)
local fixture = dofile("tests/support/model_fixture.lua")
for _, activeCount in ipairs({ 2, 3 }) do
	for _, nestedBogies in ipairs({ false, true }) do
		local tilting = models.rail({ 30, 425, 2000 })
		tilting.metadata.swayingWaying.skipFromLod = activeCount
		tilting.metadata.railVehicle.config = { axles = { "wheel" }, fakeBogies = {} }
		local bodies = {}
		for index, lod in ipairs(tilting.lods) do
			local body = {
				name = "body_tilt",
				transf = models.identity(),
				animations = { tilt = { type = "FILE_REF", params = { id = "authored_tilt.ani" } } },
				children = { { name = "body", mesh = "body.msh" } },
			}
			body.transf[15] = 1.1
			bodies[index] = body
			lod.node.mesh = nil
			lod.node.children = { body }
			if index < 3 then
				local container = nestedBogies and body or lod.node
				container.children[2] = { name = "bogie", children = { { name = "wheel", mesh = "wheel.msh" } } }
			end
			tilting.metadata.railVehicle.config.fakeBogies[index] = {
				{ group = "body_tilt", position = 7.2 },
				{ group = "body_tilt", position = -7.2 },
			}
		end
		modifier.modify(
			"tests::/tilting_lod_" .. activeCount .. "_" .. tostring(nestedBogies) .. ".mdl",
			tilting,
			config
		)
		assert(tilting.metadata.transformatorConfig.params.swayingWaying, "simplified tilting LODs must allow sway")
		local placement = tilting.metadata.railVehicle.config.fakeBogies[1][1].group
		for index, lod in ipairs(tilting.lods) do
			local container = nestedBogies and bodies[index] or lod.node
			local sway =
				assert(fixture.childNamed(container, placement), "placement stays on the same container in every LOD")
			assert(
				fixture.descendantNamed(lod.node, "body_tilt") == bodies[index],
				"the authored tilt node is retained"
			)
			assert(bodies[index].animations.tilt.params.id == "authored_tilt.ani", "authored tilting is retained")
			assert((sway.animations ~= nil) == (index <= activeCount), "only active LODs animate")
			assert(tilting.metadata.railVehicle.config.fakeBogies[index][1].group == placement)
			if index < 3 then
				assert(fixture.childNamed(container, "bogie"), "bogies stay outside procedural motion")
			end
		end
	end
end

local compatibility = harness.require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
for _, kind in ipairs({ "train", "tilting", "tram" }) do
	local file = kind == "tilting" and "tilting_train.trf" or "default_" .. kind .. ".trf"
	local alias = "::shared/" .. file
	local canonical = "::/vehicle/" .. (kind == "tram" and "tram" or "train") .. "/shared/" .. file
	assert(
		compatibility.wrapperFor(alias) == compatibility.wrapperFor(canonical),
		"native shorthand uses the native wrapper"
	)
	assert(compatibility.isDirect(alias), "native shorthand retains native LOD policy")
	assert(not compatibility.isDirect("shared/" .. file), "relative custom resources are not native aliases")
	assert(not compatibility.isDirect("custom::shared/" .. file), "another namespace owns its shorthand")
end
local shortNative = models.rail({ 400 })
shortNative.metadata.transformatorConfig.transformator.name = "::shared/default_train.trf"
modifier.modify("tests::/short_native.mdl", shortNative, config)
assert(
	shortNative.metadata.transformatorConfig.params.swayingWaying,
	"native shorthand requires no custom callback lookup"
)
print("Model safety checks passed")
