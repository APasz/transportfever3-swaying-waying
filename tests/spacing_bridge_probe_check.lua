local touchedApi = false
_G.api = setmetatable({}, {
	__index = function()
		touchedApi = true
		error("The disabled bridge probe must not access the engine")
	end,
})
_G.ug_require = function()
	error("The disabled bridge probe must not load engine helpers")
end
local probe = dofile("content/swaying_waying/spacing_bridge_probe.lua")
for _, name in ipairs({ "test", "clear" }) do
	local ok, failure = pcall(probe[name], 6988)
	assert(not ok, "Old console-history commands must fail before queuing work")
	assert(failure:find("Spacing bridge probe disabled", 1, true), failure)
	assert(not touchedApi, "Disabled bridge commands must not touch the engine")
end
print("Spacing bridge probe checks passed")
