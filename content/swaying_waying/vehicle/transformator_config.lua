local function create(scriptKey)
	local config = {
		updateScript = {
			fileName = "transformator.script@" .. scriptKey .. ".updateFn",
			params = {},
		},
		updateParticleSystemScript = {
			fileName = "transformator.script@" .. scriptKey .. ".updateParticleSystemFn",
			params = {},
		},
	}
	if scriptKey == "any" then
		config.getEmittableModelsScript = {
			fileName = "transformator.script@any.getEmittableModelsFn",
			params = {},
		}
		config.computeEmittedModelsScript = {
			fileName = "transformator.script@any.computeEmittedModelsFn",
			params = {},
		}
	end
	return config
end

local module = {
	create = create,
}

return module
