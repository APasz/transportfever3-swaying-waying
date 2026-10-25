local equal = dofile("tests/assertions.lua").equal
local fixture = dofile("tests/support/model_fixture.lua")
local gui = dofile("tests/support/gui_environment.lua")

do
	local contract = gui.new()
	local invalid = contract.react.RegisterRecipe("ComponentRoot", function()
		return contract.builtin.Component({ layout = contract.builtin.BoxLayout({ children = {} }) })
	end)
	local ok, failure = pcall(invalid, {})
	equal(ok, false, "ordinary recipes cannot return a component root")
	assert(
		tostring(failure):find("Recipe child must be a layout", 1, true),
		"the native layout constraint is diagnosed"
	)
	local valid = contract.react.RegisterRecipe("LayoutRoot", function()
		return contract.builtin.BoxLayout({
			children = { contract.builtin.Component({ layout = contract.builtin.BoxLayout({ children = {} }) }) },
		})
	end)
	equal(pcall(valid, {}), true, "components remain valid children of a layout")
end

local function instance(id, x)
	local matrix = fixture.identity()
	matrix[13] = x
	return { modelId = id, transf = matrix, transf0 = matrix }
end

local function model(name, kind, paired)
	local pose = fixture.identity()
	pose[13], pose[15] = 5, 2
	local cameras = { schema = 1, count = 1, positions = { { index = 1, kind = kind, crewSeat = 1, pose = pose } } }
	if paired then
		cameras.count, cameras.positions[2] = 2, { index = 2, kind = "Sway", crewSeat = 1, pose = pose }
	end
	return {
		boundingInfo = { bbMin = { x = -10, y = -2, z = 0 }, bbMax = { x = 10, y = 2, z = 5 } },
		metadata = {
			description = { name = name },
			extent = { bbMin = { x = -10, y = -2, z = 0 }, bbMax = { x = 10, y = 2, z = 5 } },
			metadata = { swayingWayingCameraHud = cameras },
		},
	}
end

local harness = gui.new()
local react, freeCam = harness.react, harness.freeCam
local original = freeCam.FreeCamOptions
local priorCalls = 0
local previous = react.RegisterRecipe("OtherCameraOverlay", function(params)
	priorCalls = priorCalls + 1
	return harness.builtin.BoxLayout({
		children = {
			react.CallOriginalRecipe(original, params),
			harness.builtin.TextView({ text = "Other overlay" }),
		},
	})
end)
_react.recipeReplace[react.GetRecipeId(original)] = previous
local module = harness.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua")
module.doReplace(harness.replacementApi)
module.doReplace(harness.replacementApi)
equal(harness.replacements, 1, "HUD registration is idempotent")
equal(freeCam.FreeCamOptions, original, "the shared recipe handle stays intact")
equal(harness.labels(harness.render()), "Other overlay", "the earlier overlay remains mounted outside cockpit mode")
local reads = harness.componentReads
for _ = 1, 3 do
	harness.frame()
end
equal(harness.componentReads, reads, "an inactive HUD does not scan vehicles")

harness.names[1] = "Train 12"
harness.components[1] = { tv = {}, cl = { carriages = { 10, 20 } } }
harness.components[10] = { mil = { fatInstances = { instance(101, 100) } } }
harness.components[20] = { mil = { fatInstances = { instance(102, 130) } } }
harness.models[101], harness.models[102] = model("A4", "Stable"), model("Big Boy", "Sway")
harness.eye = { x = 105, y = 0, z = 2 }
local ctx, params = {}, { cockpitCameraForEntity = 1 }
freeCam.FreeCamTool.push(ctx, params)
equal(harness.pushes, 1, "the original cockpit push runs exactly once")
equal(harness.lastPush[1], ctx, "the original push receives its context")
equal(harness.lastPush[2], params, "the original push receives the unchanged parameters")
local visibleTree = harness.frame()
equal(
	harness.labels(visibleTree),
	"A4 | Crew seat 1 · Stable | Other overlay | Train 12",
	"the HUD shows the consist, carriage model, and unique camera"
)
local panel = assert(harness.find(visibleTree, "apasz.swaying_waying.camera-hud"))
local hudRoot = visibleTree.params.children[2].params.children[1].params.item
equal(
	hudRoot.recipeMeta.styleSheet.anchorPoint[1],
	1,
	"the floating HUD anchors its outer right edge at the right edge of the screen"
)
equal(hudRoot.recipeMeta.styleSheet.anchorPoint[2], 0, "the floating HUD keeps a fixed top edge")
equal(panel.params.meta.styleSheet, nil, "inner content does not apply a second anchor offset")
assert(priorCalls > 1, "the earlier camera overlay remains mounted in cockpit mode")
local modelReads = harness.modelReads
harness.names[1] = "Mallard"
equal(
	harness.labels(harness.frame()),
	"A4 | Crew seat 1 · Stable | Mallard | Other overlay",
	"player renames refresh without rebuilding model data"
)
equal(harness.modelReads, modelReads, "static model information is cached")
local panelReports = 0
for _, message in ipairs(harness.messages) do
	if message:find("Camera HUD panel:", 1, true) then
		panelReports = panelReports + 1
		assert(message:find("visible=true", 1, true), "the panel diagnostic reports native visibility")
		assert(message:find("size=(300,100)", 1, true), "the panel diagnostic reports native dimensions")
	end
end
equal(panelReports, 1, "panel geometry is reported once per cockpit entry")
reads = harness.componentReads
harness.frame(0.01)
equal(harness.componentReads, reads, "snapshot work respects the refresh interval")

harness.eye.x = 135
equal(
	harness.labels(harness.frame()),
	"Big Boy | Crew seat 1 · Sway | Mallard | Other overlay",
	"switching within a consist updates the displayed model"
)
harness.models[103] = model("A4", "Stable", true)
harness.components[10].mil.fatInstances[1].modelId = 103
harness.eye.x = 105
equal(
	harness.labels(harness.frame()),
	"A4 | Mallard | Other overlay",
	"coincident camera types are suppressed while names remain visible"
)

harness.eye.x = 0 / 0
local vehicleOnlyTree = harness.frame()
equal(
	harness.labels(vehicleOnlyTree),
	"Mallard | Other overlay",
	"transient NaN eye coordinates never enter spatial queries"
)
local vehicleOnlyRoot = vehicleOnlyTree.params.children[2].params.children[1].params.item
equal(#hudRoot.params.children[1].params.layout.params.children, 3, "the original HUD has three text lines")
equal(#vehicleOnlyRoot.params.children[1].params.layout.params.children, 1, "the fallback HUD has one text line")
equal(vehicleOnlyRoot.recipeMeta, hudRoot.recipeMeta, "changing line count preserves the outer anchor")
equal(
	vehicleOnlyRoot.params.children[1].params.meta.styleSheet,
	nil,
	"the shorter HUD also avoids an inner anchor offset"
)
harness.eye.x = 105
harness.activeTool = { name = "Pause" }
equal(harness.labels(harness.frame()), "Other overlay", "shelving the cockpit hides its HUD")
harness.activeTool = { name = "FreeCam" }
equal(harness.labels(harness.frame()), "A4 | Mallard | Other overlay", "restoring the cockpit shows its HUD")
harness.event("stoppedFollowAction")
equal(harness.pops, 1, "the earlier exit event still reaches the native tool callback")
equal(harness.labels(harness.frame()), "Other overlay", "leaving cockpit mode removes the HUD")
freeCam.FreeCamTool.push({}, {})
equal(harness.labels(harness.frame()), "Other overlay", "ordinary free camera has no cockpit information")

freeCam.FreeCamTool.push(ctx, params)
harness.components[1] = nil
equal(harness.labels(harness.frame()), "Other overlay", "deleted vehicles clear the HUD")
reads = harness.componentReads
harness.frame()
equal(harness.componentReads, reads, "deleted cockpit entities do not remain in the refresh loop")

do
	local disabled = gui.new()
	disabled.cameraConfig.hudEnabled = false
	disabled.modParams = { apasz_swaying_waying = { apasz_swaying_waying_camera_hud = 2 } }
	local requireModule = disabled.require
	disabled.require = function(name)
		assert(not name:match("^::/gui/"), "disabled HUD must not load native UI modules")
		return requireModule(name)
	end
	_G.ug_require = disabled.require
	local push, pop = disabled.freeCam.FreeCamTool.push, disabled.freeCam.FreeCamTool.pop
	disabled
		.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua")
		.doReplace(disabled.replacementApi)
	equal(disabled.replacements, 0, "the development switch stays off even with the old HUD save setting enabled")
	equal(disabled.freeCam.FreeCamTool.push, push, "disabled HUD does not hook cockpit entry")
	equal(disabled.freeCam.FreeCamTool.pop, pop, "disabled HUD does not hook cockpit exit")
	disabled.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.css.lua")
	local stylesheet = data()
	equal(#stylesheet, 0, "disabled HUD registers no stylesheet rules")
end

do
	local vanilla = gui.new()
	vanilla.models[101] = model("A4", "Stable")
	vanilla.models[101].metadata.extent = nil
	vanilla.components[1] = { tv = {}, cl = { carriages = {} }, mil = { fatInstances = { instance(101, 100) } } }
	vanilla.names[1], vanilla.eye = "A4", { x = 105, y = 0, z = 2 }
	vanilla.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua").doReplace(vanilla.replacementApi)
	vanilla.render()
	vanilla.freeCam.FreeCamTool.push({}, { cockpitCameraForEntity = 1 })
	equal(
		vanilla.labels(vanilla.frame()),
		"A4 | Crew seat 1 · Stable",
		"standalone vehicles work without duplicate name/model lines"
	)
	vanilla.event("stoppedFollowAction")
	equal(vanilla.pops, 1, "vanilla input and exit handling survive composition")
	equal(vanilla.labels(vanilla.frame()), "", "the vanilla-only HUD exits cleanly")
end

do
	local exterior = gui.new()
	exterior.models[101], exterior.models[102] = model("A4", "Model"), model("Big Boy", "Sway")
	local authored = exterior.models[101].metadata.metadata.swayingWayingCameraHud.positions[1]
	authored.crewSeat, authored.pose[14] = nil, 8
	exterior.names[1], exterior.eye = "Train 1", { x = 105, y = 8, z = 2 }
	exterior.components[1] = { tv = {}, cl = { carriages = { 10, 20 } } }
	exterior.components[10] = { mil = { fatInstances = { instance(101, 100) } } }
	exterior.components[20] = { mil = { fatInstances = { instance(102, 130) } } }
	exterior
		.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua")
		.doReplace(exterior.replacementApi)
	exterior.render()
	exterior.freeCam.FreeCamTool.push({}, { cockpitCameraForEntity = 1 })
	equal(
		exterior.labels(exterior.frame()),
		"A4 | Model camera 1 | Train 1",
		"known exterior viewpoints identify their model and camera outside body bounds"
	)
	local duplicate = model("A4", "Model")
	duplicate.metadata.metadata.swayingWayingCameraHud.positions[1].pose = fixture.identity()
	local coincident = duplicate.metadata.metadata.swayingWayingCameraHud.positions[1].pose
	coincident[13], coincident[14], coincident[15] = -25, 8, 2
	exterior.models[103], exterior.components[20].mil.fatInstances[1].modelId = duplicate, 103
	equal(
		exterior.labels(exterior.frame()),
		"Train 1",
		"coincident exterior cameras on separate carriages remain ambiguous, even for repeated models"
	)
end

do
	local spatial = gui.new()
	local a4, bigBoy = model("A4", "Stable"), model("Big Boy", "Sway")
	for _, entry in ipairs({ a4, bigBoy }) do
		entry.metadata.metadata = nil
		entry.boundingInfo = { bbMin = { x = -30, y = -12, z = -12 }, bbMax = { x = 30, y = 12, z = 10 } }
	end
	-- Native metadata records are userdata, unlike source-file Lua tables.
	local description, extent = assert(io.tmpfile()), assert(io.tmpfile())
	local descriptionMeta, extentMeta = getmetatable(description), getmetatable(extent)
	debug.setmetatable(description, { __index = a4.metadata.description })
	debug.setmetatable(extent, { __index = a4.metadata.extent })
	a4.metadata.description, a4.metadata.extent = description, extent
	spatial.models[101], spatial.models[102] = a4, bigBoy
	spatial.names[1], spatial.eye = "Train 1", { x = 105, y = 0, z = 2 }
	spatial.components[1] = { tv = {}, cl = { carriages = { 10, 20 } } }
	spatial.components[10] = { mil = { fatInstances = { instance(101, 100) } } }
	spatial.components[20] = { mil = { fatInstances = { instance(102, 130) } } }
	spatial.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua").doReplace(spatial.replacementApi)
	spatial.render()
	spatial.freeCam.FreeCamTool.push({}, { cockpitCameraForEntity = 1 })
	local tree = spatial.frame()
	debug.setmetatable(description, descriptionMeta)
	debug.setmetatable(extent, extentMeta)
	description:close()
	extent:close()
	equal(
		spatial.labels(tree),
		"A4 | Train 1",
		"native descriptions and physical extents work despite overlapping render bounds"
	)
	local fallback = model("Big Boy", "Sway")
	fallback.metadata.extent, fallback.metadata.metadata = nil, nil
	spatial.models[103], spatial.components[20].mil.fatInstances[1].modelId = fallback, 103
	spatial.eye.x = 135
	equal(
		spatial.labels(spatial.frame()),
		"Big Boy | Train 1",
		"models without physical extents can still use render bounds"
	)
end

do
	local recovering = gui.new()
	recovering.models[101] = model("A4", "Stable")
	recovering.models[101].metadata.metadata.swayingWayingCameraHud.schema = 99
	recovering.names[1], recovering.eye = "Mallard", { x = 105, y = 0, z = 2 }
	recovering.components[1] = { tv = {}, mil = { fatInstances = { instance(101, 100) } } }
	recovering
		.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua")
		.doReplace(recovering.replacementApi)
	recovering.render()
	recovering.freeCam.FreeCamTool.push({}, { cockpitCameraForEntity = 1 })
	equal(
		recovering.labels(recovering.frame()),
		"A4 | Mallard",
		"invalid camera metadata preserves vehicle and model names"
	)
	equal(#recovering.warnings, 1, "invalid metadata is diagnosed")
	recovering.frame()
	equal(#recovering.warnings, 1, "cached invalid metadata does not flood the log")
	local getComponent = api.engine.getComponent
	api.engine.getComponent = function()
		error("transient native query failure")
	end
	local ok, tree = pcall(recovering.frame)
	equal(ok, true, "native query failures stay inside the HUD boundary")
	equal(recovering.labels(tree), "", "query failures clear stale vehicle details")
	api.engine.getComponent = getComponent
	equal(recovering.labels(recovering.frame()), "A4 | Mallard", "the HUD recovers after a native query succeeds")
end

do
	local overlay = gui.new()
	overlay.freeCamVisible = false
	overlay.models[101] = model("A4", "Stable")
	overlay.components[1] = { tv = {}, mil = { fatInstances = { instance(101, 100) } } }
	overlay.names[1], overlay.eye = "Mallard", { x = 105, y = 0, z = 2 }
	local callout = overlay.builtin.FloatingLayoutChild({
		h = 0,
		v = 0,
		item = overlay.builtin.TextView({ text = "Existing callout" }),
	})
	overlay.calloutChildren[1] = callout
	local calloutRecipe, freeCamRecipe = overlay.calloutContainer, overlay.freeCam.FreeCamOptions
	local floatingLayout = overlay.builtin.FloatingLayout
	local previousCalls = 0
	_react.recipeReplace[overlay.react.GetRecipeId(floatingLayout)] = function(params)
		previousCalls = previousCalls + 1
		return overlay.react.CallOriginalRecipe(floatingLayout, params)
	end
	overlay.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua").doReplace(overlay.replacementApi)
	overlay.render()
	overlay.freeCam.FreeCamTool.push({}, { cockpitCameraForEntity = 1 })
	local tree = overlay.frame()
	equal(
		overlay.labels(tree),
		"A4 | Crew seat 1 · Stable | Existing callout | Mallard",
		"the HUD stays visible when the native free-camera controls are hidden"
	)
	equal(overlay.calloutContainer, calloutRecipe, "the native callout recipe identity stays intact")
	equal(overlay.freeCam.FreeCamOptions, freeCamRecipe, "native free-camera controls need no replacement")
	equal(overlay.getCalloutApi(), overlay.calloutApi, "the native callout API stays intact")
	equal(#overlay.calloutChildren, 1, "the native layout's child list is not mutated")
	equal(overlay.calloutChildren[1], callout, "existing callout nodes retain their identity")
	local calloutLayout = tree.params.children[2]
	equal(calloutLayout.params.children[2], callout, "existing callouts stay above the HUD")
	equal(calloutLayout.params.children[1].params.overflowMode, "keep-inside", "the HUD is clamped inside the viewport")
	assert(previousCalls > 0, "an existing floating-layout replacement still runs")
	local untouched = {}
	local unrelated = overlay.react.RegisterRecipe("UnrelatedFloatingLayout", function()
		return overlay.builtin.FloatingLayout({ children = untouched })
	end)
	equal(unrelated().params.children, untouched, "floating layouts outside CalloutContainer stay untouched")
end

do
	local incompatible = gui.new()
	local recipeId = incompatible.react.GetRecipeId(incompatible.builtin.FloatingLayout)
	_react.recipeReplace[recipeId] = false
	local push = incompatible.freeCam.FreeCamTool.push
	local ok = pcall(
		incompatible.require("apasz_swaying_waying::/gui/swaying_waying/camera_hud.script.lua").doReplace,
		incompatible.replacementApi
	)
	equal(ok, true, "unsupported UI internals cannot abort game UI bootstrap")
	equal(incompatible.replacements, 0, "invalid UI replacements are left untouched")
	equal(incompatible.freeCam.FreeCamTool.push, push, "failed installation leaves the original lifecycle intact")
	equal(#incompatible.warnings, 1, "unsupported UI internals receive a clear diagnostic")
end

print("Camera HUD UI checks passed")
