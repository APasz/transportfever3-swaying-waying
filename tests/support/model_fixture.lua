local function identity()
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

local function childNamed(node, name)
	for _, child in ipairs(node.children or {}) do
		if child.name == name then
			return child
		end
	end
	return nil
end

local function descendantNamed(node, name)
	if node.name == name then
		return node
	end
	for _, child in ipairs(node.children or {}) do
		local found = descendantNamed(child, name)
		if found ~= nil then
			return found
		end
	end
	return nil
end

local function railModel(transformatorName, carrier)
	return {
		boundingInfo = { bbMin = { -5, -1, 0 }, bbMax = { 5, 1, 5 } },
		lods = {
			{
				node = {
					name = "RootNode",
					transf = identity(),
					mesh = "root_mesh.msh",
					materials = { "root.mtl" },
					children = {
						{ name = "bogie", transf = identity() },
					},
				},
			},
		},
		metadata = {
			railVehicle = {},
			transportVehicle = { carrier = carrier or "RAIL" },
			seats = { { group = "RootNode" } },
			lightSources = { { meshId = "RootNode" } },
			cameraConfig = {
				positions = { { group = "RootNode", transf = identity() } },
			},
			metadata = {
				foreignLayout = { group = "RootNode" },
			},
			transformatorConfig = transformatorName and {
				transformator = { name = transformatorName },
				params = { preserved = 42 },
			} or nil,
		},
	}
end

local function setPassengerComfort(model, comfort)
	model.metadata.transportVehicle.comfortFactor = comfort
	model.metadata.transportVehicle.compartments = {
		{
			loadConfigs = {
				{
					cargoEntry = {
						cargoTypeSet = {
							cargoClassesIncluded = { "PASSENGERS" },
						},
					},
				},
			},
		},
	}
end

return {
	identity = identity,
	childNamed = childNamed,
	descendantNamed = descendantNamed,
	railModel = railModel,
	setPassengerComfort = setPassengerComfort,
}
