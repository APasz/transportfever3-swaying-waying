local gameDirectory = os.getenv("TPF3_GAME_DIR")
    or ((os.getenv("HOME") or "") .. "/.local/share/Steam/steamapps/common/Transport Fever 3")

return {
    build_dir = "content",
    source_dir = "src",
    -- Teal has no 5.2 target; 5.1 emits bit32 calls supported by the game's Lua 5.2.
    gen_target = "5.1",

    include = {
        "**/*.tl",
    },

    include_dir = {
        gameDirectory .. "/api/tealdef",
        gameDirectory .. "/base/tealdef",
    },

    global_env_def = "all_def",
}
