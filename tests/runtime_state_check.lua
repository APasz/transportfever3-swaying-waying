local harness = dofile("tests/support/harness.lua").new()
local settings = harness.require("apasz_swaying_waying::/swaying_waying/settings.lua")
local runtimeConfig = harness.require("apasz_swaying_waying::/swaying_waying/runtime_config.lua")
local validate = runtimeConfig.validate
local validations = 0
runtimeConfig.validate = function(source)
	validations = validations + 1
	return validate(source)
end
local state = harness.require("apasz_swaying_waying::/swaying_waying/runtime_state.lua")
local source = {
	schema = 2,
	revision = 1,
	modelFile = "tests::/shared.mdl",
	originalTransformator = "authored::/vehicle.trf",
	carrier = "RAIL",
	profile = "DEFAULT",
	axisReversed = false,
	vehicleFactor = 1,
	wheelbase = 10,
	settings = settings.resolve({ intensity = 1 }),
	sections = { { lag = 0, wheelbase = 10 }, { lag = 12, wheelbase = 8 } },
}
local first = assert(state.get(source, 1, 100))
local second = assert(state.get(source, 2, 100))
assert(first ~= second and first.sample ~= second.sample, "carriages own separate mutable samples")
assert(first.model == second.model, "carriages share one compiled model configuration")
assert(
	first.model.samplingDistance == source.settings.samplingDistance,
	"compiled models retain the selected sampling interval"
)
assert(first.model.curveSamplingDistance == 1, "compiled models default to one-metre curve sampling")
assert(first.model.speedDependent == true, "compiled models retain ordinary speed scaling by default")
assert(validations == 1, "shared model settings are validated once")
first.sample.distance = 200
first.responseTime = 123
first.motionVelocity = 1
first.curveVelocity = 2
first.curveSampleDistance = 100
first.curvature = 0.002
assert(second.sample.distance == 0, "carriage samples cannot overwrite each other")
assert(
	second.responseTime == nil and second.motionVelocity == 0 and second.curveVelocity == 0,
	"carriages own separate damping history"
)
assert(second.curveSampleDistance == nil and second.curvature == nil, "carriages own separate curvature history")
assert(state.get(source, 1, 100) == first, "repeated frames reuse carriage state")
local reconstructed = {}
for key, value in pairs(source) do
	reconstructed[key] = value
end
assert(
	state.get(reconstructed, 1, 100) == first,
	"native parameter table reconstruction must not allocate a new carriage state"
)
local replaced = assert(state.get(source, 1, 101))
assert(replaced ~= first and replaced.sample ~= first.sample, "reused carriage identities reset mutable state")
assert(
	replaced.responseTime == nil and replaced.motionVelocity == 0,
	"reused carriage identities reset damping history"
)
assert(
	replaced.curveSampleDistance == nil and replaced.curvature == nil,
	"reused carriage identities reset curvature history"
)
source.revision = source.revision + 1
source.sections[1].lag = 0 / 0
for _ = 1, 20 do
	assert(state.get(source, 2, 100) == nil, "invalid configuration adds no motion")
end
assert(validations == 2, "invalid configurations are compiled once per revision")
assert(#harness.warnings == 1, "invalid configurations produce one clear warning")
for _, detail in ipairs({
	"Invalid runtime section lag",
	"model=" .. source.modelFile,
	"revision=" .. source.revision,
	"transformator=" .. source.originalTransformator,
}) do
	assert(harness.warnings[1]:find(detail, 1, true), "invalid configuration warnings include " .. detail)
end
local rejected = state.model(source)
assert(
	rejected.source.originalTransformator == source.originalTransformator,
	"authored callbacks remain available independently of invalid motion settings"
)
source.sections[1].lag = 0
source.revision = source.revision + 1
local recovered = assert(state.get(source, 2, 100))
assert(
	#harness.messages == 1 and harness.messages[1]:find("Sway configuration recovered", 1, true),
	"a corrected revision reports configuration recovery"
)
assert(harness.messages[1]:find("model=" .. source.modelFile, 1, true), "recovery identifies its model")
state.get(source, 2, 100)
assert(#harness.messages == 1, "successful frames do not repeat the recovery message")
assert(recovered.model ~= second.model and validations == 3, "a corrected revision can recover")
assert(recovered.responseTime == nil and recovered.curveVelocity == 0, "a new model revision resets damping history")
source.revision = source.revision + 1
source.settings.curveLeanIntensity = 0
assert(not state.get(source, 2, 100).model.curveLeanEnabled, "disabled curve lean is retained in compiled settings")

local identitySource = {}
for key, value in pairs(source) do
	identitySource[key] = value
end
identitySource.modelFile, identitySource.profile = "tests::/identity_a.mdl", "QUICK"
local originalIdentity = assert(state.get(identitySource, 700, 100))
identitySource.modelFile, identitySource.profile = "tests::/identity_b.mdl", "SLOW"
local changedIdentity = assert(state.get(identitySource, 700, 100))
assert(
	changedIdentity ~= originalIdentity,
	"reused input tables cannot disguise a different model at the same revision"
)
assert(
	originalIdentity.model.motion.profile == "QUICK",
	"changing input identity cannot alter existing compiled motion"
)
assert(changedIdentity.model.motion.profile == "SLOW", "a new model identity compiles its own profile")
identitySource.modelFile, identitySource.profile = "tests::/identity_a.mdl", "QUICK"
local restoredIdentity = assert(state.get(identitySource, 700, 100))
assert(restoredIdentity.model == originalIdentity.model, "returning to a known model reuses its compiled configuration")
source.revision = source.revision + 1
source.settings.rollBalance = 0
source.settings.pitchBalance = 0
source.settings.heaveBalance = 0
source.settings.curveLeanIntensity = 1
local curveOnly = assert(state.get(source, 800, 100))
assert(not curveOnly.model.proceduralMotionEnabled, "zero balances skip every procedural motion source")
assert(curveOnly.model.curveLeanEnabled, "zero procedural balances retain independent curve lean")
source.revision = source.revision + 1
source.settings.curveLeanIntensity = 0
local inactive = assert(state.get(source, 800, 100))
assert(not inactive.model.proceduralMotionEnabled and not inactive.model.curveLeanEnabled, "all motion can be disabled")
print("Runtime state checks passed")
