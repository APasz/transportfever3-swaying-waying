local equal = dofile("tests/assertions.lua").equal

local function fixture(enabled)
	local harness = dofile("tests/support/harness.lua").new()
	harness.overrides["apasz_swaying_waying::/swaying_waying/curvature_probe_config.lua"] = enabled
	local module = harness.require("apasz_swaying_waying::/swaying_waying/curvature_probe.lua")
	local item = { module = module, messages = harness.messages, warnings = harness.warnings, pointCalls = 0 }
	item.params = {
		entityId = 100,
		vehicleStaticInfo = { carriageEntity = 101 },
		previousInfo = { world = { gameTime = 84 }, railVehicle = { curvature = 0.001 } },
		currentInfo = {
			world = { gameTime = 100 },
			vehicle = { speed = 20, positionInCarriageList = 0, carriageListLength = 4 },
			railVehicle = { curvature = 0.002 },
			landVehicle = {
				reversed = false,
				carriagesReversed = { false, false, false, true },
				wheelAnimationInfo = { totalDist = 123 },
			},
		},
		landVehicleApi = {
			getVehicleEdgeInfo = function(_, offset)
				equal(offset, 0, "the point sample stays at the current carriage")
				item.pointCalls = item.pointCalls + 1
				return { curvature = 0.003 }
			end,
			getAverageCurvature = function()
				error("The probe must reuse the motion query")
			end,
		},
	}
	function item.observe(average)
		return module.observe(item.params, average)
	end
	return item
end

local function contains(message, expected)
	assert(message:find(expected, 1, true), "Missing curvature probe detail: " .. expected)
end

do
	local item = fixture(false)
	equal(item.module.observe, nil, "disabled diagnostics expose no callback")
	equal(#item.messages, 0, "disabled diagnostics do not log")
	equal(item.pointCalls, 0, "disabled diagnostics make no native calls")
end
assert(not pcall(fixture, "invalid"), "invalid diagnostic switches fail clearly")

do
	local item = fixture(true)
	assert(item.observe(0.004))
	contains(item.messages[1], "Curvature probe begin:")
	local line = item.messages[2]
	contains(line, "vehicle=100 carriage=101 position=0 count=4 sample=1")
	contains(line, "time=100 previousTime=84 distance=123 speed=20 reversed=false facing=false")
	contains(line, "supplied=0.002 previousSupplied=0.001 average40=0.004 point=0.003")
	item.params.currentInfo.world.gameTime = 150
	item.params.currentInfo.railVehicle.curvature = 0.003
	assert(not item.observe(0.005), "render frames between samples do not log or query")
	item.params.currentInfo.world.gameTime = 200
	assert(item.observe(0.005))
	contains(item.messages[3], "frames=2 suppliedChanges=1 averageChanges=1")
	equal(item.pointCalls, 2, "point queries run only for logged samples")
	assert(not item.observe(0.005), "duplicate callbacks and pauses respect the log interval")
	item.params.currentInfo.world.gameTime = 50
	assert(item.observe(0.005), "clock rewinds produce a fresh bounded observation")
	item.params.entityId = 200
	assert(not item.observe(0.005), "each context observes only its selected consist")
end

do
	local item = fixture(true)
	item.params.currentInfo.vehicle.speed = 0
	assert(not item.observe(), "stopped vehicles do not select the diagnostic consist")
	item.params.currentInfo.vehicle.speed = 20
	item.params.currentInfo.vehicle.carriageListLength = 1
	assert(not item.observe(), "a single locomotive cannot establish per-carriage locality")
	item.params.currentInfo.railVehicle = nil
	assert(not item.observe(), "missing rail data is skipped")
	equal(#item.messages, 0)
	equal(item.pointCalls, 0)
end

do
	local item = fixture(true)
	item.params.currentInfo.vehicle.carriageListLength = 10
	item.params.currentInfo.landVehicle.carriagesReversed = nil
	for position = 0, 9 do
		item.params.currentInfo.vehicle.positionInCarriageList = position
		item.params.vehicleStaticInfo.carriageEntity = 101 + position
		equal(item.observe(0.004), position % 3 == 0, "four observations span a long consist")
	end
	equal(item.pointCalls, 4, "carriage sampling has a fixed per-context bound")
	item.params.currentInfo.vehicle.positionInCarriageList = 0
	item.params.vehicleStaticInfo.carriageEntity = 999
	assert(not item.observe(0.004), "changing carriage identities cannot grow the diagnostic state")
end

do
	local item = fixture(true)
	item.params.previousInfo = nil
	item.params.currentInfo.railVehicle.curvature = 0 / 0
	item.params.landVehicleApi.getVehicleEdgeInfo = function()
		error("unavailable native point")
	end
	assert(item.observe())
	contains(item.messages[2], "previousTime=unavailable")
	contains(item.messages[2], "supplied=invalid(")
	contains(item.messages[2], "previousSupplied=unavailable average40=unavailable point=unavailable")
	equal(#item.warnings, 1, "failed point queries produce a diagnostic")
	contains(item.warnings[1], "unavailable native point")
	item.params.currentInfo.world.gameTime = item.params.currentInfo.world.gameTime + 100
	assert(item.observe())
	equal(#item.warnings, 1, "failed point queries do not repeat warnings")
end

do
	local item = fixture(true)
	for sample = 1, 300 do
		item.params.currentInfo.world.gameTime = sample * 100
		equal(item.observe(0.004), sample <= 256, "each carriage stops logging at its sample limit")
	end
	equal(item.pointCalls, 256, "completed probes stop their extra native queries")
	equal(#item.messages, 258, "begin, bounded samples, and completion have a fixed log budget")
	contains(item.messages[#item.messages], "Curvature probe complete:")
	contains(item.messages[#item.messages], "samples=256")
end

print("Curvature probe checks passed")
