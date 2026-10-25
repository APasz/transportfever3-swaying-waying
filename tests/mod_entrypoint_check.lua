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
local registeredModifier = nil
_G.getCurrentModId = function()
	return constants.MOD_ID
end
_G.addModifier = function(kind, modifier)
	assertEqual(kind, "loadModel", "mod registers a model modifier")
	registeredModifier = modifier
end
dofile("content/mod.script.lua")
local runFn = data().runFn
runFn({}, {}, {
	[constants.MOD_ID] = {
		[constants.ENABLED_PARAM_KEY] = 1,
		[constants.INTENSITY_PARAM_KEY] = 4,
	},
}, nil)
assertEqual(registeredModifier, nil, "disabled setting does not register the modifier")
assertEqual(#messages, 1, "disabled startup emits one settings message")
assert(messages[1]:find("Startup: enabled=false", 1, true), "disabled startup is explicit")

runFn({}, {}, {
	[constants.MOD_ID] = {
		[constants.ENABLED_PARAM_KEY] = 2,
		[constants.INTENSITY_PARAM_KEY] = 4,
	},
}, nil)
local defaultSettingsModel = railModel(nil)
registeredModifier("example::/vehicle/train/default_settings.mdl", defaultSettingsModel)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.rollBalance,
	1.0,
	"omitted roll balance defaults to neutral"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.curveLeanIntensity,
	1.0,
	"missing curve-lean intensity uses the default for existing saves"
)
assertEqual(
	(
		defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.pitchBalance > 0
		or defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.heaveBalance > 0
	),
	true,
	"default balances enable secondary motion"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.pitchBalance,
	1.0,
	"omitted pitch balance defaults to neutral"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.heaveBalance,
	1.0,
	"omitted heave balance defaults to neutral"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.trackInfluence,
	1.0,
	"omitted track influence defaults to fully enabled"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.vehicleVariation,
	1.0,
	"omitted vehicle variation defaults to normal"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.samplingDistance,
	constants.DEFAULT_SAMPLE_DISTANCE,
	"omitted sampling interval uses the current default in existing saves"
)
assertEqual(
	defaultSettingsModel.metadata.transformatorConfig.params.swayingWaying.settings.curveSamplingDistance,
	1,
	"omitted curve sampling interval defaults to one metre in existing saves"
)

runFn({}, {}, {
	[constants.MOD_ID] = {
		[constants.ENABLED_PARAM_KEY] = 2,
		[constants.INTENSITY_PARAM_KEY] = 8,
		[constants.ROLL_BALANCE_PARAM_KEY] = 3,
		[constants.PITCH_BALANCE_PARAM_KEY] = 3,
		[constants.HEAVE_BALANCE_PARAM_KEY] = 7,
		[constants.CURVE_LEAN_INTENSITY_PARAM_KEY] = 7,
		[constants.CURVE_SAMPLING_DISTANCE_PARAM_KEY] = 4,
		[constants.TRACK_INFLUENCE_PARAM_KEY] = 1,
		[constants.SAMPLING_DISTANCE_PARAM_KEY] = 2,
		[constants.VEHICLE_VARIATION_PARAM_KEY] = 5,
	},
}, nil)
assertEqual(type(registeredModifier), "function", "enabled setting registers the modifier")
local startup = messages[#messages]
for _, detail in ipairs({
	"Startup: enabled=true",
	"intensity=2",
	"rollBalance=0.5",
	"curveSamplingDistance=5",
	"modelDiagnostics=false",
	"debug=false",
	"curvatureProbe=false",
	"lodProbe=false",
	"disabled motion=[",
}) do
	assert(startup:find(detail, 1, true), "startup includes " .. detail)
end
local configuredModel = railModel(nil)
registeredModifier("example::/vehicle/train/configured.mdl", configuredModel)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.rollBalance,
	0.5,
	"selected roll balance is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.intensity,
	2.0,
	"selected intensity is applied"
)
assertEqual(
	(
		configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.pitchBalance > 0
		or configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.heaveBalance > 0
	),
	true,
	"nonzero pitch and heave balances enable secondary motion"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.pitchBalance,
	0.5,
	"selected pitch balance is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.heaveBalance,
	1.5,
	"selected heave balance is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.curveLeanIntensity,
	1.5,
	"selected curve-lean intensity is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.trackInfluence,
	0.0,
	"selected track influence is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.vehicleVariation,
	2.0,
	"selected vehicle variation is applied"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.samplingDistance,
	1,
	"the selected sampling interval reaches model runtime settings"
)
assertEqual(
	configuredModel.metadata.transformatorConfig.params.swayingWaying.settings.curveSamplingDistance,
	5,
	"the selected curve sampling interval reaches model runtime settings"
)

do
	local model = railModel("::/vehicle/train/shared/default_train.trf")
	local originalMessage = log.message
	log.message = function()
		error("injected diagnostic failure")
	end
	local returned = registeredModifier("example::/vehicle/train/rollback_diagnostics.mdl", model)
	log.message = originalMessage
	assertEqual(returned, model, "failure returns the original model")
	assert(childNamed(model.lods[1].node, constants.SWAY_NODE), "reporting failure does not undo a safe adaptation")
	assert(model.metadata.transformatorConfig.params.swayingWaying, "reporting failure retains runtime configuration")
	assert(warnings[#warnings]:find("Could not report prepared model", 1, true), "reporting failure is identified")

	model = railModel("::/vehicle/train/shared/default_train.trf")
	local root, metadata = model.lods[1].node, model.metadata
	local children = root.children
	local originalConfig = metadata.transformatorConfig
	local originalParams = originalConfig.params
	setmetatable(originalParams, {
		__newindex = function(target, key, value)
			if key == constants.RUNTIME_PARAM then
				error("injected configuration failure")
			end
			rawset(target, key, value)
		end,
	})
	registeredModifier("example::/vehicle/train/rollback_configuration.mdl", model)
	assertEqual(metadata.transformatorConfig, originalConfig, "late rollback preserves configuration identity")
	assertEqual(originalConfig.params, originalParams, "late rollback preserves parameter identity")
	assertEqual(originalParams.preserved, 42, "late rollback retains existing parameters")
	assertEqual(originalParams.swayingWaying, nil, "late rollback removes already-written parameters")
	assertEqual(root.children, children, "late rollback restores the original hierarchy")
	assertEqual(metadata.seats[1].group, "RootNode", "late rollback restores retargeted references")
	setmetatable(originalParams, nil)
	registeredModifier("example::/vehicle/train/retry_after_rollback.mdl", model)
	assertEqual(
		type(childNamed(root, constants.SWAY_NODE)),
		"table",
		"rolled-back models can be adapted successfully later"
	)
end

do
	runFn({}, {}, { just_more_weather_1 = {} }, nil)
	local model = railModel("::/vehicle/train/shared/default_train.trf")
	model.metadata.snowPowderCompatibility = true
	model.metadata.snowPowderFailure = true
	local config = model.metadata.transformatorConfig
	registeredModifier("example::/vehicle/train/rollback_compatibility.mdl", model)
	assertEqual(
		config.transformator.name,
		"::/vehicle/train/shared/default_train.trf",
		"failing compatibility adapters restore the original transformator"
	)
	assertEqual(model.metadata.foreignData, nil, "failing compatibility adapters restore arbitrary metadata changes")
	assertEqual(model.lods[1].node.mesh, "root_mesh.msh", "failing compatibility adapters retain the original body")
end

local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua")
local byId = {}
for _, definition in ipairs(settings.definitions) do
	byId[definition.id] = definition
end

do
	local sway = assert(byId.enabled)
	assertEqual(sway.uiType, "ComboBox", "sway modes use one dropdown")
	assertEqual(sway.labels[sway.defaultIndex], "On", "ordinary sway remains the default")
	local modes = {
		{ label = "Off", enabled = false, speedDependent = true },
		{ label = "On", enabled = true, speedDependent = true },
		{ label = "Speedless Sway", enabled = true, speedDependent = false },
	}
	assertEqual(#sway.labels, #modes, "Speedless Sway appends to the saved Off/On positions")
	for index, expected in ipairs(modes) do
		local saved = { [constants.MOD_ID] = { [sway.key] = index, [constants.CAMERAS_PARAM_KEY] = 4 } }
		local enabled, config = settings.read(saved)
		assertEqual(sway.labels[index], expected.label, "saved mode positions retain their meaning")
		assertEqual(enabled, expected.enabled, "both active sway modes enable motion")
		assertEqual(config.speedDependent, expected.speedDependent, "only Speedless Sway bypasses speed scaling")
		registeredModifier = nil
		runFn({}, {}, saved, nil)
		local model = railModel(nil)
		model.metadata.cameraConfig = nil
		model.metadata.seatProvider =
			{ seats = { { crew = true, animation = "driving", group = "RootNode", transf = identity() } } }
		registeredModifier("tests::/sway_mode_" .. index .. ".mdl", model)
		assertEqual(
			#model.metadata.cameraConfig.positions,
			expected.enabled and 2 or 1,
			"camera modes respect sway availability"
		)
		if expected.enabled then
			assertEqual(
				model.metadata.transformatorConfig.params.swayingWaying.settings.speedDependent,
				expected.speedDependent,
				"the selected speed response reaches model runtime settings"
			)
		else
			assertEqual(model.metadata.transformatorConfig, nil, "Off leaves model motion untouched")
		end
	end
	local enabled, defaults = settings.read(nil)
	assertEqual(enabled, true, "missing saved modes retain enabled sway")
	assertEqual(defaults.speedDependent, true, "missing saved modes retain speed scaling")
	for _, invalid in ipairs({ 0, -1, 1.5, 4, 0 / 0, math.huge }) do
		local active, selected = settings.read({ [constants.MOD_ID] = { [sway.key] = invalid } })
		assertEqual(active and selected.speedDependent, true, "invalid saved modes use On")
	end
	for _, invalid in ipairs({ 0, 1, "false", {} }) do
		assert(not pcall(settings.resolve, { speedDependent = invalid }), "speed dependence must be a boolean")
	end
end

do
	local diagnostics = assert(byId.modelDiagnostics)
	assertEqual(diagnostics.uiType, "CheckBox", "model diagnostics use an independent checkbox")
	assertEqual(diagnostics.values[diagnostics.defaultIndex], 0, "model diagnostics default off")
	for index, expected in ipairs({ false, true }) do
		local _, config, detailed = settings.read({ [constants.MOD_ID] = { [diagnostics.key] = index } })
		assertEqual(detailed, expected, "saved model diagnostic positions resolve to booleans")
		assertEqual(config.modelDiagnostics, nil, "diagnostic settings stay outside runtime motion configuration")
	end
	runFn({}, {}, { [constants.MOD_ID] = { [diagnostics.key] = 2 } }, nil)
	local firstDetailed = #messages + 1
	registeredModifier("tests::/ui_diagnostics.mdl", railModel(nil))
	assertEqual(#messages, firstDetailed + 1, "the in-game option adds a LOD report to the model summary")
	assert(messages[#messages]:find(" LOD 0: applied", 1, true), "the in-game option reaches model reporting")
	assertEqual(#verboseMessages, 0, "model diagnostics do not require general debug logging")
	assertEqual(byId.curveLeanEnabled, nil, "curve lean has no separate toggle")
	local curve = assert(byId.curveLeanIntensity)
	assertEqual(curve.labels[1], "Off", "curve lean intensity starts with Off")
	assertEqual(curve.values[1], 0, "Off resolves to zero curve lean intensity")
	assertEqual(curve.values[curve.defaultIndex], 1, "curve lean intensity defaults to 1x")
	for index, intensity in ipairs(curve.values) do
		local _, selected = settings.read({ [constants.MOD_ID] = { [curve.key] = index } })
		assertEqual(selected.curveLeanIntensity, intensity, "each combined slider position resolves to its intensity")
		assertEqual(selected.curveLeanEnabled, nil, "intensity is the only stored curve lean control")
	end
	for _, invalid in ipairs({ -1, 2.1, 0 / 0, math.huge, false }) do
		assert(
			not pcall(settings.resolve, { curveLeanIntensity = invalid }),
			"invalid curve lean intensities fail explicitly"
		)
	end
	for _, invalid in ipairs({ 0, -1, 1.5, #curve.values + 1, 0 / 0, math.huge }) do
		local _, selected = settings.read({ [constants.MOD_ID] = { [curve.key] = invalid } })
		assertEqual(selected.curveLeanIntensity, 1, "invalid saved curve lean positions use the 1x default")
	end
	assertEqual(constants.DEFAULT_SAMPLE_DISTANCE, 5, "track sampling defaults to five metres")
	local cases = dofile("tests/support/sampling_cases.lua")
	for id, default in pairs({ samplingDistance = constants.DEFAULT_SAMPLE_DISTANCE, curveSamplingDistance = 1 }) do
		local sampling = assert(byId[id])
		assertEqual(sampling.values[sampling.defaultIndex], default, "the sampling UI and runtime share their default")
		assertEqual(#sampling.values, #cases, "query-budget checks cover every sampling option")
		for index, option in ipairs(cases) do
			local distance = option.distance
			assertEqual(sampling.values[index], distance, "sampling options match the tested query budgets")
			local _, selected = settings.read({ [constants.MOD_ID] = { [sampling.key] = index } })
			assertEqual(selected[id], distance, "each sampling UI option resolves to its distance")
			assertEqual(
				settings.resolve({ [id] = distance })[id],
				distance,
				"resolved settings preserve every sampling option"
			)
		end
		for _, invalid in ipairs({ -1, 0 / 0, math.huge, 16, false }) do
			assert(not pcall(settings.resolve, { [id] = invalid }), "invalid sampling settings fail explicitly")
		end
		for _, invalid in ipairs({ 0, -1, 1.5, 100, 0 / 0, math.huge }) do
			local _, selected = settings.read({ [constants.MOD_ID] = { [sampling.key] = invalid } })
			assertEqual(selected[id], default, "invalid saved sampling indices use the default")
		end
	end
end

do
	local _, _, _, defaultMode = settings.read(nil)
	assertEqual(defaultMode, "Disabled", "camera additions default off for existing saves")
	local cameraLabels = { "Disabled", "Stable", "Sway", "Both", "Stable + Extra", "Sway + Extra", "Both + Extra" }
	assertEqual(#byId.cameras.labels, #cameraLabels, "Extra camera choices append to the four saved positions")
	for index, mode in ipairs({ "Disabled", "Stable", "Sway", "Both", "Stable", "Sway", "Both" }) do
		local _, motion, _, selected, extra =
			settings.read({ [constants.MOD_ID] = { [constants.CAMERAS_PARAM_KEY] = index } })
		assertEqual(selected, mode, "camera settings resolve to named states")
		assertEqual(extra, index > 4, "Extra coverage is independent of the camera motion mode")
		assertEqual(byId.cameras.labels[index], cameraLabels[index], "camera labels retain the original saved order")
		assertEqual(motion.cameras, nil, "camera settings stay outside runtime motion configuration")
		registeredModifier = nil
		runFn(
			{},
			{},
			{ [constants.MOD_ID] = { [constants.ENABLED_PARAM_KEY] = 1, [constants.CAMERAS_PARAM_KEY] = index } },
			nil
		)
		assertEqual(
			type(registeredModifier) == "function",
			mode == "Stable" or mode == "Both",
			"only stable cameras remain available without sway"
		)
		if registeredModifier then
			local model = railModel(nil)
			model.metadata.cameraConfig = nil
			model.metadata.seatProvider =
				{ seats = { { crew = true, animation = "driving", group = "RootNode", transf = identity() } } }
			registeredModifier("tests::/camera_only.mdl", model)
			assertEqual(#model.metadata.cameraConfig.positions, 1, "stable camera selection reaches the model loader")
			assertEqual(model.metadata.transformatorConfig, nil, "stable camera-only mode leaves sway disabled")
			model = railModel(nil)
			model.metadata.cameraConfig, model.metadata.seats = nil, nil
			registeredModifier("tests::/freight_camera_only.mdl", model)
			assertEqual(
				model.metadata.cameraConfig ~= nil,
				extra,
				"only Extra camera choices add freight views through the model loader"
			)
			assertEqual(model.metadata.transformatorConfig, nil, "freight camera-only mode leaves sway disabled")
		end
	end
end

do
	local weatherModule = "just_more_weather_1::/jmw/neige_poudre.lua"
	local weatherAdapter = moduleOverrides[weatherModule]
	local wagon = dofile("tests/support/wagon_cameras.lua").new({ extras = {} })
	local imports = { just_more_weather_1 = 0, dome_wagon_cameras = 0 }
	_G.ug_require = function(name)
		local namespace = name:match("^(.-)::")
		if imports[namespace] ~= nil then
			imports[namespace] = imports[namespace] + 1
		end
		return harness.require(name)
	end
	local cases = {
		{ name = "absent", installed = false, weather = false, cameras = false },
		{ name = "disabled", installed = true, weather = false, cameras = false },
		{ name = "disabled_own_cameras_off", installed = true, weather = false, cameras = false, cameraMode = 1 },
		{ name = "enabled", installed = true, weather = true, cameras = true },
		{ name = "weather_only", installed = true, weather = true, cameras = false },
		{ name = "cameras_only", installed = true, weather = false, cameras = true },
		{ name = "disabled_after_enabled", installed = true, weather = false, cameras = false },
		{ name = "missing_mod_params", installed = true, weather = false, cameras = false, missingParams = true },
	}
	for _, case in ipairs(cases) do
		moduleOverrides[weatherModule] = case.installed and weatherAdapter or nil
		moduleOverrides["dome_wagon_cameras::/camera_logic.lua"] = case.installed and wagon.logic or nil
		moduleOverrides["dome_wagon_cameras::/camera_positions.lua"] = case.installed and wagon.config or nil
		local params = { [constants.MOD_ID] = { [constants.CAMERAS_PARAM_KEY] = case.cameraMode or 4 } }
		if case.weather then
			params.just_more_weather_1 = {}
		end
		if case.cameras then
			params.dome_wagon_cameras = {}
		end
		local callsBefore, warningsBefore = harness.snowPowderCalls, #warnings
		local weatherImports, cameraImports = imports.just_more_weather_1, imports.dome_wagon_cameras
		runFn({}, {}, not case.missingParams and params or nil, nil)
		local model = railModel("::/vehicle/train/shared/default_train.trf")
		model.metadata.snowPowderCompatibility = true
		registeredModifier("tests::/optional_mods_" .. case.name .. ".mdl", model)
		local runtime = assert(model.metadata.transformatorConfig.params.swayingWaying)
		assertEqual(
			runtime.originalTransformator,
			case.weather and "just_more_weather_1::/vehicle/jmw/jmw_train.trf"
				or "::/vehicle/train/shared/default_train.trf",
			case.name .. ": only enabled weather changes the original transformator"
		)
		assertEqual(harness.snowPowderCalls - callsBefore, case.weather and 1 or 0, case.name .. ": weather activation")
		assertEqual(
			imports.just_more_weather_1 - weatherImports,
			case.weather and 1 or 0,
			case.name .. ": disabled weather helpers are never loaded"
		)
		assertEqual(
			imports.dome_wagon_cameras - cameraImports,
			case.cameras and 2 or 0,
			case.name .. ": disabled camera helpers are never loaded"
		)
		assertEqual(
			model.metadata.metadata.domeWagonCameras ~= nil,
			case.cameras,
			case.name .. ": only enabled camera integration adds overlay metadata"
		)
		assertEqual(#warnings, warningsBefore, case.name .. ": optional mods do not prevent safe sway and cameras")
	end
	moduleOverrides[weatherModule] = weatherAdapter
	moduleOverrides["dome_wagon_cameras::/camera_logic.lua"] = nil
	moduleOverrides["dome_wagon_cameras::/camera_positions.lua"] = nil
	_G.ug_require = harness.require
end

do
	local wagon = dofile("tests/support/wagon_cameras.lua").new({ extras = {} })
	local normalize, layout = wagon.logic.normalizeList, wagon.logic.layout
	local normalizations = 0
	wagon.logic.normalizeList = function(raw)
		normalizations = normalizations + 1
		return normalize(raw)
	end
	wagon.logic.layout = function(metadata, defaults)
		local result = layout(metadata)
		result.default.fov = defaults.fov
		return result
	end
	local logicModule = "dome_wagon_cameras::/camera_logic.lua"
	local positionsModule = "dome_wagon_cameras::/camera_positions.lua"
	moduleOverrides[logicModule] = wagon.logic
	local function startupParams(active)
		local params = { [constants.MOD_ID] = { [constants.CAMERAS_PARAM_KEY] = 4 } }
		if active then
			params.just_more_weather_1, params.dome_wagon_cameras = {}, {}
		end
		return params
	end
	for loadIndex, fov in ipairs({ 65, 75 }) do
		moduleOverrides[positionsModule] = { default = { fov = fov } }
		runFn({}, {}, startupParams(true), nil)
		for modelIndex = 1, 2 do
			local model = railModel("::/vehicle/train/shared/default_train.trf")
			registeredModifier("tests::/reload_" .. loadIndex .. "_" .. modelIndex .. ".mdl", model)
			assertEqual(model.metadata.metadata.domeWagonCameras.default.fov, fov, "new loads refresh camera settings")
		end
		assertEqual(normalizations, loadIndex, "camera settings are normalized once per load")
	end
	local warningsBefore = #warnings
	moduleOverrides[logicModule] = {}
	runFn({}, {}, startupParams(true), nil)
	local model = railModel("::/vehicle/train/shared/default_train.trf")
	registeredModifier("tests::/failed_camera_lookup.mdl", model)
	assert(model.metadata.transformatorConfig.params.swayingWaying, "failed camera lookup preserves sway")
	assertEqual(model.metadata.metadata.domeWagonCameras, nil, "invalid camera APIs cannot publish a layout")
	assertEqual(#warnings, warningsBefore + 1, "failed camera API lookup is reported")
	moduleOverrides[logicModule] = wagon.logic
	runFn({}, {}, startupParams(true), nil)
	model = railModel("::/vehicle/train/shared/default_train.trf")
	registeredModifier("tests::/recovered_camera_lookup.mdl", model)
	assert(model.metadata.metadata.domeWagonCameras, "new loads retry a previously failed camera API lookup")
	for _, active in ipairs({ false, true }) do
		local params = startupParams(active)
		runFn({}, {}, params, nil)
		params.just_more_weather_1 = not active and {} or nil
		params.dome_wagon_cameras = not active and {} or nil
		model = railModel("::/vehicle/train/shared/default_train.trf")
		model.metadata.snowPowderCompatibility = true
		registeredModifier("tests::/startup_snapshot_" .. tostring(active) .. ".mdl", model)
		assertEqual(
			model.metadata.transformatorConfig.params.swayingWaying.originalTransformator,
			active and "just_more_weather_1::/vehicle/jmw/jmw_train.trf" or "::/vehicle/train/shared/default_train.trf",
			"weather activation retains the startup snapshot"
		)
		assertEqual(
			model.metadata.metadata.domeWagonCameras ~= nil,
			active,
			"camera activation retains the startup snapshot"
		)
	end
	moduleOverrides[logicModule], moduleOverrides[positionsModule] = nil, nil
end

print("Mod entry point checks passed")
