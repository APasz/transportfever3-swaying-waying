local function fixture(debugEnabled)
	local harness = dofile("tests/support/harness.lua").new()
	harness.overrides["apasz_swaying_waying::/swaying_waying/logging_config.lua"] = debugEnabled
	local shared = harness.require("apasz_swaying_waying::/swaying_waying/logging.lua")
	local constructor, calls = shared.new, 0
	shared.new = function(name, enabled)
		calls = calls + 1
		assert(name == "Swaying Waying" and enabled == debugEnabled, "the adapter configures the shared factory")
		return constructor(name, enabled)
	end
	local logger = harness.require("apasz_swaying_waying::/swaying_waying/logger.lua")
	assert(calls == 1, "the mod creates its logger through the shared factory")
	assert(
		harness.require("apasz_swaying_waying::/swaying_waying/logger.lua") == logger,
		"all callers in a Lua context share one logger and warning ledger"
	)
	return harness, logger
end

local harness, logger = fixture(false)
logger.debug("hidden")
assert(#harness.verbose == 0, "production debug logging stays disabled")
logger.info("information")
logger.warn("recoverable failure")
logger.warnOnce("recurring", "first failure")
logger.warnOnce("recurring", "repeated failure")
assert(harness.messages[1] == "[Swaying Waying] information", "info uses the native message severity")
assert(harness.warnings[1] == "[Swaying Waying] recoverable failure", "warnings use the native warning severity")
assert(
	#harness.warnings == 2 and harness.warnings[2] == "[Swaying Waying] first failure",
	"recurring warnings are deduplicated by the shared implementation"
)
logger.error("serious failure", "original cause")
logger.error("another failure")
assert(
	harness.errors[1].message == "[Swaying Waying] serious failure" and harness.errors[1].details == "original cause",
	"non-throwing errors preserve details"
)
assert(harness.errors[2].details == nil, "error details are optional")
local succeeded, failure = pcall(logger.fail, "invalid state")
assert(
	not succeeded and failure:find("[Swaying Waying] ERROR: invalid state", 1, true),
	"explicit failures retain the shared logger's error format"
)

harness, logger = fixture(true)
logger.debug("development detail")
assert(harness.verbose[1] == "[Swaying Waying] development detail", "the local debug switch reaches the shared logger")
assert(not pcall(fixture, "invalid"), "invalid debug switches fail explicitly")

do
	local absent = dofile("tests/support/harness.lua").new()
	local compatibility = absent.require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
	compatibility.configure({ just_more_weather_1 = {} })
	compatibility.prepare("tests::/optional_weather.mdl", {})
	assert(#absent.warnings == 0 and #absent.verbose == 0, "absent optional mods stay quiet in production")
	local malformed = dofile("tests/support/harness.lua").new()
	malformed.overrides["just_more_weather_1::/jmw/neige_poudre.lua"] = {}
	compatibility = malformed.require("apasz_swaying_waying::/swaying_waying/model_compatibility.lua")
	compatibility.configure({ just_more_weather_1 = {} })
	compatibility.prepare("tests::/malformed_weather.mdl", {})
	compatibility.prepare("tests::/another_model.mdl", {})
	assert(
		#malformed.warnings == 1 and malformed.warnings[1]:find("addToModel", 1, true),
		"present optional modules with missing adapters report the integration failure once"
	)
end
do
	local environment = dofile("tests/support/model_environment.lua").new()
	local modifier = environment.require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")
	local models = dofile("tests/support/model_fixture.lua")
	for index, metadata in ipairs({ "invalid", { sections = {} } }) do
		local model = models.railModel(nil)
		model.metadata.swayingWaying = metadata
		local fileName = "tests::/invalid_logging_metadata_" .. index .. ".mdl"
		modifier.modify(fileName, model, { intensity = 1 })
		assert(model.metadata.transformatorConfig == nil, "invalid author metadata prevents adaptation")
		assert(
			environment.warnings[index]:find("Skipping sway for " .. fileName, 1, true),
			"invalid author metadata warnings describe the actual skipped outcome"
		)
	end
end
print("Logging integration checks passed")
