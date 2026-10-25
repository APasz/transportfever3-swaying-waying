local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pairs = _tl_compat and _tl_compat.pairs or pairs
local pcall = _tl_compat and _tl_compat.pcall or pcall
local string = _tl_compat and _tl_compat.string or string
local table = _tl_compat and _tl_compat.table or table
local _tl_table_pack = table.pack or function(...)
	return { n = select("#", ...), ... }
end
local _tl_table_unpack = unpack or table.unpack
local cameraConfig = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua")
assert(type(cameraConfig.hudEnabled) == "boolean", "Camera HUD development switch must be a boolean")
local module = { doReplace = function(_replacementApi) end }

function data()
	return module
end

if not cameraConfig.hudEnabled then
	return module
end

local react = ug_require("::/gui/main/react.lua")
local builtin = ug_require("::/gui/main/builtin.lua")
local styleutil = ug_require("::/gui/main/styleutil.tl")
local freeCam = ug_require("::/gui/main/free_cam_options.tl")
local gameGlobals = ug_require("::/gui/main/game_react_globals.tl")
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local policy = ug_require("apasz_swaying_waying::/swaying_waying/camera_hud_policy.lua")
local cache = ug_require("apasz_swaying_waying::/swaying_waying/bounded_cache.lua")
local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")

local floatingChild = builtin.FloatingLayoutChild

local REFRESH_INTERVAL = 0.2
local MODEL_CACHE_CAPACITY = 512
local PANEL_ID = "apasz.swaying_waying.camera-hud"
local HUD_PARAMS = {
	meta = { styleSheet = styleutil.makeStyle({ anchorPoint = { 1, 0 } }) },
}
local models = cache.create(MODEL_CACHE_CAPACITY)
local cockpitEntity = nil
local cockpitGeneration = 0
local installed = false

local function reset(entity)
	cockpitEntity = entity
	cockpitGeneration = cockpitGeneration + 1
end

local function modelInfo(modelId)
	local cached = cache.get(models, modelId)
	if cached ~= nil then
		return cached
	end
	local model = api.res.modelRep.get(modelId)
	local metadata = model.metadata
	local description = metadata.description
	local name = description ~= nil and description.name or nil
	local extent = metadata.extent
	local minimum, maximum = model.boundingInfo.bbMin, model.boundingInfo.bbMax
	if extent ~= nil then
		minimum, maximum = extent.bbMin, extent.bbMax
	end
	local custom = values.asTable(metadata.metadata)
	local hud = custom ~= nil and (custom)[constants.CAMERA_HUD_METADATA_KEY] or nil
	local valid, cameras = pcall(policy.read, hud)
	if not valid then
		logger.warnOnce(
			"camera-hud-model:" .. tostring(modelId),
			"Ignoring invalid camera HUD metadata: " .. tostring(cameras)
		)
	end
	local info = {
		name = type(name) == "string" and _(name) or "",
		minimum = minimum,
		maximum = maximum,
		cameras = valid and cameras or nil,
	}
	cache.put(models, modelId, info)
	logger.info(
		"Camera HUD model: id="
			.. tostring(modelId)
			.. "; name="
			.. info.name
			.. "; description="
			.. type(description)
			.. "; customMetadata="
			.. type(metadata.metadata)
			.. "; cameras="
			.. (info.cameras ~= nil and tostring((info.cameras).count) or "none")
	)
	return info
end

local function cameraLabel(camera)
	if camera.kind == "Model" then
		return string.format(_("Model camera %d"), camera.index)
	end
	local label = _(camera.kind)
	if camera.crewSeat ~= nil then
		label = string.format(_("Crew seat %d"), camera.crewSeat) .. " · " .. label
	end
	return label
end

local function readSnapshot(entity)
	if not api.engine.entityExists(entity) then
		reset(nil)
		return nil
	end
	local transport = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if transport == nil then
		return nil
	end
	local snapshot = { vehicle = api.engine.util.getEntityName(entity) or "", model = "", camera = "" }
	local eye = api.gui.camera.getEye()
	if not policy.finitePoint(eye) then
		return snapshot
	end
	local carriages = api.engine.getComponent(entity, api.type.ComponentType.CARRIAGE_LIST)
	local entities = carriages ~= nil and #carriages.carriages > 0 and carriages.carriages or { entity }
	local bodies, viewpoints = 0, 0
	local body = nil
	local viewpoint = nil
	local selected = nil
	for _, carriage in ipairs(entities) do
		local instances = api.engine.getComponent(carriage, api.type.ComponentType.MODEL_INSTANCE_LIST)
		local instance = instances ~= nil and instances.fatInstances[1] or nil
		if instance ~= nil then
			local info = modelInfo(instance.modelId)
			local current = policy.localEye(instance.transf, eye)
			local previous = policy.localEye(instance.transf0, eye)
			if current ~= nil and previous ~= nil then
				if info.cameras ~= nil then
					local camera, nearby = policy.cameraAt(info.cameras, previous, current)
					if nearby then
						viewpoints = viewpoints + 1
						viewpoint, selected = info, camera
					end
				end
				if policy.contains(previous, current, info.minimum, info.maximum) then
					bodies = bodies + 1
					body = info
				end
			end
		end
	end

	if viewpoints == 1 then
		snapshot.model = (viewpoint).name
		if selected ~= nil then
			snapshot.camera = cameraLabel(selected)
		end
	elseif viewpoints == 0 and bodies == 1 then
		snapshot.model = (body).name
	end
	return snapshot
end

local function equal(left, right)
	if left == nil or right == nil then
		return left == right
	end
	local a, b = left, right
	return a.vehicle == b.vehicle and a.model == b.model and a.camera == b.camera
end

local function activeSnapshot()
	local stack = gameGlobals.getDefaultToolStackApi()
	if stack == nil then
		return nil
	end
	local tool = stack.getActiveTool()
	if tool == nil or tool.name ~= freeCam.FreeCamTool.name then
		return nil
	end
	return readSnapshot(cockpitEntity)
end

local function reportPanel(panel)
	local node = panel:get()
	if node == nil or node:getIdentity() == nil then
		return false
	end
	local first, last = node:getPosition(0, 0), node:getPosition(1, 1)
	local size = api.gui.byId.getSize(PANEL_ID)
	local viewport = api.gui.camera.getSize()
	logger.info(
		string.format(
			"Camera HUD panel: visible=%s; bounds=(%.3f,%.3f)-(%.3f,%.3f); size=(%.0f,%.0f); viewport=(%d,%d)",
			tostring(api.gui.byId.isVisibleRecursive(PANEL_ID)),
			first.x,
			first.y,
			last.x,
			last.y,
			size.x,
			size.y,
			viewport.x,
			viewport.y
		)
	)
	return true
end

local function addLabel(children, text)
	if text ~= "" then
		children[#children + 1] = builtin.TextView({ meta = { class = "font-scale-body" }, text = text })
	end
end

local CameraHud = react.RegisterRecipe("ApaszSwayingWayingCameraHud", function(_params)
	react.setMouseTransparent(true)
	react.setDisableFocusable(true)
	local state = react.useState(nil)
	local generation = react.useRef(cockpitGeneration)
	local nextRefresh = react.useRef(0.0)
	local panel = react.useNodeRef()
	local snapshotLogged = react.useRef(-1)
	local panelLogged = react.useRef(-1)
	react.onEvent("stoppedFollowAction", function(_event, _param)
		reset(nil)
		state:set(nil)
	end)
	react.onStep(function()
		local changed = generation:get() ~= cockpitGeneration
		local now = api.util.getApplicationTime()
		if not changed and now < nextRefresh:get() then
			return
		end
		generation:set(cockpitGeneration)
		nextRefresh:set(now + REFRESH_INTERVAL)
		if cockpitEntity == nil then
			if state:old() ~= nil then
				state:set(nil)
			end
			return
		end
		local ok, snapshot = pcall(activeSnapshot)
		if not ok then
			logger.warnOnce("camera-hud-snapshot", "Could not read onboard camera information: " .. tostring(snapshot))
			snapshot = nil
		end
		if snapshot ~= nil then
			if snapshotLogged:get() ~= cockpitGeneration then
				local visible = snapshot
				logger.info(
					"Camera HUD snapshot: entity="
						.. tostring(cockpitEntity)
						.. "; vehicle="
						.. visible.vehicle
						.. "; model="
						.. visible.model
						.. "; camera="
						.. visible.camera
				)
				snapshotLogged:set(cockpitGeneration)
			end
			if panelLogged:get() ~= cockpitGeneration then
				local inspected, ready = pcall(reportPanel, panel)
				if not inspected then
					logger.warnOnce("camera-hud-panel", "Could not inspect camera HUD panel: " .. tostring(ready))
				end
				if not inspected or ready then
					panelLogged:set(cockpitGeneration)
				end
			end
		end
		if not equal(state:old(), snapshot) then
			state:set(snapshot)
		end
	end)
	local snapshot = state:old()
	if snapshot == nil then
		return builtin.BoxLayout({ children = {} })
	end
	local visible = snapshot
	local children = {}
	addLabel(children, visible.vehicle)
	if visible.model ~= visible.vehicle then
		addLabel(children, visible.model)
	end
	addLabel(children, visible.camera)
	if #children == 0 then
		return builtin.BoxLayout({ children = {} })
	end
	return builtin.BoxLayout({
		children = {
			builtin.Component(react.ref(panel), {
				meta = {
					id = PANEL_ID,
					class = "swaying-waying-camera-hud",
				},
				layout = builtin.BoxLayout({ orientation = builtin.type.Orientation.Vertical, children = children }),
			}),
		},
	})
end)

local function install(replacementApi)
	if installed then
		return false
	end

	local registry = values.asTable(_react)
	assert(
		registry ~= nil and type((registry).recipeReplace) == "table" and type((registry).originalRecipeFn) == "table",
		"Camera HUD cannot inspect React replacements"
	)
	local recipeId = react.GetRecipeId(builtin.FloatingLayout)
	assert(recipeId ~= nil, "Camera HUD requires the registered FloatingLayout recipe")
	local recipes = _react
	local previous = recipes.recipeReplace[recipeId]
	assert(previous == nil or type(previous) == "function", "Camera HUD found an invalid FloatingLayout replacement")
	local render = previous or recipes.originalRecipeFn[recipeId]
	assert(type(render) == "function", "Camera HUD cannot resolve the active FloatingLayout renderer")
	local tool = freeCam.FreeCamTool
	local push, pop = tool.push, tool.pop
	assert(type(push) == "function" and type(pop) == "function", "Camera HUD requires FreeCam tool lifecycle callbacks")
	local function replacement(...)
		if react.getCurrentRecipeName() ~= "CalloutContainer" then
			return render(...)
		end
		local arguments = _tl_table_pack(...)
		local params = values.asTable(arguments[arguments.n])
		assert(params ~= nil, "Camera HUD requires FloatingLayout parameters")
		local original = params
		local children = values.asArray(original.children)
		assert(children ~= nil, "Camera HUD requires FloatingLayout children")
		local extended = {}
		for key, value in pairs(original) do
			extended[key] = value
		end
		local items = {
			floatingChild({
				localKey = "apasz-swaying-waying-camera-hud",
				h = 1,
				v = 0,
				item = CameraHud(HUD_PARAMS),
				overflowMode = builtin.type.FloatingLayoutOverflowMode.KeepInside,
			}),
		}
		for _, item in ipairs(children) do
			items[#items + 1] = item
		end
		extended.children = items
		arguments[arguments.n] = extended
		return render(_tl_table_unpack(arguments, 1, arguments.n))
	end
	replacementApi.ReplaceRecipe(builtin.FloatingLayout, replacement)
	tool.push = function(ctx, params)
		reset(nil)
		push(ctx, params)
		reset(params.cockpitCameraForEntity)
		if cockpitEntity ~= nil then
			logger.info("Camera HUD entered: entity=" .. tostring(cockpitEntity))
		end
	end
	tool.pop = function(ctx, params)
		reset(nil)
		pop(ctx, params)
	end
	installed = true
	logger.info("Onboard camera information ready" .. (previous ~= nil and " (composed with existing UI)" or ""))
	return true
end

local function doReplace(replacementApi)
	local ok, failure = pcall(install, replacementApi)
	if not ok then
		logger.warnOnce("camera-hud-install", "Could not install onboard camera information: " .. tostring(failure))
	end
end

module.doReplace = doReplace
return module
