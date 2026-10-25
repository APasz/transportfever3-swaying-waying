local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local bit32 = bit32
if not bit32 then
	local p, m = pcall(require, "bit32")
	if p then
		bit32 = m
	end
end
local math = _tl_compat and _tl_compat.math or math
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

local function mix(value)
	value = bit32.bxor(value, (bit32.rshift(value, 16)))

	local low = (value % HASH_HALF_PERIOD) * HASH_MULTIPLIER
	local high = ((bit32.rshift(value, 16)) * HASH_MULTIPLIER) % HASH_HALF_PERIOD
	return ((low + high * HASH_HALF_PERIOD) % HASH_PERIOD)
end

local function latticeValue(cell, seed)
	local value = mix(mix(bit32.band((bit32.bxor(cell, seed)), HASH_MASK)))
	value = bit32.bxor(value, (bit32.rshift(value, 16)))
	return value * (2.0 / HASH_MASK) - 1.0
end

local function interpolate(fraction, first, delta)
	local blend = fraction * fraction * fraction * (fraction * (fraction * 6.0 - 15.0) + 10.0)
	return first + delta * blend
end

local function coefficients(lower, seed)
	local cell = (lower % HASH_PERIOD)
	local first = latticeValue(cell, seed)
	local second = latticeValue(bit32.band((cell + 1), HASH_MASK), seed)
	return first, second - first
end

local function sample(coordinate, seed, cached)
	assert(coordinate > -math.huge and coordinate < math.huge, "Invalid irregularity coordinate")
	local broadCoordinate = coordinate / BROAD_SPACING
	local detailCell, broadCell = math.floor(coordinate), math.floor(broadCoordinate)
	local detailStart, detailDelta, broadStart, broadDelta
	if cached == nil then
		detailStart, detailDelta = coefficients(detailCell, seed)
		broadStart, broadDelta = coefficients(broadCell, bit32.bxor(seed, BROAD_SEED))
	else
		local present = cached
		if present.seed ~= seed or present.detailCell ~= detailCell then
			present.detailStart, present.detailDelta = coefficients(detailCell, seed)
			present.detailCell = detailCell
		end
		if present.seed ~= seed or present.broadCell ~= broadCell then
			present.broadStart, present.broadDelta = coefficients(broadCell, bit32.bxor(seed, BROAD_SEED))
			present.broadCell = broadCell
		end
		present.seed = seed
		detailStart, detailDelta = present.detailStart, present.detailDelta
		broadStart, broadDelta = present.broadStart, present.broadDelta
	end
	return DETAIL_WEIGHT * interpolate(coordinate - detailCell, detailStart, detailDelta)
		+ (1.0 - DETAIL_WEIGHT) * interpolate(broadCoordinate - broadCell, broadStart, broadDelta)
end

local function lateral(coordinate, seed, cached)
	return sample(coordinate, bit32.bxor(seed, LATERAL_SEED), cached)
end

local function vertical(coordinate, seed, cached)
	return sample(coordinate, bit32.bxor(seed, VERTICAL_SEED), cached)
end

local function warp(cycles, seed, cached)
	return cycles + PHASE_VARIATION_CYCLES * sample(cycles / SPACING_CYCLES, bit32.bxor(seed, SPACING_SEED), cached)
end

local function createCache()
	return { detailStart = 0.0, detailDelta = 0.0, broadStart = 0.0, broadDelta = 0.0 }
end

local function create()
	return {
		lateral = createCache(),
		front = createCache(),
		rear = createCache(),
		spacingLateral = createCache(),
		spacingFront = createCache(),
		spacingRear = createCache(),
	}
end

local function blend(regular, irregular)
	return regular + STRENGTH * irregular * (1.0 - regular * regular)
end

local module = {
	blend = blend,
	create = create,
	lateral = lateral,
	vertical = vertical,
	warp = warp,
}
return module
