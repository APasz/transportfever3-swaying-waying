local assertEqual = dofile("tests/assertions.lua").equal
local paths = dofile("content/swaying_waying/resource_paths.lua")
local resources = {}
local loads = {}
local warnings = {}
local verbose = {}
local vanillaUpdate = function() end
local vanilla = {
	updateFn = vanillaUpdate,
	updateParticleSystemFn = function() end,
}
local sentinel = function() end
_G.data = sentinel
_G.ug_require = function(name)
	if name == "apasz_swaying_waying::/swaying_waying/values.lua" then
		return dofile("content/swaying_waying/values.lua")
	elseif name == "apasz_swaying_waying::/swaying_waying/constants.lua" then
		return dofile("content/swaying_waying/constants.lua")
	elseif name == "apasz_swaying_waying::/swaying_waying/resource_paths.lua" then
		return paths
	elseif name == "apasz_swaying_waying::/swaying_waying/logger.lua" then
		return {
			warnOnce = function(key, message)
				warnings[key] = message
			end,
			debug = function(message)
				verbose[#verbose + 1] = message
			end,
		}
	elseif name == "::/vehicle/train/shared/transformator_train.script.tl" then
		return { train = vanilla }
	elseif name == "::/vehicle/tram/shared/transformator_tram.script.tl" then
		return { tram = vanilla }
	end
	loads[name] = (loads[name] or 0) + 1
	local resource = assert(resources[name], "Missing fixture: " .. name)
	return resource()
end
local loader = dofile("content/swaying_waying/origin_loader.lua")
local function callbackConfig(script)
	return {
		updateScript = { fileName = script .. "@update" },
		updateParticleSystemScript = { fileName = script .. "@particles" },
	}
end
local function origin(name, model)
	return loader.get("example::/" .. name .. ".trf", model or "example::/car.mdl", "RAIL")
end

resources["example::/direct.script.lua"] = function()
	return { update = vanillaUpdate, particles = vanillaUpdate }
end
resources["example::/global.trf.lua"] = function()
	_G.data = function()
		_G.data = function() end
		return callbackConfig("example::/direct.script.lua")
	end
end
assert(origin("global").update == vanillaUpdate)
assert(_G.data == sentinel, "global data factories must restore the wrapper entry point")

local configCalls = 0
resources["example::/factory.trf.lua"] = function()
	return {
		data = function()
			configCalls = configCalls + 1
			_G.data = function() end
			return callbackConfig("example::/factory.script.lua")
		end,
	}
end
local scriptCalls = 0
resources["example::/factory.script.lua"] = function()
	return {
		data = function()
			scriptCalls = scriptCalls + 1
			_G.data = function() end
			local count = 0
			local function callback(_, _, output)
				count = count + 1
				output.count = count
			end
			return { update = callback, particles = callback }
		end,
	}
end
local shared = origin("factory")
local output = {}
shared.update({}, {}, output)
shared.particles({}, {}, output)
assert(output.count == 2, "callbacks from one script factory must share their module state")
assert(_G.data == sentinel, "config and script factories must restore the wrapper entry point")
assert(origin("factory", "other::/car.mdl").update == shared.update)
assert(configCalls == 1 and scriptCalls == 1, "resource factories must run once across models and callbacks")

resources["example::/mixed.script.lua"] = function()
	return {
		update = vanillaUpdate,
		data = function()
			return { particles = vanillaUpdate }
		end,
	}
end
resources["example::/mixed.trf.lua"] = function()
	local config = callbackConfig("example::/mixed.script.lua")
	config.getEmittableModelsScript = { fileName = "example::/mixed.script.lua@update" }
	return config
end
local mixed = origin("mixed")
assert(mixed.update == vanillaUpdate and mixed.particles == vanillaUpdate, "direct exports survive factory lookup")
assert(mixed.getEmittableModels == vanillaUpdate, "cached factory exports preserve later direct lookups")

local nestedFactoryCalls = 0
resources["example::/nested.script.lua"] = function()
	return {
		vehicle = { update = vanillaUpdate },
		data = function()
			nestedFactoryCalls = nestedFactoryCalls + 1
			return { vehicle = { particles = vanillaUpdate } }
		end,
	}
end
resources["example::/nested.trf.lua"] = function()
	return {
		updateScript = { fileName = "example::/nested.script.lua@vehicle.update" },
		updateParticleSystemScript = { fileName = "example::/nested.script.lua@vehicle.particles" },
	}
end
local nested = origin("nested")
assert(
	nested and nested.update == vanillaUpdate and nested.particles == vanillaUpdate,
	"nested direct and factory callbacks must coexist"
)
assert(nestedFactoryCalls == 1, "nested callback factories run only once")

resources["example::/particles_only.trf.lua"] = function()
	return { updateParticleSystemScript = { fileName = "example::/direct.script.lua@particles" } }
end
local particlesOnly = origin("particles_only")
assert(
	particlesOnly and particlesOnly.update == nil and particlesOnly.particles == vanillaUpdate,
	"a particle-only transformator must retain its callback without adding an authored animation update"
)
resources["example::/emissions_only.trf.lua"] = function()
	return {
		data = function()
			return {
				getEmittableModelsScript = { fileName = "example::/direct.script.lua@update" },
				computeEmittedModelsScript = { fileName = "example::/direct.script.lua@particles" },
			}
		end,
	}
end
local emissionsOnly = origin("emissions_only")
assert(
	emissionsOnly and emissionsOnly.update == nil and emissionsOnly.particles == nil,
	"an emission-only transformator may omit animation and particle updates"
)
assert(
	emissionsOnly.getEmittableModels == vanillaUpdate and emissionsOnly.computeEmittedModels == vanillaUpdate,
	"emission-only factory configurations retain both authored callbacks"
)

local failedCalls = 0
resources["example::/failed.trf.lua"] = function()
	return {
		data = function()
			failedCalls = failedCalls + 1
			_G.data = function() end
			error("broken factory")
		end,
	}
end
assert(origin("failed") == nil, "broken factories must not replace authored behaviour")
assert(origin("failed", "other::/car.mdl") == nil)
assert(failedCalls == 1, "failed factories must be cached")
assert(
	warnings["transformator-factory-failed:example::/failed.trf.lua"]:find("broken factory", 1, true),
	"factory failures retain their original cause"
)
assert(_G.data == sentinel, "throwing factories must restore the wrapper entry point")
resources["example::/missing.trf.lua"] = function()
	_G.data = function() end
	error("broken resource")
end
assert(origin("missing") == nil)
assert(origin("missing", "other::/car.mdl") == nil)
assert(loads["example::/missing.trf.lua"] == 1, "failed resource loads must be cached")
local failedLookup = false
for _, message in ipairs(verbose) do
	if message:find("example::/missing.trf.lua", 1, true) and message:find("broken resource", 1, true) then
		failedLookup = true
	end
end
assert(failedLookup, "resource lookup failures retain their filename and cause in debug output")
assert(_G.data == sentinel, "throwing resource loads must restore the wrapper entry point")
assert(next(warnings) ~= nil, "failed origins must be reported")

resources["example::/partial.trf.lua"] = function()
	return {
		updateScript = { fileName = "example::/direct.script.lua@update" },
		getEmittableModelsScript = { fileName = "example::/direct.script.lua@missing" },
	}
end
assert(origin("partial") == nil, "an unresolved declared optional callback must reject the wrapper")

local trfFiles = paths.trfCandidates("custom.trf", "example::/vehicle/train/car.mdl")
assertEqual(trfFiles[1], "example::/vehicle/train/custom.trf.lua", "relative transformator uses the model folder")
assertEqual(trfFiles[2], "example::/custom.trf.lua", "relative transformator has an owner-root fallback")
local scriptFiles, scriptMembers =
	paths.scriptCandidates("custom.script@vehicle.updateFn", "example::/vehicle/train/custom.trf.lua")
assertEqual(
	scriptFiles[1],
	"example::/vehicle/train/custom.script.lua",
	"relative script uses the transformator folder"
)
assertEqual(scriptMembers[1], "vehicle", "script member root is parsed")
assertEqual(scriptMembers[2], "updateFn", "script member leaf is parsed")
print("Origin loader checks passed")
