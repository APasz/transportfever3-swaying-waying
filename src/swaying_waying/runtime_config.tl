local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua") as SwayingWaying.Settings

local function read(params: TransformatorParams): SwayingWaying.ModelRuntimeConfig
    -- The loader installs this record; compilation validates it once per revision.
    return (params.transformatorConfigParams as SwayingWaying.RawTable)[constants.RUNTIME_PARAM] as SwayingWaying.ModelRuntimeConfig
end

local function validate(value: SwayingWaying.ModelRuntimeConfig): SwayingWaying.Config
    assert(value.schema == constants.RUNTIME_SCHEMA, "Unsupported Swaying Waying runtime schema")
    assert(type(value.modelFile) == "string" and value.modelFile ~= "", "Missing runtime model identity")
    assert(type(value.originalTransformator) == "string" and value.originalTransformator ~= "", "Missing original transformator")
    assert(validation.positiveInteger(value.revision) ~= nil, "Invalid runtime configuration revision")
    assert(value.carrier == "RAIL" or value.carrier == "TRAM", "Invalid runtime carrier")
    assert(value.profile == "DEFAULT" or value.profile == "QUICK" or value.profile == "SLOW", "Invalid runtime motion profile")
    assert(type(value.axisReversed) == "boolean", "Invalid model axis orientation")
    assert(validation.nonnegative(value.vehicleFactor), "Invalid vehicle response factor")
    assert(validation.wheelbase(value.wheelbase), "Invalid runtime wheelbase")
    assert(type(value.settings) == "table", "Missing runtime settings")
    local resolved = settings.resolve(value.settings)
    for key, expected in pairs(resolved as SwayingWaying.RawTable) do
        assert((value.settings as SwayingWaying.RawTable)[key] == expected, "Missing runtime setting: " .. key as string)
    end
    local sections = validation.asTable(value.sections)
    assert(sections ~= nil, "Missing runtime sections")
    local count = validation.arraySize(sections as SwayingWaying.RawTable)
    assert(count ~= nil and count <= constants.MAX_SECTION_COUNT, "Invalid runtime section array")
    for _, section in ipairs(value.sections) do
        assert(type(section) == "table" and validation.nonnegative(section.lag), "Invalid runtime section lag")
        assert(validation.wheelbase(section.wheelbase), "Invalid runtime section wheelbase")
    end
    return resolved
end

local module: SwayingWaying.RuntimeConfig = { read = read, validate = validate }
return module
