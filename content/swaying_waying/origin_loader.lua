local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local dynamicTable = validation.asTable
local paths = ug_require("apasz_swaying_waying::/swaying_waying/resource_paths.lua")

local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")

local resources = {}
local origins = {}
local failed = {}
local CALLBACK_FIELDS = {
	"updateScript",
	"updateParticleSystemScript",
	"getEmittableModelsScript",
	"computeEmittedModelsScript",
}

local function evaluateData(loader, fileName)
	local savedData = data
	local succeeded, result = pcall(loader)
	data = savedData
	if not succeeded then
		logger.warnOnce(
			"transformator-factory-failed:" .. fileName,
			"Original transformator resource factory failed for " .. fileName .. ": " .. tostring(result)
		)
		return nil
	end
	return dynamicTable(result)
end

local function loadResourceOnce(fileName)
	local savedData = data
	local succeeded, resource = pcall(ug_require, fileName)
	local definedData = data
	data = savedData
	if not succeeded then
		logger.debug("Could not load original transformator resource " .. fileName .. ": " .. tostring(resource))
		return nil
	end
	if type(resource) == "table" then
		return resource
	end
	if type(definedData) == "function" and definedData ~= savedData then
		return evaluateData(definedData, fileName)
	end
	return nil
end

local function loadResource(fileName)
	local cached = resources[fileName]
	if cached ~= nil then
		return cached
	end
	local resource = { fileName = fileName, factoryLoaded = false }
	resources[fileName] = resource
	resource.value = loadResourceOnce(fileName)
	return resource
end

local function factoryExports(resource)
	if not resource.factoryLoaded then
		resource.factoryLoaded = true
		local value = resource.value
		if value ~= nil and type((value).data) == "function" then
			resource.factoryValue = evaluateData((value).data, resource.fileName)
		end
	end
	return resource.factoryValue
end

local function hasCallbacks(value)
	if value ~= nil then
		for _, field in ipairs(CALLBACK_FIELDS) do
			if (value)[field] ~= nil then
				return true
			end
		end
	end
	return false
end

local function transformatorConfig(resource)
	local value = resource.value
	if hasCallbacks(value) then
		return value
	end
	local exports = factoryExports(resource)
	if hasCallbacks(exports) then
		return exports
	end
	return nil
end

local function exportedFunction(exports, members)
	local member = exports
	for _, key in ipairs(members) do
		local memberTable = dynamicTable(member)
		member = memberTable ~= nil and (memberTable)[key] or nil
	end
	return type(member) == "function" and member or nil
end

local function scriptFunction(reference, transformatorFile)
	if reference == "" then
		return nil
	end
	local files, members = paths.scriptCandidates(reference, transformatorFile)
	for _, fileName in ipairs(files) do
		local resource = loadResource(fileName)
		local callback = exportedFunction(resource.value, members)
		if callback == nil then
			callback = exportedFunction(factoryExports(resource), members)
		end
		if callback ~= nil then
			return callback
		end
	end
	return nil
end

local function callbackFrom(config, fieldName, transformatorFile)
	if config[fieldName] == nil then
		return nil, {}, true
	end
	local callbackConfig = dynamicTable(config[fieldName])
	if callbackConfig == nil then
		return nil, {}, false
	end
	local presentConfig = callbackConfig
	local capture = type(presentConfig.params) == "table" and presentConfig.params or {}
	local reference = presentConfig.fileName
	local callback = type(reference) == "string" and scriptFunction(reference, transformatorFile) or nil
	if type(callback) ~= "function" then
		logger.warnOnce(
			"missing-transformator-callback:" .. transformatorFile .. ":" .. fieldName,
			"Could not load " .. fieldName .. " from original transformator " .. transformatorFile
		)

		return nil, capture, false
	end
	return callback, capture, true
end

local function get(name, modelFile, carrier)
	local key = name .. "|" .. modelFile .. "|" .. carrier
	local cached = origins[key]
	if cached ~= nil then
		return cached
	end

	if failed[key] then
		return nil
	end
	for _, transformatorFile in ipairs(paths.trfCandidates(name, modelFile)) do
		local config = dynamicTable(transformatorConfig(loadResource(transformatorFile)))
		if config ~= nil then
			local presentConfig = config
			local update, updateCapture, updateValid = callbackFrom(presentConfig, "updateScript", transformatorFile)

			if updateValid then
				local particleUpdate, particleCapture, particlesValid =
					callbackFrom(presentConfig, "updateParticleSystemScript", transformatorFile)

				local getEmittableModels, getEmittableModelsCapture, discoveryValid =
					callbackFrom(presentConfig, "getEmittableModelsScript", transformatorFile)

				local computeEmittedModels, computeEmittedModelsCapture, emissionValid =
					callbackFrom(presentConfig, "computeEmittedModelsScript", transformatorFile)

				local origin = {
					update = type(update) == "function" and update or nil,
					capture = updateCapture,
					particles = type(particleUpdate) == "function" and particleUpdate or nil,
					particlesCapture = particleCapture,
					getEmittableModels = type(getEmittableModels) == "function" and getEmittableModels or nil,
					getEmittableModelsCapture = getEmittableModelsCapture,
					computeEmittedModels = type(computeEmittedModels) == "function" and computeEmittedModels or nil,
					computeEmittedModelsCapture = computeEmittedModelsCapture,
				}
				if particlesValid and discoveryValid and emissionValid then
					origins[key] = origin
					return origin
				end
			end
		end
	end

	failed[key] = true
	logger.warnOnce(
		"missing-transformator:" .. key,
		"Could not preserve every callback from original transformator " .. name .. " for " .. modelFile
	)

	return nil
end

local module = {
	get = get,
}

return module
