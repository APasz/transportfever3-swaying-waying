local cameraConfig = ug_require("apasz_swaying_waying::/swaying_waying/camera_config.lua")

function data()
	if not cameraConfig.hudEnabled then
		return {}
	end
	local stylesheet = ug_require("::/gui/main/stylesheetutil.lua")
	local result = {}
	local add = stylesheet.makeAdder(result)
	add("!swaying-waying-camera-hud", { margin = { 12, 12, 12, 12 }, padding = { 0, 0, 0, 0 } })
	add("!swaying-waying-camera-hud > BoxLayout", { innerSpacing = { 0, 0 }, outerSpacing = { 0, 0 } })
	add("!swaying-waying-camera-hud TextView", {
		maxSize = { 420, -1 },
		textAutoWrap = true,
		gravity = { 1, 0 },
		textAlignment = { 1, 0 },
	})
	return result
end
