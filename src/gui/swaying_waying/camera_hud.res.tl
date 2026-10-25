function data(): any
    local config: ReactReplacementConfigDesc = {
        filePath = "apasz_swaying_waying::/gui/swaying_waying/camera_hud.script",
        doReplaceFn = "doReplace",
        -- Compose after ordinary UI replacements, including Wagon Cameras (210).
        order = 1000,
    }
    return { type = "react-replacement-config", data = config }
end
