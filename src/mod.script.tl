local modelModifier = ug_require(
    "apasz_swaying_waying::/swaying_waying/model_modifier.lua"
) as SwayingWaying.ModelModifier

local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua") as SwayingWaying.Settings
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua") as SwayingWaying.Logger
local debugLoggingEnabled = ug_require("apasz_swaying_waying::/swaying_waying/logging_config.lua") as boolean
local curvatureProbeEnabled = ug_require("apasz_swaying_waying::/swaying_waying/curvature_probe_config.lua") as boolean
local lodProbeEnabled = ug_require("apasz_swaying_waying::/swaying_waying/lod_probe_config.lua") as boolean
local motionConfig = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua") as SwayingWaying.MotionConfig
local cameraConfig = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua") as SwayingWaying.CameraConfig
local type ConfigDict = {string: string}
local type AllModParams = SwayingWaying.AllModParams

local function logStartup(enabled: boolean, config: SwayingWaying.Config, modelDiagnosticsEnabled: boolean,
    cameraMode: SwayingWaying.CameraMode, extraCameras: boolean, cameraHudEnabled: boolean)
    local disabledMotion: {string} = {}
    for name, active in pairs(motionConfig as {string: boolean}) do
        if not active then
            disabledMotion[#disabledMotion + 1] = name
        end
    end
    table.sort(disabledMotion)
    logger.info("Startup: enabled=" .. tostring(enabled) .. "; " .. settings.describe(config)
        .. "; modelDiagnostics=" .. tostring(modelDiagnosticsEnabled)
        .. "; cameras=" .. cameraMode
        .. "; extraCameras=" .. tostring(extraCameras)
        .. "; cameraHud=" .. tostring(cameraHudEnabled)
        .. "; multipleCrewCameras=" .. tostring(cameraConfig.multipleCrewSeats)
        .. "; debug=" .. tostring(debugLoggingEnabled)
        .. "; curvatureProbe=" .. tostring(curvatureProbeEnabled)
        .. "; lodProbe=" .. tostring(lodProbeEnabled)
        .. "; disabled motion=[" .. table.concat(disabledMotion, ", ") .. "]")
end

function data(): any
    return {
        runFn = function(
            _captureParams: table,
            _configDict: ConfigDict,
            allModParams: AllModParams | nil,
            _baseConfig: BaseConfig | nil
        )
            local enabled, config, modelDiagnosticsEnabled, cameraMode, extraCameras = settings.read(allModParams)
            modelModifier.configure(allModParams)
            logStartup(enabled, config, modelDiagnosticsEnabled, cameraMode, extraCameras, cameraConfig.hudEnabled)
            local effectiveMode = settings.effectiveCameraMode(cameraMode, enabled)
            if not enabled and effectiveMode == "Disabled" then
                return
            end
            local options: SwayingWaying.ModelLoadOptions = {
                swayEnabled = enabled, cameraMode = effectiveMode, extraCameras = extraCameras,
            }
            addModifier("loadModel", function(fileName: string, model: Model): Model
                return modelModifier.modify(fileName, model, config, modelDiagnosticsEnabled, options) as Model
            end)
        end,
    }
end
