local function identity()
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

local function rail(boundaries)
	local model = {
		lods = {},
		metadata = {
			transportVehicle = { carrier = "RAIL" },
			railVehicle = {},
			transformatorConfig = {
				transformator = { name = "::/vehicle/train/shared/default_train.trf" },
				skipFromLod = #boundaries,
			},
			swayingWaying = { skipFromLod = #boundaries },
			seats = { { group = "RootNode" } },
			cameraConfig = { positions = { { group = "RootNode", transf = identity() } } },
		},
	}
	local visibleFrom = 0
	for index, visibleTo in ipairs(boundaries) do
		model.lods[index] = {
			visibleFrom = visibleFrom,
			visibleTo = visibleTo,
			node = { name = "RootNode", transf = identity(), mesh = "body.msh" },
		}
		visibleFrom = visibleTo
	end
	return model
end

return { rail = rail, identity = identity }
