local logging = ug_require("apasz_swaying_waying::/swaying_waying/logging.lua") as ModLogging.Module
local debugEnabled = ug_require("apasz_swaying_waying::/swaying_waying/logging_config.lua") as boolean

return logging.new("Swaying Waying", debugEnabled)
