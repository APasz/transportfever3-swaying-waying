local assertions = dofile("tests/assertions.lua")
local assertEqual = assertions.equal
local assertNear = assertions.near
local harness = dofile("tests/support/harness.lua").new()
local motionConfig = harness.require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
local motion = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
local irregularity = harness.require("apasz_swaying_waying::/swaying_waying/irregularity.lua")
-- Keep exact sinusoidal reference checks independent of the new component.
motionConfig.irregularity = false

for _, profile in ipairs({ "DEFAULT", "QUICK", "SLOW" }) do
	assertEqual(motion.speedFactor(0, profile), 0, "On targets neutral at rest")
	assertNear(motion.speedFactor(5 / 3.6, profile), 0.05, 0.000001, "On starts with 5% strength at 5 km/h")
	assertNear(motion.speedFactor(-5 / 3.6, profile), 0.05, 0.000001, "On starts with 5% strength in reverse")
	assertEqual(motion.speedFactor(100, profile), 1, "On remains capped at full strength")
	assertEqual(motion.speedFactor(0, profile, false), 0, "Speedless Sway targets neutral at rest")
	for _, speed in ipairs({ -4.999 / 3.6, -0.001, 0, 0.001, 4.999 / 3.6 }) do
		for _, speedDependent in ipairs({ true, false }) do
			assertEqual(motion.speedFactor(speed, profile, speedDependent), 0, "both modes target neutral below 5 km/h")
		end
	end
	for _, speed in ipairs({ -100, -5.001 / 3.6, -5 / 3.6, 5 / 3.6, 5.001 / 3.6, 2, 20, 100 }) do
		assertEqual(
			motion.speedFactor(speed, profile, false),
			1,
			"Speedless Sway has full strength from 5 km/h in every profile"
		)
		assertEqual(
			motion.speedFactor(speed, profile, true),
			motion.speedFactor(speed, profile),
			"On is the default speed envelope"
		)
	end
end
assertNear(
	motion.speedFactor(64 / 3.6, "DEFAULT"),
	0.525,
	0.000001,
	"On ramps smoothly between minimum and full strength"
)
assert(not pcall(motion.speedFactor, 10, "DEFAULT", "false"), "invalid speed-dependence flags fail explicitly")

local function sampleAt(speed, distance, phaseSeed, shortWeight, profileName)
	return {
		motionScale = motion.speedFactor(speed, profileName or "DEFAULT"),
		distance = distance,
		phaseSeed = phaseSeed,
		sharedDistance = distance,
		sharedPhaseSeed = 0,
		sharedAxisReversed = false,
		curveTilt = 0.5,
		swayFactor = 1.0,
		shortWeight = shortWeight,
	}
end

assertNear(
	motion.swayDegrees(sampleAt(2.0, 15.0, 7, 0.65), "DEFAULT"),
	0.05 * motion.swayDegrees(sampleAt(120.0 / 3.6, 15.0, 7, 0.65), "DEFAULT"),
	0.000001,
	"default profile retains minimum sway below its ramp threshold"
)
assertNear(
	motion.swayDegrees(sampleAt(120.0 / 3.6, 10.0, 0, 0.65), "DEFAULT"),
	1.2 * (0.52 + 0.28 * math.sin(2.0 * math.pi * 10.0 / 65.0) + 0.20 * math.sin(2.0 * math.pi * 10.0 / 97.0)),
	0.000001,
	"default profile reaches full sway at 120 km/h"
)
assertNear(
	motion.swayDegrees(sampleAt(90.0 / 3.6, 7.5, 0, 0.65, "QUICK"), "QUICK"),
	1.2 * (0.52 + 0.28 * math.sin(2.0 * math.pi * 7.5 / 65.0) + 0.20 * math.sin(2.0 * math.pi * 7.5 / 73.0)),
	0.000001,
	"quick profile reaches full sway at 90 km/h"
)
assertNear(
	motion.swayDegrees(sampleAt(160.0 / 3.6, 14.0, 0, 0.65, "SLOW"), "SLOW"),
	1.2 * (0.52 + 0.28 * math.sin(2.0 * math.pi * 14.0 / 65.0) + 0.20 * math.sin(2.0 * math.pi * 14.0 / 137.0)),
	0.000001,
	"slow profile reaches full sway at 160 km/h"
)
assertNear(
	motion.swayDegrees(sampleAt(18.0 / 3.6, 14.0, 0, 0.65, "SLOW"), "SLOW"),
	0.05 * motion.swayDegrees(sampleAt(160.0 / 3.6, 14.0, 0, 0.65, "SLOW"), "SLOW"),
	0.000001,
	"slow profile retains minimum sway at its ramp threshold"
)
assertNear(motion.curveLeanDegrees(0.5), 0.0, 0.000001, "straight track is level")
assertNear(motion.curveLeanDegrees(1.0), -1.5, 0.000001, "curve lean is outward")
assertNear(motion.curveLeanDegrees(0 / 0), 0, 0.000001, "invalid curve tilt is neutral")
assertNear(
	motion.animationTime({
		motionScale = motion.speedFactor(0.0, "DEFAULT"),
		distance = 0.0,
		phaseSeed = 1,
		sharedDistance = 0.0,
		sharedPhaseSeed = 0,
		sharedAxisReversed = false,
		curveTilt = 0.5,
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
	2500.0,
	0.000001,
	"stationary animation is centred"
)
assertEqual(motion.animationTime({
	motionScale = motion.speedFactor(30.0, "DEFAULT"),
	distance = 123.0,
	phaseSeed = 11,
	sharedDistance = 123.0,
	sharedPhaseSeed = 0,
	sharedAxisReversed = false,
	curveTilt = 1.0,
	swayFactor = 1.0,
	shortWeight = 0.65,
}, {
	rollIntensity = 100.0,
	pitchIntensity = 1.0,
	heaveIntensity = 1.0,
	curveLeanIntensity = 100.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
}) >= 2500.0 - 8.0 * 277.778, true, "animation is lower-clamped")
assertEqual(motion.animationTime({
	motionScale = motion.speedFactor(30.0, "DEFAULT"),
	distance = 123.0,
	phaseSeed = 11,
	sharedDistance = 123.0,
	sharedPhaseSeed = 0,
	sharedAxisReversed = false,
	curveTilt = 0.0,
	swayFactor = 1.0,
	shortWeight = 0.65,
}, {
	rollIntensity = 100.0,
	pitchIntensity = 1.0,
	heaveIntensity = 1.0,
	curveLeanIntensity = 100.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
}) <= 2500.0 + 8.0 * 277.778, true, "animation is upper-clamped")
local responseTestSway = motion.swayDegrees(sampleAt(18.0, 123.0, 11, 0.65), "DEFAULT")
local responseTestLean = motion.curveLeanDegrees(1.0)
assertNear(
	motion.animationTime({
		motionScale = motion.speedFactor(18.0, "DEFAULT"),
		distance = 123.0,
		phaseSeed = 11,
		sharedDistance = 123.0,
		sharedPhaseSeed = 0,
		sharedAxisReversed = false,
		curveTilt = 1.0,
		swayFactor = 0.7,
		shortWeight = 0.65,
	}, {
		rollIntensity = 0.5,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.5,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}),
	2500.0 + (responseTestSway * 0.7 * 0.5 + responseTestLean * 1.5) * 277.778,
	0.000001,
	"sway and curve-lean intensities are independent"
)

local stoppedHeave, stoppedPitch = motion.secondaryMotion(sampleAt(0.0, 123.0, 11, 0.65), "DEFAULT", 10.0)
assertNear(stoppedHeave, 0.0, 0.000001, "stationary vehicles have no procedural heave")
assertNear(stoppedPitch, 0.0, 0.000001, "stationary vehicles have no procedural pitch")
local stationaryGeometry = motion.secondaryGeometry("DEFAULT", 10.0)
local originalSin = math.sin
local originalCos = math.cos
local trigonometricCalls = 0
math.sin = function(value)
	trigonometricCalls = trigonometricCalls + 1
	return originalSin(value)
end
math.cos = function(value)
	trigonometricCalls = trigonometricCalls + 1
	return originalCos(value)
end
motion.animationTimes({
	motionScale = motion.speedFactor(0.0, "DEFAULT"),
	distance = 123.0,
	phaseSeed = 11,
	sharedDistance = 123.0,
	sharedPhaseSeed = 0,
	sharedAxisReversed = false,
	curveTilt = 0.5,
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
}, stationaryGeometry)
assertEqual(trigonometricCalls, 0, "stationary combined motion skips waveform evaluation")
motion.animationTimes({
	motionScale = motion.speedFactor(120.0 / 3.6, "DEFAULT"),
	distance = 123.0,
	phaseSeed = 11,
	sharedDistance = 123.0,
	sharedPhaseSeed = 0,
	sharedAxisReversed = false,
	curveTilt = 0.5,
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
}, stationaryGeometry)
math.sin = originalSin
math.cos = originalCos
assertEqual(trigonometricCalls, 6, "three-wave combined motion evaluates six trigonometric terms")
local movingHeave, movingPitch = motion.secondaryMotion(sampleAt(120.0 / 3.6, 123.0, 11, 0.65), "DEFAULT", 10.0)
assertEqual(math.abs(movingHeave) <= 0.02, true, "default heave remains within two centimetres")
assertEqual(math.abs(movingPitch) <= 0.2, true, "default pitch remains within 0.2 degrees")
assertEqual(math.abs(movingHeave) > 0.000001, true, "moving vehicles receive vertical motion")
assertEqual(math.abs(movingPitch) > 0.000001, true, "moving vehicles receive longitudinal rocking")
local heaveTime, pitchTime = motion.secondaryAnimationTimes(0.02, 0.2, 1.0, {
	rollIntensity = 1.0,
	pitchIntensity = 1.0,
	heaveIntensity = 1.0,
	curveLeanIntensity = 1.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
})
assertNear(heaveTime, 3000.0, 0.000001, "two centimetres maps to the heave animation")
assertNear(pitchTime, 3000.0, 0.000001, "0.2 degrees maps to the pitch animation")
local _, mirroredPitchTime = motion.secondaryAnimationTimes(0.02, 0.2, 1.0, {
	rollIntensity = 1.0,
	pitchIntensity = 1.0,
	heaveIntensity = 1.0,
	curveLeanIntensity = 1.0,
	modelAxisSign = -1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
})
assertNear(mirroredPitchTime, 2000.0, 0.000001, "mirrored models reverse pitch without reversing heave")
local balancedHeaveTime, balancedPitchTime = motion.secondaryAnimationTimes(0.02, 0.2, 1.0, {
	rollIntensity = 1.0,
	pitchIntensity = 1.5,
	heaveIntensity = 0.5,
	curveLeanIntensity = 1.0,
	modelAxisSign = 1.0,
	profile = "DEFAULT",
	secondaryMotionEnabled = true,
})
assertNear(balancedHeaveTime, 2750.0, 0.000001, "heave balance scales vertical movement independently")
assertNear(balancedPitchTime, 3250.0, 0.000001, "pitch balance scales rocking independently")

for _, sample in ipairs({
	{ speed = 0.0, distance = 0.0, profile = "DEFAULT", wheelbase = 10.0, modelAxisSign = 1.0 },
	{ speed = 90.0 / 3.6, distance = 73.0, profile = "QUICK", wheelbase = 6.0, modelAxisSign = -1.0 },
	{ speed = 120.0 / 3.6, distance = 123.0, profile = "DEFAULT", wheelbase = 10.0, modelAxisSign = 1.0 },
	{ speed = 160.0 / 3.6, distance = -41.0, profile = "SLOW", wheelbase = 18.0, modelAxisSign = -1.0 },
}) do
	local combinedRoll, combinedHeave, combinedPitch = motion.animationTimes({
		motionScale = motion.speedFactor(sample.speed, sample.profile),
		distance = sample.distance,
		phaseSeed = 11,
		sharedDistance = sample.distance,
		sharedPhaseSeed = 0,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 0.9,
		shortWeight = 0.6,
	}, {
		rollIntensity = 1.25,
		pitchIntensity = 1.25,
		heaveIntensity = 1.25,
		curveLeanIntensity = 0.8,
		modelAxisSign = sample.modelAxisSign,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}, motion.secondaryGeometry(sample.profile, sample.wheelbase))
	local separateRoll = motion.animationTime({
		motionScale = motion.speedFactor(sample.speed, sample.profile),
		distance = sample.distance,
		phaseSeed = 11,
		sharedDistance = sample.distance,
		sharedPhaseSeed = 0,
		sharedAxisReversed = false,
		curveTilt = 0.75,
		swayFactor = 0.9,
		shortWeight = 0.6,
	}, {
		rollIntensity = 1.25,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 0.8,
		modelAxisSign = sample.modelAxisSign,
		profile = sample.profile,
		secondaryMotionEnabled = true,
	})
	local sampledHeave, sampledPitch = motion.secondaryMotion(
		sampleAt(sample.speed, sample.distance, 11, 0.6, sample.profile),
		sample.profile,
		sample.wheelbase
	)
	local separateHeave, separatePitch = motion.secondaryAnimationTimes(sampledHeave, sampledPitch, 0.9, {
		rollIntensity = 1.0,
		pitchIntensity = 1.25,
		heaveIntensity = 1.25,
		curveLeanIntensity = 1.0,
		modelAxisSign = sample.modelAxisSign,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	})
	assertNear(combinedRoll, separateRoll, 0.000001, "combined roll matches the independent calculation")
	assertNear(combinedHeave, separateHeave, 0.000001, "combined heave matches the independent calculation")
	assertNear(combinedPitch, separatePitch, 0.000001, "combined pitch matches the independent calculation")
end

local referenceProfiles = {
	QUICK = { short = 30.0, third = 73.0 },
	DEFAULT = { short = 40.0, third = 97.0 },
	SLOW = { short = 56.0, third = 137.0 },
}

local function referencePhase(seed)
	return (seed % 997) * 0.61803 * 2.0 * math.pi
end

local function referenceShortCycles(distance, wavelength, seed)
	local cycles = distance / wavelength
	return motionConfig.irregularity and irregularity.warp(cycles, seed) or cycles
end

local function individualSway(sample, profileName)
	local profile = referenceProfiles[profileName]
	local phase = referencePhase(sample.phaseSeed)
	return 1.2
		* (
			0.8
				* sample.shortWeight
				* math.sin(
					2.0 * math.pi * referenceShortCycles(sample.distance, profile.short, sample.phaseSeed) + phase
				)
			+ 0.2 * math.sin(2.0 * math.pi * sample.distance / profile.third + phase * 2.3)
		)
end

local function referenceHeight(sample, profileName, offset, longSeed)
	local profile = referenceProfiles[profileName]
	local phase = referencePhase(sample.phaseSeed) + 0.37 * 2.0 * math.pi
	local longPhase = referencePhase(longSeed) + 0.37 * 2.0 * math.pi
	local sharedOffset = sample.sharedAxisReversed and -offset or offset
	local regular = 0.025
		* (
			0.8
				* sample.shortWeight
				* math.sin(
					2.0 * math.pi * referenceShortCycles(sample.distance + offset, profile.short, sample.phaseSeed)
						+ phase
				)
			+ 0.8 * (1.0 - sample.shortWeight) * math.sin(
				2.0 * math.pi * (sample.sharedDistance + sharedOffset) / 65.0 + longPhase * 1.7
			)
			+ 0.2 * math.sin(2.0 * math.pi * (sample.distance + offset) / profile.third + phase * 2.3)
		)
	if motionConfig.irregularity then
		return 0.025
			* irregularity.blend(
				regular / 0.025,
				irregularity.vertical((sample.distance + offset) / (profile.short * 0.5), sample.phaseSeed)
			)
	end
	return regular
end

local function limit(value, magnitude)
	return math.max(-magnitude, math.min(magnitude, value))
end

for _, irregular in ipairs({ false, true }) do
	motionConfig.irregularity = irregular
	for _, mode in ipairs({ { carriageLag = true, seed = 73 }, { carriageLag = false, seed = 31 } }) do
		motionConfig.carriageLag = mode.carriageLag
		for profileName in pairs(referenceProfiles) do
			local settings = {
				rollIntensity = 1.0,
				pitchIntensity = 1.0,
				heaveIntensity = 1.0,
				curveLeanIntensity = 0.0,
				modelAxisSign = 1.0,
				profile = profileName,
				secondaryMotionEnabled = true,
			}
			for _, wheelbase in ipairs({ 2.0, 10.0, 30.0 }) do
				local geometry = motion.secondaryGeometry(profileName, wheelbase)
				assertEqual(geometry, motion.secondaryGeometry(profileName, wheelbase), "three-wave geometry is cached")
				for _, distance in ipairs({ -41.0, 0.0, 123.0, 100000.0 }) do
					for _, shortWeight in ipairs({ 0.0, 0.45, 0.65, 0.80, 1.0 }) do
						local sample = sampleAt(60.0, distance, 31, shortWeight)
						sample.sharedDistance = -distance - 80.0
						sample.sharedPhaseSeed = 73
						sample.sharedAxisReversed = shortWeight < 0.5
						local roll, heave, pitch = motion.animationTimes(sample, settings, geometry)
						local front = referenceHeight(sample, profileName, wheelbase * 0.5, mode.seed)
						local rear = referenceHeight(sample, profileName, -wheelbase * 0.5, mode.seed)
						local expectedSway = individualSway(sample, profileName)
							+ 1.2
								* 0.8
								* (1.0 - shortWeight)
								* (sample.sharedAxisReversed and -1.0 or 1.0)
								* math.sin(
									2.0 * math.pi * sample.sharedDistance / 65.0 + referencePhase(mode.seed) * 1.7
								)
						if irregular then
							expectedSway = 1.2
								* irregularity.blend(
									expectedSway / 1.2,
									irregularity.lateral(
										sample.distance / (referenceProfiles[profileName].short * 0.5),
										sample.phaseSeed
									)
								)
						end
						local expectedHeave = limit((front + rear) * 0.5, 0.02)
						local expectedPitch = limit((front - rear) / wheelbase * 180.0 / math.pi, 0.2)
						assertNear(
							roll,
							2500.0 + expectedSway * 277.778,
							0.000001,
							"roll matches either long-wave phase mode"
						)
						assertNear(
							heave,
							2500.0 + expectedHeave * 25000.0,
							0.000001,
							"heave matches independent support samples"
						)
						assertNear(
							pitch,
							2500.0 + expectedPitch * 2500.0,
							0.000001,
							"pitch matches independent support samples"
						)
						assertEqual(math.abs(expectedSway) <= 1.2, true, "three-wave weights preserve the roll ceiling")
					end
				end
			end
		end
	end
end
motionConfig.irregularity = false
motionConfig.carriageLag = true

for _, reversed in ipairs({ false, true }) do
	local leadIndex = reversed and 4 or 0
	local lead = sampleAt(60.0, 123.0, 31, 0.65)
	lead.sharedPhaseSeed = 11
	lead.sharedDistance = (reversed and -123.0 or 123.0) - leadIndex * 20.0
	local leadShared = motion.swayDegrees(lead, "DEFAULT") - individualSway(lead, "DEFAULT")
	for step, profileName in ipairs({ "QUICK", "DEFAULT", "SLOW", "DEFAULT" }) do
		local index = reversed and (leadIndex - step) or step
		local follower = sampleAt(60.0, 123.0 + step * 20.0, 31 + step, 0.65)
		follower.sharedPhaseSeed = lead.sharedPhaseSeed
		follower.sharedAxisReversed = step % 2 == 1
		follower.sharedDistance = (reversed and -follower.distance or follower.distance) - index * 20.0
		local followerShared = motion.swayDegrees(follower, profileName) - individualSway(follower, profileName)
		if follower.sharedAxisReversed then
			followerShared = -followerShared
		end
		assertNear(
			followerShared,
			leadShared,
			0.000001,
			"the same physical shared sway reaches following mixed-profile carriages facing either way"
		)
	end
end

do
	motionConfig.carriageLag = false
	motionConfig.shortWave = false
	motionConfig.thirdWave = false
	local sample = sampleAt(60.0, 123.0, 31, 0.65)
	sample.sharedPhaseSeed = 11
	local original = motion.swayDegrees(sample, "DEFAULT")
	assertNear(
		original,
		1.2 * 0.8 * 0.35 * math.sin(2.0 * math.pi * 123.0 / 65.0 + referencePhase(31) * 1.7),
		0.000001,
		"an isolated per-carriage long wave uses the carriage phase"
	)
	sample.phaseSeed = 32
	local nextCarriage = motion.swayDegrees(sample, "DEFAULT")
	assertEqual(math.abs(nextCarriage - original) > 0.001, true, "each carriage has its own long-wave phase")
	sample.sharedPhaseSeed = 12
	assertNear(
		motion.swayDegrees(sample, "DEFAULT"),
		nextCarriage,
		0.000001,
		"the independent long-wave phase does not use the consist cache key"
	)
	sample.sharedDistance = sample.sharedDistance + 65.0
	assertNear(motion.swayDegrees(sample, "DEFAULT"), nextCarriage, 0.000001, "the long wavelength remains 65 m")
	motionConfig.carriageLag = true
	motionConfig.shortWave = true
	motionConfig.thirdWave = true
end

do
	local sample = sampleAt(60.0, 123.0, 31, 0.65)
	sample.sharedDistance = 83.0
	sample.sharedPhaseSeed = 11
	local settings = {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 0.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}
	motionConfig.shortWave = false
	motionConfig.thirdWave = false
	for _, profileName in ipairs({ "QUICK", "DEFAULT", "SLOW" }) do
		settings.profile = profileName
		for _, wheelbase in ipairs({ 2.0, 10.0, 30.0 }) do
			local geometry = motion.secondaryGeometry(profileName, wheelbase)
			for _, modelAxisSign in ipairs({ -1.0, 1.0 }) do
				settings.modelAxisSign = modelAxisSign
				sample.sharedAxisReversed = false
				local forward = { motion.animationTimes(sample, settings, geometry) }
				sample.sharedAxisReversed = true
				local backward = { motion.animationTimes(sample, settings, geometry) }
				assertNear(backward[1], 5000.0 - forward[1], 0.000001, "shared roll follows carriage axes")
				assertNear(backward[2], forward[2], 0.000001, "shared heave is independent of carriage facing")
				assertNear(backward[3], 5000.0 - forward[3], 0.000001, "shared pitch follows carriage axes")
				local heave, pitch = motion.secondaryMotion(sample, profileName, wheelbase)
				local heaveTime, pitchTime = motion.secondaryAnimationTimes(heave, pitch, sample.swayFactor, settings)
				assertNear(
					backward[1],
					motion.animationTime(sample, settings),
					0.000001,
					"roll-only orientation matches combined motion"
				)
				assertNear(
					backward[2],
					heaveTime,
					0.000001,
					"shared heave matches direct support samples in either orientation"
				)
				assertNear(
					backward[3],
					pitchTime,
					0.000001,
					"shared pitch matches direct support samples in either orientation"
				)
			end
		end
	end
	motionConfig.shortWave = true
	motionConfig.thirdWave = true
	motionConfig.longWave = false
	settings.curveLeanIntensity = 1.0
	sample.curveTilt = 0.75
	local geometry = motion.secondaryGeometry(settings.profile, 10.0)
	sample.sharedAxisReversed = false
	local forward = { motion.animationTimes(sample, settings, geometry) }
	sample.sharedAxisReversed = true
	local backward = { motion.animationTimes(sample, settings, geometry) }
	for channel = 1, 3 do
		assertNear(
			backward[channel],
			forward[channel],
			0.000001,
			"shared orientation preserves individual waves and curve lean"
		)
	end
	motionConfig.longWave = true
end

do
	local first = sampleAt(60.0, 123.0, 31, 0.65)
	first.sharedPhaseSeed = 11
	local second = sampleAt(60.0, first.distance, 32, first.shortWeight)
	second.sharedPhaseSeed = first.sharedPhaseSeed
	local firstSway = motion.swayDegrees(first, "DEFAULT")
	assertEqual(
		math.abs(firstSway - motion.swayDegrees(second, "DEFAULT")) > 0.001,
		true,
		"carriages retain individual motion"
	)
	second.phaseSeed = first.phaseSeed
	second.sharedPhaseSeed = 12
	assertEqual(
		math.abs(firstSway - motion.swayDegrees(second, "DEFAULT")) > 0.001,
		true,
		"different consists have distinct shared phases"
	)
	first.distance = first.distance + 520.0
	first.sharedDistance = first.sharedDistance + 520.0
	assertEqual(
		math.abs(firstSway - motion.swayDegrees(first, "DEFAULT")) > 0.001,
		true,
		"the third wave breaks the former 520 metre repeat"
	)
end

do
	local sample = sampleAt(12.0, 123.0, 31, 0.65)
	sample.sharedDistance = 83.0
	sample.sharedPhaseSeed = 11
	local settings = {
		rollIntensity = 1.0,
		pitchIntensity = 1.0,
		heaveIntensity = 1.0,
		curveLeanIntensity = 1.0,
		modelAxisSign = 1.0,
		profile = "DEFAULT",
		secondaryMotionEnabled = true,
	}
	local geometry = motion.secondaryGeometry("DEFAULT", 10.0)
	local function frame()
		return { motion.animationTimes(sample, settings, geometry) }
	end
	local baseline = frame()
	local waveNames = { "shortWave", "longWave", "thirdWave" }
	local contributions = {}
	for _, selected in ipairs(waveNames) do
		for _, name in ipairs(waveNames) do
			motionConfig[name] = name == selected
		end
		local isolated = frame()
		contributions[selected] = isolated
		local heave, pitch = motion.secondaryMotion(sample, "DEFAULT", 10.0)
		local heaveTime, pitchTime = motion.secondaryAnimationTimes(heave, pitch, sample.swayFactor, settings)
		assertNear(
			isolated[1],
			motion.animationTime(sample, settings),
			0.000001,
			"isolated roll uses the same wave mask"
		)
		assertNear(isolated[2], heaveTime, 0.000001, "isolated heave retains coherent support samples")
		assertNear(isolated[3], pitchTime, 0.000001, "isolated pitch retains coherent support samples")
	end
	for channel = 1, 3 do
		local sum = 2500.0
		for _, name in ipairs(waveNames) do
			sum = sum + contributions[name][channel] - 2500.0
		end
		assertNear(sum, baseline[channel], 0.000001, "isolating waves preserves their original weights")
	end

	local sine = math.sin
	local cosine = math.cos
	local calls = 0
	math.sin = function(angle)
		calls = calls + 1
		return sine(angle)
	end
	math.cos = function(angle)
		calls = calls + 1
		return cosine(angle)
	end
	for mask = 0, 7 do
		local active = 0
		for index, name in ipairs(waveNames) do
			local enabled = math.floor(mask / 2 ^ (index - 1)) % 2 == 1
			motionConfig[name] = enabled
			active = active + (enabled and 1 or 0)
		end
		calls = 0
		frame()
		assertEqual(calls, active * 2, "disabled waves skip combined trigonometry")
		calls = 0
		motion.animationTime(sample, settings)
		assertEqual(calls, active, "disabled waves skip roll-only trigonometry")
	end
	for _, name in ipairs(waveNames) do
		motionConfig[name] = true
	end
	settings.secondaryMotionEnabled = false
	calls = 0
	local rollOnly = frame()
	assertEqual(calls, 3, "disabled secondary game setting uses roll-only trigonometry")
	assertNear(rollOnly[1], baseline[1], 0.000001, "disabled secondary setting preserves roll")
	assertNear(rollOnly[2], 2500.0, 0.000001, "disabled secondary setting centres heave")
	assertNear(rollOnly[3], 2500.0, 0.000001, "disabled secondary setting centres pitch")
	local disabledHeave, disabledPitch = motion.secondaryAnimationTimes(0.01, 0.1, 1.0, settings)
	assertNear(disabledHeave, 2500.0, 0.000001, "direct secondary mapping respects the game setting")
	assertNear(disabledPitch, 2500.0, 0.000001, "direct pitch mapping respects the game setting")
	settings.secondaryMotionEnabled = true
	settings.pitchIntensity = 0.0
	settings.heaveIntensity = 0.0
	calls = 0
	frame()
	assertEqual(calls, 3, "zero secondary intensity uses roll-only trigonometry")
	settings.rollIntensity = 0.0
	sample.curveTilt = 1.0
	calls = 0
	local leanOnly = frame()
	assertEqual(calls, 0, "zero procedural intensities skip all waveform evaluation")
	assertNear(leanOnly[1], 2500.0 - 1.5 * 277.778, 0.000001, "zero procedural intensity preserves curve lean")
	settings.rollIntensity = 1.0
	settings.pitchIntensity = 1.0
	settings.heaveIntensity = 1.0
	sample.curveTilt = 0.5
	motionConfig.shortWave = false
	motionConfig.longWave = true
	motionConfig.thirdWave = false
	motionConfig.pitch = false
	motionConfig.heave = false
	calls = 0
	local isolatedRoll = frame()
	assertEqual(calls, 1, "long-wave roll isolation uses one sine")
	assertNear(isolatedRoll[2], 2500.0, 0.000001, "disabled heave is centred")
	assertNear(isolatedRoll[3], 2500.0, 0.000001, "disabled pitch is centred")
	motionConfig.roll = false
	calls = 0
	local disabled = frame()
	assertEqual(calls, 0, "disabling every axis skips all waveform evaluation")
	math.sin = sine
	math.cos = cosine
	for channel = 1, 3 do
		assertNear(disabled[channel], 2500.0, 0.000001, "every disabled axis is centred")
	end
	assertNear(motion.swayDegrees(sample, "DEFAULT"), 0.0, 0.000001, "roll switch also controls raw sway")
	assertNear(motion.curveLeanDegrees(1.0), 0.0, 0.000001, "roll switch also disables curve lean")
	local heave, pitch = motion.secondaryMotion(sample, "DEFAULT", 10.0)
	assertNear(heave, 0.0, 0.000001, "heave switch also controls raw suspension motion")
	assertNear(pitch, 0.0, 0.000001, "pitch switch also controls raw suspension motion")

	for name in pairs(motionConfig) do
		motionConfig[name] = true
	end
	motionConfig.irregularity = false
	for index, name in ipairs({ "roll", "heave", "pitch" }) do
		motionConfig[name] = false
		local result = frame()
		for channel = 1, 3 do
			assertNear(
				result[channel],
				channel == index and 2500.0 or baseline[channel],
				0.000001,
				"axis switches are independent"
			)
		end
		motionConfig[name] = true
	end
	sample.curveTilt = 1.0
	motionConfig.curveLean = false
	assertNear(frame()[1], baseline[1], 0.000001, "curve lean can be disabled without disabling procedural roll")
	assertNear(motion.curveLeanDegrees(1.0), 0.0, 0.000001, "curve lean switch also controls its direct helper")
	motionConfig.curveLean = true
	sample.curveTilt = 0.5
	sample.motionScale = motion.speedFactor(60.0, "DEFAULT")
	local fullStrength = frame()
	motionConfig.speedEnvelope = false
	sample.motionScale = motion.speedFactor(5.0 / 3.6, "DEFAULT")
	local unscaled = frame()
	for channel = 1, 3 do
		assertNear(
			unscaled[channel],
			fullStrength[channel],
			0.000001,
			"disabling the speed envelope uses full strength from 5 km/h"
		)
	end
	for _, speed in ipairs({ -4.999 / 3.6, 0, 4.999 / 3.6 }) do
		assertEqual(motion.speedFactor(speed, "DEFAULT"), 0, "developer isolation retains the minimum motion speed")
	end
	motionConfig.speedEnvelope = true
end

print("Motion checks passed")
