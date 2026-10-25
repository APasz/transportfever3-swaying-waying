local function fixture(enabled)
	local harness = dofile("tests/support/harness.lua").new()
	harness.overrides["apasz_swaying_waying::/swaying_waying/lod_probe_config.lua"] = enabled
	local module = harness.require("apasz_swaying_waying::/swaying_waying/lod_probe.lua")
	local item =
		{ module = module, messages = harness.messages, warnings = harness.warnings, transforms = 0, animations = 0 }
	item.params = {
		entityId = 100,
		vehicleStaticInfo = { carriageEntity = 101, modelInfo = { axles = {} } },
		currentInfo = { world = { gameTime = 0 }, vehicle = { positionInCarriageList = 0 } },
		modelMetadataInfo = { seats = {} },
		candidateLod = 2,
	}
	item.output = {
		getUserTransfs = function()
			item.transforms = item.transforms + 1
			return { { type = 1 }, { type = 0 }, { type = 1 } }
		end,
		getAnimationStates = function()
			item.animations = item.animations + 1
			return { { animation = "native_z" }, { animation = "native_a" } }
		end,
		addAnimationState = function()
			error("LOD inspection must not write animation states")
		end,
		setUserTransf = function()
			error("LOD inspection must not write transforms")
		end,
	}
	function item.observe()
		return module.observe(item.params, item.output, "tests::/lod.mdl")
	end
	return item
end

local function contains(line, expected)
	assert(line:find(expected, 1, true), "Missing LOD probe detail: " .. expected)
end

assert(fixture(false).module.observe == nil, "disabled LOD diagnostics have no observer")
assert(not pcall(fixture, "invalid"), "invalid diagnostic switches fail clearly")
do
	local item = fixture(true)
	item.params.currentInfo.vehicle.positionInCarriageList = 1
	assert(not item.observe(), "inspection waits for a leading carriage")
	item.params.currentInfo.vehicle.positionInCarriageList = 0
	assert(item.observe())
	contains(item.messages[1], "LOD probe begin:")
	contains(item.messages[2], "candidateLod:2")
	contains(item.messages[3], "sample=1 callback=1 time=0 transforms=3[0:1,1:2]")
	contains(item.messages[3], "nativeAnimations=[native_a,native_z]")
	item.params.vehicleStaticInfo.carriageEntity = 102
	assert(not item.observe(), "other carriages do not consume the callback budget")
	item.params.vehicleStaticInfo.carriageEntity = 101
	item.params.candidateLod = 3
	for _ = 1, 63 do
		assert(not item.observe(), "read-only getters are throttled between samples")
	end
	assert(item.observe(), "paused simulation time does not prevent a zoom capture")
	contains(item.messages[4], "candidateLod:3")
	assert(item.transforms == 2 and item.animations == 2, "each log sample makes only its two supported getter calls")
end
do
	local item = fixture(true)
	item.output.getUserTransfs = nil
	item.output.getAnimationStates = function()
		error("unavailable native output")
	end
	assert(item.observe())
	contains(item.messages[3], "transforms=unavailable nativeAnimations=unavailable")
	assert(#item.warnings == 2, "unavailable native output getters report their failures")
	contains(item.warnings[2], "unavailable native output")
	for _ = 1, 64 do
		item.observe()
	end
	assert(#item.warnings == 2, "unavailable output getters do not repeat warnings")
end
do
	local item = fixture(true)
	for _ = 1, 4000 do
		item.observe()
	end
	assert(item.transforms == 48 and item.animations == 48, "completed diagnostics stop native getter calls")
	assert(#item.messages == 51, "inventory, bounded samples, and completion have a fixed log budget")
	contains(item.messages[#item.messages], "LOD probe complete:")
	assert(item.params.currentInfo.world.gameTime == 0, "inspection never advances simulation time")
end

print("LOD probe checks passed")
