local factory = ug_require(
    "apasz_swaying_waying::/swaying_waying/vehicle/transformator_config.lua"
) as SwayingWaying.TransformatorConfigFactory

function data(): any
    return factory.create("any")
end
