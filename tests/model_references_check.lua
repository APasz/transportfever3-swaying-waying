local harness = dofile("tests/support/harness.lua").new()
local references = harness.require("apasz_swaying_waying::/swaying_waying/model_references.lua")
local targets = {
	attachments = { body = "body_content" },
	placements = { body = "body_placement" },
	meshes = { body = "body_mesh" },
}
local metadata = {
	seats = { { group = "body" } },
	seatProvider = { seats = { { group = "body" } } },
	labelList = { labels = { { childId = "body" }, { childId = "" } } },
	lights = { { meshId = "body" } },
	lightSourceList = { lights = { { meshId = "body" } } },
	particleSystem = { emitters = { { child = "body" } } },
	railVehicle = { config = { group = "body", fakeBogies = { { { group = "body" } } } } },
	loadIndicator = { slots = { { childId = "body" } }, configs = { { cargoBay = { childId = "body" } } } },
	transportVehicle = { compartments = { { loadConfigs = { { cargoEntry = { seats = { { group = "body" } } } } } } } },
	cameraConfig = { positions = { { group = "body" } } },
	foreign = { group = "body", nested = { childId = "body" } },
	swayingWaying = { sections = { { group = "body" } } },
}
local bindings = references.collect(metadata)
assert(references.hasReferences(bindings, targets))
references.retarget(bindings, targets)
assert(metadata.seats[1].group == "body_content")
assert(metadata.seatProvider.seats[1].group == "body_content")
assert(metadata.labelList.labels[1].childId == "body_content")
assert(metadata.lights[1].meshId == "body_mesh")
assert(metadata.lightSourceList.lights[1].meshId == "body_mesh")
assert(metadata.particleSystem.emitters[1].child == "body_content")
assert(metadata.railVehicle.config.fakeBogies[1][1].group == "body_placement")
assert(metadata.loadIndicator.slots[1].childId == "body_content")
assert(metadata.loadIndicator.configs[1].cargoBay.childId == "body_content")
assert(metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.seats[1].group == "body_content")
assert(metadata.railVehicle.config.group == "body")
assert(metadata.cameraConfig.positions[1].group == "body")
assert(metadata.foreign.group == "body" and metadata.foreign.nested.childId == "body")
assert(metadata.swayingWaying.sections[1].group == "body")
assert(not references.hasReferences(references.collect(metadata), targets))
local labels = references.defaultLabels(metadata)
assert(#labels == 1 and labels[1] == metadata.labelList.labels[2])
local root = {}
local original = { [root] = { names = { body = { {} } } } }
references.validate(bindings, targets, original, { [root] = { body_content = 1, body_mesh = 1, body_placement = 1 } })
assert(not pcall(references.validate, bindings, targets, original, { [root] = {} }))
print("Model reference checks passed")
