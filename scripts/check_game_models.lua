local manifest = dofile(assert(arg[1], "Expected model-check manifest"))
local harness = dofile("tests/support/harness.lua").new()
harness.overrides["apasz_swaying_waying::/swaying_waying/logging_config.lua"] = manifest.verbose
_G._ = function(value)
	return value
end
math.pow = math.pow or function(base, exponent)
	return base ^ exponent
end
local requireResource = dofile("tests/support/resource_loader.lua").new(manifest.roots, harness.require)
_G.ug_require = requireResource
local modifier = harness.require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
local allModParams = {}
for namespace in pairs(manifest.roots) do
	allModParams[namespace] = {}
end
modifier.configure(allModParams)
local nodes = harness.require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local policy = harness.require("apasz_swaying_waying::/swaying_waying/model_policy.lua")
local settings = harness.require("apasz_swaying_waying::/swaying_waying/settings.lua").resolve({ intensity = 1 })
local visuals = dofile("tests/support/model_visuals.lua")
local adapted, skipped, failed, nonRail, optedOut, cameraOnly = 0, 0, 0, 0, 0, 0

for _, resource in ipairs(manifest.resources) do
	local messageStart, warningStart, verboseStart = #harness.messages, #harness.warnings, #harness.verbose
	local succeeded, result = pcall(function()
		local model = requireResource(resource)
		assert(type(model) == "table", "Model must export a data() table")
		if not model.metadata or not policy.carrier(model.metadata) then
			nonRail = nonRail + 1
			return "Not rail"
		end
		nodes.validate(model)
		local originalVisuals = visuals.snapshot(model)
		modifier.modify(resource, model, settings, manifest.verbose)
		visuals.validate(originalVisuals, visuals.snapshot(model), resource)
		local config = model.metadata.transformatorConfig
		if config and config.params and config.params.swayingWaying then
			nodes.validate(model)
			adapted = adapted + 1
			return "Adapted"
		end
		local vehicleSettings = policy.vehicleSettings(resource, model.metadata, 1)
		if vehicleSettings == nil or (not vehicleSettings.swayEnabled and not vehicleSettings.cameraEnabled) then
			optedOut = optedOut + 1
			return "Opted out"
		elseif not vehicleSettings.swayEnabled then
			cameraOnly = cameraOnly + 1
			return "Camera-only (sway disabled by author)"
		end
		skipped = skipped + 1
		return "Skipped"
	end)
	if not succeeded then
		failed = failed + 1
		print("Failed: " .. resource .. ": " .. tostring(result))
	elseif manifest.author or manifest.verbose or result == "Skipped" then
		print(result .. ": " .. resource)
	end
	for index = warningStart + 1, #harness.warnings do
		print(harness.warnings[index])
	end
	if manifest.verbose then
		for index = messageStart + 1, #harness.messages do
			print(harness.messages[index])
		end
		for index = verboseStart + 1, #harness.verbose do
			print(harness.verbose[index])
		end
	end
end
print(
	string.format(
		"Models: %d adapted; %d opted out; %d skipped; %d failed; %d non-rail; %d camera-only",
		adapted,
		optedOut,
		skipped,
		failed,
		nonRail,
		cameraOnly
	)
)
if
	failed > 0
	or (adapted + skipped + optedOut + cameraOnly == 0)
	or (manifest.strict and (skipped > 0 or #harness.warnings > 0))
then
	os.exit(1)
end
