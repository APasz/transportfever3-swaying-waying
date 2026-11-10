local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local origins = ug_require("apasz_swaying_waying::/swaying_waying/origin_loader.lua")
local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua")
local runtimeConfig = ug_require("apasz_swaying_waying::/swaying_waying/runtime_config.lua")
local injection = ug_require("apasz_swaying_waying::/swaying_waying/model_injection.lua")
local policy = ug_require("apasz_swaying_waying::/swaying_waying/model_policy.lua")
local authorOptions = policy.options
local carrierOf = policy.carrier
local vehicleMotionSettings = policy.vehicleSettings
local hasAuthoredSwayAnimations = policy.authoredSway
local compatibility = ug_require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
local wrapperFor, defaultTransformator = compatibility.wrapperFor, compatibility.defaultFor
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local dynamicTable = validation.asTable
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local transaction = ug_require("apasz_swaying_waying::/swaying_waying/model_transaction.lua")
local nodes = ug_require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local cameras = ug_require("apasz_swaying_waying::/swaying_waying/model_cameras.lua")
local cameraCompatibility = ug_require("apasz_swaying_waying::/swaying_waying/camera_compatibility.lua")

local OWN_TRANSFORMATORS = {
	[constants.TRAIN_TRANSFORMATOR] = true,
	[constants.TILTING_TRANSFORMATOR] = true,
	[constants.TRAM_TRANSFORMATOR] = true,
	[constants.ANY_TRANSFORMATOR] = true,
}
local DEFAULT_LOAD_OPTIONS = { swayEnabled = true, cameraMode = "Disabled" }
local function canOwnSwayChannels(name)
	return type(name) == "string" and not compatibility.isDirect(name)
end

local function transformatorName(config)
	if config == nil then
		return nil
	end
	local transformator = dynamicTable((config).transformator)
	if transformator == nil then
		return nil
	end
	return (transformator).name
end

local function captureCameras(fileName, model, mode, extra)
	local succeeded, plan = pcall(cameras.capture, fileName, model, mode, extra)
	if not succeeded then
		logger.warnOnce(
			"camera-capture:" .. fileName,
			"Onboard cameras skipped for " .. fileName .. ": " .. tostring(plan)
		)
		return nil
	end
	return plan
end

local function applyCameras(fileName, model, plan, attachments, wrappers)
	local added = { positions = {}, rests = {} }
	if #plan.views == 0 then
		return added, false
	end
	local updated = false
	local succeeded, failure = pcall(transaction.run, model, function(draft)
		added, updated = cameras.apply(fileName, draft, plan, attachments, wrappers)
		nodes.validate(draft)
		return updated
	end, cameras.scope(model))
	if not succeeded then
		logger.warnOnce(
			"camera-apply:" .. fileName,
			"Onboard cameras skipped for " .. fileName .. ": " .. tostring(failure)
		)
		return { positions = {}, rests = {} }, false
	end
	return added, updated
end

local function prepareModel(fileName, model, config, detailed, loadOptions)
	local loadConfig = loadOptions or DEFAULT_LOAD_OPTIONS
	local cameraMode = settings.effectiveCameraMode(loadConfig.cameraMode, loadConfig.swayEnabled)
	if not loadConfig.swayEnabled and cameraMode == "Disabled" then
		return model
	end
	local modelCandidate = dynamicTable(model)
	if modelCandidate == nil then
		return model
	end
	local modelTable = modelCandidate
	local metadataCandidate = dynamicTable(modelTable.metadata)
	if metadataCandidate == nil then
		return model
	end
	local metadata = metadataCandidate
	local carrier = carrierOf(metadata)
	if carrier == nil then
		return model
	end
	local presentCarrier = carrier
	config = settings.resolve(config)
	local pitchBalance = config.pitchBalance or 1.0
	local heaveBalance = config.heaveBalance or 1.0
	local vehicleVariation = config.vehicleVariation or 1.0
	local vehicleSettings = vehicleMotionSettings(fileName, metadata, vehicleVariation)

	if vehicleSettings == nil then
		logger.info(fileName .. ": sway skipped (author opt-out)")
		return model
	end
	local presentVehicleSettings = vehicleSettings
	local swayEnabled = loadConfig.swayEnabled and presentVehicleSettings.swayEnabled
	cameraMode = presentVehicleSettings.cameraEnabled
			and settings.effectiveCameraMode(loadConfig.cameraMode, swayEnabled)
		or "Disabled"
	if not swayEnabled and cameraMode == "Disabled" then
		return model
	end
	local secondaryMotionEnabled = pitchBalance > 0.0 or heaveBalance > 0.0
	local options = nil
	if swayEnabled then
		options = authorOptions(fileName, metadata)
		if not (options).valid then
			return model
		end
	end

	local transformatorConfig = dynamicTable(metadata.transformatorConfig)
	local currentName = transformatorName(transformatorConfig)
	if type(currentName) == "string" and OWN_TRANSFORMATORS[currentName] then
		return model
	end

	if
		presentVehicleSettings.swayEnabled
		and canOwnSwayChannels(currentName)
		and hasAuthoredSwayAnimations(modelTable, transformatorConfig)
	then
		logger.info(fileName .. ": sway skipped (author-owned sway)")
		return model
	end

	local committedReport = nil
	local prepared = transaction.run(model, function(draft)
		local draftTable = draft
		local refreshIndexedParts = compatibility.capture(fileName, draftTable)
		local function finish(changed)
			if changed and refreshIndexedParts ~= nil then
				(refreshIndexedParts)(draftTable)
			end
			return changed
		end
		local draftMetadata = draftTable.metadata
		local draftTransformatorConfig = nil
		local draftName = nil

		if swayEnabled then
			compatibility.prepare(fileName, draft)
		end
		nodes.validate(draft)
		local cameraCompatibilityReady, cameraCompatibilityChanged =
			cameraCompatibility.prepare(fileName, draftTable, cameraMode ~= "Disabled")
		local cameraPlan = nil
		if cameraMode ~= "Disabled" then
			cameraPlan = captureCameras(fileName, draftTable, cameraMode, loadConfig.extraCameras)
		end
		draftTransformatorConfig = dynamicTable(draftMetadata.transformatorConfig)
		draftName = transformatorName(draftTransformatorConfig)

		if not swayEnabled then
			if cameraPlan == nil then
				return finish(cameraCompatibilityChanged)
			end
			local added, updated = applyCameras(fileName, draftTable, cameraPlan, {}, nil)
			if not updated then
				return finish(cameraCompatibilityChanged)
			end
			if cameraCompatibilityReady then
				cameraCompatibility.refresh(fileName, draftTable, added)
			end
			local params = draftTransformatorConfig ~= nil and dynamicTable((draftTransformatorConfig).params) or nil
			if #added.positions > 0 and type(draftName) == "string" and params ~= nil then
				compatibility.refresh(fileName, draftTable, draftName, params)
			end
			return finish(true)
		end

		local swayOptions = options
		local originalName
		if type(draftName) == "string" and draftName ~= "" then
			originalName = draftName
		else
			originalName = defaultTransformator(presentCarrier)
		end
		if wrapperFor(originalName) == constants.ANY_TRANSFORMATOR then
			assert(
				origins.get(originalName, fileName, presentCarrier) ~= nil,
				"Cannot preserve original transformator: " .. originalName
			)
		end
		local result = injection.apply(
			fileName,
			draft,
			draftTransformatorConfig,
			draftName,
			originalName,
			swayOptions,
			secondaryMotionEnabled,
			detailed
		)

		if not result.added then
			if swayOptions.sections == nil then
				logger.warnOnce("missing-root:" .. fileName, "Cannot safely add sway to model hierarchy: " .. fileName)
			end
			return false
		end

		local configTable
		if draftTransformatorConfig ~= nil then
			configTable = draftTransformatorConfig
		else
			configTable = { skipFromLod = result.activeLodCount }
			draftMetadata.transformatorConfig = configTable
		end
		if result.transformatorLodCount ~= nil then
			configTable.skipFromLod = result.transformatorLodCount
		end
		local params
		local existingParams = dynamicTable(configTable.params)
		if existingParams ~= nil then
			params = existingParams
		else
			params = {}
			configTable.params = params
		end
		assert(
			params[constants.RUNTIME_PARAM] == nil,
			"Model already contains the reserved swayingWaying runtime parameter"
		)
		if cameraPlan ~= nil then
			local addedCameras = applyCameras(fileName, draftTable, cameraPlan, result.attachments, result.wrappers)
			if cameraCompatibilityReady then
				cameraCompatibility.refresh(fileName, draftTable, addedCameras)
			end
		end
		compatibility.refresh(fileName, draftTable, originalName, params)
		local configured = {
			schema = constants.RUNTIME_SCHEMA,
			revision = 1,
			modelFile = fileName,
			originalTransformator = originalName,
			carrier = presentCarrier,
			profile = presentVehicleSettings.profile,
			axisReversed = result.modelAxisSign < 0,
			vehicleFactor = presentVehicleSettings.swayFactor,
			wheelbase = result.wheelbases[1] or constants.DEFAULT_WHEELBASE,
			settings = config,
			sections = {},
		}
		for index, section in ipairs(result.sections) do
			configured.sections[index] = { lag = section.lag, wheelbase = result.wheelbases[index] }
		end
		runtimeConfig.validate(configured)
		params[constants.RUNTIME_PARAM] = configured

		local transformator = dynamicTable(configTable.transformator)
		if transformator == nil then
			transformator = {}
			configTable.transformator = transformator
		end
		(transformator).name = wrapperFor(originalName)

		committedReport = result.report
		return finish(true)
	end)
	if committedReport ~= nil then
		local reported, failure = pcall(committedReport)
		if not reported then
			logger.warnOnce(
				"model-report:" .. fileName,
				"Could not report prepared model " .. fileName .. ": " .. tostring(failure)
			)
		end
	end
	return prepared
end

local module = {
	configure = function(allModParams)
		compatibility.configure(allModParams)
		cameraCompatibility.reset()
	end,
	modify = function(fileName, model, config, detailed, options)
		assert(detailed == nil or type(detailed) == "boolean", "Model diagnostics switch must be a boolean")
		local succeeded, prepared = pcall(prepareModel, fileName, model, config, detailed == true, options)
		if not succeeded then
			logger.warnOnce("model:" .. fileName, "Skipping unsafe model " .. fileName .. ": " .. tostring(prepared))
			return model
		end
		return prepared
	end,
}

return module
