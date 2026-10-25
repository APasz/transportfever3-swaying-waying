local assertions = dofile("tests/assertions.lua")
local assertEqual = assertions.equal
local messages = {}
_G.ug_require = function(name)
	assert(name == "apasz_swaying_waying::/swaying_waying/logger.lua")
	return {
		info = function(message)
			messages[#messages + 1] = message
		end,
		warn = function(message)
			messages[#messages + 1] = message
		end,
	}
end
local carriages = { 101, 102, 103 }
local info = {
	[101] = { owningVehicle = 100, index = 0, offset = -10.0, reversed = false },
	[102] = { owningVehicle = 100, index = 1, offset = -29.0, reversed = true },
	[103] = { owningVehicle = 100, index = 2, offset = -44.0, reversed = false },
}
local components = {
	[100] = { CARRIAGE_LIST = { carriages = carriages } },
	[101] = { CARRIAGE = { reversed = true } },
	[102] = { CARRIAGE = { reversed = false }, CUSTOM_STATE = { state = { foreign = true } } },
	[103] = { CARRIAGE = { reversed = true } },
	[200] = {},
}
_G.api = {
	type = {
		ComponentType = {
			CARRIAGE_LIST = "CARRIAGE_LIST",
			CARRIAGE = "CARRIAGE",
			TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE",
		},
	},
	engine = {
		entityExists = function(entity)
			return components[entity] ~= nil
		end,
		getComponent = function(entity, component)
			assert(
				component == "CARRIAGE_LIST" or component == "CARRIAGE",
				"inspection only reads consist and carriage components"
			)
			return assert(components[entity])[component]
		end,
		getEntitiesWithComponent = function(component)
			if component == "CARRIAGE_LIST" then
				error("Cannot loop over this component type")
			end
			assertEqual(component, "TRANSPORT_VEHICLE")
			return { 100, 200 }
		end,
		system = {
			carriageListSystem = {
				getVehicleInfo = function(entity)
					return assert(info[entity])
				end,
				getVehicleData = function(entity)
					assertEqual(entity, 100, "native vehicle data is requested for the owning consist")
					return { length = 64.0, bounds = { back = -54.0, front = 10.0 } }
				end,
			},
		},
	},
	cmd = setmetatable({}, {
		__index = function()
			error("The spacing probe must not issue game commands")
		end,
	}),
}
local probe = dofile("content/swaying_waying/spacing_probe.lua")
local function contains(message, text)
	assert(message:find(text, 1, true), "Missing probe detail: " .. text)
end
local function inspect(entity)
	messages = {}
	probe.inspect(entity)
	assertEqual(messages[1], "Spacing probe engine: begin", "inspection logs its start")
	assertEqual(messages[#messages], "Spacing probe engine: complete", "inspection logs its completion")
	return messages
end
local targeted = inspect(100)
assertEqual(#targeted, 6, "one report describes the consist and each carriage")
contains(targeted[2], "vehicle=100 count=3 length=64.000000")
contains(targeted[3], "position=0 offset=-10.000000 delta=0.000000")
contains(targeted[3], "apiCarriageReversed=true")
contains(targeted[4], "offset=-29.000000 delta=-19.000000 apiListReversed=true")
contains(targeted[4], "apiCarriageReversed=false")
contains(targeted[5], "delta=-15.000000")
local byCarriage = inspect(102)
assertEqual(byCarriage[2], targeted[2], "a carriage entity resolves to its owning consist")
local all = inspect()
contains(all[2], "inspecting 1 consists")
assertEqual(#all, 7, "all-consist inspection filters out vehicles without carriage lists")
assertEqual(components[102].CUSTOM_STATE.state.foreign, true, "inspection preserves foreign custom state")
assertEqual(#carriages, 3, "inspection preserves consist membership")
local function rejects(entity, text)
	messages = {}
	local ok, failure = pcall(probe.inspect, entity)
	assertEqual(ok, false, "invalid probe input must fail clearly")
	contains(failure, text)
	assertEqual(messages[1], "Spacing probe engine: begin", "failed inspection still logs its start")
	contains(messages[#messages], "Spacing probe engine: failed:")
	contains(messages[#messages], text)
end
rejects(999, "entity does not exist")
rejects(200, "expected a consist or carriage entity")
info[102].offset = 0 / 0
rejects(100, "invalid native carriage offset")
info[102].offset = -29.0
info[102].owningVehicle = -1
rejects(102, "carriage has no owning vehicle")
info[102].owningVehicle = 100

print("Spacing probe checks passed")
