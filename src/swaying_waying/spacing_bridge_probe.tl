-- Keep console-history calls harmless after the native missing-component crash.
local function disabled(_entity: integer)
    error("Spacing bridge probe disabled: updating missing custom state causes a fatal engine assertion", 0)
end

local module: SwayingWaying.SpacingBridgeProbe = {
    test = disabled,
    clear = disabled,
}

return module
