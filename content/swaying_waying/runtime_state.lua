local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local cache = ug_require("apasz_swaying_waying::/swaying_waying/bounded_cache.lua")
local motion = ug_require("apasz_swaying_waying::/swaying_waying/motion.lua")
local switches = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
local config = ug_require("apasz_swaying_waying::/swaying_waying/runtime_config.lua")
local bindings = ug_require("apasz_swaying_waying::/swaying_waying/animation_bindings.lua")
local memory = ug_require("apasz_swaying_waying::/swaying_waying/memory_policy.lua")

local models = cache.create(constants.MAX_RUNTIME_VEHICLE_STATES)
local carriages = cache.create(constants.MAX_RUNTIME_VEHICLE_STATES)
local overflow = nil
local selectedBudget = nil
local overflowReported = {}

local function compile(source)
	local selected = config.validate(source)
	local secondary = selected.pitchBalance > 0.0 or selected.heaveBalance > 0.0
	local motionSettings = {
		rollIntensity = selected.intensity * selected.rollBalance,
		pitchIntensity = selected.intensity * selected.pitchBalance,
		heaveIntensity = selected.intensity * selected.heaveBalance,
		curveLeanIntensity = selected.curveLeanIntensity,
		modelAxisSign = source.axisReversed and -1.0 or 1.0,
		profile = source.profile,
		secondaryMotionEnabled = secondary,
	}
	local sections = {}
	if #source.sections == 0 then
		sections[1] = {
			lag = 0,
			geometry = motion.secondaryGeometry(source.profile, source.wheelbase),
			animations = bindings.get(0, secondary),
		}
	else
		for index, section in ipairs(source.sections) do
			sections[index] = {
				lag = section.lag,
				geometry = motion.secondaryGeometry(source.profile, section.wheelbase),
				animations = bindings.get(index, secondary),
			}
		end
	end
	return {
		memoryUsage = selected.memoryUsage or "Standard",
		sharedWaves = memory.budget(selected.memoryUsage).sharedWaves,
		modelFile = source.modelFile,
		speedDependent = selected.speedDependent,
		trackInfluence = selected.trackInfluence,
		samplingDistance = selected.samplingDistance,
		curveSamplingDistance = selected.curveSamplingDistance,
		curveBalance = selected.curveBalance,
		vehicleVariation = selected.vehicleVariation,
		vehicleFactor = source.vehicleFactor,
		revision = source.revision,
		motion = motionSettings,
		proceduralMotionEnabled = motion.hasProceduralMotion(motionSettings),
		secondaryMotionEnabled = motion.hasSecondaryMotion(motionSettings),
		curveLeanEnabled = switches.roll and switches.curveLean and selected.curveLeanIntensity > 0.0,
		sections = sections,
	}
end

local function model(source)
	local existing = cache.get(models, source.modelFile)
	if existing ~= nil and (existing).revision == source.revision then
		return existing
	end
	local entry = {
		source = source,
		revision = source.revision,
		originLoaded = false,
	}
	local succeeded, compiled = pcall(compile, source)
	if succeeded then
		entry.compiled = compiled
		if existing ~= nil and (existing).compiled == nil then
			logger.info(
				"Sway configuration recovered [model="
					.. source.modelFile
					.. ", revision="
					.. source.revision
					.. ", transformator="
					.. source.originalTransformator
					.. "]"
			)
		end
	else
		logger.warnOnce(
			"runtime-config:" .. tostring(source.modelFile) .. ":" .. tostring(source.revision),
			"Disabling sway for invalid model configuration: "
				.. tostring(compiled)
				.. " [model="
				.. tostring(source.modelFile)
				.. ", revision="
				.. tostring(source.revision)
				.. ", transformator="
				.. tostring(source.originalTransformator)
				.. "]"
		)
	end
	cache.put(models, source.modelFile, entry)
	return entry
end

local function get(source, entity, purchaseTime, time)
	if time ~= nil then
		cache.advance(carriages, time)
	end
	local existing = cache.get(carriages, entity)
	if existing ~= nil then
		local present = existing
		if
			present.purchaseTime == purchaseTime
			and present.model.modelFile == source.modelFile
			and present.model.revision == source.revision
		then
			return present
		end
	end
	local compiled = model(source).compiled
	if compiled == nil then
		return nil
	end
	local presentCompiled = compiled
	local budget = memory.budget(presentCompiled.memoryUsage)
	if budget ~= selectedBudget then
		cache.configure(carriages, budget.carriages, budget.retention)
		selectedBudget = budget
	end
	local retained = existing ~= nil or cache.canPut(carriages)
	local state
	if not retained and overflow ~= nil then
		state = overflow
		state.purchaseTime, state.model = purchaseTime, presentCompiled
		state.responseTime, state.curveSampleDistance, state.curvature = nil, nil, nil
		state.motionVelocity, state.curveVelocity = 0.0, 0.0
		state.waves, state.waveBasis, state.sample.waves = nil, nil, nil
		state.sample.motionScale, state.sample.curveTilt = 0.0, 0.5
	else
		state = {
			retained = retained,
			purchaseTime = purchaseTime,
			model = presentCompiled,
			motionVelocity = 0.0,
			curveVelocity = 0.0,
			sample = {
				motionScale = 0,
				distance = 0,
				phaseSeed = 0,
				sharedDistance = 0,
				sharedPhaseSeed = 0,
				sharedAxisReversed = false,
				curveTilt = 0.5,
				swayFactor = 1,
				shortWeight = constants.NEUTRAL_TRACK_SHORT_WEIGHT,
			},
		}
	end
	if retained then
		cache.put(carriages, entity, state)
	else
		overflow = state
		if not overflowReported[presentCompiled.memoryUsage] then
			overflowReported[presentCompiled.memoryUsage] = true
			logger.warnOnce(
				"memory-capacity:" .. presentCompiled.memoryUsage,
				"Carriage history budget reached ("
					.. presentCompiled.memoryUsage
					.. ", "
					.. budget.carriages
					.. " per Lua context); excess carriages use motion without retained damping history. "
					.. "Select a larger Memory usage preset when available."
			)
		end
	end
	return state
end

local module = { get = get, model = model }
return module
