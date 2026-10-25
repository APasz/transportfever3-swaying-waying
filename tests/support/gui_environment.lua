local function new()
	local harness = dofile("tests/support/harness.lua").new()
	harness.cameraConfig = harness.require("apasz_swaying_waying::/swaying_waying/camera_config.lua")
	harness.cameraConfig.hudEnabled = true
	local contexts, bodies, ids = {}, {}, {}
	local current, cursor
	local clock = 0
	harness.components, harness.models, harness.names = {}, {}, {}
	harness.componentReads, harness.modelReads, harness.replacements = 0, 0, 0
	harness.pushes, harness.pops, harness.inputHandlers = 0, 0, 0
	harness.eye = { x = 0, y = 0, z = 2 }
	harness.viewport = { x = 2048, y = 1152 }
	harness.panelSize = { x = 300, y = 100 }
	harness.panelVisible = true
	harness.nodeRefs = {}
	harness.freeCamVisible = true
	harness.calloutChildren = {}
	harness.activeTool = { name = "FreeCam" }
	harness.modParams = {}
	_G._ = function(text)
		return text
	end
	_G._react = { recipeReplace = {}, originalRecipeFn = {} }

	local react, builtin, freeCam = {}, {}, {}
	local function render(id, params)
		local previous, previousCursor = current, cursor
		current, cursor = contexts[id] or { slots = {} }, 0
		current.name = bodies[id].name
		contexts[id] = current
		current.events, current.step = {}, nil
		local recipe = bodies[id]
		local result = recipe.render(params)
		current, cursor = previous, previousCursor
		assert(
			result == nil or result.kind == "BoxLayout" or result.kind == "FloatingLayout",
			"Recipe child must be a layout (recipe='" .. recipe.name .. "')"
		)
		if result ~= nil and params ~= nil and params.meta ~= nil then
			result.recipeMeta = params.meta
		end
		return result
	end
	function react.RegisterRecipe(name, body)
		local id = #bodies + 1
		bodies[id] = { name = name, render = body }
		local recipe = function(params)
			local replacement = _react.recipeReplace[id]
			if replacement then
				return replacement(params)
			end
			return render(id, params)
		end
		ids[recipe] = id
		_react.originalRecipeFn[id] = function(params)
			return render(id, params)
		end
		return recipe
	end
	function react.GetRecipeId(recipe)
		return ids[recipe]
	end
	function react.getCurrentRecipeName()
		return current and current.name or nil
	end
	function react.provideApi(value)
		current.api = value
	end
	function react.CallOriginalRecipe(recipe, params)
		return render(assert(ids[recipe]), params)
	end
	local function slot(value, state)
		cursor = cursor + 1
		if current.slots[cursor] == nil then
			current.slots[cursor] = { value = value, state = state }
		end
		local ref = current.slots[cursor]
		assert(ref.state == state, "React hooks must retain their order")
		function ref:get()
			assert(not self.state, "native React states use old(), not get()")
			return self.value
		end
		function ref:old()
			return self.value
		end
		function ref:set(nextValue)
			self.value = nextValue
		end
		return ref
	end
	function react.useRef(value)
		return slot(value, false)
	end
	function react.useState(value)
		return slot(value, true)
	end
	function react.useNodeRef()
		return slot(nil, false)
	end
	function react.ref(reference)
		return { is_react_ref_info = true, data = reference }
	end
	function react.onStep(callback)
		current.step = callback
	end
	function react.onEvent(event, callback)
		current.events[event] = callback
	end
	function react.setMouseTransparent(value)
		current.mouseTransparent = value
	end
	function react.setDisableFocusable(value)
		current.disableFocusable = value
	end
	function react.useInputAction()
		harness.inputHandlers = harness.inputHandlers + 1
	end
	for _, kind in ipairs({ "BoxLayout", "Component", "TextView", "FloatingLayoutChild" }) do
		builtin[kind] = function(first, second)
			local reference = first and first.is_react_ref_info and first.data or nil
			local params = reference and second or first
			if reference then
				local node = {
					getIdentity = function()
						return 1
					end,
					getPosition = function(_, x, y)
						return { x = 0.8 + x * 0.18, y = 0.02 + y * 0.1 }
					end,
				}
				reference:set(node)
				harness.nodeRefs[params.meta.id] = node
			end
			return { kind = kind, params = params }
		end
	end
	builtin.type = {
		Orientation = { Vertical = "vertical" },
		FloatingLayoutOverflowMode = { KeepInside = "keep-inside" },
	}
	builtin.FloatingLayout = react.RegisterRecipe("FloatingLayout", function(params)
		return { kind = "FloatingLayout", params = params }
	end)
	harness.calloutApi = { open = function() end, close = function() end }
	harness.calloutContainer = react.RegisterRecipe("CalloutContainer", function()
		react.provideApi(harness.calloutApi)
		return builtin.FloatingLayout({ children = harness.calloutChildren })
	end)
	freeCam.FreeCamTool = {
		name = "FreeCam",
		push = function(ctx, params)
			harness.pushes = harness.pushes + 1
			harness.lastPush = { ctx, params }
		end,
		pop = function(ctx, params)
			harness.pops = harness.pops + 1
			harness.lastPop = { ctx, params }
		end,
	}
	freeCam.FreeCamOptions = react.RegisterRecipe("FreeCamOptions", function()
		react.useInputAction("IA_BACK")
		react.onEvent("stoppedFollowAction", function()
			freeCam.FreeCamTool.pop({}, {})
		end)
		return builtin.BoxLayout({ children = {} })
	end)
	harness.overrides["::/gui/main/react.lua"] = react
	harness.overrides["::/gui/main/builtin.lua"] = builtin
	harness.overrides["::/gui/main/free_cam_options.tl"] = freeCam
	harness.overrides["::/gui/main/styleutil.tl"] = {
		makeStyle = function(style)
			return style
		end,
	}
	_G.api = {
		type = { ComponentType = { TRANSPORT_VEHICLE = "tv", CARRIAGE_LIST = "cl", MODEL_INSTANCE_LIST = "mil" } },
		util = {
			getApplicationTime = function()
				return clock
			end,
		},
		gui = {
			byId = {
				getSize = function()
					return harness.panelSize
				end,
				isVisibleRecursive = function()
					return harness.panelVisible
				end,
			},
			camera = {
				getEye = function()
					return harness.eye
				end,
				getSize = function()
					return harness.viewport
				end,
			},
		},
		res = {
			modelRep = {
				get = function(id)
					harness.modelReads = harness.modelReads + 1
					return assert(harness.models[id], "unknown fixture model")
				end,
			},
		},
		engine = {
			config = {
				getModParams = function()
					return harness.modParams
				end,
			},
			entityExists = function(entity)
				return harness.components[entity] ~= nil
			end,
			getComponent = function(entity, kind)
				harness.componentReads = harness.componentReads + 1
				return harness.components[entity] and harness.components[entity][kind]
			end,
			util = {
				getEntityName = function(entity)
					return harness.names[entity]
				end,
			},
		},
	}
	local toolApi = {
		getActiveTool = function()
			return harness.activeTool
		end,
	}
	harness.overrides["::/gui/main/game_react_globals.tl"] = {
		getDefaultToolStackApi = function()
			return toolApi
		end,
	}
	local toolStack = {
		get = function()
			return {
				getApi = function()
					return toolApi
				end,
			}
		end,
	}
	harness.params = {
		getGameContext = function()
			return { toolStack = toolStack }
		end,
	}
	harness.replacementApi = {
		ReplaceRecipe = function(original, replacement)
			harness.replacements = harness.replacements + 1
			_react.recipeReplace[assert(ids[original])] = replacement
		end,
	}
	harness.react, harness.builtin, harness.freeCam = react, builtin, freeCam
	function harness.render()
		local controls = freeCam.FreeCamOptions(harness.params)
		controls.hidden = not harness.freeCamVisible
		return builtin.BoxLayout({ children = { controls, harness.calloutContainer() } })
	end
	function harness.getCalloutApi()
		return contexts[ids[harness.calloutContainer]].api
	end
	function harness.frame(seconds)
		clock = clock + (seconds or 0.21)
		for _, context in pairs(contexts) do
			if context.step then
				context.step()
			end
		end
		return harness.render()
	end
	function harness.event(name)
		for _, context in pairs(contexts) do
			if context.events[name] then
				context.events[name](name, nil)
			end
		end
	end
	function harness.visit(tree, callback)
		local function visit(node)
			if type(node) ~= "table" or node.hidden then
				return
			end
			callback(node)
			for _, child in pairs(node) do
				visit(child)
			end
		end
		visit(tree)
	end
	function harness.find(tree, id)
		local found
		harness.visit(tree, function(node)
			if node.params and node.params.meta and node.params.meta.id == id then
				found = node
			end
		end)
		return found
	end
	function harness.labels(tree)
		local labels = {}
		harness.visit(tree, function(node)
			if node.kind == "TextView" then
				labels[#labels + 1] = node.params.text
			end
		end)
		table.sort(labels)
		return table.concat(labels, " | ")
	end
	return harness
end

return { new = new }
