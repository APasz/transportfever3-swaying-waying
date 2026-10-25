local function new()
	local harness = dofile("tests/support/harness.lua").new()
	-- Authored model fixtures test hierarchy adaptation separately from resource resolution.
	harness.overrides["apasz_swaying_waying::/swaying_waying/origin_loader.lua"] = {
		get = function()
			return {}
		end,
	}
	harness.snowPowderCalls = 0
	harness.overrides["just_more_weather_1::/jmw/neige_poudre.lua"] = {
		addToModel = function(model)
			local metadata = model.metadata
			if not metadata or not metadata.snowPowderCompatibility then
				return 0
			end
			harness.snowPowderCalls = harness.snowPowderCalls + 1
			metadata.transformatorConfig.transformator.name = "just_more_weather_1::/vehicle/jmw/jmw_train.trf"
			if metadata.snowPowderFailure then
				metadata.foreignData = { changed = true }
				error("injected compatibility failure")
			end
			return 4
		end,
	}
	return harness
end
return { new = new }
