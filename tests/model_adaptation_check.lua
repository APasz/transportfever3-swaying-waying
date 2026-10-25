local harness = dofile("tests/support/model_environment.lua").new()
local moduleOverrides = harness.overrides
local warnings, messages, verboseMessages = harness.warnings, harness.messages, harness.verbose
local assertions = dofile("tests/assertions.lua")
local assertEqual, assertNear = assertions.equal, assertions.near
local fixture = dofile("tests/support/model_fixture.lua")
local railModel = fixture.railModel
local identity, childNamed, descendantNamed = fixture.identity, fixture.childNamed, fixture.descendantNamed
local setPassengerComfort = fixture.setPassengerComfort
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local modelModifier = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
local defaultModel = railModel("::/vehicle/train/shared/default_train.trf")
local originalDefaultConfig = defaultModel.metadata.transformatorConfig
modelModifier.modify("example::/vehicle/train/default.mdl", defaultModel, {
	intensity = 1.25,
	curveLeanIntensity = 0.75,
})
local defaultRoot = defaultModel.lods[1].node
local swayNode = defaultRoot.children[1]
local pitchNode = childNamed(swayNode, constants.PITCH_NODE)
local rollNode = childNamed(pitchNode, constants.ROLL_NODE)
local contentNode = childNamed(rollNode, constants.SWAY_CONTENT_NODE)
assertEqual(swayNode.name, constants.SWAY_NODE, "sway node is injected")
assertEqual(contentNode.name, constants.SWAY_CONTENT_NODE, "counter-transform content node is injected")
assertNear(swayNode.transf[15], 0.0, 0.000001, "heave node starts at the authored origin")
assertNear(pitchNode.transf[15], 1.0, 0.000001, "pitch pivot uses model bounds")
assertNear(contentNode.transf[15], -1.0, 0.000001, "content cancels the pivot translation")
assertEqual(
	rollNode.animations[constants.SWAY_ANIMATION].params.id,
	constants.BASE_TILT_ANIMATION,
	"sway uses the shared tilt animation"
)
assertEqual(
	pitchNode.animations[constants.PITCH_ANIMATION].params.id,
	constants.PITCH_ANIMATION_FILE,
	"pitch uses the dedicated longitudinal animation"
)
assertEqual(
	swayNode.animations[constants.HEAVE_ANIMATION].params.id,
	constants.HEAVE_ANIMATION_FILE,
	"heave uses the dedicated vertical animation"
)
assertEqual(defaultRoot.mesh, nil, "root mesh is moved below sway")
assertEqual(contentNode.children[1].mesh, "root_mesh.msh", "moved root mesh is preserved")
assertEqual(contentNode.children[2].name, "bogie", "existing children are preserved")
assertEqual(
	defaultModel.metadata.seats[1].group,
	constants.SWAY_CONTENT_NODE,
	"root-attached groups follow sway without inheriting the pivot offset"
)
assertEqual(
	defaultModel.metadata.lightSources[1].meshId,
	"RootNode_swaying_waying_mesh",
	"root mesh references are retargeted"
)
assertEqual(
	defaultModel.metadata.cameraConfig.positions[1].group,
	"RootNode",
	"cockpit camera anchors remain valid across authored LODs"
)
assertEqual(
	defaultModel.metadata.metadata.foreignLayout.group,
	"RootNode",
	"private metadata owned by other mods is not rewritten"
)
local defaultConfig = defaultModel.metadata.transformatorConfig
assertEqual(defaultConfig, originalDefaultConfig, "existing transformator configuration is updated in place")
assertEqual(defaultConfig.transformator.name, constants.TRAIN_TRANSFORMATOR, "standard trains use the direct wrapper")
assertEqual(defaultConfig.params.preserved, 42, "existing transformator parameters are preserved")
assertEqual(defaultConfig.params.swayingWaying.settings.intensity, 1.25, "intensity reaches the transformator")
assertEqual(
	(
		defaultConfig.params.swayingWaying.settings.pitchBalance > 0
		or defaultConfig.params.swayingWaying.settings.heaveBalance > 0
	),
	true,
	"secondary motion is enabled by default"
)
assertEqual(defaultConfig.params.swayingWaying.settings.pitchBalance, 1.0, "pitch balance defaults to neutral")
assertEqual(defaultConfig.params.swayingWaying.settings.heaveBalance, 1.0, "heave balance defaults to neutral")
assertNear(defaultConfig.params.swayingWaying.wheelbase, 6.5, 0.000001, "model length supplies a wheelbase fallback")
assertEqual(
	defaultConfig.params.swayingWaying.settings.curveLeanIntensity,
	0.75,
	"curve-lean intensity reaches the transformator"
)
assertEqual(defaultConfig.params.swayingWaying.settings.trackInfluence, 1.0, "track influence defaults to full")
assertEqual(defaultConfig.params.swayingWaying.settings.vehicleVariation, 1.0, "vehicle variation defaults to normal")
assertEqual(defaultConfig.params.swayingWaying.vehicleFactor, 1.0, "untagged vehicles use neutral response")
assertEqual(defaultConfig.params.swayingWaying.profile, "DEFAULT", "untagged vehicles use the default motion profile")

local rollOnlyModel = railModel("::/vehicle/train/shared/default_train.trf")
modelModifier.modify("example::/vehicle/train/roll_only.mdl", rollOnlyModel, {
	intensity = 1.0,
	pitchBalance = 0.0,
	heaveBalance = 0.0,
	curveLeanIntensity = 1.0,
})
local rollOnlySway = childNamed(rollOnlyModel.lods[1].node, constants.SWAY_NODE)
assertEqual(
	type(rollOnlySway.animations[constants.SWAY_ANIMATION]),
	"table",
	"zero secondary balances keep the original roll hierarchy"
)
assertEqual(
	descendantNamed(rollOnlySway, constants.PITCH_NODE),
	nil,
	"zero secondary balances omit pitch and heave hierarchy nodes"
)
assertEqual(
	(
		rollOnlyModel.metadata.transformatorConfig.params.swayingWaying.settings.pitchBalance > 0
		or rollOnlyModel.metadata.transformatorConfig.params.swayingWaying.settings.heaveBalance > 0
	),
	false,
	"zero secondary balances disable their runtime calculations"
)

local snowPowderModel = railModel("::/vehicle/train/shared/default_train.trf")
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
compatibility.configure({ just_more_weather_1 = {} })
snowPowderModel.metadata.snowPowderCompatibility = true
modelModifier.modify("example::/vehicle/train/snow_powder.mdl", snowPowderModel, {
	intensity = 1.0,
})
assertEqual(harness.snowPowderCalls, 1, "Realistic Environment Pro adapter is applied before sway")
assertEqual(
	snowPowderModel.metadata.transformatorConfig.params.swayingWaying.originalTransformator,
	"just_more_weather_1::/vehicle/jmw/jmw_train.trf",
	"Realistic Environment Pro particle transformator is preserved"
)
modelModifier.modify("example::/vehicle/train/snow_powder.mdl", snowPowderModel, {
	intensity = 1.0,
})
assertEqual(harness.snowPowderCalls, 1, "compatibility adapter remains idempotent")
compatibility.configure(nil)

local rougherVehicle = railModel(nil)
rougherVehicle.metadata.transportVehicle.filterTags = { "default", constants.ROUGHER_TAG }
modelModifier.modify("example::/vehicle/train/rougher.mdl", rougherVehicle, {
	intensity = 1.0,
})
assertEqual(
	rougherVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	1.25,
	"rougher vehicle tag reaches the transformator"
)

local smootherVehicle = railModel(nil)
smootherVehicle.metadata.transportVehicle.filterTags = { "default", constants.SMOOTHER_TAG }
modelModifier.modify("example::/vehicle/train/smoother.mdl", smootherVehicle, {
	intensity = 1.0,
})
assertEqual(
	smootherVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	0.7,
	"smoother vehicle tag reaches the transformator"
)

local quickVehicle = railModel(nil)
quickVehicle.metadata.transportVehicle.filterTags = { constants.QUICK_TAG }
modelModifier.modify("example::/vehicle/train/quick.mdl", quickVehicle, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	quickVehicle.metadata.transformatorConfig.params.swayingWaying.profile,
	"QUICK",
	"quick vehicle tag reaches the transformator"
)

local slowVehicle = railModel(nil)
slowVehicle.metadata.transportVehicle.filterTags = { constants.SLOW_TAG }
modelModifier.modify("example::/vehicle/train/slow.mdl", slowVehicle, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	slowVehicle.metadata.transformatorConfig.params.swayingWaying.profile,
	"SLOW",
	"slow vehicle tag reaches the transformator"
)

local conflictingProfileVehicle = railModel(nil)
conflictingProfileVehicle.metadata.transportVehicle.filterTags = {
	constants.QUICK_TAG,
	constants.SLOW_TAG,
}
local profileConflictWarnings = #warnings
modelModifier.modify("example::/vehicle/train/conflicting_profile.mdl", conflictingProfileVehicle, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	conflictingProfileVehicle.metadata.transformatorConfig.params.swayingWaying.profile,
	"DEFAULT",
	"conflicting motion profiles resolve to the default"
)
assertEqual(#warnings, profileConflictWarnings + 1, "conflicting motion profiles are logged")

local conflictingVehicle = railModel(nil)
conflictingVehicle.metadata.transportVehicle.filterTags = {
	constants.ROUGHER_TAG,
	constants.SMOOTHER_TAG,
}
local vehicleConflictWarnings = #warnings
modelModifier.modify("example::/vehicle/train/conflicting.mdl", conflictingVehicle, {
	intensity = 1.0,
})
assertEqual(
	conflictingVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	1.0,
	"conflicting vehicle response tags resolve neutrally"
)
assertEqual(#warnings, vehicleConflictWarnings + 1, "conflicting vehicle response tags are logged")

local noSwayVehicle = railModel("custom.trf")
local noSwayRoot = noSwayVehicle.lods[1].node
local noSwayWarnings = #warnings
noSwayVehicle.metadata.transportVehicle.filterTags = {
	constants.ROUGHER_TAG,
	constants.QUICK_TAG,
	constants.SLOW_TAG,
	constants.NONE_TAG,
}
noSwayVehicle.metadata.swayingWaying = { sections = "invalid but opted out" }
modelModifier.modify("example::/vehicle/train/no_sway.mdl", noSwayVehicle, {
	intensity = 1.0,
})
assertEqual(noSwayVehicle.lods[1].node, noSwayRoot, "none tag leaves the model hierarchy unchanged")
assertEqual(
	noSwayVehicle.metadata.transformatorConfig.transformator.name,
	"custom.trf",
	"none tag leaves the authored transformator unchanged"
)
assertEqual(#warnings, noSwayWarnings, "none tag takes precedence without response conflicts")

local lowComfortVehicle = railModel(nil)
setPassengerComfort(lowComfortVehicle, 0.0)
modelModifier.modify("example::/vehicle/waggon/low_comfort.mdl", lowComfortVehicle, {
	intensity = 1.0,
})
assertNear(
	lowComfortVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	1.10,
	0.000001,
	"passenger comfort reaches the transformator"
)

local authoredVariationVehicle = railModel(nil)
setPassengerComfort(authoredVariationVehicle, 0.0)
authoredVariationVehicle.metadata.transportVehicle.filterTags = { constants.ROUGHER_TAG }
modelModifier.modify("example::/vehicle/waggon/authored_variation.mdl", authoredVariationVehicle, {
	intensity = 1.0,
	vehicleVariation = 0.0,
})
assertNear(
	authoredVariationVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	1.25,
	0.000001,
	"disabled automatic variation preserves explicit author response tags"
)

local smoothComfortVehicle = railModel(nil)
setPassengerComfort(smoothComfortVehicle, 1.0)
smoothComfortVehicle.metadata.transportVehicle.filterTags = { constants.SMOOTHER_TAG }
modelModifier.modify("example::/vehicle/waggon/smooth_comfort.mdl", smoothComfortVehicle, {
	intensity = 1.0,
})
assertNear(
	smoothComfortVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	0.90 * 0.70,
	0.000001,
	"authored tags multiply passenger comfort response"
)

local freightComfortVehicle = railModel(nil)
freightComfortVehicle.metadata.transportVehicle.comfortFactor = 0.0
modelModifier.modify("example::/vehicle/waggon/freight_comfort.mdl", freightComfortVehicle, {
	intensity = 1.0,
})
assertNear(
	freightComfortVehicle.metadata.transformatorConfig.params.swayingWaying.vehicleFactor,
	1.0,
	0.000001,
	"non-passenger stock ignores comfort metadata"
)

local rootPositionedModel = railModel("::/vehicle/train/shared/default_train.trf")
rootPositionedModel.metadata.labelList = {
	labels = {
		{ childId = "", filter = "NUMBER" },
	},
}
rootPositionedModel.metadata.railVehicle.config = {
	axles = { "bogie" },
	fakeBogies = {
		{},
		{},
		{
			{ group = "RootNode", position = 2.5, offset = 0 },
			{ group = "RootNode", position = -2.5, offset = 0 },
		},
	},
}
modelModifier.modify("example::/vehicle/waggon/root_positioned.mdl", rootPositionedModel, {
	intensity = 1.0,
})
local positionedRoot = rootPositionedModel.lods[1].node
assertEqual(positionedRoot.children[1].name, "bogie", "axle subtree stays outside root sway")
assertEqual(
	positionedRoot.children[2].name,
	constants.SWAY_NODE,
	"root-positioned body is wrapped inside its placement group"
)
assertEqual(
	rootPositionedModel.metadata.railVehicle.config.fakeBogies[3][1].group,
	constants.SWAY_NODE,
	"engine placement follows the animated root wrapper"
)
assertEqual(
	rootPositionedModel.metadata.seats[1].group,
	constants.SWAY_CONTENT_NODE,
	"root attachments are retargeted below the pivot offset"
)
assertEqual(
	rootPositionedModel.metadata.labelList.labels[1].childId,
	constants.SWAY_CONTENT_NODE,
	"root-attached labels follow sway without inheriting the pivot offset"
)
assertNear(
	rootPositionedModel.metadata.transformatorConfig.params.swayingWaying.wheelbase,
	5.0,
	0.000001,
	"paired fake-bogie positions provide the effective wheelbase"
)

local articulatedModel = railModel("::/vehicle/train/shared/default_train.trf")
articulatedModel.lods[1].node.children = {
	{
		name = "front_group",
		transf = identity(),
		children = {
			{ name = "front_body", mesh = "front.msh", transf = identity() },
			{ name = "front_axle", mesh = "wheel.msh", transf = identity() },
		},
	},
	{
		name = "back_group",
		transf = identity(),
		children = {
			{ name = "back_body", mesh = "back.msh", transf = identity() },
			{ name = "back_axle", mesh = "wheel.msh", transf = identity() },
		},
	},
	{
		name = "connector_skin",
		skin = "connector.msh",
		skinMaterials = { "connector.mtl" },
		transf = identity(),
		children = {
			{ name = "front_connector", transf = identity(), authoredMarker = "preserved" },
		},
	},
}
articulatedModel.metadata.railVehicle.config = {
	axles = { "front_axle", "back_axle" },
	fakeBogies = {
		{},
		{},
		{
			{ group = "front_group", position = 5, offset = 0 },
			{ group = "back_group", position = -5, offset = 0 },
			{ group = "front_connector", position = 0, offset = 0 },
		},
	},
}
articulatedModel.metadata.seats[1].group = "front_group"
articulatedModel.metadata.labelList = {
	labels = { { childId = "", filter = "NUMBER" } },
}
modelModifier.modify("example::/vehicle/train/articulated.mdl", articulatedModel, {
	intensity = 1.0,
})
local articulatedRoot = articulatedModel.lods[1].node
assertEqual(
	childNamed(articulatedRoot, constants.SWAY_NODE),
	nil,
	"positioned groups avoid an ineffective outer wrapper"
)
local frontGroup = childNamed(articulatedRoot, "front_group")
local frontSway = childNamed(frontGroup, constants.SWAY_NODE .. "_front_group")
assertEqual(childNamed(frontGroup, "front_axle").name, "front_axle", "positioned axle stays outside sway")
assertEqual(
	descendantNamed(frontSway, constants.SWAY_CONTENT_NODE .. "_front_group").children[1].name,
	"front_body",
	"positioned body moves inside sway"
)
assertEqual(
	articulatedModel.metadata.railVehicle.config.fakeBogies[3][1].group,
	"front_group",
	"articulated engine placement remains on its authored group"
)
assertEqual(
	articulatedModel.metadata.seats[1].group,
	constants.SWAY_CONTENT_NODE .. "_front_group",
	"articulated attachments follow body sway below the pivot offset"
)
assertEqual(
	articulatedModel.metadata.labelList.labels[1].childId,
	"",
	"ambiguous root labels are not assigned to an arbitrary articulated section"
)
local connectorSkin = childNamed(articulatedRoot, "connector_skin")
local connectorLocator = childNamed(connectorSkin, "front_connector")
assertEqual(connectorLocator.name, "front_connector", "connector locator remains available to its skin")
assertEqual(connectorLocator.authoredMarker, "preserved", "connector locator metadata remains on the original locator")
assertEqual(
	articulatedModel.metadata.railVehicle.config.fakeBogies[3][3].group,
	"front_connector",
	"connector placement remains on its authored locator"
)

do
	local function posedPoint(root, targetName, point, roll, pitch, heave)
		local path = {}
		local function find(node)
			path[#path + 1] = node
			if node.name == targetName then
				return true
			end
			for _, child in ipairs(node.children or {}) do
				if find(child) then
					return true
				end
			end
			path[#path] = nil
			return false
		end
		assertEqual(find(root), true, "motion probe target exists")
		local x, y, z = point[1], point[2], point[3]
		for index = #path, 1, -1 do
			local node = path[index]
			local animations = node.animations or {}
			if animations[constants.SWAY_ANIMATION] then
				y, z = math.cos(roll) * y - math.sin(roll) * z, math.sin(roll) * y + math.cos(roll) * z
			end
			if animations[constants.PITCH_ANIMATION] then
				x, z = math.cos(pitch) * x + math.sin(pitch) * z, -math.sin(pitch) * x + math.cos(pitch) * z
			end
			if animations[constants.HEAVE_ANIMATION] then
				z = z + heave
			end
			local t = node.transf or identity()
			x, y, z =
				t[1] * x + t[5] * y + t[9] * z + t[13],
				t[2] * x + t[6] * y + t[10] * z + t[14],
				t[3] * x + t[7] * y + t[11] * z + t[15]
		end
		return { x, y, z }
	end

	local function jacobsLod(includeAxles)
		local bogieChildren = {
			{ name = "jacobs_bogie", mesh = "bogie.msh", transf = identity() },
		}
		if includeAxles then
			bogieChildren[#bogieChildren + 1] = { name = "jacobs_wheel_1", mesh = "wheel.msh", transf = identity() }
			bogieChildren[#bogieChildren + 1] = { name = "jacobs_wheel_2", mesh = "wheel.msh", transf = identity() }
		end
		return {
			node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = "group_1",
						transf = identity(),
						children = {
							{ name = "body", mesh = "body.msh", transf = identity() },
							{ name = "interior", mesh = "interior.msh", transf = identity() },
							{ name = "bogie_group", transf = identity(), children = bogieChildren },
						},
					},
					{
						name = "articulation_skin",
						skin = "gangway.msh",
						skinMaterials = { "gangway.mtl" },
						transf = identity(),
						children = {
							{ name = "bone_self", transf = identity() },
							{ name = "bone_other", transf = identity() },
						},
					},
				},
			},
		}
	end

	local jacobsModel = railModel("::/vehicle/train/shared/default_train.trf")
	jacobsModel.lods = { jacobsLod(true), jacobsLod(false) }
	jacobsModel.metadata.transformatorConfig.skipFromLod = 2
	jacobsModel.metadata.railVehicle.config = {
		axles = { "jacobs_wheel_1", "jacobs_wheel_2" },
		fakeBogies = {
			{
				{ group = "group_1", position = 8, offset = 0 },
				{ group = "bone_self", position = 8, offset = 0 },
				{ group = "bone_self", position = -8, offset = 0 },
				{ group = "bone_other", position = -8, offset = 0 },
				{ group = "bone_other", position = -24, offset = 0 },
			},
			{ { group = "group_1", position = 8, offset = 0 } },
			{
				{ group = "RootNode", position = 8, offset = 0 },
				{ group = "RootNode", position = -8, offset = 0 },
			},
		},
	}
	jacobsModel.metadata.seats[1].group = "interior"
	jacobsModel.metadata.labelList = { labels = { { childId = "interior", filter = "NUMBER" } } }
	modelModifier.modify("example::/vehicle/train/jacobs.mdl", jacobsModel, {
		intensity = 1.0,
	})
	local jacobsRoot = jacobsModel.lods[1].node
	local jacobsBodyGroup = childNamed(jacobsRoot, "group_1")
	local jacobsSway = childNamed(jacobsBodyGroup, constants.SWAY_NODE .. "_group_1")
	assertEqual(
		#jacobsModel.metadata.transformatorConfig.params.swayingWaying.sections,
		0,
		"Jacobs placement locators prevent speculative section inference"
	)
	assertEqual(childNamed(jacobsRoot, constants.SWAY_NODE), nil, "Jacobs articulation avoids an outer sway pivot")
	assertEqual(childNamed(jacobsBodyGroup, "bogie_group").name, "bogie_group", "Jacobs bogie stays outside body sway")
	assertEqual(
		descendantNamed(jacobsSway, constants.SWAY_CONTENT_NODE .. "_group_1").children[1].name,
		"body",
		"Jacobs vehicle body receives sway"
	)
	assertEqual(
		type(descendantNamed(jacobsSway, constants.ROLL_NODE .. "_group_1").animations[constants.SWAY_ANIMATION]),
		"table",
		"Jacobs vehicle body retains the shared sway channel"
	)
	assertEqual(
		type(descendantNamed(jacobsModel.lods[2].node, constants.SWAY_NODE .. "_group_1")),
		"table",
		"Jacobs body target remains consistent in an axle-free active LOD"
	)
	assertEqual(
		descendantNamed(jacobsRoot, constants.SWAY_NODE .. "_bone_self"),
		nil,
		"Jacobs articulation bones remain untouched"
	)
	assertEqual(
		jacobsModel.metadata.railVehicle.config.fakeBogies[1][1].group,
		"group_1",
		"Jacobs body placement retains its authored group"
	)
	assertEqual(
		jacobsModel.metadata.railVehicle.config.fakeBogies[1][2].group,
		"bone_self",
		"Jacobs self pivot retains its authored group"
	)
	assertEqual(
		jacobsModel.metadata.railVehicle.config.fakeBogies[3][1].group,
		"RootNode",
		"Jacobs root placement retains its authored group"
	)
	assertEqual(
		jacobsModel.metadata.seats[1].group,
		"interior",
		"Jacobs interior attachments keep their body-local anchor"
	)
	assertEqual(
		jacobsModel.metadata.labelList.labels[1].childId,
		"interior",
		"Jacobs labels keep their body-local anchor"
	)

	local cantCoreModule = "devers_1::/vehicle/train/devers/devers_core.lua"
	local savedCantCore = moduleOverrides[cantCoreModule]
	moduleOverrides[cantCoreModule] = {
		encodeRest = function(nodeCount)
			return tostring(nodeCount)
		end,
	}
	for _, bodyPlaced in ipairs({ false, true }) do
		for _, cantFirst in ipairs({ false, true }) do
			local cabModel = railModel(cantFirst and "devers_1::/vehicle/train/devers/devers_any.trf" or "cab.trf")
			cabModel.lods = { jacobsLod(true), jacobsLod(true), jacobsLod(false) }
			cabModel.metadata.transformatorConfig.skipFromLod = 3
			cabModel.metadata.railVehicle.config = {
				axles = { "jacobs_wheel_1", "jacobs_wheel_2" },
				fakeBogies = {
					{
						{ group = "bone_self", position = 8, offset = 0 },
						{ group = "bone_self", position = -8, offset = 0 },
						{ group = "bone_other", position = -8, offset = 0 },
						{ group = "bone_other", position = -24, offset = 0 },
						{ group = "coupler_lod0", position = 5, offset = 0 },
						{ group = "coupler_lod0", position = 10, offset = 0 },
					},
					{},
					{
						{ group = cantFirst and "devers_roulis" or "RootNode", position = 8, offset = 0 },
						{ group = cantFirst and "devers_roulis" or "RootNode", position = -8, offset = 0 },
					},
				},
			}
			local fakeBogies = cabModel.metadata.railVehicle.config.fakeBogies
			if bodyPlaced then
				for lodIndex = 1, 2 do
					local entries = fakeBogies[lodIndex]
					entries[#entries + 1] = { group = "group_1", position = 8, offset = 0 }
				end
			end
			local cabContainers = {}
			local couplerTransforms = {}
			local direction = bodyPlaced and -1 or 1
			for lodIndex, lod in ipairs(cabModel.lods) do
				local root = lod.node
				local bodyTransform = childNamed(root, "group_1").transf
				bodyTransform[13], bodyTransform[15] = 2, 0.2
				local couplerTransform = identity()
				couplerTransform[1], couplerTransform[6] = direction, direction
				couplerTransform[13], couplerTransform[15] = direction * 10, 0.6
				couplerTransforms[lodIndex] = couplerTransform
				root.children[#root.children + 1] = {
					name = "coupler_lod" .. (lodIndex - 1),
					transf = couplerTransform,
					mesh = "coupler.msh",
				}
				local container = root
				if cantFirst then
					container = {
						name = "devers_roulis",
						transf = identity(),
						animations = { devers_roll = {} },
						children = root.children,
					}
					root.children = { container }
				end
				cabContainers[lodIndex] = container
			end
			local cabWarnings = #warnings
			modelModifier.modify(
				"example::/vehicle/train/cab_" .. tostring(bodyPlaced) .. "_" .. tostring(cantFirst) .. ".mdl",
				cabModel,
				{
					intensity = 1.0,
				}
			)
			for lodIndex, container in ipairs(cabContainers) do
				local bodyGroup = childNamed(container, "group_1")
				local sway = childNamed(bodyGroup, constants.SWAY_NODE .. "_group_1")
				assertEqual(type(sway), "table", "both cab rigs receive body sway in every active LOD")
				assertEqual(descendantNamed(sway, "body").mesh, "body.msh", "cab shell stays below all motion pivots")
				if lodIndex <= 2 then
					assertEqual(
						type(childNamed(bodyGroup, "bogie_group")),
						"table",
						"cab bogie stays outside body sway"
					)
				end
				assertEqual(descendantNamed(sway, "bone_self"), nil, "articulation bones remain outside cab motion")
				local couplerName = "coupler_lod" .. (lodIndex - 1)
				local coupler = childNamed(container, couplerName)
				assertEqual(coupler.transf, couplerTransforms[lodIndex], "coupler placement and yaw remain authored")
				local couplerSway = childNamed(coupler, constants.SWAY_NODE .. "_" .. couplerName)
				assertEqual(type(couplerSway), "table", "separately placed couplers receive the body's motion")
				local couplerContent = constants.SWAY_CONTENT_NODE .. "_" .. couplerName
				local bodyContent = constants.SWAY_CONTENT_NODE .. "_group_1"
				for _, motionPose in ipairs({ { 0, 0, 0 }, { 0.05, -0.02, 0.03 } }) do
					local expected = posedPoint(
						container,
						bodyContent,
						{ direction * 10 - 2 + direction * 0.4, direction * 0.2, 0.7 },
						table.unpack(motionPose)
					)
					local actual = posedPoint(container, couplerContent, { 0.4, 0.2, 0.3 }, table.unpack(motionPose))
					for axis = 1, 3 do
						assertNear(
							actual[axis],
							expected[axis],
							0.000001,
							"front/rear couplers share the body's pivot and axes"
						)
					end
				end
				assertEqual(
					childNamed(container, constants.SWAY_NODE .. "_devers_roulis"),
					nil,
					"cant wrapper is not mistaken for a cab body"
				)
			end
			assertEqual(fakeBogies[1][1].group, "bone_self", "cab articulation placement is preserved")
			assertEqual(fakeBogies[1][5].group, "coupler_lod0", "cab coupling placement is preserved")
			assertEqual(
				fakeBogies[3][1].group,
				cantFirst and "devers_roulis" or "RootNode",
				"outer placement stays outside cab motion"
			)
			assertEqual(#warnings, cabWarnings, "both cab rigs adapt without warnings")
		end
	end
	moduleOverrides[cantCoreModule] = savedCantCore

	local unsafeJacobsModel = railModel("::/vehicle/train/shared/default_train.trf")
	local unsafeJacobsRoot = unsafeJacobsModel.lods[1].node
	unsafeJacobsModel.metadata.railVehicle.config = {
		fakeBogies = {
			{ { group = "connector_bone", position = 0, offset = 0 } },
			{},
			{ { group = "RootNode", position = 0, offset = 0 } },
		},
	}
	local unsafeJacobsWarnings = #warnings
	modelModifier.modify("example::/vehicle/train/unsafe_jacobs.mdl", unsafeJacobsModel, {
		intensity = 1.0,
	})
	assertEqual(
		unsafeJacobsModel.lods[1].node,
		unsafeJacobsRoot,
		"ambiguous articulated rigs remain structurally unchanged"
	)
	assertEqual(#warnings, unsafeJacobsWarnings + 1, "ambiguous articulated rigs are logged once")
end

do
	local function talentLod()
		return {
			node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = "front_grp",
						transf = identity(),
						children = {
							{ name = "front_body", mesh = "front.msh", transf = identity() },
							{ name = "front_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
					{
						name = "middle_grp",
						transf = identity(),
						children = {
							{ name = "middle_body", mesh = "middle.msh", transf = identity() },
						},
					},
					{
						name = "back_grp",
						transf = identity(),
						children = {
							{ name = "back_body", mesh = "back.msh", transf = identity() },
							{ name = "back_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
					{
						name = "connector_skin",
						skin = "connectors.msh",
						skinMaterials = { "connectors.mtl" },
						transf = identity(),
						children = {
							{ name = "front_connector", transf = identity() },
							{ name = "middle_1_connector", transf = identity() },
							{ name = "middle_2_connector", transf = identity() },
							{ name = "back_connector", transf = identity() },
						},
					},
				},
			},
		}
	end

	local talentModel = railModel("::/vehicle/train/shared/default_train.trf")
	talentModel.lods = { talentLod(), talentLod() }
	talentModel.metadata.transformatorConfig.skipFromLod = 2
	talentModel.metadata.railVehicle.config = {
		axles = { "front_axle", "back_axle" },
		fakeBogies = {
			{
				{ group = "middle_grp", position = 6.89, offset = 0 },
				{ group = "middle_grp", position = -6.89, offset = 0 },
				{ group = "front_connector", position = 20.23, offset = 0 },
				{ group = "front_connector", position = 6.89, offset = 0 },
				{ group = "middle_1_connector", position = 6.89, offset = 0 },
				{ group = "middle_1_connector", position = -6.89, offset = 0 },
				{ group = "middle_2_connector", position = -6.89, offset = 0 },
				{ group = "middle_2_connector", position = 6.89, offset = 0 },
				{ group = "back_connector", position = -6.89, offset = 0 },
				{ group = "back_connector", position = -20.23, offset = 0 },
			},
			{
				{ group = "middle_grp", position = 6.89, offset = 0 },
				{ group = "middle_grp", position = -6.89, offset = 0 },
			},
			{
				{ group = "front_grp", position = 20.23, offset = 0 },
				{ group = "front_grp", position = 6.89, offset = 0 },
				{ group = "middle_grp", position = 6.89, offset = 0 },
				{ group = "middle_grp", position = -6.89, offset = 0 },
				{ group = "back_grp", position = -6.89, offset = 0 },
				{ group = "back_grp", position = -20.23, offset = 0 },
			},
		},
	}
	modelModifier.modify("example::/vehicle/train/articulated_multiple_unit.mdl", talentModel, {
		intensity = 1.0,
	})

	local talentConfig = talentModel.metadata.transformatorConfig
	assertEqual(#talentConfig.params.swayingWaying.sections, 3, "axleless body sections are inferred")
	assertNear(
		talentConfig.params.swayingWaying.sections[2].lag,
		13.56,
		0.000001,
		"the centre body receives its support-derived lag"
	)
	assertNear(
		talentConfig.params.swayingWaying.sections[3].lag,
		27.12,
		0.000001,
		"the rear body receives its support-derived lag"
	)
	local talentRoot = talentModel.lods[1].node
	local middleSway = childNamed(childNamed(talentRoot, "middle_grp"), constants.SWAY_NODE .. "_middle_grp")
	assertEqual(
		type(
			descendantNamed(middleSway, constants.ROLL_NODE .. "_middle_grp").animations[constants.SWAY_SECTION_ANIMATION_PREFIX .. 2]
		),
		"table",
		"the axleless centre body receives independent sway"
	)
	assertEqual(
		descendantNamed(talentRoot, constants.SWAY_NODE .. "_front_connector"),
		nil,
		"empty connector locators are not promoted to body sections"
	)
	assertEqual(
		talentModel.metadata.railVehicle.config.fakeBogies[3][3].group,
		"middle_grp",
		"articulated body placement remains unchanged"
	)
end

do
	local function tiltingBodyLod()
		return {
			node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = "tilting_body_grp",
						transf = identity(),
						animations = {
							tilt = { type = "FILE_REF", params = { id = constants.BASE_TILT_ANIMATION } },
						},
						children = {
							{ name = "tilting_body", mesh = "body.msh", transf = identity() },
							{ name = "front_connector_loc", transf = identity() },
							{ name = "rear_connector_loc", transf = identity() },
						},
					},
					{
						name = "front_bogie_grp",
						transf = identity(),
						children = {
							{ name = "front_bogie", mesh = "bogie.msh", transf = identity() },
							{ name = "wheel_1", mesh = "wheel.msh", transf = identity() },
							{ name = "wheel_2", mesh = "wheel.msh", transf = identity() },
						},
					},
					{
						name = "rear_bogie_grp",
						transf = identity(),
						children = {
							{ name = "rear_bogie", mesh = "bogie.msh", transf = identity() },
							{ name = "wheel_3", mesh = "wheel.msh", transf = identity() },
							{ name = "wheel_4", mesh = "wheel.msh", transf = identity() },
						},
					},
				},
			},
		}
	end

	local tiltingBodyModel = railModel("::/vehicle/train/shared/tilting_train.trf")
	tiltingBodyModel.lods = { tiltingBodyLod(), tiltingBodyLod() }
	tiltingBodyModel.metadata.transformatorConfig.skipFromLod = 2
	tiltingBodyModel.metadata.railVehicle.config = {
		axles = { "wheel_1", "wheel_2", "wheel_3", "wheel_4" },
		fakeBogies = {
			{
				{ group = "front_connector_loc", position = 9.4, offset = 0 },
				{ group = "front_connector_loc", position = -9.4, offset = 0 },
				{ group = "rear_connector_loc", position = -16.2, offset = 0 },
				{ group = "rear_connector_loc", position = -35.0, offset = 0 },
				{ group = "tilting_body_grp", position = 9.4, offset = 0 },
				{ group = "tilting_body_grp", position = -9.4, offset = 0 },
			},
			{},
			{
				{ group = "RootNode", position = 9.4, offset = 0 },
				{ group = "RootNode", position = -9.4, offset = 0 },
			},
		},
	}
	modelModifier.modify("example::/vehicle/train/tilting_body_sibling_bogies.mdl", tiltingBodyModel, {
		intensity = 1.0,
	})

	local tiltingRoot = tiltingBodyModel.lods[1].node
	local tiltingBody = childNamed(tiltingRoot, "tilting_body_grp")
	local tiltingSway = childNamed(tiltingBody, constants.SWAY_NODE .. "_tilting_body_grp")
	assertEqual(
		#tiltingBodyModel.metadata.transformatorConfig.params.swayingWaying.sections,
		0,
		"a single tilting shell retains the shared sway channel"
	)
	assertEqual(type(tiltingBody.animations.tilt), "table", "native body tilt remains on the outer group")
	assertEqual(
		childNamed(tiltingBody, "front_connector_loc").name,
		"front_connector_loc",
		"vehicle-placement locators remain outside body sway"
	)
	assertEqual(
		descendantNamed(tiltingSway, "front_connector_loc"),
		nil,
		"body sway does not feed back through a connector locator"
	)
	assertEqual(
		type(
			descendantNamed(tiltingSway, constants.ROLL_NODE .. "_tilting_body_grp").animations[constants.SWAY_ANIMATION]
		),
		"table",
		"the tilting shell receives sway inside its native tilt group"
	)
	assertEqual(
		descendantNamed(childNamed(tiltingRoot, "front_bogie_grp"), constants.SWAY_NODE .. "_front_bogie_grp"),
		nil,
		"sibling bogies remain outside body sway"
	)
	assertEqual(
		tiltingBodyModel.metadata.railVehicle.config.fakeBogies[1][5].group,
		"tilting_body_grp",
		"tilting body placement remains unchanged"
	)
end

local function authoredSectionLod()
	return {
		node = {
			name = "RootNode",
			transf = identity(),
			children = {
				{
					name = "engine_group",
					transf = identity(),
					children = {
						{ name = "engine_body", mesh = "engine.msh", transf = identity() },
						{ name = "engine_axle", mesh = "wheel.msh", transf = identity() },
					},
				},
				{
					name = "tender_group",
					transf = identity(),
					children = {
						{ name = "tender_body", mesh = "tender.msh", transf = identity() },
						{ name = "tender_axle", mesh = "wheel.msh", transf = identity() },
					},
				},
				{ name = "fixed_detail", mesh = "fixed.msh", transf = identity() },
			},
		},
	}
end

local authoredSectionModel = railModel("::/vehicle/train/shared/default_train.trf")
authoredSectionModel.lods = {
	authoredSectionLod(),
	authoredSectionLod(),
	authoredSectionLod(),
}
authoredSectionModel.metadata.transformatorConfig.skipFromLod = 1
authoredSectionModel.metadata.railVehicle.config = {
	axles = { "engine_axle", "tender_axle" },
	fakeBogies = {
		{},
		{},
		{
			{ group = "engine_group", position = 5, offset = 0 },
			{ group = "tender_group", position = -5, offset = 0 },
		},
	},
}
authoredSectionModel.metadata.swayingWaying = {
	skipFromLod = 2,
	wheelbase = 12.0,
	sections = {
		{ group = "engine_group", lag = 0.0 },
		{ group = "tender_group", lag = 8.0, wheelbase = 8.0 },
	},
}
modelModifier.modify("example::/vehicle/train/authored_sections.mdl", authoredSectionModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
local sectionConfig = authoredSectionModel.metadata.transformatorConfig
assertEqual(sectionConfig.skipFromLod, 2, "author LOD limit overrides the inherited transformator limit")
assertEqual(#sectionConfig.params.swayingWaying.sections, 2, "authored section count reaches the transformator")
assertNear(sectionConfig.params.swayingWaying.sections[1].lag, 0.0, 0.000001, "first section lag is retained")
assertNear(sectionConfig.params.swayingWaying.sections[2].lag, 8.0, 0.000001, "second section lag is retained")
assertNear(
	sectionConfig.params.swayingWaying.sections[1].wheelbase,
	12.0,
	0.000001,
	"top-level wheelbase applies to sections without an override"
)
assertNear(
	sectionConfig.params.swayingWaying.sections[2].wheelbase,
	8.0,
	0.000001,
	"section wheelbase overrides the top-level value"
)
for lodIndex = 1, 2 do
	local root = authoredSectionModel.lods[lodIndex].node
	local engine = childNamed(root, "engine_group")
	local tender = childNamed(root, "tender_group")
	local engineSway = childNamed(engine, constants.SWAY_NODE .. "_engine_group")
	local tenderSway = childNamed(tender, constants.SWAY_NODE .. "_tender_group")
	local engineRoll = descendantNamed(engineSway, constants.ROLL_NODE .. "_engine_group")
	local tenderRoll = descendantNamed(tenderSway, constants.ROLL_NODE .. "_tender_group")
	assertEqual(
		type(engineRoll.animations[constants.SWAY_SECTION_ANIMATION_PREFIX .. 1]),
		"table",
		"active engine section uses its independent animation"
	)
	assertEqual(
		type(tenderRoll.animations[constants.SWAY_SECTION_ANIMATION_PREFIX .. 2]),
		"table",
		"active tender section uses its independent animation"
	)
	assertEqual(
		type(engineSway.animations[constants.HEAVE_SECTION_ANIMATION_PREFIX .. 1]),
		"table",
		"active engine section has an independent heave channel"
	)
	assertEqual(
		type(
			descendantNamed(engineSway, constants.PITCH_NODE .. "_engine_group").animations[constants.PITCH_SECTION_ANIMATION_PREFIX .. 1]
		),
		"table",
		"active engine section has an independent pitch channel"
	)
	assertEqual(childNamed(root, "fixed_detail").name, "fixed_detail", "unlisted authored sections remain fixed")
end
local inactiveSectionRoot = authoredSectionModel.lods[3].node
local inactiveEngineSway =
	childNamed(childNamed(inactiveSectionRoot, "engine_group"), constants.SWAY_NODE .. "_engine_group")
assertEqual(inactiveEngineSway.animations, nil, "inactive LOD anchors carry no sway animation")
assertEqual(
	authoredSectionModel.metadata.railVehicle.config.fakeBogies[3][1].group,
	constants.SWAY_NODE .. "_engine_group",
	"section placement follows the independent sway wrapper"
)
assertEqual(
	authoredSectionModel.metadata.swayingWaying.sections[1].group,
	"engine_group",
	"author metadata is not rewritten as an attachment"
)

do
	local function automaticSectionLod()
		return {
			node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = "front_grp",
						transf = identity(),
						children = {
							{ name = "front_body", mesh = "front.msh", transf = identity() },
							{ name = "front_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
					{
						name = "back_grp",
						transf = identity(),
						children = {
							{ name = "back_body", mesh = "back.msh", transf = identity() },
							{ name = "back_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
				},
			},
		}
	end

	local automaticSectionModel = railModel("::/vehicle/train/shared/default_train.trf")
	automaticSectionModel.lods = { automaticSectionLod(), automaticSectionLod() }
	automaticSectionModel.metadata.transformatorConfig.skipFromLod = 2
	automaticSectionModel.metadata.railVehicle.config = {
		axles = { "front_axle", "back_axle" },
		fakeBogies = {
			{},
			{},
			{
				{ group = "front_grp", position = 9.0, offset = 0 },
				{ group = "front_grp", position = -0.9, offset = 0 },
				{ group = "back_grp", position = -3.7, offset = 0 },
				{ group = "back_grp", position = -8.6, offset = 0 },
			},
		},
	}
	modelModifier.modify("example::/vehicle/train/tender_locomotive.mdl", automaticSectionModel, {
		intensity = 1.0,
		curveLeanIntensity = 1.0,
	})

	local config = automaticSectionModel.metadata.transformatorConfig
	assertEqual(#config.params.swayingWaying.sections, 2, "stable body groups infer two motion sections")
	assertNear(
		config.params.swayingWaying.sections[2].lag,
		10.2,
		0.000001,
		"the trailing section samples motion at its longitudinal separation"
	)
	assertNear(
		config.params.swayingWaying.sections[1].wheelbase,
		9.9,
		0.000001,
		"the leading section wheelbase comes from its support points"
	)
	assertNear(
		config.params.swayingWaying.sections[2].wheelbase,
		4.9,
		0.000001,
		"the trailing section wheelbase comes from its support points"
	)
	local root = automaticSectionModel.lods[1].node
	local engineSway = childNamed(childNamed(root, "front_grp"), constants.SWAY_NODE .. "_front_grp")
	local tenderSway = childNamed(childNamed(root, "back_grp"), constants.SWAY_NODE .. "_back_grp")
	assertEqual(
		type(
			descendantNamed(engineSway, constants.ROLL_NODE .. "_front_grp").animations[constants.SWAY_SECTION_ANIMATION_PREFIX .. 1]
		),
		"table",
		"the leading section uses its own sway channel"
	)
	assertEqual(
		type(
			descendantNamed(tenderSway, constants.ROLL_NODE .. "_back_grp").animations[constants.SWAY_SECTION_ANIMATION_PREFIX .. 2]
		),
		"table",
		"the trailing section uses its own sway channel"
	)
	assertEqual(
		automaticSectionModel.metadata.railVehicle.config.fakeBogies[3][1].group,
		"front_grp",
		"automatic sections preserve leading placement"
	)
	assertEqual(
		automaticSectionModel.metadata.railVehicle.config.fakeBogies[3][3].group,
		"back_grp",
		"automatic sections preserve trailing placement"
	)
	assertEqual(automaticSectionModel.metadata.swayingWaying, nil, "automatic sections do not mutate author metadata")

	local coincidentSectionModel = railModel("::/vehicle/train/shared/default_train.trf")
	coincidentSectionModel.lods = { automaticSectionLod(), automaticSectionLod() }
	coincidentSectionModel.metadata.transformatorConfig.skipFromLod = 2
	coincidentSectionModel.metadata.railVehicle.config = {
		axles = { "front_axle", "back_axle" },
		fakeBogies = {
			{},
			{},
			{
				{ group = "front_grp", position = 5, offset = 0 },
				{ group = "front_grp", position = -5, offset = 0 },
				{ group = "back_grp", position = 5, offset = 0 },
				{ group = "back_grp", position = -5, offset = 0 },
			},
		},
	}
	modelModifier.modify("example::/vehicle/train/coincident_sections.mdl", coincidentSectionModel, {
		intensity = 1.0,
	})
	assertEqual(
		#coincidentSectionModel.metadata.transformatorConfig.params.swayingWaying.sections,
		0,
		"coincident body supports retain shared sway"
	)
	for _, groupName in ipairs({ "front_grp", "back_grp" }) do
		local group = childNamed(coincidentSectionModel.lods[1].node, groupName)
		local sway = childNamed(group, constants.SWAY_NODE .. "_" .. groupName)
		assertEqual(
			type(descendantNamed(sway, constants.ROLL_NODE .. "_" .. groupName).animations[constants.SWAY_ANIMATION]),
			"table",
			"coincident body groups use the shared sway channel"
		)
	end

	local unsupportedModel = railModel("::/vehicle/train/shared/default_train.trf")
	local unsupportedWarnings = #warnings
	modelModifier.modify("example::/vehicle/train/unsupported_sections.mdl", unsupportedModel, {
		intensity = 1.0,
	})
	assertEqual(
		#unsupportedModel.metadata.transformatorConfig.params.swayingWaying.sections,
		0,
		"an unsupported hierarchy falls back to generic sway"
	)
	assertEqual(#warnings, unsupportedWarnings, "failed automatic inference does not produce a compatibility warning")
end

local invalidSectionModel = railModel("::/vehicle/train/shared/default_train.trf")
invalidSectionModel.metadata.swayingWaying = {
	sections = { { group = "missing_group", lag = 0.0 } },
}
local invalidSectionRoot = invalidSectionModel.lods[1].node
local invalidSectionWarnings = #warnings
modelModifier.modify("example::/vehicle/train/invalid_sections.mdl", invalidSectionModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	invalidSectionModel.lods[1].node,
	invalidSectionRoot,
	"invalid authored sections leave the hierarchy untouched"
)
assertEqual(#warnings, invalidSectionWarnings + 1, "invalid authored section groups are logged once")

local invalidAuthorMetadataModel = railModel("::/vehicle/train/shared/default_train.trf")
invalidAuthorMetadataModel.metadata.swayingWaying = "invalid"
local invalidAuthorMetadataRoot = invalidAuthorMetadataModel.lods[1].node
local invalidAuthorMetadataWarnings = #warnings
modelModifier.modify("example::/vehicle/train/invalid_author_metadata.mdl", invalidAuthorMetadataModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	invalidAuthorMetadataModel.lods[1].node,
	invalidAuthorMetadataRoot,
	"invalid author metadata leaves the hierarchy untouched"
)
assertEqual(#warnings, invalidAuthorMetadataWarnings + 1, "invalid author metadata is logged once")

local invalidWheelbaseModel = railModel("::/vehicle/train/shared/default_train.trf")
invalidWheelbaseModel.metadata.swayingWaying = { wheelbase = 1.0 }
local invalidWheelbaseWarnings = #warnings
modelModifier.modify("example::/vehicle/train/invalid_wheelbase.mdl", invalidWheelbaseModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	invalidWheelbaseModel.metadata.transformatorConfig.params.swayingWaying,
	nil,
	"invalid author wheelbase prevents accidental automatic adaptation"
)
assertEqual(#warnings, invalidWheelbaseWarnings + 1, "invalid author wheelbase is logged once")

local missingActiveRootModel = railModel("::/vehicle/train/shared/default_train.trf")
missingActiveRootModel.lods[2] = {}
missingActiveRootModel.metadata.transformatorConfig.skipFromLod = 2
local missingActiveRootWarnings = #warnings
modelModifier.modify("example::/vehicle/train/missing_active_root.mdl", missingActiveRootModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	childNamed(missingActiveRootModel.lods[1].node, constants.SWAY_NODE),
	nil,
	"missing active LOD root prevents partial hierarchy injection"
)
assertEqual(
	missingActiveRootModel.metadata.transformatorConfig.transformator.name,
	"::/vehicle/train/shared/default_train.trf",
	"missing active LOD root leaves the transformator untouched"
)
assertEqual(#warnings, missingActiveRootWarnings + 1, "missing active LOD root is logged once")

local activeOnlyModel = railModel("::/vehicle/train/shared/default_train.trf")
activeOnlyModel.lods[2] = authoredSectionLod()
activeOnlyModel.metadata.seats = nil
activeOnlyModel.metadata.lightSources = nil
activeOnlyModel.metadata.transformatorConfig.skipFromLod = 1
activeOnlyModel.metadata.swayingWaying = { skipFromLod = 1 }
modelModifier.modify("example::/vehicle/train/active_lod_only.mdl", activeOnlyModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	childNamed(activeOnlyModel.lods[2].node, constants.SWAY_NODE),
	nil,
	"an explicit author LOD limit leaves later unreferenced LODs unmodified"
)

do
	local minimumDirectLodModel = railModel("::/vehicle/train/shared/default_train.trf")
	minimumDirectLodModel.lods[2] = railModel(nil).lods[1]
	minimumDirectLodModel.lods[3] = railModel(nil).lods[1]
	minimumDirectLodModel.metadata.seats = nil
	minimumDirectLodModel.metadata.lightSources = nil
	minimumDirectLodModel.metadata.transformatorConfig.skipFromLod = 1
	modelModifier.modify("example::/vehicle/train/minimum_direct_lods.mdl", minimumDirectLodModel, {
		intensity = 1.0,
		curveLeanIntensity = 1.0,
	})
	assertEqual(
		minimumDirectLodModel.metadata.transformatorConfig.skipFromLod,
		2,
		"direct transformators retain the two-LOD fallback without visibility distances"
	)
	assertEqual(
		type(childNamed(minimumDirectLodModel.lods[2].node, constants.SWAY_NODE).animations),
		"table",
		"the second direct-transformator LOD receives active sway"
	)
	assertEqual(
		childNamed(minimumDirectLodModel.lods[3].node, constants.SWAY_NODE),
		nil,
		"the distant direct-transformator LOD remains untouched"
	)

	local noConfigLodModel = railModel(nil)
	noConfigLodModel.lods[2] = railModel(nil).lods[1]
	noConfigLodModel.lods[3] = railModel(nil).lods[1]
	noConfigLodModel.metadata.seats = nil
	noConfigLodModel.metadata.lightSources = nil
	modelModifier.modify("example::/vehicle/train/no_config_lods.mdl", noConfigLodModel, {
		intensity = 1.0,
		curveLeanIntensity = 1.0,
	})
	assertEqual(
		noConfigLodModel.metadata.transformatorConfig.skipFromLod,
		2,
		"unconfigured models retain the two-LOD fallback without visibility distances"
	)
	assertEqual(
		type(childNamed(noConfigLodModel.lods[2].node, constants.SWAY_NODE).animations),
		"table",
		"the second unconfigured LOD receives active sway"
	)
	assertEqual(
		childNamed(noConfigLodModel.lods[3].node, constants.SWAY_NODE),
		nil,
		"the distant unconfigured LOD remains untouched"
	)

	local customLimitedLodModel = railModel("custom.trf")
	customLimitedLodModel.lods[2] = railModel(nil).lods[1]
	customLimitedLodModel.metadata.seats = nil
	customLimitedLodModel.metadata.lightSources = nil
	customLimitedLodModel.metadata.transformatorConfig.skipFromLod = 1
	modelModifier.modify("example::/vehicle/train/custom_lod_limit.mdl", customLimitedLodModel, {
		intensity = 1.0,
		curveLeanIntensity = 1.0,
	})
	assertEqual(
		customLimitedLodModel.metadata.transformatorConfig.skipFromLod,
		1,
		"custom transformator LOD limits remain unchanged"
	)
	assertEqual(
		childNamed(customLimitedLodModel.lods[2].node, constants.SWAY_NODE),
		nil,
		"custom transformator inactive LODs remain untouched"
	)
end

do
	local function distanceModel(boundaries, transformatorName, inheritedLimit)
		local model = railModel(transformatorName)
		model.metadata.seats = nil
		model.metadata.lightSources = nil
		if model.metadata.transformatorConfig then
			model.metadata.transformatorConfig.skipFromLod = inheritedLimit
		end
		local visibleFrom = 0
		for index, visibleTo in ipairs(boundaries) do
			local lod = railModel(nil).lods[1]
			lod.visibleFrom = visibleFrom
			lod.visibleTo = visibleTo
			model.lods[index] = lod
			visibleFrom = visibleTo
		end
		return model
	end

	for _, case in ipairs({
		{ name = "common", boundaries = { 100, 400, 1600 }, active = 2 },
		{ name = "three_lods", boundaries = { 100, 200, 450, 1600 }, active = 3 },
		{ name = "one_lod", boundaries = { 600, 1600 }, active = 1 },
		{ name = "minimum_range", boundaries = { 120, 250, 1300 }, active = 3 },
		{ name = "below_minimum", boundaries = { 349, 650, 1600 }, active = 2 },
		{ name = "exact_minimum", boundaries = { 350, 1500 }, active = 1 },
		{ name = "equal_distance", boundaries = { 400, 600, 1600 }, active = 1 },
		{ name = "short_model", boundaries = { 100, 300 }, active = 2 },
		{ name = "preserve_original", boundaries = { 100, 500, 1600 }, active = 2, inherited = 3, callback = 3 },
		{ name = "no_inherited_limit", boundaries = { 100, 400, 1600 }, active = 2, omitLimit = true, callback = 3 },
		{ name = "no_configuration", boundaries = { 100, 220, 460, 1600 }, active = 3, noConfig = true },
		{ name = "custom_upper_bound", boundaries = { 100, 400, 1600 }, active = 1, custom = true },
		{
			name = "custom_longer_limit",
			boundaries = { 100, 400, 1600 },
			active = 2,
			custom = true,
			inherited = 3,
			callback = 3,
		},
		{ name = "author_shorter_limit", boundaries = { 100, 400, 1600 }, active = 1, authored = 1 },
		{ name = "author_longer_limit", boundaries = { 100, 400, 1600 }, active = 3, authored = 3 },
	}) do
		local originalName = case.custom and "custom.trf" or "::/vehicle/train/shared/default_train.trf"
		local model = distanceModel(case.boundaries, originalName, case.inherited or 1)
		if case.noConfig then
			model.metadata.transformatorConfig = nil
		elseif case.omitLimit then
			model.metadata.transformatorConfig.skipFromLod = nil
		end
		if case.authored then
			model.metadata.swayingWaying = { skipFromLod = case.authored }
		end
		modelModifier.modify("example::/vehicle/train/distance_" .. case.name .. ".mdl", model, {
			intensity = 1.0,
		})
		assertEqual(#model.lods, #case.boundaries, case.name .. " preserves the model LOD count")
		assertEqual(
			model.metadata.transformatorConfig.skipFromLod,
			case.callback or case.active,
			case.name .. " preserves the callback range needed by original animations and sway"
		)
		local visibleFrom = 0
		for index, visibleTo in ipairs(case.boundaries) do
			local lod = model.lods[index]
			assertEqual(lod.visibleFrom, visibleFrom, case.name .. " preserves the authored visibility start")
			assertEqual(lod.visibleTo, visibleTo, case.name .. " preserves the authored visibility end")
			local sway = childNamed(lod.node, constants.SWAY_NODE)
			assertEqual(
				sway ~= nil and sway.animations ~= nil,
				index <= case.active,
				case.name .. " selects sway LODs by distance"
			)
			visibleFrom = visibleTo
		end
	end

	for index, case in ipairs({
		{},
		{ value = -1 },
		{ value = math.huge },
		{ value = 0 / 0 },
		{ value = "200" },
		{ value = 50 },
	}) do
		local model = distanceModel({ 100, 200, 450, 1600 }, "::/vehicle/train/shared/default_train.trf", 1)
		model.lods[2].visibleTo = case.value
		local firstMessage = #messages + 1
		local firstWarning = #warnings + 1
		modelModifier.modify("example::/vehicle/train/distance_fallback_" .. index .. ".mdl", model, {
			intensity = 1.0,
		})
		assertEqual(model.metadata.transformatorConfig.skipFromLod, 2, "unusable distances retain the legacy fallback")
		if case.value == nil then
			assertEqual(#messages, firstMessage, "missing optional bounds keep normal output to one model result")
			assertEqual(#warnings, firstWarning - 1, "missing optional bounds do not warn")
		else
			assertEqual(
				warnings[firstWarning]:find("Using legacy sway LOD selection", 1, true) ~= nil,
				true,
				"invalid distance fallback reports its reason"
			)
		end
	end
end

local authoredLodModel = railModel("::/vehicle/train/shared/default_train.trf")
authoredLodModel.lods[2] = railModel(nil).lods[1]
authoredLodModel.lods[3] = railModel(nil).lods[1]
authoredLodModel.metadata.seats = nil
authoredLodModel.metadata.lightSources = nil
authoredLodModel.metadata.transformatorConfig.skipFromLod = 1
authoredLodModel.metadata.swayingWaying = { skipFromLod = 2, wheelbase = 9.0 }
modelModifier.modify("example::/vehicle/train/authored_lod.mdl", authoredLodModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(authoredLodModel.metadata.transformatorConfig.skipFromLod, 2, "author LOD override works without sections")
assertNear(
	authoredLodModel.metadata.transformatorConfig.params.swayingWaying.wheelbase,
	9.0,
	0.000001,
	"top-level wheelbase override works without sections"
)
assertEqual(
	type(childNamed(authoredLodModel.lods[2].node, constants.SWAY_NODE).animations),
	"table",
	"author LOD override activates the requested extra LOD"
)
assertEqual(
	childNamed(authoredLodModel.lods[3].node, constants.SWAY_NODE),
	nil,
	"author LOD override leaves later unreferenced LODs untouched"
)

do
	local function diagnosticModel()
		local model = railModel("::/vehicle/train/shared/default_train.trf")
		model.lods[2] = railModel(nil).lods[1]
		model.lods[3] = railModel(nil).lods[1]
		for index, range in ipairs({ { 0, 123.5 }, { 123.5, 400 }, { 400, 2000 } }) do
			model.lods[index].visibleFrom = range[1]
			model.lods[index].visibleTo = range[2]
		end
		model.metadata.swayingWaying = { skipFromLod = 2 }
		return model
	end
	local function lodLogs(fileName, model, config)
		local firstMessage = #messages + 1
		modelModifier.modify(fileName, model, config or { intensity = 1.0 }, true)
		local prefix = "[Swaying Waying] " .. fileName .. " LOD "
		local result = {}
		for index = firstMessage, #messages do
			if messages[index]:sub(1, #prefix) == prefix then
				result[#result + 1] = messages[index]
			end
		end
		return result
	end
	local function assertLogContains(message, text)
		assertEqual(type(message), "string", "LOD diagnostic exists")
		assertEqual(message:find(text, 1, true) ~= nil, true, "LOD diagnostic contains " .. text)
	end

	local normalModel = diagnosticModel()
	local firstResult = #messages + 1
	modelModifier.modify("example::/vehicle/train/concise_diagnostics.mdl", normalModel, { intensity = 1.0 })
	assertEqual(#messages, firstResult, "normal logging emits one concise model result")
	assertLogContains(messages[firstResult], "sway applied; active LODs=2/3; sections=1")
	assertEqual(messages[firstResult]:find("motion nodes=", 1, true), nil, "normal logging omits LOD inventories")
	assert(
		not pcall(modelModifier.modify, "tests::/invalid_switch.mdl", diagnosticModel(), { intensity = 1 }, "invalid"),
		"invalid model diagnostic switches fail explicitly"
	)

	local model = diagnosticModel()
	local verboseCount = #verboseMessages
	local logs = lodLogs("example::/vehicle/train/lod_diagnostics.mdl", model)
	assertEqual(#verboseMessages, verboseCount, "debug diagnostics are disabled by default")
	assertEqual(#logs, 3, "detailed logging reports visibility for active and inactive LODs")
	for index = 1, 2 do
		local message = logs[index]
		assertLogContains(message, "LOD " .. (index - 1) .. ": applied")
		assertLogContains(message, "body groups=1")
		assertLogContains(message, "motion nodes=[" .. constants.SWAY_NODE .. "]")
		assertLogContains(message, "moving visuals=1/1")
	end
	assertLogContains(logs[1], "visibleFrom=0 m; visibleTo=123.5 m")
	assertLogContains(logs[2], "visibleFrom=123.5 m; visibleTo=400 m")
	assertLogContains(logs[3], "LOD 2: inactive (beyond sway LOD limit); visibleFrom=400 m; visibleTo=2000 m")
	assertEqual(
		type(childNamed(model.lods[3].node, constants.SWAY_NODE)),
		"table",
		"inactive reference anchor still exists"
	)

	local partialModel = diagnosticModel()
	partialModel.lods[1].node = { name = "RootNode", transf = identity() }
	local partialLogs = lodLogs("example::/vehicle/train/partial_lod_diagnostics.mdl", partialModel)
	assertEqual(#partialLogs, 3, "rejected adaptation still reports visibility for every LOD")
	assertLogContains(partialLogs[1], "LOD 0: not applied (no body groups wrapped)")
	assertLogContains(partialLogs[1], "body groups=0; motion nodes=[]; moving visuals=0/0")
	assertLogContains(partialLogs[2], "LOD 1: not applied (no body groups wrapped)")
	assertLogContains(partialLogs[1], "visibleFrom=0 m; visibleTo=123.5 m")

	local unspecifiedModel = railModel(nil)
	unspecifiedModel.lods[1].visibleTo = 250
	local unspecifiedLogs = lodLogs("example::/vehicle/train/unspecified_visibility.mdl", unspecifiedModel)
	assertLogContains(unspecifiedLogs[1], "visibleFrom=unspecified; visibleTo=250 m")
	unspecifiedModel = railModel(nil)
	unspecifiedModel.lods[1].visibleFrom = 250
	unspecifiedLogs = lodLogs("example::/vehicle/train/unspecified_end_visibility.mdl", unspecifiedModel)
	assertLogContains(unspecifiedLogs[1], "visibleFrom=250 m; visibleTo=unspecified")

	for _, invalidDistance in ipairs({ -1, math.huge, 0 / 0, "250" }) do
		local invalidModel = railModel(nil)
		invalidModel.lods[1].visibleFrom = invalidDistance
		invalidModel.lods[1].visibleTo = invalidDistance
		local invalidLogs = lodLogs("example::/vehicle/train/invalid_visibility.mdl", invalidModel)
		assertLogContains(invalidLogs[1], "visibleFrom=invalid (")
		assertLogContains(invalidLogs[1], "; visibleTo=invalid (")
	end

	local function groupedDiagnosticModel()
		local candidate = diagnosticModel()
		candidate.metadata.transformatorConfig.transformator.name = "example::/vehicle/train/custom.trf"
		candidate.metadata.railVehicle.config = {
			axles = { "wheel_z", "wheel_a", "absent_wheel" },
			fakeBogies = {
				{
					{ group = "locator_z", position = 0, offset = 0 },
					{ group = "RootNode", position = 0, offset = 0 },
					{ group = "locator_a", position = 0, offset = 0 },
					{ group = "absent_locator", position = 0, offset = 0 },
				},
			},
		}
		for index = 1, 2 do
			candidate.lods[index].node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = "body_lod" .. (index - 1),
						transf = identity(),
						children = {
							{ name = "body_mesh", mesh = "body.msh", transf = identity() },
							{
								name = "bogie_group",
								transf = identity(),
								children = {
									{ name = "wheel_z", mesh = "wheel.msh", transf = identity() },
									{ name = "wheel_a", mesh = "wheel.msh", transf = identity() },
								},
							},
						},
					},
					{ name = "coupler", mesh = "coupler.msh", transf = identity() },
					{
						name = "articulation",
						skin = "gangway.msh",
						transf = identity(),
						children = {
							{ name = "locator_z", transf = identity() },
							{ name = "locator_a", transf = identity() },
						},
					},
				},
			}
		end
		return candidate
	end

	local groupedLogs = lodLogs("example::/vehicle/train/grouped_diagnostics.mdl", groupedDiagnosticModel())
	assertEqual(#groupedLogs, 3, "detailed diagnostics cover every LOD")
	assertEqual(groupedLogs[3]:find("detected body groups=", 1, true), nil, "inactive anchors omit group inventories")
	for index = 1, 2 do
		local message = groupedLogs[index]
		assertLogContains(message, "example::/vehicle/train/grouped_diagnostics.mdl LOD " .. (index - 1) .. ": applied")
		assertLogContains(message, "original transformator=example::/vehicle/train/custom.trf")
		assertLogContains(message, "detected body groups=[body_lod" .. (index - 1) .. "]")
		assertLogContains(message, "excluded axle groups=[wheel_a, wheel_z]")
		assertLogContains(message, "excluded placement groups=[RootNode, locator_a, locator_z]")
		assertLogContains(message, constants.SWAY_NODE .. "_coupler")
		assertLogContains(message, "body groups=1")
		assertLogContains(message, "moving visuals=2/5")
	end
	assertLogContains(groupedLogs[1], "visibleFrom=0 m; visibleTo=123.5 m")
	assertLogContains(groupedLogs[2], "visibleFrom=123.5 m; visibleTo=400 m")

	local simplifiedModel = groupedDiagnosticModel()
	simplifiedModel.lods[2].node.children[1].name = "body_lod0"
	simplifiedModel.lods[2].node.children[1].children[2] = nil
	local simplifiedLogs = lodLogs("example::/vehicle/train/simplified_diagnostics.mdl", simplifiedModel)
	assertLogContains(simplifiedLogs[2], "LOD 1: applied")
	assertLogContains(simplifiedLogs[2], "detected body groups=[body_lod0]")
	assertLogContains(simplifiedLogs[2], "excluded axle groups=[]")

	local sectionModel = diagnosticModel()
	sectionModel.metadata.swayingWaying.sections = {
		{ group = "rear_body", lag = 0 },
		{ group = "front_body", lag = 10 },
	}
	for index = 1, 2 do
		sectionModel.lods[index].node = {
			name = "RootNode",
			transf = identity(),
			children = {
				{ name = "rear_body", mesh = "rear.msh", transf = identity() },
				{ name = "front_body", mesh = "front.msh", transf = identity() },
			},
		}
	end
	local sectionLogs = lodLogs("example::/vehicle/train/section_diagnostics.mdl", sectionModel)
	assertEqual(#sectionLogs, 3, "section diagnostics cover active and inactive LODs")
	for index = 1, 2 do
		local message = sectionLogs[index]
		assertLogContains(message, "body groups=2")
		assertLogContains(message, "detected body groups=[front_body, rear_body]")
		assertLogContains(message, "moving visuals=2/2")
	end
	local rollOnlyModel = railModel(nil)
	rollOnlyModel.metadata.swayingWaying = { sections = { { group = "RootNode", lag = 0 } } }
	local rollOnlyLogs = lodLogs("example::/vehicle/train/roll_only_diagnostics.mdl", rollOnlyModel, {
		intensity = 1.0,
		pitchBalance = 0.0,
		heaveBalance = 0.0,
	})
	assertLogContains(rollOnlyLogs[1], "motion nodes=[" .. constants.SWAY_NODE .. "]")
	assertLogContains(rollOnlyLogs[1], "moving visuals=1/1")
	assertLogContains(rollOnlyLogs[1], "detected body groups=[RootNode]")

	local locatorModel = railModel(nil)
	locatorModel.lods[1].node = {
		name = "RootNode",
		transf = identity(),
		children = { { name = "body_locator", transf = identity() } },
	}
	locatorModel.metadata.swayingWaying = { sections = { { group = "body_locator", lag = 0 } } }
	local locatorLogs = lodLogs("example::/vehicle/train/locator_diagnostics.mdl", locatorModel)
	assertLogContains(locatorLogs[1], "LOD 0: applied; body groups=1")
	assertLogContains(locatorLogs[1], "motion nodes=[" .. constants.SWAY_NODE .. "_body_locator]")
	assertLogContains(locatorLogs[1], "detected body groups=[body_locator]")

	local defaultLogs = lodLogs("example::/vehicle/train/default_diagnostics.mdl", railModel(nil))
	assertLogContains(defaultLogs[1], "original transformator=::/vehicle/train/shared/default_train.trf")
	assertLogContains(defaultLogs[1], "detected body groups=[RootNode]")
	assertLogContains(defaultLogs[1], "excluded axle groups=[]; excluded placement groups=[]")
	assertLogContains(partialLogs[1], "detected body groups=[]")

	for _, animations in ipairs({
		{},
		{ doors = { type = "FILE_REF", params = { id = constants.HEAVE_ANIMATION_FILE } } },
		{ [constants.HEAVE_ANIMATION] = { type = "FILE_REF", params = { id = "other_mod::/bounce.ani" } } },
		{ [constants.HEAVE_ANIMATION] = { type = "KEYFRAME", params = { id = constants.HEAVE_ANIMATION_FILE } } },
	}) do
		local unrelatedAnimationModel = railModel(nil)
		local bogie = unrelatedAnimationModel.lods[1].node.children[1]
		bogie.name = constants.SWAY_NODE .. "_authored_bogie"
		bogie.mesh = "bogie.msh"
		bogie.animations = animations
		unrelatedAnimationModel.metadata.railVehicle.config = { axles = { bogie.name } }
		local unrelatedLogs =
			lodLogs("example::/vehicle/train/unrelated_animation_diagnostics.mdl", unrelatedAnimationModel)
		assertLogContains(unrelatedLogs[1], "motion nodes=[" .. constants.SWAY_NODE .. "]")
		assertLogContains(unrelatedLogs[1], "moving visuals=1/2")
		assertLogContains(unrelatedLogs[1], "excluded axle groups=[" .. bogie.name .. "]")
	end

	for _, case in ipairs({
		{
			name = "unresolved_body",
			reason = "body groups could not be identified",
			configure = function(candidate)
				candidate.metadata.railVehicle.config = {
					fakeBogies = {
						{ { group = "missing_locator", position = 0, offset = 0 } },
						{},
						{ { group = "RootNode", position = 0, offset = 0 } },
					},
				}
			end,
		},
		{
			name = "invalid_root",
			reason = "invalid active LOD root",
			configure = function(candidate)
				candidate.lods[2].node = nil
			end,
		},
		{
			name = "invalid_section",
			reason = "invalid section groups",
			configure = function(candidate)
				candidate.metadata.swayingWaying.sections = { { group = "missing_section", lag = 0 } }
			end,
		},
	}) do
		local skippedModel = diagnosticModel()
		case.configure(skippedModel)
		local skippedLogs = lodLogs("example::/vehicle/train/" .. case.name .. "_diagnostics.mdl", skippedModel)
		assertEqual(#skippedLogs, 3, "planning failures report visibility for every LOD")
		for index = 1, 2 do
			local message = skippedLogs[index]
			assertLogContains(message, "LOD " .. (index - 1) .. ": not applied (" .. case.reason .. ")")
			assertLogContains(message, "body groups=0; motion nodes=[]; moving visuals=0/")
			assertLogContains(message, "original transformator=::/vehicle/train/shared/default_train.trf")
			assertLogContains(message, "detected body groups=[]")
			assertLogContains(message, "excluded axle groups=[]")
			assertLogContains(message, "excluded placement groups=[")
		end
		assertLogContains(skippedLogs[1], "visibleFrom=0 m; visibleTo=123.5 m")
		assertLogContains(skippedLogs[2], "visibleFrom=123.5 m; visibleTo=400 m")
		assertLogContains(
			skippedLogs[3],
			"LOD 2: inactive (beyond sway LOD limit); visibleFrom=400 m; visibleTo=2000 m"
		)
	end
end

local inactiveLabelModel = railModel("::/vehicle/train/shared/default_train.trf")
inactiveLabelModel.lods[2] = railModel(nil).lods[1]
inactiveLabelModel.lods[3] = {
	node = { name = "RootNode", transf = identity() },
}
inactiveLabelModel.metadata.seats = nil
inactiveLabelModel.metadata.lightSources = nil
inactiveLabelModel.metadata.labelList = {
	labels = { { childId = "", filter = "NUMBER" } },
}
inactiveLabelModel.metadata.transformatorConfig.skipFromLod = 1
inactiveLabelModel.metadata.swayingWaying = { skipFromLod = 1 }
modelModifier.modify("example::/vehicle/train/inactive_label_anchor.mdl", inactiveLabelModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
local inactiveLabelSway = childNamed(inactiveLabelModel.lods[2].node, constants.SWAY_NODE)
assertEqual(type(inactiveLabelSway), "table", "inactive LOD keeps the retargeted label anchor")
assertEqual(inactiveLabelSway.animations, nil, "inactive label anchor is not animated")
local emptyLodLabelSway = childNamed(inactiveLabelModel.lods[3].node, constants.SWAY_NODE)
assertEqual(type(emptyLodLabelSway), "table", "empty inactive LOD keeps a root motion anchor for labels")
assertEqual(emptyLodLabelSway.animations, nil, "empty LOD label anchor is not animated")
assertEqual(
	type(descendantNamed(emptyLodLabelSway, constants.SWAY_CONTENT_NODE)),
	"table",
	"empty inactive LOD exposes the retargeted label node"
)
assertEqual(
	inactiveLabelModel.metadata.labelList.labels[1].childId,
	constants.SWAY_CONTENT_NODE,
	"default root label targets the cross-LOD content anchor"
)

local invalidInheritedLodModel = railModel("::/vehicle/train/shared/default_train.trf")
invalidInheritedLodModel.lods[2] = railModel(nil).lods[1]
invalidInheritedLodModel.metadata.transformatorConfig.skipFromLod = 0 / 0
local invalidInheritedLodWarnings = #warnings
modelModifier.modify("example::/vehicle/train/invalid_inherited_lod.mdl", invalidInheritedLodModel, {
	intensity = 1.0,
	curveLeanIntensity = 1.0,
})
assertEqual(
	type(childNamed(invalidInheritedLodModel.lods[2].node, constants.SWAY_NODE)),
	"table",
	"invalid inherited LOD limit safely falls back to all LODs"
)
assertEqual(
	invalidInheritedLodModel.metadata.transformatorConfig.skipFromLod,
	2,
	"invalid inherited LOD limit is normalised for the transformator"
)
assertEqual(#warnings, invalidInheritedLodWarnings + 1, "invalid inherited LOD limit is logged once")

local singleBodyModel = railModel("::/vehicle/train/shared/default_train.trf")
singleBodyModel.lods[1].node.mesh = nil
singleBodyModel.lods[1].node.materials = nil
singleBodyModel.lods[1].node.children = {
	{ name = "body", mesh = "body.msh", transf = identity() },
	{ name = "glass", mesh = "glass.msh", transf = identity() },
	{
		name = "bogie_group",
		transf = identity(),
		children = {
			{ name = "bogie", mesh = "bogie.msh", transf = identity() },
			{ name = "wheel", mesh = "wheel.msh", transf = identity() },
		},
	},
}
singleBodyModel.metadata.railVehicle.config = {
	axles = { "wheel" },
	fakeBogies = {
		{},
		{},
		{
			{ group = "body", position = 8.98, offset = 0 },
			{ group = "body", position = -8.98, offset = 0 },
		},
	},
}
modelModifier.modify("example::/vehicle/waggon/single_body.mdl", singleBodyModel, {
	intensity = 1.0,
})
local singleBodyRoot = singleBodyModel.lods[1].node
local singleBodySway = childNamed(singleBodyRoot, constants.SWAY_NODE)
local singleBodyContent = descendantNamed(singleBodySway, constants.SWAY_CONTENT_NODE)
assertEqual(childNamed(singleBodyRoot, "bogie_group").name, "bogie_group", "single-body axles stay fixed")
assertEqual(singleBodyContent.children[1].name, "body", "single-body shell receives sway")
assertEqual(singleBodyContent.children[2].name, "glass", "single-body fixtures receive sway")
assertEqual(
	singleBodyModel.metadata.railVehicle.config.fakeBogies[3][1].group,
	constants.SWAY_NODE,
	"single-body engine placement targets the animated wrapper"
)

do
	local function boxcarRoot(wrapperDepth)
		local root = { name = "RootNode", transf = identity() }
		local container = root
		for wrapperIndex = 1, wrapperDepth do
			local wrapper = {
				name = "compat_" .. wrapperIndex,
				transf = identity(),
				animations = { cant = { type = "FILE_REF", params = { id = "cant.ani" } } },
			}
			container.children = { wrapper }
			container = wrapper
		end
		return root, container
	end
	for wrapperDepth = 0, 2 do
		local boxcar = railModel("::/vehicle/train/shared/default_train.trf")
		boxcar.metadata.transformatorConfig.skipFromLod = 2
		boxcar.metadata.seats = nil
		boxcar.metadata.lightSources = nil
		boxcar.metadata.railVehicle.config = {
			axles = { "w1", "w2", "w3", "w4" },
			fakeBogies = {
				{},
				{},
				{
					{ group = "body", position = 4.98392, offset = 0 },
					{ group = "body", position = -4.98392, offset = 0 },
				},
			},
		}
		local containers = {}
		local doorsByLod = {}
		for lodIndex = 1, 2 do
			local root, container = boxcarRoot(wrapperDepth)
			container.children = { { name = "body", mesh = "body.msh", transf = identity() } }
			for bogieIndex = 1, 2 do
				container.children[#container.children + 1] = {
					name = "b" .. bogieIndex .. "_grp",
					transf = identity(),
					children = {
						{ name = "w" .. (bogieIndex * 2 - 1), mesh = "wheel.msh", transf = identity() },
						{ name = "w" .. (bogieIndex * 2), mesh = "wheel.msh", transf = identity() },
					},
				}
			end
			local doors = {}
			for _, side in ipairs({ "lft", "rgt" }) do
				local door = {
					name = "d_" .. side,
					mesh = "door.msh",
					transf = identity(),
					animations = {
						open_all_doors = { type = "FILE_REF", params = { id = "open_" .. side .. ".ani" } },
						close_all_doors = { type = "FILE_REF", params = { id = "close_" .. side .. ".ani" } },
					},
				}
				container.children[#container.children + 1] = door
				doors[#doors + 1] = door
			end
			boxcar.lods[lodIndex] = { node = root }
			containers[lodIndex] = container
			doorsByLod[lodIndex] = doors
		end
		local inactiveRoot, inactiveContainer = boxcarRoot(wrapperDepth)
		inactiveContainer.children = { { name = "body", transf = identity(), mesh = "distant.msh" } }
		boxcar.lods[3] = { node = inactiveRoot }
		modelModifier.modify("example::/vehicle/waggon/boxcar_1930_wrapped_" .. wrapperDepth .. ".mdl", boxcar, {
			intensity = 1.0,
		})
		local suffix = wrapperDepth > 0 and "_compat_" .. wrapperDepth or ""
		for lodIndex, container in ipairs(containers) do
			local sway = childNamed(container, constants.SWAY_NODE .. suffix)
			assertEqual(type(sway), "table", "single-body sway stays inside earlier wrappers")
			local content = descendantNamed(sway, constants.SWAY_CONTENT_NODE .. suffix)
			assertEqual(childNamed(content, "body").mesh, "body.msh", "boxcar body shares the motion container")
			for _, door in ipairs(doorsByLod[lodIndex]) do
				assertEqual(
					childNamed(content, door.name),
					door,
					"sibling doors share the body's sway, pitch, and heave"
				)
				assertEqual(
					door.animations.open_all_doors.params.id,
					"open_" .. door.name:sub(3) .. ".ani",
					"door opening is preserved"
				)
				assertEqual(
					door.animations.close_all_doors.params.id,
					"close_" .. door.name:sub(3) .. ".ani",
					"door closing is preserved"
				)
			end
			assertEqual(type(childNamed(container, "b1_grp")), "table", "front bogie remains outside body motion")
			assertEqual(type(childNamed(container, "b2_grp")), "table", "rear bogie remains outside body motion")
			if wrapperDepth > 0 then
				assertEqual(container.animations.cant.params.id, "cant.ani", "earlier wrapper animation is preserved")
			end
		end
		assertEqual(
			boxcar.metadata.railVehicle.config.fakeBogies[3][1].group,
			constants.SWAY_NODE .. suffix,
			"body placement follows the shared motion container"
		)
		local inactiveSway = childNamed(inactiveContainer, constants.SWAY_NODE .. suffix)
		assertEqual(type(inactiveSway), "table", "axle-free inactive LOD retains its placement anchor")
		assertEqual(inactiveSway.animations, nil, "inactive boxcar LOD receives no motion")
		assertEqual(descendantNamed(inactiveSway, "body").mesh, "distant.msh", "inactive boxcar mesh is preserved")
	end
end

do
	local function steamLod(engineGroupName, tenderGroupName)
		return {
			node = {
				name = "RootNode",
				transf = identity(),
				children = {
					{
						name = engineGroupName,
						transf = identity(),
						children = {
							{ name = "engine_body", mesh = "engine.msh", transf = identity() },
							{ name = "engine_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
					{
						name = tenderGroupName,
						transf = identity(),
						children = {
							{ name = "tender_body", mesh = "tender.msh", transf = identity() },
							{ name = "tender_axle", mesh = "wheel.msh", transf = identity() },
						},
					},
				},
			},
		}
	end

	local steamModel = railModel("::/vehicle/train/shared/default_train.trf")
	steamModel.lods = {
		steamLod("engine_group", "tender_group"),
		steamLod("engine_lod1", "tender_lod1"),
		{ node = { name = "RootNode", transf = identity(), mesh = "distant_steam.msh" } },
	}
	steamModel.metadata.transformatorConfig.skipFromLod = 1
	steamModel.metadata.railVehicle.config = {
		axles = { "engine_axle", "tender_axle" },
		fakeBogies = {
			{},
			{},
			{
				{ group = "engine_group", position = 5, offset = 0 },
				{ group = "tender_group", position = -5, offset = 0 },
			},
		},
	}
	modelModifier.modify("example::/vehicle/train/steam.mdl", steamModel, {
		intensity = 1.0,
	})
	local steamRoot = steamModel.lods[1].node
	assertEqual(childNamed(steamRoot, constants.SWAY_NODE), nil, "multi-part steam roots remain fixed")
	local engineGroup = childNamed(steamRoot, "engine_group")
	local tenderGroup = childNamed(steamRoot, "tender_group")
	local engineSway = childNamed(engineGroup, constants.SWAY_NODE .. "_engine_group")
	local tenderSway = childNamed(tenderGroup, constants.SWAY_NODE .. "_tender_group")
	assertEqual(
		#steamModel.metadata.transformatorConfig.params.swayingWaying.sections,
		0,
		"renamed active-LOD groups prevent automatic section inference"
	)
	assertEqual(childNamed(engineGroup, "engine_axle").name, "engine_axle", "engine axle stays fixed")
	assertEqual(
		descendantNamed(engineSway, constants.SWAY_CONTENT_NODE .. "_engine_group").children[1].name,
		"engine_body",
		"engine body receives sway"
	)
	assertEqual(childNamed(tenderGroup, "tender_axle").name, "tender_axle", "tender axle stays fixed")
	assertEqual(
		descendantNamed(tenderSway, constants.SWAY_CONTENT_NODE .. "_tender_group").children[1].name,
		"tender_body",
		"tender body receives sway"
	)
	assertEqual(
		type(descendantNamed(engineSway, constants.ROLL_NODE .. "_engine_group").animations[constants.SWAY_ANIMATION]),
		"table",
		"renamed engine groups retain the shared sway channel"
	)
	assertEqual(
		type(descendantNamed(tenderSway, constants.ROLL_NODE .. "_tender_group").animations[constants.SWAY_ANIMATION]),
		"table",
		"renamed tender groups retain the shared sway channel"
	)
	assertEqual(
		steamModel.metadata.railVehicle.config.fakeBogies[3][1].group,
		"engine_group",
		"engine placement remains on its authored group"
	)
	assertEqual(
		steamModel.metadata.railVehicle.config.fakeBogies[3][2].group,
		"tender_group",
		"tender placement remains on its authored group"
	)
	local steamLod1Root = steamModel.lods[2].node
	local engineLod1 = childNamed(steamLod1Root, "engine_lod1")
	local tenderLod1 = childNamed(steamLod1Root, "tender_lod1")
	assertEqual(
		type(childNamed(engineLod1, constants.SWAY_NODE .. "_engine_lod1").animations),
		"table",
		"renamed second-LOD engine body receives active sway"
	)
	assertEqual(
		type(childNamed(tenderLod1, constants.SWAY_NODE .. "_tender_lod1").animations),
		"table",
		"renamed second-LOD tender body receives active sway"
	)
	assertEqual(steamModel.metadata.transformatorConfig.skipFromLod, 2, "steam locomotives receive two active LODs")
	assertEqual(childNamed(steamModel.lods[3].node, constants.SWAY_NODE), nil, "distant steam LOD remains untouched")
end

local sameSwayNode = swayNode
modelModifier.modify("example::/vehicle/train/default.mdl", defaultModel, {
	intensity = 2.0,
	curveLeanIntensity = 0,
})
assertEqual(defaultRoot.children[1], sameSwayNode, "model injection is idempotent")

local realTrackCantTransformator = "devers_1::/vehicle/train/devers/devers_train.trf"
local encodedCantRest = {}
moduleOverrides["devers_1::/vehicle/train/devers/devers_core.lua"] = {
	encodeRest = function(nodeCount, poses)
		encodedCantRest[#encodedCantRest + 1] = { nodeCount = nodeCount, poses = poses }
		return "refreshed:" .. nodeCount
	end,
}
local cantFirstModel = railModel(realTrackCantTransformator)
cantFirstModel.lods[1].node.mesh = nil
cantFirstModel.lods[1].node.materials = nil
cantFirstModel.lods[1].node.children = {
	{
		name = "devers_roulis",
		transf = identity(),
		animations = { devers_roll = {} },
		children = {
			{ name = "cant_body", mesh = "body.msh", transf = identity() },
			{ name = "cant_axle", mesh = "wheel.msh", transf = identity() },
		},
	},
}
cantFirstModel.metadata.railVehicle.config = {
	axles = { "cant_axle" },
	fakeBogies = {
		{},
		{},
		{ { group = "devers_roulis", position = 0, offset = 0 } },
	},
}
cantFirstModel.metadata.transformatorConfig.params = {
	devers_rest1 = "stale",
	devers_trf = "custom.trf",
}
modelModifier.modify("example::/vehicle/train/cant_first.mdl", cantFirstModel, {
	intensity = 1.0,
})
assertEqual(#encodedCantRest, 1, "reverse-order Real Track Cant data is re-encoded")
assertEqual(encodedCantRest[1].nodeCount, 8, "cant data uses the final node hierarchy")
assertNear(encodedCantRest[1].poses[4][15], 1.0, 0.000001, "cant data includes the inserted sway pivot transform")
assertNear(encodedCantRest[1].poses[6][15], 0.0, 0.000001, "cant data includes the sway counter-transform")
assertEqual(
	cantFirstModel.metadata.transformatorConfig.params.devers_rest1,
	"refreshed:8",
	"stale Real Track Cant placement data is replaced"
)
assertEqual(
	cantFirstModel.metadata.transformatorConfig.params.devers_trf,
	"custom.trf",
	"Real Track Cant original-transformator parameters are preserved"
)
assertEqual(
	cantFirstModel.metadata.transformatorConfig.params.swayingWaying.originalTransformator,
	realTrackCantTransformator,
	"reverse-order wrapper retains the Real Track Cant transformator"
)

local cantFirstRootLabelModel = railModel(realTrackCantTransformator)
cantFirstRootLabelModel.lods[1].node.mesh = nil
cantFirstRootLabelModel.lods[1].node.materials = nil
cantFirstRootLabelModel.lods[1].node.children = {
	{
		name = "devers_roulis",
		transf = identity(),
		animations = { devers_roll = {} },
		children = {
			{ name = "cant_body", mesh = "body.msh", transf = identity() },
			{ name = "cant_axle", mesh = "wheel.msh", transf = identity() },
		},
	},
}
cantFirstRootLabelModel.lods[2] = {
	node = { name = "RootNode", transf = identity() },
}
cantFirstRootLabelModel.metadata.seats = nil
cantFirstRootLabelModel.metadata.lightSources = nil
cantFirstRootLabelModel.metadata.labelList = {
	labels = { { childId = "", filter = "NUMBER" } },
}
cantFirstRootLabelModel.metadata.railVehicle.config = {
	axles = { "cant_axle" },
	fakeBogies = { {}, {}, {} },
}
cantFirstRootLabelModel.metadata.transformatorConfig.skipFromLod = 1
cantFirstRootLabelModel.metadata.swayingWaying = { skipFromLod = 1 }
modelModifier.modify("example::/vehicle/train/cant_first_root_label.mdl", cantFirstRootLabelModel, {
	intensity = 1.0,
})
local cantLabelTarget = constants.SWAY_CONTENT_NODE .. "_devers_roulis"
assertEqual(
	cantFirstRootLabelModel.metadata.labelList.labels[1].childId,
	cantLabelTarget,
	"default labels follow the sole body wrapper below an earlier cant wrapper"
)
assertEqual(
	type(descendantNamed(cantFirstRootLabelModel.lods[1].node, cantLabelTarget)),
	"table",
	"cant-first active LOD contains the selected label target"
)
assertEqual(
	type(descendantNamed(cantFirstRootLabelModel.lods[2].node, cantLabelTarget)),
	"table",
	"cant-first empty LOD contains the selected label target"
)

do
	local model = railModel(realTrackCantTransformator)
	local root = model.lods[1].node
	root.mesh, root.materials = nil, nil
	root.children = {
		{
			name = "devers_roulis",
			transf = identity(),
			animations = { devers_roll = {} },
			children = {
				{ name = "body", mesh = "body.msh", transf = identity() },
				{ name = "axle", mesh = "wheel.msh", transf = identity() },
			},
		},
	}
	local farContainer = { name = "devers_roulis", transf = identity(), animations = { devers_roll = {} } }
	farContainer.transf[13] = 3
	model.lods[2] = { node = { name = "RootNode", transf = identity(), children = { farContainer } } }
	model.metadata.seats, model.metadata.lightSources, model.metadata.cameraConfig = nil, nil, nil
	model.metadata.labelList = { labels = { { childId = "devers_roulis" } } }
	model.metadata.railVehicle.config = { axles = { "axle" }, fakeBogies = { {}, {}, {} } }
	model.metadata.transformatorConfig.skipFromLod = 1
	model.metadata.swayingWaying = { skipFromLod = 1 }
	modelModifier.modify("example::/vehicle/train/cant_empty_named_far.mdl", model, { intensity = 1 })
	assert(
		model.metadata.transformatorConfig.params.swayingWaying,
		"empty distant attachments do not prevent safe sway"
	)
	local target = model.metadata.labelList.labels[1].childId
	assertEqual(target, constants.SWAY_CONTENT_NODE .. "_devers_roulis", "the active attachment remains authoritative")
	assert(descendantNamed(root, target), "the active attachment is retained")
	local anchor =
		assert(descendantNamed(farContainer, target), "the distant attachment stays within its authored frame")
	assertEqual(
		descendantNamed(farContainer, constants.SWAY_NODE .. "_devers_roulis").animations,
		nil,
		"distant attachment anchors do not enable procedural motion"
	)
	assertNear(farContainer.transf[13], 3, 1e-7, "the authored distant placement is retained")
	assertNear(
		anchor.transf[15] + descendantNamed(farContainer, constants.SWAY_NODE .. "_devers_roulis").transf[15],
		0,
		1e-7,
		"distant attachment counter-transforms cancel"
	)
end

local tiltingModel = railModel("/vehicle/train/shared/tilting_train.trf")
modelModifier.modify("example::/vehicle/train/tilting.mdl", tiltingModel, {
	intensity = 1.0,
})
assertEqual(
	tiltingModel.metadata.transformatorConfig.transformator.name,
	constants.TILTING_TRANSFORMATOR,
	"tilting trains retain their native tilt wrapper"
)

local customModel = railModel("custom.trf")
modelModifier.modify("example::/vehicle/train/custom.mdl", customModel, {
	intensity = 0.5,
	curveLeanIntensity = 0,
})
assertEqual(
	customModel.metadata.transformatorConfig.transformator.name,
	constants.ANY_TRANSFORMATOR,
	"custom transformators use the generic wrapper"
)
assertEqual(
	customModel.metadata.transformatorConfig.params.swayingWaying.originalTransformator,
	"custom.trf",
	"custom transformator name is retained"
)
assertEqual(
	customModel.metadata.transformatorConfig.params.swayingWaying.modelFile,
	"example::/vehicle/train/custom.mdl",
	"custom transformator owner is retained"
)

local authoredSwayModel = railModel("custom.trf")
authoredSwayModel.metadata.transformatorConfig.skipFromLod = 1
authoredSwayModel.lods[1].node.children = {
	{
		name = "engine_sway",
		transf = identity(),
		animations = {
			sway = { params = { id = constants.BASE_TILT_ANIMATION }, type = "FILE_REF" },
		},
	},
	{
		name = "tender_sway",
		transf = identity(),
		animations = {
			tender_sway = { params = { id = constants.BASE_TILT_ANIMATION }, type = "FILE_REF" },
		},
	},
}
local authoredRoot = authoredSwayModel.lods[1].node
local authoredConfig = authoredSwayModel.metadata.transformatorConfig
modelModifier.modify("example::/vehicle/train/authored_sway.mdl", authoredSwayModel, {
	intensity = 1.0,
})
local authoredEngine = childNamed(authoredRoot, "engine_sway")
local authoredTender = childNamed(authoredRoot, "tender_sway")
assertEqual(authoredSwayModel.lods[1].node, authoredRoot, "author-owned sway hierarchy is untouched")
assertEqual(
	authoredSwayModel.metadata.transformatorConfig,
	authoredConfig,
	"author-owned sway configuration is untouched"
)
assertEqual(authoredConfig.transformator.name, "custom.trf", "author-owned sway retains its custom transformator")
assertEqual(
	childNamed(authoredRoot, constants.SWAY_NODE),
	nil,
	"authored engine and tender pivots do not receive a generic outer wrapper"
)
assertEqual(
	type(authoredEngine.animations[constants.AUTHORED_SWAY_ANIMATION]),
	"table",
	"authored engine pivot retains its transformator channel"
)
assertEqual(
	type(authoredTender.animations[constants.AUTHORED_TENDER_SWAY_ANIMATION]),
	"table",
	"authored tender pivot retains its transformator channel"
)
assertEqual(authoredConfig.params.swayingWaying, nil, "author-owned sway receives no Swaying W parameters")

local cantAuthoredSwayModel = railModel("devers_1::/vehicle/train/devers/devers_any.trf")
cantAuthoredSwayModel.lods[1].node.children = authoredRoot.children
local cantAuthoredRoot = cantAuthoredSwayModel.lods[1].node
local cantAuthoredConfig = cantAuthoredSwayModel.metadata.transformatorConfig
modelModifier.modify("example::/vehicle/train/cant_authored_sway.mdl", cantAuthoredSwayModel, {
	intensity = 1.0,
})
assertEqual(
	cantAuthoredSwayModel.lods[1].node,
	cantAuthoredRoot,
	"Real Track Cant hierarchy around author-owned sway is untouched"
)
assertEqual(
	cantAuthoredSwayModel.metadata.transformatorConfig,
	cantAuthoredConfig,
	"Real Track Cant configuration around author-owned sway is untouched"
)
assertEqual(
	cantAuthoredConfig.transformator.name,
	"devers_1::/vehicle/train/devers/devers_any.trf",
	"Real Track Cant retains ownership of authored sway models"
)

local unrelatedSwayModel = railModel("custom.trf")
local unrelatedSwayNode = {
	name = "unrelated_sway",
	transf = identity(),
	animations = {
		sway = { params = { id = "example::/vehicle/shared/ani/door.ani" }, type = "FILE_REF" },
	},
}
unrelatedSwayModel.lods[1].node.children = {
	unrelatedSwayNode,
	{
		name = "tender_sway",
		transf = identity(),
		animations = {
			tender_sway = { params = { id = constants.BASE_TILT_ANIMATION }, type = "FILE_REF" },
		},
	},
}
modelModifier.modify("example::/vehicle/train/unrelated_sway.mdl", unrelatedSwayModel, {
	intensity = 1.0,
})
assertEqual(
	type(unrelatedSwayNode.animations.sway),
	"table",
	"unrelated animation names are not adopted as authored body sway"
)
assertEqual(
	unrelatedSwayModel.metadata.transformatorConfig.transformator.name,
	constants.ANY_TRANSFORMATOR,
	"authored sway requires both legacy tilt channels"
)
assertEqual(
	type(childNamed(unrelatedSwayModel.lods[1].node, constants.SWAY_NODE)),
	"table",
	"unrelated sway animation names still receive generic sway"
)

local tramModel = railModel(nil, "TRAM")
modelModifier.modify("example::/vehicle/tram/tram.mdl", tramModel, {
	intensity = 1.0,
})
assertEqual(
	tramModel.metadata.transformatorConfig.transformator.name,
	constants.TRAM_TRANSFORMATOR,
	"trams use the tram wrapper"
)

local mirroredModel = railModel(nil)
mirroredModel.lods[1].node.transf[1] = -1
modelModifier.modify("example::/vehicle/train/mirrored.mdl", mirroredModel, {
	intensity = 1.0,
})
assertEqual(
	mirroredModel.metadata.transformatorConfig.params.swayingWaying.axisReversed,
	true,
	"reversed model roots invert sway"
)

local roadModel = railModel(nil, "ROAD")
roadModel.metadata.railVehicle = nil
local roadRoot = roadModel.lods[1].node
modelModifier.modify("example::/vehicle/bus/bus.mdl", roadModel, {
	intensity = 1.0,
})
assertEqual(roadModel.lods[1].node, roadRoot, "road vehicles are untouched")
assertEqual(roadRoot.children[1].name, "bogie", "road vehicle hierarchy is untouched")

local warningCount = #warnings
local emptyModel = railModel(nil)
emptyModel.lods[1].node.children = {}
emptyModel.lods[1].node.mesh = nil
emptyModel.lods[1].node.materials = nil
modelModifier.modify("example::/vehicle/train/empty.mdl", emptyModel, {
	intensity = 1.0,
})
assertEqual(emptyModel.metadata.transformatorConfig, nil, "unsupported models are left unchanged")
assertEqual(#warnings, warningCount + 1, "unsupported models are logged")

for _, kind in ipairs({ "train", "tilting", "any" }) do
	local name = "cayde_devers_1::/cayde_devers/train/cant_" .. kind .. ".trf"
	local model = railModel(name)
	local root, originalConfig = model.lods[1].node, model.metadata.transformatorConfig
	originalConfig.params.cc_parts = "2:0"
	originalConfig.params.cc_pinfo = "2|0,0,0"
	local warningCount = #warnings
	modelModifier.modify("example::/cayde_first_" .. kind .. ".mdl", model, { intensity = 1 })
	assertEqual(model.lods[1].node, root, "unsafe cant order preserves root identity")
	assertEqual(root.mesh, "root_mesh.msh", "unsafe cant order leaves geometry in place")
	assertEqual(#root.children, 1, "unsafe cant order introduces no nodes")
	assertEqual(originalConfig.transformator.name, name, "Cayde retains its transformator")
	assertEqual(originalConfig.params.cc_parts, "2:0", "Cayde retains its valid part indices")
	assertEqual(originalConfig.params.cc_pinfo, "2|0,0,0", "Cayde retains its placement metadata")
	assertEqual(originalConfig.params.swayingWaying, nil, "unsafe cant order installs no sway")
	assertEqual(model.metadata.seats[1].group, "RootNode", "attachments remain unchanged on rollback")
	assertEqual(#warnings, warningCount + 1, "unsafe cant order reports a diagnostic")
	assert(warnings[#warnings]:find("Cayde's Track Cant is incompatible with Swaying Waying", 1, true))
end

print("Model adaptation checks passed")
