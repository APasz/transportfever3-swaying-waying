local fixture = dofile("tests/support/wave_fixture.lua")
local frames = tonumber(arg[1] or "120")
assert(
	frames and frames >= 1 and frames % 1 == 0,
	"Usage: lua scripts/benchmark_motion.lua [frames] [baseline-motion.lua]"
)
local VEHICLES, REPEATS = 1000, 3
local baselinePath = arg[2]
local constants = dofile("content/swaying_waying/constants.lua")
local motionConfig = dofile("content/swaying_waying/motion_config.lua")

local function median(values)
	table.sort(values)
	return values[math.floor(#values / 2) + 1]
end

local function waves(consistSize, contextCount, secondaryMotion, changingTrack)
	local contexts, references, states = {}, {}, {}
	for context = 1, contextCount do
		local harness = dofile("tests/support/harness.lua").new()
		harness.require("apasz_swaying_waying::/swaying_waying/motion_config.lua").carriageLag =
			motionConfig.carriageLag
		contexts[context] = harness.require("apasz_swaying_waying::/swaying_waying/motion.lua")
		references[context] = baselinePath and dofile(baselinePath) or contexts[context]
	end
	for index = 1, VEHICLES do
		local consist = math.floor((index - 1) / consistSize) + 1
		local position = (index - 1) % consistSize
		local context = (index - 1) % contextCount + 1
		local motion = contexts[context]
		local state = fixture(motion, "DEFAULT", consist, index + VEHICLES, position)
		state.model.motion.secondaryMotionEnabled = secondaryMotion
		state.sample.sharedAxisReversed = index % 2 == 0
		state.lag = motionConfig.carriageLag and position * 20 or 0
		state.consist, state.motion = consist, motion
		state.reference = references[context]
		state.geometry = state.model.sections[1].geometry
		state.referenceGeometry = state.reference.secondaryGeometry("DEFAULT", 11)
		states[index] = state
	end
	local function evaluate(shared, iterations)
		local started = os.clock()
		local rollChecksum, heaveChecksum, pitchChecksum = 0, 0, 0
		for frame = 1, iterations do
			local shortWeight = changingTrack and (0.65 + 0.1 * math.exp(-frame / 120)) or 0.65
			for index = 1, VEHICLES do
				local state = states[index]
				local sample = state.sample
				local distance = 123 + frame / 3 + state.consist * 30
				sample.distance, sample.sharedDistance, sample.waves = distance, distance - state.lag, nil
				sample.shortWeight = shortWeight
				local motion = shared and state.motion or state.reference
				local geometry = shared and state.geometry or state.referenceGeometry
				if
					shared
					and state.model.motion.secondaryMotionEnabled
					and consistSize >= constants.MIN_SHARED_WAVE_CARRIAGES
				then
					motion.prepareWaves(state, distance, state.lag)
					if sample.waves then
						motion.sectionWaves(state, 1)
					end
				end
				local roll, heave, pitch = motion.animationTimes(sample, state.model.motion, geometry)
				rollChecksum = rollChecksum + roll
				heaveChecksum = heaveChecksum + heave
				pitchChecksum = pitchChecksum + pitch
			end
		end
		return os.clock() - started, rollChecksum, heaveChecksum, pitchChecksum
	end
	-- Warm coefficient and geometry caches outside the timing window.
	evaluate(true, 3)
	local references, candidates = {}, {}
	for repeatIndex = 1, REPEATS do
		local reference, expectedRoll, expectedHeave, expectedPitch = evaluate(false, frames)
		local candidate, actualRoll, actualHeave, actualPitch = evaluate(true, frames)
		assert(math.abs(actualRoll - expectedRoll) < 0.01, "Wave benchmark roll poses disagree")
		assert(math.abs(actualHeave - expectedHeave) < 0.01, "Wave benchmark heave poses disagree")
		assert(math.abs(actualPitch - expectedPitch) < 0.01, "Wave benchmark pitch poses disagree")
		references[repeatIndex], candidates[repeatIndex] = reference, candidate
	end
	local reference, candidate = median(references), median(candidates)
	print(
		string.format(
			"waves axes=%s spectrum=%s cars/consist=%d contexts=%d reference=%.6fs candidate=%.6fs ratio=%.3f",
			secondaryMotion and "full" or "roll",
			changingTrack and "changing" or "steady",
			consistSize,
			contextCount,
			reference,
			candidate,
			candidate / reference
		)
	)
end

local function stationary()
	local harness = dofile("tests/support/harness.lua").new()
	harness.require("apasz_swaying_waying::/swaying_waying/motion_config.lua").carriageLag = motionConfig.carriageLag
	local response = harness.require("apasz_swaying_waying::/swaying_waying/motion_response.lua")
	local constants = harness.require("apasz_swaying_waying::/swaying_waying/constants.lua")
	local track = harness.require("apasz_swaying_waying::/swaying_waying/track_response.lua")
	track.response = function()
		return 1, 0.65
	end
	local function native() end
	local scripts = { train = { updateFn = native, updateParticleSystemFn = native } }
	harness.overrides["::/vehicle/train/shared/transformator_train.script.tl"] = scripts
	harness.overrides["::/vehicle/train/shared/transformator_tiltingTrain.script.tl"] = { tiltingTrain = scripts.train }
	harness.overrides["::/vehicle/tram/shared/transformator_tram.script.tl"] = { tram = scripts.train }
	harness.overrides["::/scripts/transformator_util.tl"] = {}
	local controller = harness.require("apasz_swaying_waying::/swaying_waying/vehicle/transformator.script.lua")
	local settings = harness.require("apasz_swaying_waying::/swaying_waying/settings.lua")
	local source = {
		schema = constants.RUNTIME_SCHEMA,
		revision = 1,
		modelFile = "tests::/stationary_benchmark.mdl",
		originalTransformator = "::/vehicle/train/shared/default_train.trf",
		carrier = "RAIL",
		profile = "DEFAULT",
		axisReversed = false,
		vehicleFactor = 1,
		wheelbase = 10,
		sections = {},
		settings = settings.resolve({ intensity = 1 }),
	}
	local params = {
		entityId = 100,
		vehicleStaticInfo = { carriageEntity = 1, purchaseTime = 100 },
		currentInfo = {
			world = { gameTime = 0 },
			vehicle = { speed = 0, maintenance = 0, positionInCarriageList = 0, carriageListLength = VEHICLES },
			landVehicle = { reversed = false, carriagesReversed = { false }, wheelAnimationInfo = { totalDist = 123 } },
		},
		transformatorConfigParams = { swayingWaying = source },
		landVehicleApi = {},
	}
	local output = { addAnimationState = native }
	local capture = {}
	local isNeutral = response.neutral
	local function evaluate(shortcut)
		response.neutral = shortcut and isNeutral or function()
			return false
		end
		local started = os.clock()
		for frame = 1, frames do
			params.currentInfo.world.gameTime = frame * 16
			for carriage = 1, VEHICLES do
				params.vehicleStaticInfo.carriageEntity = carriage
				controller.train.updateFn(capture, params, output)
			end
		end
		return os.clock() - started
	end
	evaluate(true)
	local references, candidates = {}, {}
	for repeatIndex = 1, REPEATS do
		references[repeatIndex], candidates[repeatIndex] = evaluate(false), evaluate(true)
	end
	response.neutral = isNeutral
	local reference, candidate = median(references), median(candidates)
	print(string.format("stationary full=%.6fs shortcut=%.6fs ratio=%.3f", reference, candidate, candidate / reference))
end

print(
	string.format(
		"Standalone Lua CPU benchmark: %d vehicles, %d frames, median of %d runs; no native query or render timing.",
		VEHICLES,
		frames,
		REPEATS
	)
)
if baselinePath then
	print("Wave reference: " .. baselinePath)
end
print("Long-wave phase: " .. (motionConfig.carriageLag and "shared with 20 m carriage lag" or "per carriage"))
stationary()
for _, consistSize in ipairs({ 1, 7, 20, 100 }) do
	waves(consistSize, 1, true, false)
	waves(consistSize, 10, true, false)
end
for _, consistSize in ipairs({ 20, 100 }) do
	waves(consistSize, 10, false, false)
	waves(consistSize, 1, true, true)
	waves(consistSize, 10, true, true)
end
