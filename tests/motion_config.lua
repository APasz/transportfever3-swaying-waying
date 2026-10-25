local config = dofile("content/swaying_waying/motion_config.lua")
local isolation = os.getenv("SWAYING_WAYING_TEST_ISOLATION") == "1"
-- Preserve experimental and diagnostic switches on disk while exercising every component in regressions.
for name, value in pairs(config) do
	assert(type(value) == "boolean", "Expected a boolean motion switch: " .. name)
	assert(
		isolation or value or name == "carriageLag",
		"Release motion component is disabled: " .. name .. " (use --isolation for diagnostic builds)"
	)
	config[name] = true
end
return config
