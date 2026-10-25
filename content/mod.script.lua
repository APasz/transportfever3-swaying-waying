local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local pairs = _tl_compat and _tl_compat.pairs or pairs
local table = _tl_compat and _tl_compat.table or table
local modelModifier = ug_require("apasz_swaying_waying::/swaying_waying/model_modifier.lua")

local settings = ug_require("apasz_swaying_waying::/swaying_waying/settings.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")
local debugLoggingEnabled = ug_require("apasz_swaying_waying::/swaying_waying/logging_config.lua")
local curvatureProbeEnabled = ug_require("apasz_swaying_waying::/swaying_waying/curvature_probe_config.lua")
local lodProbeEnabled = ug_require("apasz_swaying_waying::/swaying_waying/lod_probe_config.lua")
local motionConfig = ug_require("apasz_swaying_waying::/swaying_waying/motion_config.lua")
local cameraConfig = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua")

local function logStartup(enabled, config, modelDiagnosticsEnabled, cameraMode, extraCameras, cameraHudEnabled)
	local disabledMotion = {}
	for name, active in pairs(motionConfig) do
		if not active then
			disabledMotion[#disabledMotion + 1] = name
		end
	end
	table.sort(disabledMotion)
	logger.info(
		"Startup: enabled="
			.. tostring(enabled)
			.. "; "
			.. settings.describe(config)
			.. "; modelDiagnostics="
			.. tostring(modelDiagnosticsEnabled)
			.. "; cameras="
			.. cameraMode
			.. "; extraCameras="
			.. tostring(extraCameras)
			.. "; cameraHud="
			.. tostring(cameraHudEnabled)
			.. "; multipleCrewCameras="
			.. tostring(cameraConfig.multipleCrewSeats)
			.. "; debug="
			.. tostring(debugLoggingEnabled)
			.. "; curvatureProbe="
			.. tostring(curvatureProbeEnabled)
			.. "; lodProbe="
			.. tostring(lodProbeEnabled)
			.. "; disabled motion=["
			.. table.concat(disabledMotion, ", ")
			.. "]"
	)
end

function data()
	return {
		runFn = function(_captureParams, _configDict, allModParams, _baseConfig)
			local enabled, config, modelDiagnosticsEnabled, cameraMode, extraCameras = settings.read(allModParams)
			modelModifier.configure(allModParams)
			logStartup(enabled, config, modelDiagnosticsEnabled, cameraMode, extraCameras, cameraConfig.hudEnabled)
			local effectiveMode = settings.effectiveCameraMode(cameraMode, enabled)
			if not enabled and effectiveMode == "Disabled" then
				return
			end
			local options = {
				swayEnabled = enabled,
				cameraMode = effectiveMode,
				extraCameras = extraCameras,
			}
			addModifier("loadModel", function(fileName, model)
				return modelModifier.modify(fileName, model, config, modelDiagnosticsEnabled, options)
			end)
		end,
	}
end
