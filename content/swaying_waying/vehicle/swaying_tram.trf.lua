local factory = ug_require("apasz_swaying_waying::/swaying_waying/vehicle/transformator_config.lua")

function data()
	return factory.create("tram")
end
