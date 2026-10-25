local fixture = dofile("tests/support/model_fixture.lua")

local function camera(x, y, z)
	local transform = fixture.identity()
	transform[13], transform[14], transform[15] = x, y, z
	return { group = "RootNode", transf = transform, fov = 65 }
end

local function new(options)
	options = options or {}
	local automatic = options.automatic or { camera(0, 0, 2), camera(-3, 0, 2) }
	local extras = options.extras or { camera(0, 1, 2) }
	local logic = {}
	function logic.normalizeList(raw)
		return { default = raw.default or {} }
	end
	function logic.nodeNames()
		return {}, {}
	end
	function logic.findModelEntries()
		return {}
	end
	function logic.layout(metadata)
		local original, configured = {}, {}
		if not metadata.noWagonCameras then
			for _, position in ipairs(extras) do
				configured[#configured + 1] = position
			end
		end
		for _, authored in ipairs(metadata.cameraConfig and metadata.cameraConfig.positions or {}) do
			original[#original + 1] = {
				group = authored.group or "RootNode",
				transf = authored.transf,
				fov = authored.fov,
			}
		end
		return {
			carrier = "RAIL",
			groups = {},
			default = { position = { 0, 0, 2 }, yaw = 0, fov = 65 },
			original = original,
			defaults = not metadata.noWagonCameras and #original == 0,
			extra = configured,
			rests = { RootNode = fixture.identity() },
		}
	end
	function logic.camerasFromLayout(layout)
		local generated = {}
		if layout.defaults then
			for _, position in ipairs(automatic) do
				generated[#generated + 1] = position
			end
		end
		for _, position in ipairs(layout.extra) do
			generated[#generated + 1] = position
		end
		if #generated == 0 then
			return {}
		end
		local positions = {}
		for _, position in ipairs(layout.original) do
			positions[#positions + 1] = position
		end
		for _, position in ipairs(generated) do
			positions[#positions + 1] = position
		end
		return positions
	end
	local function apply(_, model)
		local layout = logic.layout(model.metadata)
		local positions = logic.camerasFromLayout(layout)
		if #positions > 0 then
			model.metadata.cameraConfig = { positions = positions }
		end
		if #positions > 0 or #layout.original > 0 then
			model.metadata.metadata.domeWagonCameras = layout
		end
		return model
	end
	return { logic = logic, config = { default = {} }, apply = apply, extras = extras }
end

return { new = new }
