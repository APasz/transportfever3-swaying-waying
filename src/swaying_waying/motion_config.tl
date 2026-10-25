-- Developer isolation switches. Regenerate Lua and reload the game after edits.
-- Disabled waves contribute zero; the remaining weights are not rescaled.
-- scripts/validate.sh --generate --isolation
local config: SwayingWaying.MotionConfig = {
    roll = true,
    pitch = true,
    heave = true,

    shortWave = true,
    longWave = true,
    thirdWave = true,
    irregularity = true,

    curveLean = true,
    trackResponse = true,
    vehicleResponse = true,
    speedEnvelope = true,

    -- Experimental shared long wave with 20 m spacing; per-carriage phases are the default.
    carriageLag = false,
    sectionLag = true,
}

return config
