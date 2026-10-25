local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local type ModParams = SwayingWaying.ModParams
local type AllModParams = SwayingWaying.AllModParams

local toggle: {number} = { 0, 1 }
local intensity: {number} = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }
local balance: {number} = { 0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, constants.MAX_BALANCE }
local balanceLabels: {string} = { "Off", "0.25x", "0.5x", "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x" }
local track: {number} = { 0, 0.25, 0.5, 0.75, 1, 1.25, constants.MAX_TRACK_INFLUENCE }
local variation: {number} = { 0, 0.5, 1, 1.5, constants.MAX_VEHICLE_VARIATION }
local sampling: {number} = { 0, 1, 3, constants.DEFAULT_SAMPLE_DISTANCE, 10, 15 }
local samplingLabels: {string} = { "Frame", "1 m", "3 m", "5 m", "10 m", "15 m" }
local swayModes: {SwayingWaying.SwayMode} = { "Off", "On", "Speedless Sway" }
local cameraModes: {SwayingWaying.CameraMode} = { "Disabled", "Stable", "Sway", "Both" }

local function choiceValues(labels: {string}): {number}
    local result: {number} = {}
    for index in ipairs(labels) do
        result[index] = index
    end
    return result
end

local record CameraChoice
    mode: SwayingWaying.CameraMode
    extra: boolean
end
local cameraChoices: {CameraChoice} = {}
local cameraLabels: {string} = {}
local validCameraModes: {SwayingWaying.CameraMode: boolean} = {}
for _, mode in ipairs(cameraModes) do
    validCameraModes[mode] = true
end
for _, extra in ipairs({ false, true }) do
    for _, mode in ipairs(cameraModes) do
        if not extra or mode ~= "Disabled" then
            local index = #cameraChoices + 1
            cameraChoices[index] = { mode = mode, extra = extra }
            cameraLabels[index] = mode .. (extra and " + Extra" or "")
        end
    end
end

local function effectiveCameraMode(mode: SwayingWaying.CameraMode, swayEnabled: boolean): SwayingWaying.CameraMode
    assert(validCameraModes[mode], "Invalid camera mode")
    assert(type(swayEnabled) == "boolean", "Sway enable switch must be a boolean")
    if not swayEnabled then
        if mode == "Both" then
            return "Stable"
        elseif mode == "Sway" then
            return "Disabled"
        end
    end
    return mode
end

local definitions: {SwayingWaying.SettingDefinition} = {
    {
        id = "enabled", key = constants.ENABLED_PARAM_KEY,
        name = "Sway mode",
        tooltip = "On varies sway strength with speed; Speedless Sway uses full strength from 5 km/h. Sway and curve lean settle below 5 km/h. Curve lean always follows speed.",
        uiType = "ComboBox",
        defaultIndex = 2,
        values = choiceValues(swayModes as {string}),
        labels = swayModes as {string},
    },
    {
        id = "cameras", key = constants.CAMERAS_PARAM_KEY,
        name = "Onboard cameras",
        tooltip = "One viewpoint per vehicle: Stable, body-following Sway, or Both variants. + Extra also considers passenger seats and an exterior view if needed. Preserves existing cameras. Sway requires vehicle sway. Reload to apply.",
        uiType = "ComboBox",
        defaultIndex = 1,
        values = choiceValues(cameraLabels),
        labels = cameraLabels,
    },
    {
        id = "intensity", key = constants.INTENSITY_PARAM_KEY,
        name = "Sway intensity",
        tooltip = "Sets the strength of roll, pitch and vertical suspension motion.",
        uiType = "Slider",
        defaultIndex = 4,
        values = intensity,
        labels = { "0.25x", "0.5x", "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x" },
    },
    {
        id = "rollBalance", key = constants.ROLL_BALANCE_PARAM_KEY,
        name = "Roll balance",
        tooltip = "Adjusts side-to-side rocking relative to the overall sway intensity. Curve lean is controlled separately.",
        uiType = "Slider",
        defaultIndex = 5,
        values = balance,
        labels = balanceLabels,
    },
    {
        id = "pitchBalance", key = constants.PITCH_BALANCE_PARAM_KEY,
        name = "Pitch balance",
        tooltip = "Adjusts longitudinal rocking relative to the overall sway intensity.",
        uiType = "Slider",
        defaultIndex = 5,
        values = balance,
        labels = balanceLabels,
    },
    {
        id = "heaveBalance", key = constants.HEAVE_BALANCE_PARAM_KEY,
        name = "Heave balance",
        tooltip = "Adjusts vertical suspension movement relative to the overall sway intensity.",
        uiType = "Slider",
        defaultIndex = 5,
        values = balance,
        labels = balanceLabels,
    },
    {
        id = "curveLeanIntensity", key = constants.CURVE_LEAN_INTENSITY_PARAM_KEY,
        name = "Curve lean intensity",
        tooltip = "Sets outward curve lean independently of sway intensity. Off disables it.",
        uiType = "Slider",
        defaultIndex = 5,
        values = balance,
        labels = balanceLabels,
    },
    {
        id = "curveSamplingDistance", key = constants.CURVE_SAMPLING_DISTANCE_PARAM_KEY,
        name = "Curve sampling interval",
        tooltip = "How often curvature is sampled. Every Frame gives the closest response; longer distances save CPU but may cause stepping. Suspension smoothing remains continuous.",
        uiType = "Slider",
        defaultIndex = 2,
        values = sampling,
        labels = samplingLabels,
    },
    {
        id = "trackInfluence", key = constants.TRACK_INFLUENCE_PARAM_KEY,
        name = "Track influence",
        tooltip = "How strongly track speed limits and author-defined track quality affect sway strength and rhythm.",
        uiType = "Slider",
        defaultIndex = 5,
        values = track,
        labels = { "Off", "25%", "50%", "75%", "100%", "125%", "150%" },
    },
    {
        id = "samplingDistance", key = constants.SAMPLING_DISTANCE_PARAM_KEY,
        name = "Track sampling interval",
        tooltip = "Controls track-quality updates. Smaller intervals follow track changes more closely but use more CPU. Curve sampling is controlled separately.",
        uiType = "Slider",
        defaultIndex = 4,
        values = sampling,
        labels = samplingLabels,
    },
    {
        id = "vehicleVariation", key = constants.VEHICLE_VARIATION_PARAM_KEY,
        name = "Vehicle variation",
        tooltip = "Controls automatic comfort and maintenance effects; explicit vehicle-author tags remain fully applied.",
        uiType = "Slider",
        defaultIndex = 3,
        values = variation,
        labels = { "Off", "Reduced", "Normal", "Enhanced", "Strong" },
    },
    {
        id = "modelDiagnostics", key = constants.MODEL_DIAGNOSTICS_PARAM_KEY,
        name = "Detailed model logging",
        tooltip = "Logs sway adaptation for each model LOD, including groups and visibility ranges. Enable to diagnose compatibility.",
        uiType = "CheckBox",
        defaultIndex = 1,
        values = toggle,
        labels = { "Off", "On" },
    },
}
local byId: {SwayingWaying.SettingId: SwayingWaying.SettingDefinition} = {}
for _, definition in ipairs(definitions) do
    byId[definition.id] = definition
end

local function selected(params: ModParams | nil, id: SwayingWaying.SettingId): number
    local definition = byId[id]
    local index = params ~= nil and (params as ModParams)[definition.key] or nil
    if type(index) ~= "number" or index % 1 ~= 0 or definition.values[index as integer] == nil then
        index = definition.defaultIndex
    end
    return definition.values[index as integer]
end

local function scale(value: any, id: SwayingWaying.SettingId): number
    if value == nil then
        return selected(nil, id)
    end
    local definition = byId[id]
    local maximum = definition.values[#definition.values]
    assert(type(value) == "number" and (value as number) >= 0 and (value as number) <= maximum,
        "Invalid sway setting: " .. id)
    return value as number
end

local function swayMode(params: ModParams | nil): SwayingWaying.SwayMode
    return swayModes[selected(params, "enabled") as integer]
end

local function resolveSettings(config: SwayingWaying.Config): SwayingWaying.Config
    local speedDependent = config.speedDependent
    if speedDependent == nil then
        speedDependent = swayMode(nil) ~= "Speedless Sway"
    end
    assert(type(speedDependent) == "boolean", "Invalid sway speed-dependence setting")
    return {
        speedDependent = speedDependent,
        intensity = scale(config.intensity, "intensity"),
        rollBalance = scale(config.rollBalance, "rollBalance"),
        pitchBalance = scale(config.pitchBalance, "pitchBalance"),
        heaveBalance = scale(config.heaveBalance, "heaveBalance"),
        curveLeanIntensity = scale(config.curveLeanIntensity, "curveLeanIntensity"),
        curveSamplingDistance = scale(config.curveSamplingDistance, "curveSamplingDistance"),
        trackInfluence = scale(config.trackInfluence, "trackInfluence"),
        samplingDistance = scale(config.samplingDistance, "samplingDistance"),
        vehicleVariation = scale(config.vehicleVariation, "vehicleVariation"),
    }
end

local function describe(config: SwayingWaying.Config): string
    local fields: {string} = { "speedDependent=" .. tostring(config.speedDependent) }
    for _, definition in ipairs(definitions) do
        local value = (config as SwayingWaying.RawTable)[definition.id]
        if value ~= nil then
            fields[#fields + 1] = definition.id .. "=" .. tostring(value)
        end
    end
    return table.concat(fields, ", ")
end

local function read(allModParams: AllModParams | nil): boolean, SwayingWaying.Config, boolean, SwayingWaying.CameraMode, boolean
    local params: ModParams | nil = allModParams ~= nil and (allModParams as AllModParams)[getCurrentModId()] or nil
    local cameras = cameraChoices[selected(params, "cameras") as integer]
    local mode = swayMode(params)
    return mode ~= "Off", {
        speedDependent = mode ~= "Speedless Sway",
        intensity = selected(params, "intensity"),
        rollBalance = selected(params, "rollBalance"),
        pitchBalance = selected(params, "pitchBalance"),
        heaveBalance = selected(params, "heaveBalance"),
        curveLeanIntensity = selected(params, "curveLeanIntensity"),
        curveSamplingDistance = selected(params, "curveSamplingDistance"),
        trackInfluence = selected(params, "trackInfluence"),
        samplingDistance = selected(params, "samplingDistance"),
        vehicleVariation = selected(params, "vehicleVariation"),
    }, selected(params, "modelDiagnostics") == 1, cameras.mode, cameras.extra
end

local module: SwayingWaying.Settings = {
    read = read, resolve = resolveSettings, describe = describe, definitions = definitions,
    effectiveCameraMode = effectiveCameraMode,
}
return module
