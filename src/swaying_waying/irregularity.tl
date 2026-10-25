local HASH_MASK = 0xffffffff
local HASH_PERIOD = 0x100000000
local HASH_MULTIPLIER = 0x45d9f3b
local HASH_HALF_PERIOD = 0x10000
local LATERAL_SEED = 0x68bc21eb
local VERTICAL_SEED = 0x02e5be93
local BROAD_SEED = 0x967a889b
local SPACING_SEED = 0x4a39b70d
local DETAIL_WEIGHT = 0.65
local BROAD_SPACING = 4.0
local STRENGTH = 0.10
local SPACING_CYCLES = 2.0
local PHASE_VARIATION_CYCLES = 0.08

local function mix(value: integer): integer
    value = value ~ (value >> 16)
    -- Split multiplication keeps every intermediate exact in Lua 5.2's doubles.
    local low = (value % HASH_HALF_PERIOD) * HASH_MULTIPLIER
    local high = ((value >> 16) * HASH_MULTIPLIER) % HASH_HALF_PERIOD
    return ((low + high * HASH_HALF_PERIOD) % HASH_PERIOD) as integer
end

local function latticeValue(cell: integer, seed: integer): number
    local value = mix(mix((cell ~ seed) & HASH_MASK))
    value = value ~ (value >> 16)
    return value * (2.0 / HASH_MASK) - 1.0
end

local function interpolate(fraction: number, first: number, delta: number): number
    -- Quintic interpolation joins cells with continuous slope and curvature.
    local blend = fraction * fraction * fraction * (fraction * (fraction * 6.0 - 15.0) + 10.0)
    return first + delta * blend
end

local function coefficients(lower: number, seed: integer): number, number
    local cell = (lower % HASH_PERIOD) as integer
    local first = latticeValue(cell, seed)
    local second = latticeValue((cell + 1) & HASH_MASK, seed)
    return first, second - first
end

local function sample(coordinate: number, seed: integer, cached: SwayingWaying.IrregularityCache | nil): number
    assert(coordinate > -math.huge and coordinate < math.huge, "Invalid irregularity coordinate")
    local broadCoordinate = coordinate / BROAD_SPACING
    local detailCell, broadCell = math.floor(coordinate), math.floor(broadCoordinate)
    local detailStart, detailDelta, broadStart, broadDelta: number, number, number, number
    if cached == nil then
        detailStart, detailDelta = coefficients(detailCell, seed)
        broadStart, broadDelta = coefficients(broadCell, seed ~ BROAD_SEED)
    else
        local present = cached as SwayingWaying.IrregularityCache
        if present.seed ~= seed or present.detailCell ~= detailCell then
            present.detailStart, present.detailDelta = coefficients(detailCell, seed)
            present.detailCell = detailCell
        end
        if present.seed ~= seed or present.broadCell ~= broadCell then
            present.broadStart, present.broadDelta = coefficients(broadCell, seed ~ BROAD_SEED)
            present.broadCell = broadCell
        end
        present.seed = seed
        detailStart, detailDelta = present.detailStart, present.detailDelta
        broadStart, broadDelta = present.broadStart, present.broadDelta
    end
    return DETAIL_WEIGHT * interpolate(coordinate - detailCell, detailStart, detailDelta)
        + (1.0 - DETAIL_WEIGHT) * interpolate(broadCoordinate - broadCell, broadStart, broadDelta)
end

local function lateral(coordinate: number, seed: integer, cached: SwayingWaying.IrregularityCache | nil): number
    return sample(coordinate, seed ~ LATERAL_SEED, cached)
end

local function vertical(coordinate: number, seed: integer, cached: SwayingWaying.IrregularityCache | nil): number
    return sample(coordinate, seed ~ VERTICAL_SEED, cached)
end

local function warp(cycles: number, seed: integer, cached: SwayingWaying.IrregularityCache | nil): number
    -- The phase derivative stays in [0.889375, 1.110625], so distance never
    -- reverses the wave. Bounded offsets avoid accumulated phase drift.
    return cycles + PHASE_VARIATION_CYCLES * sample(cycles / SPACING_CYCLES, seed ~ SPACING_SEED, cached)
end

local function createCache(): SwayingWaying.IrregularityCache
    return { detailStart = 0.0, detailDelta = 0.0, broadStart = 0.0, broadDelta = 0.0 }
end

local function create(): SwayingWaying.IrregularitySamples
    return {
        lateral = createCache(), front = createCache(), rear = createCache(),
        spacingLateral = createCache(), spacingFront = createCache(), spacingRear = createCache(),
    }
end

local function blend(regular: number, irregular: number): number
    -- Vanishing headroom at either limit preserves the original amplitude bounds.
    return regular + STRENGTH * irregular * (1.0 - regular * regular)
end

local module: SwayingWaying.Irregularity = {
    blend = blend,
    create = create,
    lateral = lateral,
    vertical = vertical,
    warp = warp,
}
return module
