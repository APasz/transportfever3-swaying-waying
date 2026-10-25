local harness = dofile("tests/support/harness.lua").new()
local moduleOverrides, warnings = harness.overrides, harness.warnings
local assertions = dofile("tests/assertions.lua")
local assertEqual, assertNear = assertions.equal, assertions.near
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local motion = ug_require("apasz_swaying_waying::/swaying_waying/motion.lua")
local trackResponse = ug_require("apasz_swaying_waying::/swaying_waying/track_response.lua")
local vehicleResponse = ug_require("apasz_swaying_waying::/swaying_waying/vehicle_response.lua")
local curveResponse = ug_require("apasz_swaying_waying::/swaying_waying/curve_response.lua")
local sampledCurveTilt = curveResponse.tilt
curveResponse.tilt = function()
	return 0.75
end
local function setSections(configured, count)
	assert(type(count) == "number" and count < math.huge)
	for index = 1, count do
		configured.sections[index] = configured.sections[index] or { lag = 0, wheelbase = configured.wheelbase }
	end
	for index = #configured.sections, count + 1, -1 do
		configured.sections[index] = nil
	end
end

local transformatorUtil = {
	updateParticleSystemFn = function(_, _, particleSystem)
		particleSystem.fallbackCalls = (particleSystem.fallbackCalls or 0) + 1
	end,
}
local nativeCalls = { train = 0, tilting = 0, tram = 0 }
local function nativeScript(kind, key)
	return {
		[key] = {
			updateFn = function(_, _, output)
				nativeCalls[kind] = nativeCalls[kind] + 1
				output:addAnimationState("native_" .. kind, -1, 1, false, false)
			end,
			updateParticleSystemFn = transformatorUtil.updateParticleSystemFn,
		},
	}
end

local customCalls = { update = 0, particles = 0, emittable = 0, emitted = 0 }
local customOrigin = {
	update = function(capture, _, output)
		assertEqual(capture.marker, "update", "custom update capture is preserved")
		customCalls.update = customCalls.update + 1
		output:addAnimationState("custom", -1, 1, false, false)
	end,
	capture = { marker = "update" },
	particles = function(capture)
		assertEqual(capture.marker, "particles", "custom particle capture is preserved")
		customCalls.particles = customCalls.particles + 1
	end,
	particlesCapture = { marker = "particles" },
	getEmittableModels = function(capture)
		assertEqual(capture.marker, "emittable", "custom model-discovery capture is preserved")
		customCalls.emittable = customCalls.emittable + 1
		return { "example::/random_number.mdl" }
	end,
	getEmittableModelsCapture = { marker = "emittable" },
	computeEmittedModels = function(capture, _, emitter)
		assertEqual(capture.marker, "emitted", "custom model-emission capture is preserved")
		customCalls.emitted = customCalls.emitted + 1
		emitter.forwarded = true
	end,
	computeEmittedModelsCapture = { marker = "emitted" },
}
moduleOverrides["::/scripts/transformator_util.tl"] = transformatorUtil
moduleOverrides["::/vehicle/train/shared/transformator_train.script.tl"] = nativeScript("train", "train")
moduleOverrides["::/vehicle/train/shared/transformator_tiltingTrain.script.tl"] =
	nativeScript("tilting", "tiltingTrain")
moduleOverrides["::/vehicle/tram/shared/transformator_tram.script.tl"] = nativeScript("tram", "tram")

local loadedUpdateCapture = nil
local loadedParticleCapture = nil
local loadedEmittableCapture = nil
local loadedEmittedCapture = nil
local loadedUpdate = function(capture)
	loadedUpdateCapture = capture
end
local loadedParticles = function(capture)
	loadedParticleCapture = capture
end
local loadedGetEmittableModels = function(capture)
	loadedEmittableCapture = capture
	return { "example::/number.mdl" }
end
local loadedComputeEmittedModels = function(capture, _, emitter)
	loadedEmittedCapture = capture
	emitter.loaded = true
end
moduleOverrides["example::/vehicle/train/custom.trf.lua"] = {
	updateScript = {
		fileName = "custom.script@vehicle.updateFn",
		params = { source = "update" },
	},
	updateParticleSystemScript = {
		fileName = "custom.script@vehicle.updateParticleSystemFn",
		params = { source = "particles" },
	},
	getEmittableModelsScript = {
		fileName = "custom.script@vehicle.getEmittableModelsFn",
		params = { source = "emittable" },
	},
	computeEmittedModelsScript = {
		fileName = "custom.script@vehicle.computeEmittedModelsFn",
		params = { source = "emitted" },
	},
}
moduleOverrides["example::/vehicle/train/custom.script.lua"] = {
	vehicle = {
		updateFn = loadedUpdate,
		updateParticleSystemFn = loadedParticles,
		getEmittableModelsFn = loadedGetEmittableModels,
		computeEmittedModelsFn = loadedComputeEmittedModels,
	},
}
local originLoader = dofile("content/swaying_waying/origin_loader.lua")
local loadedOrigin = originLoader.get("custom.trf", "example::/vehicle/train/car.mdl", "RAIL")
assertEqual(loadedOrigin.update, loadedUpdate, "custom update function is resolved")
assertEqual(loadedOrigin.particles, loadedParticles, "custom particle function is resolved")
assertEqual(loadedOrigin.getEmittableModels, loadedGetEmittableModels, "custom model discovery is resolved")
assertEqual(loadedOrigin.computeEmittedModels, loadedComputeEmittedModels, "custom model emission is resolved")
loadedOrigin.update(loadedOrigin.capture, {}, {})
loadedOrigin.particles(loadedOrigin.particlesCapture, {}, {})
local loadedModels = loadedOrigin.getEmittableModels(loadedOrigin.getEmittableModelsCapture, {})
local loadedEmitter = {}
loadedOrigin.computeEmittedModels(loadedOrigin.computeEmittedModelsCapture, {}, loadedEmitter)
assertEqual(loadedUpdateCapture.source, "update", "custom update parameters are preserved")
assertEqual(loadedParticleCapture.source, "particles", "custom particle parameters are preserved")
assertEqual(loadedEmittableCapture.source, "emittable", "model-discovery parameters are preserved")
assertEqual(loadedEmittedCapture.source, "emitted", "model-emission parameters are preserved")
assertEqual(loadedModels[1], "example::/number.mdl", "authored model resources are retained")
assertEqual(loadedEmitter.loaded, true, "authored model emission is retained")
local missingWarningCount = #warnings
assertEqual(
	originLoader.get("missing.trf", "example::/vehicle/tram/car.mdl", "TRAM"),
	nil,
	"unresolved authored transformators are rejected"
)
assertEqual(#warnings, missingWarningCount + 1, "unresolved custom transformator is logged")

local transformatorConfigFactory = dofile("content/swaying_waying/vehicle/transformator_config.lua")
local directTransformatorConfig = transformatorConfigFactory.create("train")
local genericTransformatorConfig = transformatorConfigFactory.create("any")
assertEqual(directTransformatorConfig.getEmittableModelsScript, nil, "direct wrappers add no unused callbacks")
assertEqual(
	genericTransformatorConfig.getEmittableModelsScript.fileName,
	"transformator.script@any.getEmittableModelsFn",
	"generic wrapper declares model discovery"
)
assertEqual(
	genericTransformatorConfig.computeEmittedModelsScript.fileName,
	"transformator.script@any.computeEmittedModelsFn",
	"generic wrapper declares model emission"
)

local originGetCalls = 0
local originRequests = {}
local originByName = { ["custom.trf"] = customOrigin }
moduleOverrides["apasz_swaying_waying::/swaying_waying/origin_loader.lua"] = {
	get = function(name, modelFile, carrier)
		originGetCalls = originGetCalls + 1
		originRequests[#originRequests + 1] = { name = name, modelFile = modelFile, carrier = carrier }
		assertEqual(carrier, "RAIL", "generic wrapper preserves the carrier")
		return assert(originByName[name], "unexpected mocked transformator: " .. tostring(name))
	end,
}

local scripts = dofile("content/swaying_waying/vehicle/transformator.script.lua")
assertEqual(type(data), "function", "transformator script defines the engine data entry point")
assertEqual(data(), scripts, "transformator data entry point returns its script table")
local animationStates = {}
local output = {
	addAnimationState = function(_, name, _, time)
		animationStates[name] = time
	end,
}
local params = {
	currentInfo = {
		world = { gameTime = 0 },
		vehicle = { speed = 18.0, maintenance = 0.0, positionInCarriageList = 0, carriageListLength = 1 },
		landVehicle = {
			reversed = false,
			carriagesReversed = { false, false, false, false },
			wheelAnimationInfo = { totalDist = 123.0 },
		},
	},
	vehicleStaticInfo = { carriageEntity = 7, purchaseTime = 100 },
	entityId = 11,
	landVehicleApi = {},
	transformatorConfigParams = {
		swayingWaying = {
			schema = 2,
			revision = 1,
			modelFile = "tests::/runtime.mdl",
			originalTransformator = "::/vehicle/train/shared/default_train.trf",
			carrier = "RAIL",
			profile = "DEFAULT",
			axisReversed = false,
			vehicleFactor = 1,
			wheelbase = 10,
			sections = {},
			settings = {
				speedDependent = true,
				intensity = 1,
				rollBalance = 1,
				pitchBalance = 1,
				heaveBalance = 1,
				curveLeanIntensity = 1,
				curveSamplingDistance = 0,
				trackInfluence = 1,
				samplingDistance = constants.DEFAULT_SAMPLE_DISTANCE,
				vehicleVariation = 1,
			},
		},
	},
}
local function refreshRuntimeSettings()
	params.vehicleStaticInfo.purchaseTime = params.vehicleStaticInfo.purchaseTime + 1
	params.transformatorConfigParams.swayingWaying.revision = params.transformatorConfigParams.swayingWaying.revision
		+ 1
end
scripts.train.updateFn({}, params, output)
assertEqual(nativeCalls.train, 1, "standard wrapper runs the native transformator")
assertEqual(type(animationStates.native_train), "number", "native animation state is retained")
assertEqual(type(animationStates[constants.SWAY_ANIMATION]), "number", "sway uses an independent animation state")
assertEqual(type(animationStates[constants.PITCH_ANIMATION]), "number", "pitch uses an independent animation state")
assertEqual(type(animationStates[constants.HEAVE_ANIMATION]), "number", "heave uses an independent animation state")
assertNear(
	animationStates[constants.SWAY_ANIMATION],
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 123.0,
		phaseSeed = 18,
		sharedDistance = 123.0,
		sharedPhaseSeed = 11,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 1.0,
		shortWeight = 0.65,
	}, {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	0.000001,
	"best-maintained stock uses the static vehicle response"
)
local expectedHeave, expectedPitch = motion.secondaryMotion({
	motionScale = motion.speedFactor(18.0, "DEFAULT"),
	distance = 123.0,
	phaseSeed = 18,
	sharedDistance = 123.0,
	sharedPhaseSeed = 11,
	sharedAxisReversed = false,
	curveTilt = 0.75,
	swayFactor = 1.0,
	shortWeight = 0.65,
}, "DEFAULT", 10.0)
local expectedHeaveTime, expectedPitchTime = motion.secondaryAnimationTimes(expectedHeave, expectedPitch, 1.0, {
	rollIntensity = 1.0,
	pitchIntensity = 1.0,
	heaveIntensity = 1.0,
	curveLeanIntensity = 1.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
})
assertNear(
	animationStates[constants.HEAVE_ANIMATION],
	expectedHeaveTime,
	0.000001,
	"heave state samples the shared vertical profile"
)
assertNear(
	animationStates[constants.PITCH_ANIMATION],
	expectedPitchTime,
	0.000001,
	"pitch state samples the shared vertical profile"
)

do
	local defaultRoll = animationStates[constants.SWAY_ANIMATION]
	local curveRoll = 2500.0 + motion.curveLeanDegrees(0.75) * 277.778
	for _, rollBalance in ipairs({ 0, 0.5, 2 }) do
		params.transformatorConfigParams.swayingWaying.settings.rollBalance = rollBalance
		refreshRuntimeSettings()
		animationStates = {}
		scripts.train.updateFn({}, params, output)
		assertNear(
			animationStates[constants.SWAY_ANIMATION],
			curveRoll + (defaultRoll - curveRoll) * rollBalance,
			0.000001,
			"roll balance scales procedural rocking while preserving curve lean"
		)
		assertNear(
			animationStates[constants.PITCH_ANIMATION],
			expectedPitchTime,
			0.000001,
			"roll balance preserves pitch"
		)
		assertNear(
			animationStates[constants.HEAVE_ANIMATION],
			expectedHeaveTime,
			0.000001,
			"roll balance preserves heave"
		)
	end
	params.transformatorConfigParams.swayingWaying.settings.rollBalance = 1
end

animationStates = {}
params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 0.5
params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 1.5
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
local balancedRuntimeHeave, balancedRuntimePitch = motion.secondaryAnimationTimes(expectedHeave, expectedPitch, 1.0, {
	rollIntensity = 1.0,
	pitchIntensity = 0.5,
	heaveIntensity = 1.5,
	curveLeanIntensity = 1.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
})
assertNear(
	animationStates[constants.HEAVE_ANIMATION],
	balancedRuntimeHeave,
	0.000001,
	"runtime heave balance is applied"
)
assertNear(
	animationStates[constants.PITCH_ANIMATION],
	balancedRuntimePitch,
	0.000001,
	"runtime pitch balance is applied"
)
params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 1.0
params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 1.0
refreshRuntimeSettings()

local configuredValues = params.transformatorConfigParams.swayingWaying.settings
local configuredLookups = 0
params.transformatorConfigParams.swayingWaying.settings = setmetatable({}, {
	__index = function(_, key)
		configuredLookups = configuredLookups + 1
		return configuredValues[key]
	end,
})
refreshRuntimeSettings()
params.vehicleStaticInfo.carriageEntity = 8
scripts.train.updateFn({}, params, output)
local firstUpdateLookups = configuredLookups
scripts.train.updateFn({}, params, output)
assertEqual(configuredLookups, firstUpdateLookups, "static settings are decoded once per model revision")
params.transformatorConfigParams.swayingWaying.settings = configuredValues
params.vehicleStaticInfo.carriageEntity = 7

animationStates = {}
params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 0
params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 0
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertEqual(type(animationStates[constants.SWAY_ANIMATION]), "number", "secondary toggle does not disable roll")
assertEqual(animationStates[constants.PITCH_ANIMATION], nil, "secondary toggle disables runtime pitch")
assertEqual(animationStates[constants.HEAVE_ANIMATION], nil, "secondary toggle disables runtime heave")
params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 1
params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 1

params.currentInfo.vehicle.maintenance = 1.0
params.transformatorConfigParams.swayingWaying.vehicleFactor = 1.25
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertNear(
	animationStates[constants.SWAY_ANIMATION],
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 123.0,
		phaseSeed = 18,
		sharedDistance = 123.0,
		sharedPhaseSeed = 11,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 1.25 * 1.10,
		shortWeight = 0.65,
	}, {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	0.000001,
	"live maintenance multiplies the authored vehicle response"
)

animationStates = {}
params.transformatorConfigParams.swayingWaying.settings.vehicleVariation = 0.0
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertNear(
	animationStates[constants.SWAY_ANIMATION],
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 123.0,
		phaseSeed = 18,
		sharedDistance = 123.0,
		sharedPhaseSeed = 11,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 1.25,
		shortWeight = 0.65,
	}, {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	0.000001,
	"disabled vehicle variation removes live maintenance response"
)
params.transformatorConfigParams.swayingWaying.settings.vehicleVariation = 1.0

do
	local disabledTrackQueries = 0
	params.landVehicleApi = {
		getBaseEdgeInfo = function()
			disabledTrackQueries = disabledTrackQueries + 1
			return nil
		end,
		getVehicleEdgeInfo = function()
			disabledTrackQueries = disabledTrackQueries + 1
			return nil
		end,
	}
	params.transformatorConfigParams.swayingWaying.settings.trackInfluence = 0.0
	refreshRuntimeSettings()
	scripts.train.updateFn({}, params, output)
	assertEqual(disabledTrackQueries, 0, "disabled track influence bypasses track inspection")
	params.landVehicleApi = {}
	params.transformatorConfigParams.swayingWaying.settings.trackInfluence = 1.0
end

animationStates = {}
params.currentInfo.vehicle.maintenance = 0.0
params.transformatorConfigParams.swayingWaying.vehicleFactor = 1.0
setSections(params.transformatorConfigParams.swayingWaying, 2)
params.transformatorConfigParams.swayingWaying.sections[1].lag = 0.0
params.transformatorConfigParams.swayingWaying.sections[2].lag = 8.0
params.transformatorConfigParams.swayingWaying.sections[1].wheelbase = 10.0
params.transformatorConfigParams.swayingWaying.sections[2].wheelbase = 8.0
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertEqual(animationStates[constants.SWAY_ANIMATION], nil, "sectioned vehicles do not emit the generic sway channel")
assertEqual(animationStates[constants.PITCH_ANIMATION], nil, "sectioned vehicles do not emit generic pitch")
assertEqual(animationStates[constants.HEAVE_ANIMATION], nil, "sectioned vehicles do not emit generic heave")
assertNear(
	animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. 1],
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 123.0,
		phaseSeed = 18,
		sharedDistance = 123.0,
		sharedPhaseSeed = 11,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 1.0,
		shortWeight = 0.65,
	}, {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	0.000001,
	"first authored section samples the current distance"
)
assertNear(
	animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. 2],
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 115.0,
		phaseSeed = 18,
		sharedDistance = 115.0,
		sharedPhaseSeed = 11,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 1.0,
		shortWeight = 0.65,
	}, {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	0.000001,
	"second authored section samples its longitudinal lag"
)
assertEqual(
	type(animationStates[constants.PITCH_SECTION_ANIMATION_PREFIX .. 1]),
	"number",
	"first authored section emits pitch"
)
assertEqual(
	type(animationStates[constants.HEAVE_SECTION_ANIMATION_PREFIX .. 2]),
	"number",
	"second authored section emits heave"
)

animationStates = {}
params.transformatorConfigParams.swayingWaying.sections = { [2] = { lag = 0, wheelbase = 10 } }
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertEqual(animationStates[constants.SWAY_ANIMATION], nil, "invalid section arrays produce no added motion")
assertEqual(type(animationStates.native_train), "number", "invalid configuration preserves authored animation")

animationStates = {}
setSections(params.transformatorConfigParams.swayingWaying, 2)
params.transformatorConfigParams.swayingWaying.sections[2].lag = 0 / 0
refreshRuntimeSettings()
scripts.train.updateFn({}, params, output)
assertEqual(
	animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. 2],
	nil,
	"invalid section lag produces no added motion"
)
params.transformatorConfigParams.swayingWaying.sections[2].lag = 8

setSections(params.transformatorConfigParams.swayingWaying, 0)

params.transformatorConfigParams.swayingWaying.originalTransformator = "custom.trf"
params.transformatorConfigParams.swayingWaying.modelFile = "example::/vehicle/train/custom.mdl"
params.transformatorConfigParams.swayingWaying.carrier = "RAIL"
refreshRuntimeSettings()
scripts.any.updateFn({}, params, output)
assertEqual(customCalls.update, 1, "generic wrapper runs the authored transformator")
local particleSystem = {}
scripts.any.updateParticleSystemFn({}, params, particleSystem)
assertEqual(customCalls.particles, 1, "generic wrapper runs authored particles")
local customModels = scripts.any.getEmittableModelsFn({}, params)
assertEqual(customCalls.emittable, 1, "generic wrapper runs authored model discovery")
assertEqual(customModels[1], "example::/random_number.mdl", "generic wrapper returns authored model resources")
local customEmitter = {}
scripts.any.computeEmittedModelsFn({}, params, customEmitter)
assertEqual(customCalls.emitted, 1, "generic wrapper runs authored model emission")
assertEqual(customEmitter.forwarded, true, "generic wrapper preserves the authored model emitter")
assertEqual(originGetCalls, 1, "generic wrapper caches its resolved transformator")
assertEqual(originRequests[1].name, "custom.trf", "generic wrapper requests the authored transformator")
assertEqual(
	originRequests[1].modelFile,
	"example::/vehicle/train/custom.mdl",
	"generic wrapper requests the authored model owner"
)
assertEqual(particleSystem.fallbackCalls, nil, "particle fallback is not duplicated")

customOrigin.particles = nil
scripts.any.updateParticleSystemFn({}, params, particleSystem)
assertEqual(particleSystem.fallbackCalls, 1, "missing custom particles use the standard fallback")
local callbackWarningCount = #warnings
customOrigin.getEmittableModels = function()
	return { [2] = "example::/sparse.mdl" }
end
assertEqual(#scripts.any.getEmittableModelsFn({}, params), 0, "invalid model discovery is rejected")
assertEqual(#warnings, callbackWarningCount + 1, "invalid model discovery is logged")
scripts.any.getEmittableModelsFn({}, params)
assertEqual(#warnings, callbackWarningCount + 1, "model-discovery failures are logged once")
customOrigin.computeEmittedModels = function()
	error("authored emission failure")
end
scripts.any.computeEmittedModelsFn({}, params, customEmitter)
assertEqual(#warnings, callbackWarningCount + 2, "model-emission failures are logged")
scripts.any.computeEmittedModelsFn({}, params, customEmitter)
assertEqual(#warnings, callbackWarningCount + 2, "model-emission failures are logged once")
customOrigin.getEmittableModels = nil
customOrigin.computeEmittedModels = nil
assertEqual(#scripts.any.getEmittableModelsFn({}, params), 0, "missing model discovery returns an empty list")
scripts.any.computeEmittedModelsFn({}, params, customEmitter)
assertEqual(customCalls.emitted, 1, "missing model emission is a no-op")

do
	local originalAnimationTimes = motion.animationTimes
	local firstSample, firstSettings
	local sampleCalls = 0
	motion.animationTimes = function(sample, settings, geometry)
		firstSample = firstSample or sample
		firstSettings = firstSettings or settings
		assertEqual(sample, firstSample, "updates and sections reuse the carriage's motion sample")
		assertEqual(settings, firstSettings, "updates and sections reuse cached motion settings")
		sampleCalls = sampleCalls + 1
		return originalAnimationTimes(sample, settings, geometry)
	end
	setSections(params.transformatorConfigParams.swayingWaying, 2)
	params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 1
	params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 1
	refreshRuntimeSettings()
	for frame = 1, 8 do
		params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = 123.0 + frame
		scripts.train.updateFn({}, params, output)
	end
	motion.animationTimes = originalAnimationTimes
	assertEqual(sampleCalls, 16, "every section is sampled on each update")
end

do
	local originalAnimationTimes = motion.animationTimes
	local samples = {}
	motion.animationTimes = function(sample, settings, geometry)
		samples[#samples + 1] = {
			distance = sample.distance,
			sharedDistance = sample.sharedDistance,
			phaseSeed = sample.phaseSeed,
			sharedPhaseSeed = sample.sharedPhaseSeed,
			sharedAxisReversed = sample.sharedAxisReversed,
		}
		return originalAnimationTimes(sample, settings, geometry)
	end
	params.entityId = 11
	params.vehicleStaticInfo.carriageEntity = 7
	params.currentInfo.vehicle.carriageListLength = 4
	params.currentInfo.vehicle.positionInCarriageList = 2
	params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = 123.0
	params.currentInfo.landVehicle.reversed = false
	setSections(params.transformatorConfigParams.swayingWaying, 2)
	params.transformatorConfigParams.swayingWaying.sections[1].lag = 0.0
	params.transformatorConfigParams.swayingWaying.sections[2].lag = 8.0
	params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 1
	params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 1
	refreshRuntimeSettings()
	scripts.train.updateFn({}, params, output)
	assertEqual(#samples, 2, "every articulated section samples consist sway")
	assertNear(samples[1].sharedDistance, 83.0, 0.000001, "carriage order adds a twenty metre distance lag")
	assertNear(samples[2].sharedDistance, 75.0, 0.000001, "section lag also delays the shared wave")
	assertNear(samples[2].distance, 115.0, 0.000001, "individual motion retains its section lag")
	assertEqual(samples[1].phaseSeed, 18, "individual waves use the carriage seed")
	assertEqual(samples[1].sharedPhaseSeed, 11, "the long wave uses the consist seed")
	assertEqual(samples[1].sharedAxisReversed, false, "forward-facing carriages use the shared axes")

	samples = {}
	params.currentInfo.landVehicle.reversed = true
	scripts.train.updateFn({}, params, output)
	assertNear(samples[1].sharedDistance, -163.0, 0.000001, "reversing reverses travel through the shared profile")
	assertNear(samples[2].sharedDistance, -171.0, 0.000001, "reversed sections retain their physical order")

	samples = {}
	params.currentInfo.landVehicle.carriagesReversed[3] = true
	scripts.train.updateFn({}, params, output)
	assertNear(
		samples[1].sharedDistance,
		83.0,
		0.000001,
		"backward-facing carriages retain the consist travel coordinate"
	)
	assertNear(
		samples[2].sharedDistance,
		91.0,
		0.000001,
		"backward-facing sections extend in the opposite shared direction"
	)
	assertNear(samples[2].distance, 115.0, 0.000001, "carriage facing preserves individual section samples")
	assertEqual(samples[1].sharedAxisReversed, true, "shared axes follow live carriage facing without a cache refresh")
	assertEqual(samples[1].phaseSeed, 18, "carriage facing preserves the local seed")
	samples = {}
	local config = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
	config.carriageLag = false
	scripts.train.updateFn({}, params, output)
	assertNear(samples[1].sharedDistance, 123.0, 0.000001, "per-carriage long waves retain normalized orientation")
	assertNear(samples[2].sharedDistance, 131.0, 0.000001, "per-carriage long waves preserve oriented section spacing")
	config.sectionLag = false
	samples = {}
	scripts.train.updateFn({}, params, output)
	assertNear(samples[2].sharedDistance, 123.0, 0.000001, "disabled section lag removes oriented offsets")
	config.carriageLag = true
	config.sectionLag = true
	samples = {}
	params.currentInfo.landVehicle.reversed = false
	scripts.train.updateFn({}, params, output)
	assertNear(
		samples[1].sharedDistance,
		-163.0,
		0.000001,
		"a reverse has the same consist coordinate for either facing"
	)
	assertNear(samples[2].sharedDistance, -155.0, 0.000001, "section orientation stays separate from consist reversal")
	params.currentInfo.landVehicle.carriagesReversed[3] = false

	samples = {}
	params.currentInfo.landVehicle.reversed = false
	params.currentInfo.vehicle.positionInCarriageList = 1
	params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = 143.0
	params.vehicleStaticInfo.carriageEntity = 9
	scripts.train.updateFn({}, params, output)
	assertNear(samples[1].sharedDistance, 123.0, 0.000001, "a following carriage reaches the former leading coordinate")
	assertEqual(samples[1].sharedPhaseSeed, 11, "a different carriage retains the common consist seed")
	assertEqual(samples[1].phaseSeed, 20, "a different carriage retains its own local seed")

	samples = {}
	params.entityId = 12
	params.currentInfo.vehicle.positionInCarriageList = 0
	params.currentInfo.vehicle.carriageListLength = 1
	scripts.train.updateFn({}, params, output)
	assertNear(samples[1].sharedDistance, 143.0, 0.000001, "a single carriage has no consist lag")
	assertEqual(samples[1].sharedPhaseSeed, 12, "changing consists immediately changes the shared seed")

	samples = {}
	local previousWarnings = #warnings
	params.currentInfo.vehicle.positionInCarriageList = 1
	scripts.train.updateFn({}, params, output)
	assertEqual(#samples, 0, "invalid carriage order does not produce motion")
	assertEqual(#warnings, previousWarnings + 1, "invalid carriage order is reported")
	samples = {}
	params.currentInfo.vehicle.positionInCarriageList = 0
	local savedOrientations = params.currentInfo.landVehicle.carriagesReversed
	params.currentInfo.landVehicle.carriagesReversed = {}
	scripts.train.updateFn({}, params, output)
	assertEqual(#samples, 0, "missing carriage orientation does not invent a shared direction")
	assertEqual(
		#warnings,
		previousWarnings + 1,
		"a second sway failure in the same revision does not repeat the warning"
	)
	assertEqual(type(animationStates.native_train), "number", "invalid orientation retains the authored transformator")
	params.currentInfo.landVehicle.carriagesReversed = savedOrientations
	motion.animationTimes = originalAnimationTimes
end

do
	local config = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
	local originalCombined = motion.animationTimes
	local originalRoll = motion.animationTime
	local originalTrack = trackResponse.response
	local originalMaintenance = vehicleResponse.maintenanceFactor
	local originalTilt = curveResponse.tilt
	local samples = {}
	local calls = {}
	local function capture(fn)
		return function(sample, settings, geometry)
			samples[#samples + 1] = {
				distance = sample.distance,
				sharedDistance = sample.sharedDistance,
				curveTilt = sample.curveTilt,
				shortWeight = sample.shortWeight,
				swayFactor = sample.swayFactor,
			}
			return fn(sample, settings, geometry)
		end
	end
	motion.animationTimes = capture(originalCombined)
	motion.animationTime = capture(originalRoll)
	local trackInterval
	trackResponse.response = function(_, _, _, _, samplingDistance)
		calls.track = calls.track + 1
		trackInterval = samplingDistance
		return 1.25, 0.80
	end
	vehicleResponse.maintenanceFactor = function()
		calls.maintenance = calls.maintenance + 1
		return 1.10
	end
	local curveSpeed, curveReversed, curveInterval, curveDistance
	curveResponse.tilt = function(_, speed, reversed, state, distance)
		calls.curve = calls.curve + 1
		curveSpeed = speed
		curveReversed = reversed
		curveInterval = state.model.curveSamplingDistance
		curveDistance = distance
		return 0.75
	end
	params.currentInfo.vehicle.positionInCarriageList = 1
	params.currentInfo.vehicle.carriageListLength = 3
	params.currentInfo.vehicle.maintenance = 1.0
	params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = 123.0
	params.currentInfo.landVehicle.reversed = false
	params.transformatorConfigParams.swayingWaying.vehicleFactor = 1.2
	params.transformatorConfigParams.swayingWaying.settings.vehicleVariation = 1.0
	params.transformatorConfigParams.swayingWaying.settings.trackInfluence = 1.0
	params.transformatorConfigParams.swayingWaying.settings.curveLeanIntensity = 1
	refreshRuntimeSettings()
	local function update()
		samples = {}
		calls = { track = 0, maintenance = 0, curve = 0 }
		animationStates = {}
		refreshRuntimeSettings()
		scripts.train.updateFn({}, params, output)
	end
	update()
	assertEqual(calls.track, 1, "enabled track response queries the track")
	assertEqual(calls.maintenance, 1, "enabled vehicle response reads maintenance")
	assertEqual(calls.curve, 1, "enabled curve lean samples curvature")
	assertNear(samples[1].swayFactor, 1.65, 0.000001, "enabled responses compose normally")
	for _, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
		local samplingDistance = option.distance
		params.transformatorConfigParams.swayingWaying.settings.samplingDistance = samplingDistance
		update()
		assertEqual(trackInterval, samplingDistance, "the controller forwards the selected track interval")
		assertEqual(calls.curve, 1, "each track sampling option retains one live curve query per carriage update")
		assertEqual(curveInterval, 0, "track sampling does not change the curve sampling interval")
	end
	params.transformatorConfigParams.swayingWaying.settings.samplingDistance = constants.DEFAULT_SAMPLE_DISTANCE
	for _, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
		params.transformatorConfigParams.swayingWaying.settings.curveSamplingDistance = option.distance
		update()
		assertEqual(curveInterval, option.distance, "the controller forwards the selected curve interval")
		assertEqual(curveDistance, 123, "curve sampling uses actual carriage travel distance")
		assertEqual(
			trackInterval,
			constants.DEFAULT_SAMPLE_DISTANCE,
			"curve sampling does not change the track interval"
		)
	end
	params.transformatorConfigParams.swayingWaying.settings.curveSamplingDistance = 0

	config.trackResponse = false
	update()
	assertEqual(calls.track, 0, "disabled track response skips track queries")
	assertNear(samples[1].shortWeight, 0.65, 0.000001, "disabled track response uses the neutral spectrum")
	assertNear(samples[1].swayFactor, 1.32, 0.000001, "disabled track response removes its amplitude modifier")
	config.trackResponse = true
	config.vehicleResponse = false
	update()
	assertEqual(calls.maintenance, 0, "disabled vehicle response skips maintenance calculations")
	assertNear(samples[1].swayFactor, 1.25, 0.000001, "disabled vehicle response removes static and live modifiers")
	config.trackResponse = false
	update()
	assertNear(samples[1].swayFactor, 1.0, 0.000001, "both response switches yield neutral amplitude")
	config.trackResponse = true
	config.vehicleResponse = true

	params.transformatorConfigParams.swayingWaying.settings.curveLeanIntensity = 0
	update()
	assertEqual(calls.curve, 0, "Off on the curve lean intensity slider skips curvature queries")
	assertNear(samples[1].curveTilt, 0.5, 0.000001, "Off on the curve lean intensity slider produces neutral lean")
	assertEqual(calls.track, 1, "Off on the curve lean intensity slider retains procedural track response")
	params.transformatorConfigParams.swayingWaying.settings.curveLeanIntensity = 1

	config.curveLean = false
	update()
	assertEqual(calls.curve, 0, "disabled curve lean skips curvature sampling")
	assertNear(samples[1].curveTilt, 0.5, 0.000001, "disabled curve lean uses neutral tilt")
	config.curveLean = true
	for _, axis in ipairs({ "roll", "pitch", "heave" }) do
		config[axis] = false
		update()
		assertEqual(
			animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. 1] ~= nil,
			axis ~= "roll",
			"roll output respects its switch"
		)
		assertEqual(
			animationStates[constants.PITCH_SECTION_ANIMATION_PREFIX .. 1] ~= nil,
			axis ~= "pitch",
			"pitch output respects its switch"
		)
		assertEqual(
			animationStates[constants.HEAVE_SECTION_ANIMATION_PREFIX .. 1] ~= nil,
			axis ~= "heave",
			"heave output respects its switch"
		)
		if axis == "roll" then
			assertEqual(calls.curve, 0, "disabled roll also skips curve lean queries")
		end
		config[axis] = true
	end

	config.shortWave = false
	config.longWave = false
	config.thirdWave = false
	config.irregularity = false
	update()
	assertEqual(calls.track + calls.maintenance, 0, "curve-only motion skips procedural response queries")
	assertEqual(calls.curve, 1, "curve-only motion retains curvature sampling")
	assertEqual(curveSpeed, params.currentInfo.vehicle.speed, "curve-only motion uses live speed")
	assertEqual(curveReversed, false, "curve-only motion uses current orientation")
	assertNear(samples[1].swayFactor, 1.0, 0.000001, "curve-only motion uses neutral procedural amplitude")
	config.curveLean = false
	update()
	assertEqual(#samples, 0, "no waves or curve lean skips motion sampling")
	assertEqual(calls.track + calls.maintenance + calls.curve, 0, "no active source skips every response query")
	config.curveLean = true
	config.shortWave = true
	config.longWave = true
	config.thirdWave = true
	config.irregularity = true
	params.transformatorConfigParams.swayingWaying.settings.intensity = 0.0
	refreshRuntimeSettings()
	update()
	assertEqual(calls.track + calls.maintenance, 0, "zero procedural intensity skips response queries")
	assertEqual(calls.curve, 1, "zero procedural intensity retains independent curve lean")
	params.transformatorConfigParams.swayingWaying.settings.curveLeanIntensity = 0.0
	refreshRuntimeSettings()
	update()
	assertEqual(#samples, 0, "zero strength on every source skips motion sampling")
	assertEqual(calls.track + calls.maintenance + calls.curve, 0, "zero curve strength skips curvature sampling")
	params.transformatorConfigParams.swayingWaying.settings.intensity = 1.0
	params.transformatorConfigParams.swayingWaying.settings.curveLeanIntensity = 1.0
	refreshRuntimeSettings()

	config.carriageLag = false
	update()
	assertNear(samples[1].sharedDistance, 123.0, 0.000001, "per-carriage long waves have no carriage distance lag")
	assertNear(samples[2].sharedDistance, 115.0, 0.000001, "disabling carriage lag preserves section lag")
	config.carriageLag = true
	config.sectionLag = false
	update()
	for _, sample in ipairs(samples) do
		assertNear(sample.distance, 123.0, 0.000001, "section lag can be disabled for individual waves")
		assertNear(sample.sharedDistance, 103.0, 0.000001, "disabling section lag preserves carriage lag")
	end
	config.sectionLag = true
	config.longWave = false
	params.currentInfo.vehicle.positionInCarriageList = 99
	local previousWarnings = #warnings
	update()
	assertEqual(#samples, 2, "disabled long wave does not require carriage order data")
	assertEqual(#warnings, previousWarnings, "disabled long wave bypasses carriage lag validation")
	params.currentInfo.vehicle.positionInCarriageList = 1
	config.longWave = true

	config.pitch = false
	config.heave = false
	update()
	assertEqual(
		type(animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. 1]),
		"number",
		"disabling secondary axes retains roll"
	)
	assertEqual(animationStates[constants.PITCH_SECTION_ANIMATION_PREFIX .. 1], nil, "disabled pitch emits no channel")
	assertEqual(animationStates[constants.HEAVE_SECTION_ANIMATION_PREFIX .. 1], nil, "disabled heave emits no channel")
	config.roll = false
	update()
	assertEqual(#samples, 0, "disabled axes skip procedural motion")
	assertEqual(calls.track + calls.maintenance + calls.curve, 0, "disabled axes skip response queries")
	assertEqual(type(animationStates.native_train), "number", "disabled sway axes preserve the authored transformator")
	config.pitch = true
	config.heave = true
	params.transformatorConfigParams.swayingWaying.settings.pitchBalance = 0
	params.transformatorConfigParams.swayingWaying.settings.heaveBalance = 0
	refreshRuntimeSettings()
	update()
	assertEqual(#samples, 0, "developer switches do not enable secondary motion disabled by game settings")

	for name in pairs(config) do
		config[name] = true
	end
	motion.animationTimes = originalCombined
	motion.animationTime = originalRoll
	trackResponse.response = originalTrack
	vehicleResponse.maintenanceFactor = originalMaintenance
	curveResponse.tilt = originalTilt
end

do
	local source = {}
	for key, value in pairs(params.transformatorConfigParams.swayingWaying) do
		source[key] = value
	end
	source.modelFile = "tests::/callbacks_without_dynamic_info.mdl"
	source.originalTransformator = "custom.trf"
	local context = { entityId = 11, transformatorConfigParams = { swayingWaying = source } }
	local discovered, emitted = 0, 0
	customOrigin.getEmittableModels = function(capture, received)
		assertEqual(capture.marker, "emittable", "early discovery keeps its authored capture")
		assertEqual(received, context, "early discovery receives the original context")
		discovered = discovered + 1
		return { "example::/early.mdl" }
	end
	customOrigin.computeEmittedModels = function(capture, received, emitter)
		assertEqual(capture.marker, "emitted", "early emission keeps its authored capture")
		assertEqual(received, context, "early emission receives the original context")
		emitter.done = true
		emitted = emitted + 1
	end
	local resources = scripts.any.getEmittableModelsFn({}, context)
	local emitter = {}
	scripts.any.computeEmittedModelsFn({}, context, emitter)
	assertEqual(resources[1], "example::/early.mdl", "discovery works without dynamic vehicle information")
	assertEqual(discovered, 1, "early discovery is forwarded once")
	assertEqual(emitted, 1, "early emission is forwarded once")
	assertEqual(emitter.done, true, "emission works without dynamic vehicle information")
end

do
	local particleCalls = 0
	originByName["particles_only.trf"] = {
		particles = function(capture, received, system)
			assertEqual(capture.marker, "particle-only", "particle-only capture is forwarded")
			assertEqual(received, params, "particle-only callback receives the original parameters")
			system.handled = true
			particleCalls = particleCalls + 1
		end,
		particlesCapture = { marker = "particle-only" },
	}
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/particles_only.mdl"
	configured.originalTransformator = "particles_only.trf"
	configured.sections = {}
	configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
	refreshRuntimeSettings()
	animationStates = {}
	local authoredUpdates = customCalls.update
	scripts.any.updateFn({}, params, output)
	local system = {}
	scripts.any.updateParticleSystemFn({}, params, system)
	assertEqual(customCalls.update, authoredUpdates, "a missing authored update is preserved")
	assertEqual(type(animationStates[constants.SWAY_ANIMATION]), "number", "particle-only vehicles receive sway")
	assertEqual(particleCalls, 1, "particle-only callbacks run once")
	assertEqual(system.handled, true, "particle-only output is preserved")
end

do
	curveResponse.tilt = sampledCurveTilt
	local actualTilt, actualScale
	local curvatureCalls, curvature = 0, 0.001
	params.landVehicleApi.getAverageCurvature = function(_, front, back)
		assertEqual(front, 40, "controller retains the native forward curvature window")
		assertEqual(back, 40, "controller retains the native backward curvature window")
		curvatureCalls = curvatureCalls + 1
		return curvature
	end
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/sampled_lean.mdl"
	configured.settings.curveSamplingDistance = 0
	refreshRuntimeSettings()
	local function update(time, distance, speed)
		params.currentInfo.world.gameTime = time
		params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = distance
		params.currentInfo.vehicle.speed = speed
		scripts.train.updateFn({}, params, output)
		local observed = ug_require("apasz_swaying_waying::/swaying_waying/runtime_state.lua").get(
			configured,
			params.vehicleStaticInfo.carriageEntity,
			params.vehicleStaticInfo.purchaseTime
		)
		actualTilt, actualScale = observed.sample.curveTilt, observed.sample.motionScale
	end
	update(0, 0, 0)
	assertEqual(curvatureCalls, 0, "stopped controller makes no curvature queries")
	assertNear(actualTilt, 0.5, 1e-12, "stopped controller outputs neutral lean")
	update(16, 0, 20)
	assertEqual(curvatureCalls, 1, "controller samples curvature on restart")
	local targetTilt = (math.tanh(-20 * 20 * 0.001 / 1.2) + 1) / 2
	assert(actualTilt < 0.5 and actualTilt > targetTilt, "controller damps the live curve-lean target")
	assert(
		actualScale > 0 and actualScale < motion.speedFactor(20, "DEFAULT"),
		"controller damps the speed-dependent amplitude"
	)
	local previousTilt = actualTilt
	update(32, 1, 30)
	assertEqual(curvatureCalls, 2, "controller refreshes curvature within the track sampling interval")
	assert(actualTilt < previousTilt, "live geometry responds to speed through the damper")
	local boundaryDistance = constants.DEFAULT_SAMPLE_DISTANCE
	update(48, boundaryDistance, 30)
	assertEqual(curvatureCalls, 3, "controller refreshes geometry at the track sampling boundary")
	update(64, boundaryDistance, 0)
	update(80, boundaryDistance, 0)
	assertEqual(curvatureCalls, 3, "controller stops curvature queries immediately at rest")
	assert(actualTilt < 0.5 and actualScale > 0, "braking retains a brief suspension settling motion")
	for time = 96, 2000, 16 do
		update(time, boundaryDistance, 0)
	end
	assertEqual(curvatureCalls, 3, "settling at rest makes no curvature queries")
	assertNear(actualTilt, 0.5, 1e-12, "stopped lean settles exactly to neutral")
	assertNear(actualScale, 0, 1e-12, "stopped procedural amplitude settles exactly to zero")
	update(2016, boundaryDistance, 30)
	assertEqual(curvatureCalls, 4, "restarting queries current geometry")
	assert(actualScale > 0 and actualScale < motion.speedFactor(30, "DEFAULT"), "restart retains amplitude damping")
	previousTilt = actualTilt
	local movingDistance = boundaryDistance + 1
	update(2016, movingDistance, 20)
	assertNear(actualTilt, previousTilt, 1e-12, "duplicate callbacks do not advance the damping clock")
	update(2032, movingDistance, 20)
	local movingCalls = curvatureCalls
	previousTilt = actualTilt
	curvature = -0.001
	update(2048, movingDistance, 20)
	assertEqual(
		curvatureCalls,
		movingCalls + 1,
		"Frame curve sampling queries fresh curvature without distance movement"
	)
	assert(actualTilt < 0.5, "a curvature reversal retains suspension movement instead of snapping to the new target")
	for time = 2064, 2448, 16 do
		update(time, movingDistance, 20)
	end
	local oppositeTilt = (math.tanh(20 * 20 * 0.001 / 1.2) + 1) / 2
	assert(
		actualTilt > 0.5 and actualTilt < oppositeTilt,
		"live curvature reaches the opposite lean gradually without waiting for distance movement"
	)
	local baseline = {}
	configured.sections = { { lag = 0, wheelbase = 10 }, { lag = 12, wheelbase = 8 } }
	for _, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
		configured.modelFile = "tests::/live_lean_" .. option.distance .. ".mdl"
		configured.settings.samplingDistance = option.distance
		refreshRuntimeSettings()
		local startCalls, time, distance, movingFrames = curvatureCalls, 0, 0, 0
		for frame = 0, 120 do
			local elapsed = frame % 11 == 0 and 0 or 8 + frame % 5 * 9
			local speed = frame % 9 < 3 and 0 or 10 + frame % 7 * 5
			time = time + elapsed
			distance = distance + speed * elapsed / 1000
			curvature = 0.003 * math.sin(distance / 7) + 0.001 * math.sin(distance / 2)
			params.currentInfo.landVehicle.reversed = frame >= 60
			update(time, distance, speed)
			if speed ~= 0 then
				movingFrames = movingFrames + 1
			end
			if option.distance == 0 then
				baseline[frame] = actualTilt
			else
				assertNear(
					actualTilt,
					baseline[frame],
					1e-12,
					"all track intervals match per-frame curve lean through changing curves, speed, and reversal"
				)
			end
		end
		assertEqual(
			curvatureCalls - startCalls,
			movingFrames,
			"live curvature is queried once per moving carriage update, independently of its section count"
		)
	end
	for _, option in ipairs(dofile("tests/support/sampling_cases.lua")) do
		configured.modelFile = "tests::/cached_lean_" .. option.distance .. ".mdl"
		configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({
			rollBalance = 0,
			pitchBalance = 0,
			heaveBalance = 0,
			curveSamplingDistance = option.distance,
		})
		refreshRuntimeSettings()
		local startCalls = curvatureCalls
		for frame = 0, 120 do
			curvature = 0.003 * math.sin(frame / 12)
			update(frame * 16, frame / 4, 20)
		end
		assertEqual(
			curvatureCalls - startCalls,
			option.calls,
			"curve-only motion respects each interval with one query shared by all sections"
		)
	end
	configured.modelFile = "tests::/cached_lean_restart.mdl"
	configured.settings.curveSamplingDistance = 5
	refreshRuntimeSettings()
	curvature = 0
	update(0, 0, 20)
	local startCalls = curvatureCalls
	update(16, 0, 0)
	curvature = 0.002
	update(32, 0, 20)
	assertEqual(curvatureCalls, startCalls + 1, "a neutral idle shortcut invalidates cached curvature before restart")
	assert(actualTilt > 0.5, "restart uses current curvature without waiting for the selected distance")
	startCalls = curvatureCalls
	curvature = -0.003
	update(16, 0, 20)
	assertEqual(curvatureCalls, startCalls + 1, "a clock rewind invalidates cached curvature without distance movement")
	assertNear(
		actualTilt,
		(math.tanh(20 * 20 * curvature / 1.2) + 1) / 2,
		1e-12,
		"a clock rewind resets lean to fresh geometry instead of the cached target"
	)
end

do
	local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua")
	local runtime = ug_require("apasz_swaying_waying::/swaying_waying/runtime_state.lua")
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/speedless_sway.mdl"
	configured.sections = {}
	configured.settings =
		settings.resolve({ speedDependent = false, trackInfluence = 0, vehicleVariation = 0, curveLeanIntensity = 0 })
	params.landVehicleApi.getAverageCurvature = function()
		return 0.001
	end
	local function update(time, speed, distance)
		animationStates = {}
		params.currentInfo.world.gameTime = time
		params.currentInfo.vehicle.speed = speed
		params.currentInfo.landVehicle.wheelAnimationInfo.totalDist = distance or 123
		scripts.train.updateFn({}, params, output)
		return assert(
			runtime.get(configured, params.vehicleStaticInfo.carriageEntity, params.vehicleStaticInfo.purchaseTime)
		)
	end
	local channels = { constants.SWAY_ANIMATION, constants.PITCH_ANIMATION, constants.HEAVE_ANIMATION }
	local reference
	for _, speed in ipairs({ 5 / 3.6, -5 / 3.6, 2, 100 }) do
		refreshRuntimeSettings()
		assertEqual(update(0, speed).sample.motionScale, 1, "Speedless Sway reaches full strength from 5 km/h")
		for _, channel in ipairs(channels) do
			assert(math.abs(animationStates[channel] - 2500) > 1e-6, "Speedless Sway moves every enabled axis")
			if reference then
				assertNear(
					animationStates[channel],
					reference[channel],
					1e-9,
					"equal travel distance gives equal motion at different speeds"
				)
			end
		end
		reference = animationStates
	end
	update(16, 100, 124)
	assert(
		math.abs(animationStates[constants.SWAY_ANIMATION] - reference[constants.SWAY_ANIMATION]) > 1e-6,
		"Speedless Sway still advances with travel distance"
	)
	local stopping = update(32, 0, 124)
	assert(
		stopping.sample.motionScale > 0 and stopping.sample.motionScale < 1,
		"Speedless Sway settles gradually when stopped"
	)
	for time = 48, 2000, 16 do
		update(time, 0, 124)
	end
	for _, channel in ipairs(channels) do
		assertEqual(animationStates[channel], 2500, "stopped Speedless Sway returns every axis to neutral")
	end
	local restarted = update(2016, 5 / 3.6, 124)
	local restartingScale = restarted.sample.motionScale
	assert(restartingScale > 0 and restartingScale < 1, "Speedless Sway eases into motion at 5 km/h")
	assertEqual(
		update(2016, 100, 124).sample.motionScale,
		restartingScale,
		"paused callbacks do not advance speedless settling"
	)
	local leanBySpeed = {}
	configured.settings.curveLeanIntensity = 1
	for _, speed in ipairs({ 2, 30 }) do
		local expectedLean
		for _, speedDependent in ipairs({ true, false }) do
			configured.settings.speedDependent = speedDependent
			refreshRuntimeSettings()
			local state = update(0, speed)
			if expectedLean then
				assertNear(
					state.sample.curveTilt,
					expectedLean,
					1e-12,
					"Speedless Sway preserves speed-dependent curve lean"
				)
			else
				expectedLean = state.sample.curveTilt
			end
		end
		leanBySpeed[speed] = math.abs(expectedLean - 0.5)
	end
	assert(leanBySpeed[30] > leanBySpeed[2], "curve lean remains stronger at higher speed")
	for _, speedDependent in ipairs({ true, false }) do
		configured.settings.speedDependent = speedDependent
		for _, direction in ipairs({ -1, 1 }) do
			refreshRuntimeSettings()
			local lowSpeed = direction * 4.999 / 3.6
			local boundarySpeed = direction * 5 / 3.6
			local cold = update(0, lowSpeed)
			assertEqual(cold.sample.motionScale, 0, "both modes load neutral below 5 km/h")
			assertEqual(cold.sample.curveTilt, 0.5, "curve lean loads neutral below 5 km/h")
			for _, channel in ipairs(channels) do
				assertEqual(animationStates[channel], 2500, "all axes load neutral below 5 km/h")
			end
			local moving = update(2000, boundarySpeed)
			local movingScale = moving.sample.motionScale
			assert(movingScale > 0 and moving.sample.curveTilt ~= 0.5, "sway and curve lean activate at exactly 5 km/h")
			local settling = update(2016, lowSpeed)
			assert(
				settling.sample.motionScale > 0 and settling.sample.motionScale < movingScale,
				"crossing below 5 km/h damps sway without snapping"
			)
			assert(settling.sample.curveTilt ~= 0.5, "crossing below 5 km/h damps curve lean without snapping")
			for time = 2032, 4000, 16 do
				update(time, lowSpeed, 123 + direction * (time - 2016) / 1000)
			end
			for _, channel in ipairs(channels) do
				assertEqual(animationStates[channel], 2500, "all axes settle while still travelling below 5 km/h")
			end
			local resumed = update(4016, boundarySpeed)
			assert(
				resumed.sample.motionScale > 0 and resumed.sample.motionScale < movingScale,
				"crossing back to 5 km/h eases sway in"
			)
		end
	end
end

do
	local configuration = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
	local runtime = ug_require("apasz_swaying_waying::/swaying_waying/runtime_state.lua")
	local original = {
		track = trackResponse.response,
		maintenance = vehicleResponse.maintenanceFactor,
		curve = curveResponse.tilt,
		speed = motion.speedFactor,
		combined = motion.animationTimes,
		roll = motion.animationTime,
		prepare = motion.prepareWaves,
	}
	local calls = {}
	local function count(name, callback)
		return function(...)
			calls[name] = (calls[name] or 0) + 1
			return callback(...)
		end
	end
	trackResponse.response = count("track", function()
		return 1, 0.65
	end)
	vehicleResponse.maintenanceFactor = count("maintenance", original.maintenance)
	curveResponse.tilt = count("curve", original.curve)
	motion.speedFactor = count("speed", original.speed)
	motion.animationTimes = count("combined", original.combined)
	motion.animationTime = count("roll", original.roll)
	motion.prepareWaves = count("prepare", original.prepare)
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/settled_idle.mdl"
	configured.sections = { { lag = 0, wheelbase = 10 }, { lag = 12, wheelbase = 8 } }
	configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
	local function update(time, speed)
		animationStates = {}
		params.currentInfo.world.gameTime = time
		params.currentInfo.vehicle.speed = speed
		scripts.train.updateFn({}, params, output)
		return runtime.get(configured, params.vehicleStaticInfo.carriageEntity, params.vehicleStaticInfo.purchaseTime)
	end
	local function neutralPose()
		for index = 1, 2 do
			assertEqual(animationStates[constants.SWAY_SECTION_ANIMATION_PREFIX .. index], 2500, "idle roll is neutral")
			assertEqual(
				animationStates[constants.HEAVE_SECTION_ANIMATION_PREFIX .. index],
				2500,
				"idle heave is neutral"
			)
			assertEqual(
				animationStates[constants.PITCH_SECTION_ANIMATION_PREFIX .. index],
				2500,
				"idle pitch is neutral"
			)
		end
		assertEqual(type(animationStates.native_train), "number", "idle shortcuts preserve the native callback")
	end
	for _, interval in ipairs({ 0, 3 }) do
		configured.settings.samplingDistance = interval
		for _, speedDependent in ipairs({ false, true }) do
			configured.settings.speedDependent = speedDependent
			refreshRuntimeSettings()
			calls = {}
			for index, speed in ipairs({ 0, -4.999 / 3.6, 4.999 / 3.6 }) do
				update(index * 50, speed)
				assertEqual(
					next(calls),
					nil,
					"both sway modes skip response and waveform work while settled below 5 km/h"
				)
				neutralPose()
			end
		end
	end
	local moving = update(216, 20)
	assert(
		moving.sample.motionScale > 0 and moving.sample.motionScale < original.speed(20, "DEFAULT"),
		"a cold stopped carriage eases into motion"
	)
	local settling = update(232, 0)
	assert(settling.sample.motionScale > 0, "stopping retains the suspension settling period")
	for time = 248, 4000, 16 do
		update(time, 0)
	end
	neutralPose()
	calls = {}
	update(1000000, 0)
	update(5000, 0)
	assertEqual(next(calls), nil, "long stops and idle clock rewinds remain on the neutral shortcut")
	local restarted = update(5016, 20)
	assert(
		restarted.sample.motionScale > 0 and restarted.sample.motionScale < original.speed(20, "DEFAULT"),
		"the idle clock keeps restart damping after a long stop"
	)
	configuration.speedEnvelope = false
	refreshRuntimeSettings()
	calls = {}
	local settled = update(6000, 4.999 / 3.6)
	assertEqual(settled.sample.motionScale, 0, "developer isolation retains settled motion below 5 km/h")
	assertEqual(next(calls), nil, "developer isolation retains the settled shortcut below 5 km/h")
	local unbounded = update(8000, 5 / 3.6)
	assertEqual(unbounded.sample.motionScale, 1, "disabling the speed envelope uses full strength from 5 km/h")
	assert(calls.track and calls.combined, "developer isolation evaluates motion at the minimum speed")
	configuration.speedEnvelope = true
	trackResponse.response, vehicleResponse.maintenanceFactor, curveResponse.tilt =
		original.track, original.maintenance, original.curve
	motion.speedFactor, motion.animationTimes, motion.animationTime, motion.prepareWaves =
		original.speed, original.combined, original.roll, original.prepare
end

do
	local runtime = ug_require("apasz_swaying_waying::/swaying_waying/runtime_state.lua")
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/shared_consist.mdl"
	configured.sections = { { lag = 0, wheelbase = 10 }, { lag = 12, wheelbase = 8 } }
	configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
	refreshRuntimeSettings()
	local vehicle, land = params.currentInfo.vehicle, params.currentInfo.landVehicle
	local previousTrack = trackResponse.response
	local previousEntity, previousCarriage = params.entityId, params.vehicleStaticInfo.carriageEntity
	local previousCount, previousPosition = vehicle.carriageListLength, vehicle.positionInCarriageList
	local previousFacing, previousReversed = land.carriagesReversed, land.reversed
	trackResponse.response = function()
		return 1, 0.65
	end
	params.entityId, vehicle.carriageListLength, vehicle.speed = 10001, constants.MIN_SHARED_WAVE_CARRIAGES, 25
	land.carriagesReversed = {}
	for position = 0, vehicle.carriageListLength - 1 do
		land.carriagesReversed[position + 1] = position % 2 == 0
	end
	local function frame(time, distance, reversed)
		params.currentInfo.world.gameTime = time
		land.wheelAnimationInfo.totalDist = distance
		for position = vehicle.carriageListLength - 1, 0, -1 do
			vehicle.positionInCarriageList = position
			params.vehicleStaticInfo.carriageEntity = 11000 + position
			local facing = land.carriagesReversed[position + 1]
			land.reversed = reversed ~= facing
			animationStates = {}
			scripts.train.updateFn({}, params, output)
			local state =
				runtime.get(configured, params.vehicleStaticInfo.carriageEntity, params.vehicleStaticInfo.purchaseTime)
			local sample = state.sample
			local distanceBase = reversed and -distance or distance
			sample.waves = nil
			for index, section in ipairs(state.model.sections) do
				sample.distance = distance - section.lag
				sample.sharedDistance = distanceBase - position * 20 - (facing and -section.lag or section.lag)
				local roll, heave, pitch = motion.animationTimes(sample, state.model.motion, section.geometry)
				assertNear(
					animationStates[section.animations.roll],
					roll,
					1e-6,
					"shared controller roll matches direct motion"
				)
				assertNear(
					animationStates[section.animations.heave],
					heave,
					1e-6,
					"shared controller heave matches direct motion"
				)
				assertNear(
					animationStates[section.animations.pitch],
					pitch,
					1e-6,
					"shared controller pitch matches direct motion"
				)
			end
			assertEqual(type(animationStates.native_train), "number", "shared waves preserve the native callback")
		end
	end
	for index = 0, 3 do
		frame(10000 + index * 16, 500 + index, false)
	end
	local shared = runtime.get(configured, 11000, params.vehicleStaticInfo.purchaseTime)
	assert(shared.waves ~= nil, "the long consist uses shared bases after warming")
	for index = 0, 3 do
		frame(10100 + index * 16, 40 - index, true)
	end
	local waves = shared.waves
	vehicle.carriageListLength, vehicle.positionInCarriageList = 1, 0
	params.vehicleStaticInfo.carriageEntity = 11000
	land.carriagesReversed, land.reversed = { true }, false
	scripts.train.updateFn({}, params, output)
	assert(
		shared.sample.waves == nil and shared.waves == waves,
		"short consists bypass sharing without reallocating phases"
	)
	vehicle.carriageListLength = constants.MIN_SHARED_WAVE_CARRIAGES
	configured.settings.pitchBalance, configured.settings.heaveBalance = 0, 0
	refreshRuntimeSettings()
	scripts.train.updateFn({}, params, output)
	local rollOnly =
		runtime.get(configured, params.vehicleStaticInfo.carriageEntity, params.vehicleStaticInfo.purchaseTime)
	assert(rollOnly.waveBasis == nil and rollOnly.waves == nil, "roll-only motion bypasses shared-wave preparation")
	params.entityId, params.vehicleStaticInfo.carriageEntity = previousEntity, previousCarriage
	vehicle.carriageListLength, vehicle.positionInCarriageList = previousCount, previousPosition
	land.carriagesReversed, land.reversed = previousFacing, previousReversed
	trackResponse.response = previousTrack
end

do
	local calls, fail = 0, false
	local emitted
	moduleOverrides["apasz_swaying_waying::/swaying_waying/lod_probe.lua"] = {
		observe = function(received, receivedOutput, modelFile)
			assertEqual(received, params, "LOD observation receives the actual carriage parameters")
			assertEqual(receivedOutput, emitted, "LOD observation receives the native output")
			assertEqual(modelFile, "tests::/lod_probe.mdl", "LOD observation identifies the authored model")
			assertEqual(type(animationStates.native_train), "number", "native output exists before LOD inspection")
			assertEqual(animationStates[constants.SWAY_ANIMATION], nil, "LOD inspection precedes added sway")
			calls = calls + 1
			if fail then
				error("injected LOD observation failure")
			end
			return true
		end,
	}
	local observed = dofile("content/swaying_waying/vehicle/transformator.script.lua")
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile, configured.sections = "tests::/lod_probe.mdl", {}
	refreshRuntimeSettings()
	emitted = output
	local function update(time, speed)
		animationStates = {}
		params.currentInfo.world.gameTime, params.currentInfo.vehicle.speed = time, speed
		observed.train.updateFn({}, params, output)
		assertEqual(type(animationStates[constants.SWAY_ANIMATION]), "number", "LOD diagnostics preserve added motion")
	end
	update(20000, 0)
	assertEqual(calls, 1, "settled idle still permits paused zoom investigation")
	fail = true
	local previousWarnings = #warnings
	update(20016, 25)
	update(20032, 25)
	assertEqual(calls, 2, "failed LOD inspection disables itself")
	assertEqual(#warnings, previousWarnings + 1, "failed LOD inspection logs once")
	moduleOverrides["apasz_swaying_waying::/swaying_waying/lod_probe.lua"] = {}
end

do
	local probeCalls, probeAverage, failProbe = 0, nil, false
	local beforeOutput
	moduleOverrides["apasz_swaying_waying::/swaying_waying/curvature_probe.lua"] = {
		observe = function(received, average)
			assertEqual(received, params, "the observer receives the actual carriage parameters")
			assertEqual(type(beforeOutput[constants.SWAY_ANIMATION]), "number", "motion is emitted before observation")
			probeCalls = probeCalls + 1
			probeAverage = average
			if failProbe then
				error("injected observation failure")
			end
			return true
		end,
	}
	local observedScripts = dofile("content/swaying_waying/vehicle/transformator.script.lua")
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/curvature_probe.mdl"
	configured.sections = {}
	configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
	refreshRuntimeSettings()
	params.currentInfo.vehicle.speed = 20
	params.currentInfo.landVehicle.reversed = false
	params.landVehicleApi.getAverageCurvature = function()
		return 0.002
	end
	local observedOutput = {
		addAnimationState = function(_, name, _, value)
			beforeOutput[name] = value
		end,
	}
	local function update(time)
		beforeOutput = {}
		params.currentInfo.world.gameTime = time
		observedScripts.train.updateFn({}, params, observedOutput)
		assertEqual(type(beforeOutput.native_train), "number", "diagnostics preserve native motion")
		assertEqual(type(beforeOutput[constants.SWAY_ANIMATION]), "number", "diagnostics preserve sway")
	end
	update(5000)
	assertEqual(probeAverage, 0.002, "observation reuses the actual curvature query")
	assertEqual(probeCalls, 1, "the controller observes each carriage once")
	local previousWarnings = #warnings
	failProbe = true
	update(5016)
	assertEqual(#warnings, previousWarnings + 1, "observation failures are reported once")
	update(5032)
	assertEqual(probeCalls, 2, "a failed observer is disabled without stopping animation")
	assertEqual(#warnings, previousWarnings + 1, "a failed observer does not repeat work or warnings")
end

do
	local configured = params.transformatorConfigParams.swayingWaying
	configured.modelFile = "tests::/logging_context_a.mdl"
	configured.sections = {}
	configured.settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
	refreshRuntimeSettings()
	params.currentInfo.vehicle.speed = 20
	local originalCurve = curveResponse.tilt
	local failedAttempts = 0
	curveResponse.tilt = function()
		failedAttempts = failedAttempts + 1
		error("injected shared runtime failure " .. failedAttempts)
	end
	local before = #warnings
	for _ = 1, 100 do
		scripts.train.updateFn({}, params, output)
	end
	assertEqual(#warnings, before + 1, "changing runtime failure details still log once per model and category")
	local diagnostic = warnings[#warnings]
	for _, detail in ipairs({
		"injected shared runtime failure",
		"model=tests::/logging_context_a.mdl",
		"transformator=" .. configured.originalTransformator,
		"revision=" .. configured.revision,
		"vehicle=" .. params.entityId,
		"carriage=" .. params.vehicleStaticInfo.carriageEntity,
	}) do
		assert(diagnostic:find(detail, 1, true), "runtime diagnostics include " .. detail)
	end
	configured.modelFile = "tests::/logging_context_b.mdl"
	scripts.train.updateFn({}, params, output)
	assertEqual(#warnings, before + 2, "an identical failure on a different model is not suppressed")
	configured.revision = configured.revision + 1
	scripts.train.updateFn({}, params, output)
	assertEqual(#warnings, before + 3, "a new model revision receives a fresh diagnostic")
	params.transformatorConfigParams.swayingWaying = nil
	scripts.train.updateFn({}, params, output)
	assertEqual(#warnings, before + 4, "diagnostics survive missing runtime configuration")
	assert(warnings[#warnings]:find("model=unavailable", 1, true), "unreadable identities are explicit in the warning")
	params.transformatorConfigParams.swayingWaying = configured
	curveResponse.tilt = originalCurve
end

do
	local savedConfig = params.transformatorConfigParams
	local previousWarnings = #warnings
	local callbacks = {
		function()
			scripts.any.updateFn({}, params, output)
		end,
		function()
			scripts.any.updateParticleSystemFn({}, params, {})
		end,
		function()
			assertEqual(
				#scripts.any.getEmittableModelsFn({}, params),
				0,
				"unresolved model discovery returns no resources"
			)
		end,
		function()
			scripts.any.computeEmittedModelsFn({}, params, {})
		end,
	}
	for _, missingContainer in ipairs({ false, true }) do
		if missingContainer then
			params.transformatorConfigParams = nil
		else
			params.transformatorConfigParams = {}
		end
		for _, callback in ipairs(callbacks) do
			assert(pcall(callback), "every custom callback contains missing runtime configuration failures")
		end
	end
	assertEqual(#warnings, previousWarnings + 1, "origin resolution failures share one warning category")
	assert(
		warnings[#warnings]:find("Could not resolve original vehicle transformator", 1, true),
		"origin resolution failures explain which operation was skipped"
	)
	params.transformatorConfigParams = savedConfig

	local configured = savedConfig.swayingWaying
	configured.modelFile = "tests::/origin_retry.mdl"
	configured.originalTransformator = "custom.trf"
	refreshRuntimeSettings()
	local loader = ug_require("apasz_swaying_waying::/swaying_waying/origin_loader.lua")
	local savedGet, attempts = loader.get, 0
	loader.get = function()
		attempts = attempts + 1
		if attempts == 1 then
			error("transient origin resolution failure")
		end
		return customOrigin
	end
	local priorUpdates = customCalls.update
	assert(pcall(scripts.any.updateFn, {}, params, output), "origin resolver exceptions stay inside the callback guard")
	assertEqual(customCalls.update, priorUpdates, "failed origin resolution does not invent an authored callback")
	scripts.any.updateFn({}, params, output)
	assertEqual(customCalls.update, priorUpdates + 1, "a later callback retries failed origin resolution")
	scripts.any.updateFn({}, params, output)
	assertEqual(attempts, 2, "a successful retry caches its authored callback")
	loader.get = savedGet
end

print("Runtime checks passed")
