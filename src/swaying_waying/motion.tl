local validation = ug_require("apasz_swaying_waying::/swaying_waying/values.lua") as SwayingWaying.Values
local clamp = validation.clamp
local constants = ug_require(
    "apasz_swaying_waying::/swaying_waying/constants.lua"
) as SwayingWaying.Constants
local config = ug_require(
    "apasz_swaying_waying::/swaying_waying/motion_config.lua"
) as SwayingWaying.MotionConfig
local cache = ug_require("apasz_swaying_waying::/swaying_waying/bounded_cache.lua") as SwayingWaying.Cache
local irregularity = ug_require("apasz_swaying_waying::/swaying_waying/irregularity.lua") as SwayingWaying.Irregularity

local SWAY_MAX_DEGREES = 1.2
local MIN_MOVING_STRENGTH = 0.05
local CURVE_LEAN_MAX_DEGREES = 1.5
local PHASE_MULTIPLIER = 0.61803
local PHASE_MODULUS = 997
local LONG_PHASE_MULTIPLIER = 1.7
local THIRD_PHASE_MULTIPLIER = 2.3
local SHARED_LONG_WAVELENGTH = 65.0
local THIRD_WEIGHT = 0.20
local TWO_PI = 2.0 * math.pi
local VERTICAL_PHASE_OFFSET = 0.37 * TWO_PI
local VERTICAL_SHORT_SIN = math.sin(VERTICAL_PHASE_OFFSET)
local VERTICAL_SHORT_COS = math.cos(VERTICAL_PHASE_OFFSET)
local VERTICAL_LONG_SIN = math.sin(
    VERTICAL_PHASE_OFFSET * LONG_PHASE_MULTIPLIER
)
local VERTICAL_LONG_COS = math.cos(
    VERTICAL_PHASE_OFFSET * LONG_PHASE_MULTIPLIER
)
local VERTICAL_THIRD_SIN = math.sin(
    VERTICAL_PHASE_OFFSET * THIRD_PHASE_MULTIPLIER
)
local VERTICAL_THIRD_COS = math.cos(
    VERTICAL_PHASE_OFFSET * THIRD_PHASE_MULTIPLIER
)
local VERTICAL_PROFILE_MAX_METRES = 0.025
local HEAVE_MAX_METRES = 0.02
local PITCH_MAX_DEGREES = 0.2
local TILT_MIN_DEGREES = -8.0
local TILT_MAX_DEGREES = 8.0
local TILT_CENTRE_MS = 2500.0
local TILT_MS_PER_DEGREE = 277.778
local DEGREES_PER_RADIAN = 180.0 / math.pi
local SECONDARY_CENTRE_MS = 2500.0
local HEAVE_MS_PER_METRE = 25000.0
local PITCH_MS_PER_DEGREE = 2500.0
local HEAVE_ANIMATION_LIMIT_METRES = 0.1
local PITCH_ANIMATION_LIMIT_DEGREES = 1.0

local record SwayProfile
    startSpeed: number
    fullSpeed: number
    shortWaveLength: number
    thirdWaveLength: number
end

local PROFILES: {SwayingWayingMotionProfile: SwayProfile} = {
    QUICK = {
        startSpeed = 5.0 / 3.6,
        fullSpeed = 90.0 / 3.6,
        shortWaveLength = 30.0,
        thirdWaveLength = 73.0,
    },
    DEFAULT = {
        startSpeed = 8.0 / 3.6,
        fullSpeed = 120.0 / 3.6,
        shortWaveLength = 40.0,
        thirdWaveLength = 97.0,
    },
    SLOW = {
        startSpeed = 18.0 / 3.6,
        fullSpeed = 160.0 / 3.6,
        shortWaveLength = 56.0,
        thirdWaveLength = 137.0,
    },
}

local function createProfileCaches<K, V>(): {SwayingWayingMotionProfile: SwayingWaying.BoundedCache<K, V>}
    local result: {SwayingWayingMotionProfile: SwayingWaying.BoundedCache<K, V>} = {}
    for profile in pairs(PROFILES) do
        local entries: SwayingWaying.BoundedCache<K, V> = cache.create(constants.MAX_RUNTIME_VEHICLE_STATES)
        result[profile] = entries
    end
    return result
end

local geometryCache: {SwayingWayingMotionProfile: SwayingWaying.BoundedCache<number, SwayingWaying.MotionGeometry>} = createProfileCaches()
local waveBases: {SwayingWayingMotionProfile: SwayingWaying.BoundedCache<integer, SwayingWaying.WaveBasis>} = createProfileCaches()

local function emptyWaveValues(): SwayingWaying.WaveValues
    return {
        shortSin = 0.0,
        shortCos = 0.0,
        longSin = 0.0,
        longCos = 0.0,
        thirdSin = 0.0,
        thirdCos = 0.0,
    }
end

local function speedFactor(speed: number, profileName: SwayingWayingMotionProfile, speedDependent: boolean | nil): number
    assert(speed > -math.huge and speed < math.huge, "Invalid sway speed")
    assert(speedDependent == nil or type(speedDependent) == "boolean", "Invalid sway speed-dependence setting")
    local absoluteSpeed = math.abs(speed)
    if absoluteSpeed < constants.MIN_MOTION_SPEED then
        return 0.0
    end
    if not config.speedEnvelope or speedDependent == false then
        return 1.0
    end
    local profile = PROFILES[profileName]
    local ratio = clamp(
        (absoluteSpeed - profile.startSpeed)
            / (profile.fullSpeed - profile.startSpeed),
        0.0,
        1.0
    )
    return MIN_MOVING_STRENGTH + (1.0 - MIN_MOVING_STRENGTH) * ratio * ratio * (3.0 - 2.0 * ratio)
end

local function phaseForSeed(phaseSeed: integer): number
    return (phaseSeed % PHASE_MODULUS) * PHASE_MULTIPLIER * TWO_PI
end

local function longPhaseSeed(sample: SwayingWaying.MotionSample): integer
    return config.carriageLag and sample.sharedPhaseSeed or sample.phaseSeed
end

local function hasSecondaryMotion(settings: SwayingWaying.MotionSettings): boolean
    return settings.secondaryMotionEnabled
        and ((config.pitch and settings.pitchIntensity > 0.0)
            or (config.heave and settings.heaveIntensity > 0.0))
end

local function hasProceduralMotion(settings: SwayingWaying.MotionSettings): boolean
    return (config.shortWave or config.longWave or config.thirdWave or config.irregularity)
        and ((config.roll and settings.rollIntensity > 0.0)
            or hasSecondaryMotion(settings))
end

local function orientShared(value: number, sample: SwayingWaying.MotionSample): number
    return sample.sharedAxisReversed and -value or value
end

local function hasRegularShortWave(): boolean
    return config.shortWave and not config.irregularity
end

local function waveAngles(
    sample: SwayingWaying.MotionSample,
    profile: SwayProfile
): number, number, number
    local longSeed = longPhaseSeed(sample)
    local reusePhase = longSeed == sample.phaseSeed
    local phase = 0.0
    if config.shortWave or config.thirdWave or (config.longWave and reusePhase) then
        phase = phaseForSeed(sample.phaseSeed)
    end
    local longPhase = config.longWave
        and (reusePhase and phase or phaseForSeed(longSeed))
        or 0.0
    local distance = sample.distance
    return hasRegularShortWave()
            and (TWO_PI * distance / profile.shortWaveLength + phase)
            or 0.0,
        config.longWave
            and (TWO_PI * sample.sharedDistance / SHARED_LONG_WAVELENGTH
                + longPhase * LONG_PHASE_MULTIPLIER)
            or 0.0,
        config.thirdWave
            and (TWO_PI * distance / profile.thirdWaveLength
                + phase * THIRD_PHASE_MULTIPLIER)
            or 0.0
end

local function waveRotation(
    angle: number,
    verticalSin: number,
    verticalCos: number,
    halfSin: number,
    halfCos: number,
    weight: number,
    axis: number
): SwayingWaying.WaveRotation
    local sine, cosine = math.sin(angle), math.cos(angle)
    local verticalSine = sine * verticalCos + cosine * verticalSin
    local verticalCosine = cosine * verticalCos - sine * verticalSin
    -- Phase, support geometry, fixed wave weight, and facing remain constant
    -- while track spectrum weights ease continuously between their targets.
    return {
        rollSin = cosine * weight * axis,
        rollCos = sine * weight * axis,
        heaveSin = verticalCosine * halfCos * weight,
        heaveCos = verticalSine * halfCos * weight,
        pitchSin = -2.0 * verticalSine * halfSin * weight * axis,
        pitchCos = 2.0 * verticalCosine * halfSin * weight * axis,
    }
end

local function preparedMotion(
    basis: SwayingWaying.WaveValues,
    rotation: SwayingWaying.SectionWaveRotations,
    weight: number,
    rollEnabled: boolean
): number, number, number
    local shortSin, shortCos = basis.shortSin, basis.shortCos
    local longSin, longCos = basis.longSin, basis.longCos
    local thirdSin, thirdCos = basis.thirdSin, basis.thirdCos
    local shortWave, longWave, thirdWave = rotation.shortWave, rotation.longWave, rotation.thirdWave
    local shortWeight = clamp(weight, 0.0, 1.0)
    local longWeight = 1.0 - shortWeight
    local vertical = config.heave or config.pitch
    return rollEnabled and (shortWeight * (shortSin * shortWave.rollSin + shortCos * shortWave.rollCos)
            + longWeight * (longSin * longWave.rollSin + longCos * longWave.rollCos)
            + thirdSin * thirdWave.rollSin + thirdCos * thirdWave.rollCos) or 0.0,
        vertical and (shortWeight * (shortSin * shortWave.heaveSin + shortCos * shortWave.heaveCos)
            + longWeight * (longSin * longWave.heaveSin + longCos * longWave.heaveCos)
            + thirdSin * thirdWave.heaveSin + thirdCos * thirdWave.heaveCos) or 0.0,
        vertical and (shortWeight * (shortSin * shortWave.pitchSin + shortCos * shortWave.pitchCos)
            + longWeight * (longSin * longWave.pitchSin + longCos * longWave.pitchCos)
            + thirdSin * thirdWave.pitchSin + thirdCos * thirdWave.pitchCos) or 0.0
end

local function prepareWaves(
    state: SwayingWaying.CarriageState,
    sharedBaseDistance: number,
    carriageLag: number
)
    local sample = state.sample
    local candidate = state.waveBasis
    -- Distance bases remain shared by consist, independently of carriage phases.
    if candidate == nil or (candidate as SwayingWaying.WaveBasis).consist ~= sample.sharedPhaseSeed then
        local profileName = state.model.motion.profile
        local bases = waveBases[profileName]
        candidate = cache.get(bases, sample.sharedPhaseSeed)
        if candidate == nil then
            local profile = PROFILES[profileName]
            candidate = {
                consist = sample.sharedPhaseSeed,
                values = emptyWaveValues(),
                reused = false,
                shared = false,
                shortWaveLength = profile.shortWaveLength,
                thirdWaveLength = profile.thirdWaveLength,
            }
            cache.put(bases, sample.sharedPhaseSeed, candidate as SwayingWaying.WaveBasis)
        end
        state.waveBasis = candidate
    end
    local basis = candidate as SwayingWaying.WaveBasis
    -- Render workers need not receive neighbouring carriages. Share only after
    -- observing repeated coordinates in this context; either path is identical.
    if basis.distance ~= sample.distance or basis.sharedDistance ~= sharedBaseDistance then
        basis.shared = basis.reused
        basis.reused = false
        basis.distance, basis.sharedDistance = sample.distance, sharedBaseDistance
    else
        basis.reused = true
    end
    if not basis.shared then
        sample.waves = nil
        return
    end
    local waves = state.waves
    local longSeed = longPhaseSeed(sample)
    if waves == nil or (waves as SwayingWaying.CarriageWaves).phaseSeed ~= sample.phaseSeed
        or (waves as SwayingWaying.CarriageWaves).longPhaseSeed ~= longSeed
        or (waves as SwayingWaying.CarriageWaves).basis ~= basis
        or (waves as SwayingWaying.CarriageWaves).carriageLag ~= carriageLag
        or (waves as SwayingWaying.CarriageWaves).sharedAxisReversed ~= sample.sharedAxisReversed
        or (waves as SwayingWaying.CarriageWaves).sectionLagEnabled ~= config.sectionLag
    then
        local profileName = state.model.motion.profile
        local profile = PROFILES[profileName]
        local phase = phaseForSeed(sample.phaseSeed)
        local longPhase = (longSeed == sample.phaseSeed and phase or phaseForSeed(longSeed)) * LONG_PHASE_MULTIPLIER
        local rotations: {SwayingWaying.SectionWaveRotations} = {}
        for index, section in ipairs(state.model.sections) do
            local lag = config.sectionLag and section.lag or 0.0
            local shortAngle = phase - TWO_PI * lag / profile.shortWaveLength
            local thirdAngle = phase * THIRD_PHASE_MULTIPLIER - TWO_PI * lag / profile.thirdWaveLength
            local sharedLag = carriageLag + (sample.sharedAxisReversed and -lag or lag)
            local longAngle = longPhase - TWO_PI * sharedLag / SHARED_LONG_WAVELENGTH
            local geometry = section.geometry
            rotations[index] = {
                geometry = geometry,
                shortWave = waveRotation(shortAngle, VERTICAL_SHORT_SIN, VERTICAL_SHORT_COS,
                    geometry.shortHalfSin, geometry.shortHalfCos, 1.0 - THIRD_WEIGHT, 1.0),
                longWave = waveRotation(longAngle, VERTICAL_LONG_SIN, VERTICAL_LONG_COS,
                    geometry.longHalfSin, geometry.longHalfCos, 1.0 - THIRD_WEIGHT, sample.sharedAxisReversed and -1.0 or 1.0),
                thirdWave = waveRotation(thirdAngle, VERTICAL_THIRD_SIN, VERTICAL_THIRD_COS,
                    geometry.thirdHalfSin, geometry.thirdHalfCos, THIRD_WEIGHT, 1.0),
            }
        end
        waves = {
            phaseSeed = sample.phaseSeed,
            longPhaseSeed = longSeed,
            carriageLag = carriageLag,
            sharedAxisReversed = sample.sharedAxisReversed,
            sectionLagEnabled = config.sectionLag,
            basis = basis,
            rotations = rotations,
            rotation = rotations[1],
        }
        state.waves = waves
    end
    local present = waves as SwayingWaying.CarriageWaves
    local values = basis.values
    -- These are exact-input caches, independent of callback order and history.
    local regularShort = hasRegularShortWave()
    if regularShort and basis.shortDistance ~= sample.distance then
        local angle = TWO_PI * sample.distance / basis.shortWaveLength
        values.shortSin, values.shortCos = math.sin(angle), math.cos(angle)
        basis.shortDistance = sample.distance
    elseif not regularShort then
        values.shortSin, values.shortCos, basis.shortDistance = 0.0, 0.0, nil
    end
    if config.longWave and basis.longDistance ~= sharedBaseDistance then
        local angle = TWO_PI * sharedBaseDistance / SHARED_LONG_WAVELENGTH
        values.longSin, values.longCos = math.sin(angle), math.cos(angle)
        basis.longDistance = sharedBaseDistance
    elseif not config.longWave then
        values.longSin, values.longCos, basis.longDistance = 0.0, 0.0, nil
    end
    if config.thirdWave and basis.thirdDistance ~= sample.distance then
        local angle = TWO_PI * sample.distance / basis.thirdWaveLength
        values.thirdSin, values.thirdCos = math.sin(angle), math.cos(angle)
        basis.thirdDistance = sample.distance
    elseif not config.thirdWave then
        values.thirdSin, values.thirdCos, basis.thirdDistance = 0.0, 0.0, nil
    end
    sample.waves = present
end

local function sectionWaves(state: SwayingWaying.CarriageState, index: integer)
    local waves = state.waves as SwayingWaying.CarriageWaves
    waves.rotation = waves.rotations[index]
end

local function blend(
    shortWave: number,
    longWave: number,
    thirdWave: number,
    shortWeight: number
): number
    return (1.0 - THIRD_WEIGHT)
        * (shortWeight * shortWave + (1.0 - shortWeight) * longWave)
        + THIRD_WEIGHT * thirdWave
end

local function irregularSamples(sample: SwayingWaying.MotionSample): SwayingWaying.IrregularitySamples
    if sample.irregularity == nil then
        sample.irregularity = irregularity.create()
    end
    return sample.irregularity as SwayingWaying.IrregularitySamples
end

local function irregularShortAngle(
    distance: number,
    profile: SwayProfile,
    seed: integer,
    phase: number,
    cached: SwayingWaying.IrregularityCache
): number
    return TWO_PI * irregularity.warp(distance / profile.shortWaveLength, seed, cached) + phase
end

local function irregularShortMotion(
    sample: SwayingWaying.MotionSample,
    profile: SwayProfile,
    geometry: SwayingWaying.MotionGeometry | nil,
    rollEnabled: boolean
): number, number, number
    local samples = irregularSamples(sample)
    local phase = phaseForSeed(sample.phaseSeed)
    local roll = rollEnabled and math.sin(irregularShortAngle(
        sample.distance, profile, sample.phaseSeed, phase, samples.spacingLateral
    )) or 0.0
    if geometry == nil or not (config.heave or config.pitch) then
        return roll, 0.0, 0.0
    end
    local halfWheelbase = (geometry as SwayingWaying.MotionGeometry).wheelbase * 0.5
    local verticalPhase = phase + VERTICAL_PHASE_OFFSET
    -- Non-uniform spacing requires actual support coordinates; fixed half-wave
    -- rotations would make pitch and heave describe a different vertical profile.
    local front = math.sin(irregularShortAngle(
        sample.distance + halfWheelbase, profile, sample.phaseSeed, verticalPhase, samples.spacingFront
    ))
    local rear = math.sin(irregularShortAngle(
        sample.distance - halfWheelbase, profile, sample.phaseSeed, verticalPhase, samples.spacingRear
    ))
    return roll, (front + rear) * 0.5, front - rear
end

local function blendedWave(
    sample: SwayingWaying.MotionSample,
    profile: SwayProfile
): number
    local shortAngle, longAngle, thirdAngle = waveAngles(sample, profile)
    local shortWave = 0.0
    if config.shortWave then
        shortWave = config.irregularity and (irregularShortMotion(sample, profile, nil, true)) or math.sin(shortAngle)
    end
    local longWave = config.longWave and math.sin(longAngle) or 0.0
    local thirdWave = config.thirdWave and math.sin(thirdAngle) or 0.0
    longWave = orientShared(longWave, sample)
    return blend(
        config.shortWave and shortWave or 0.0,
        longWave,
        config.thirdWave and thirdWave or 0.0,
        clamp(sample.shortWeight, 0.0, 1.0)
    )
end

local function irregularRoll(sample: SwayingWaying.MotionSample, profile: SwayProfile, sway: number): number
    local coordinate = sample.distance / (profile.shortWaveLength * 0.5)
    return irregularity.blend(sway, irregularity.lateral(coordinate, sample.phaseSeed, irregularSamples(sample).lateral))
end

local function swayDegrees(
    sample: SwayingWaying.MotionSample,
    profileName: SwayingWayingMotionProfile
): number
    if not config.roll then
        return 0.0
    end
    local profile = PROFILES[profileName]
    local motionScale = sample.motionScale
    if motionScale <= 0.0 then
        return 0.0
    end
    local sway = blendedWave(sample, profile)
    if config.irregularity then
        sway = irregularRoll(sample, profile, sway)
    end
    return SWAY_MAX_DEGREES * motionScale * sway
end

local function secondaryGeometry(
    profileName: SwayingWayingMotionProfile,
    wheelbase: number
): SwayingWaying.MotionGeometry
    local presentWheelbase = clamp(
        wheelbase,
        constants.MIN_WHEELBASE,
        constants.MAX_WHEELBASE
    )
    local profileCache = geometryCache[profileName]
    local cached = cache.get(profileCache, presentWheelbase)
    if cached ~= nil then
        return cached as SwayingWaying.MotionGeometry
    end
    local profile = PROFILES[profileName]
    local halfWheelbase = presentWheelbase * 0.5
    local shortOffset = TWO_PI
        * halfWheelbase
        / profile.shortWaveLength
    local longOffset = TWO_PI
        * halfWheelbase
        / SHARED_LONG_WAVELENGTH
    local thirdOffset = TWO_PI
        * halfWheelbase
        / profile.thirdWaveLength
    local geometry: SwayingWaying.MotionGeometry = {
        profile = profileName,
        wheelbase = presentWheelbase,
        shortHalfSin = math.sin(shortOffset),
        shortHalfCos = math.cos(shortOffset),
        longHalfSin = math.sin(longOffset),
        longHalfCos = math.cos(longOffset),
        thirdHalfSin = math.sin(thirdOffset),
        thirdHalfCos = math.cos(thirdOffset),
    }
    cache.put(profileCache, presentWheelbase, geometry)
    return geometry
end

local function waveMotion(
    enabled: boolean,
    angle: number,
    verticalSin: number,
    verticalCos: number,
    halfSin: number,
    halfCos: number
): number, number, number
    if not enabled then
        return 0.0, 0.0, 0.0
    end
    local sine = math.sin(angle)
    if not (config.pitch or config.heave) then
        return sine, 0.0, 0.0
    end
    local cosine = math.cos(angle)
    -- Support-point sums and differences preserve a coherent vertical profile
    -- without evaluating the wave separately at the front and rear.
    return sine,
        (sine * verticalCos + cosine * verticalSin) * halfCos,
        2.0 * (cosine * verticalCos - sine * verticalSin) * halfSin
end

local function combinedMotionAtScale(
    sample: SwayingWaying.MotionSample,
    profile: SwayProfile,
    geometry: SwayingWaying.MotionGeometry,
    motionScale: number,
    rollEnabled: boolean
): number, number, number
    rollEnabled = config.roll and rollEnabled
    if motionScale <= 0.0 or not (rollEnabled or config.pitch or config.heave) then
        return 0.0, 0.0, 0.0
    end

    local sway, heave, pitch: number, number, number
    local prepared = sample.waves
    if prepared ~= nil and (prepared as SwayingWaying.CarriageWaves).rotation.geometry == geometry then
        local waves = prepared as SwayingWaying.CarriageWaves
        local values, rotation = waves.basis.values, waves.rotation
        sway, heave, pitch = preparedMotion(values, rotation, sample.shortWeight, rollEnabled)
    else
        local shortAngle, longAngle, thirdAngle = waveAngles(sample, profile)
        local shortSway, shortHeave, shortPitch = waveMotion(
            hasRegularShortWave(),
            shortAngle, VERTICAL_SHORT_SIN, VERTICAL_SHORT_COS,
            geometry.shortHalfSin, geometry.shortHalfCos
        )
        local longSway, longHeave, longPitch = waveMotion(
            config.longWave,
            longAngle, VERTICAL_LONG_SIN, VERTICAL_LONG_COS,
            geometry.longHalfSin, geometry.longHalfCos
        )
        local thirdSway, thirdHeave, thirdPitch = waveMotion(
            config.thirdWave,
            thirdAngle, VERTICAL_THIRD_SIN, VERTICAL_THIRD_COS,
            geometry.thirdHalfSin, geometry.thirdHalfCos
        )
        -- Shared roll and pitch change sign in a backward-facing carriage's axes;
        -- vertical displacement is invariant under that rotation.
        longSway = orientShared(longSway, sample)
        longPitch = orientShared(longPitch, sample)
        local shortWeight = clamp(sample.shortWeight, 0.0, 1.0)
        sway = rollEnabled and blend(shortSway, longSway, thirdSway, shortWeight) or 0.0
        heave = blend(shortHeave, longHeave, thirdHeave, shortWeight)
        pitch = blend(shortPitch, longPitch, thirdPitch, shortWeight)
    end
    if config.irregularity then
        if config.shortWave then
            local shortSway, shortHeave, shortPitch = irregularShortMotion(sample, profile, geometry, rollEnabled)
            local weight = (1.0 - THIRD_WEIGHT) * clamp(sample.shortWeight, 0.0, 1.0)
            sway, heave, pitch = sway + weight * shortSway, heave + weight * shortHeave, pitch + weight * shortPitch
        end
        local spacing = profile.shortWaveLength * 0.5
        if rollEnabled then
            sway = irregularRoll(sample, profile, sway)
        end
        if config.heave or config.pitch then
            local samples = irregularSamples(sample)
            local halfWheelbase = geometry.wheelbase * 0.5
            -- Perturb the support heights before deriving either axis so disabling
            -- pitch or heave cannot alter the other axis's underlying profile.
            local front = irregularity.blend(heave + pitch * 0.5,
                irregularity.vertical((sample.distance + halfWheelbase) / spacing, sample.phaseSeed, samples.front))
            local rear = irregularity.blend(heave - pitch * 0.5,
                irregularity.vertical((sample.distance - halfWheelbase) / spacing, sample.phaseSeed, samples.rear))
            heave = (front + rear) * 0.5
            pitch = front - rear
        end
    end
    sway = rollEnabled and SWAY_MAX_DEGREES * motionScale * sway or 0.0
    local verticalScale = VERTICAL_PROFILE_MAX_METRES * motionScale
    heave = config.heave and clamp(
        verticalScale * heave,
        -HEAVE_MAX_METRES,
        HEAVE_MAX_METRES
    ) or 0.0
    pitch = config.pitch and clamp(
        verticalScale * pitch
            / geometry.wheelbase
            * DEGREES_PER_RADIAN,
        -PITCH_MAX_DEGREES,
        PITCH_MAX_DEGREES
    ) or 0.0
    return sway, heave, pitch
end

local function secondaryMotion(
    sample: SwayingWaying.MotionSample,
    profileName: SwayingWayingMotionProfile,
    wheelbase: number
): number, number
    local profile = PROFILES[profileName]
    local _, heave, pitch = combinedMotionAtScale(sample, profile,
        secondaryGeometry(profileName, wheelbase), sample.motionScale, false)
    return heave, pitch
end

local function secondaryAnimationTimes(
    heave: number,
    pitch: number,
    motionFactor: number,
    settings: SwayingWaying.MotionSettings
): number, number
    if not settings.secondaryMotionEnabled then
        return SECONDARY_CENTRE_MS, SECONDARY_CENTRE_MS
    end
    local scaledHeave = config.heave and clamp(
        heave * motionFactor * settings.heaveIntensity,
        -HEAVE_ANIMATION_LIMIT_METRES,
        HEAVE_ANIMATION_LIMIT_METRES
    ) or 0.0
    local scaledPitch = config.pitch and clamp(
        pitch * motionFactor * settings.pitchIntensity * settings.modelAxisSign,
        -PITCH_ANIMATION_LIMIT_DEGREES,
        PITCH_ANIMATION_LIMIT_DEGREES
    ) or 0.0
    return SECONDARY_CENTRE_MS + scaledHeave * HEAVE_MS_PER_METRE,
        SECONDARY_CENTRE_MS + scaledPitch * PITCH_MS_PER_DEGREE
end

local function curveLeanDegrees(tilt: number): number
    if not (config.roll and config.curveLean) or tilt ~= tilt or tilt <= -math.huge or tilt >= math.huge then
        return 0.0
    end
    return -(clamp(tilt, 0.0, 1.0) - 0.5) * 2.0 * CURVE_LEAN_MAX_DEGREES
end

local function animationTimeFromSway(
    sway: number,
    sample: SwayingWaying.MotionSample,
    settings: SwayingWaying.MotionSettings
): number
    if not config.roll then
        return TILT_CENTRE_MS
    end
    local degrees = (
        sway * sample.swayFactor * settings.rollIntensity
            + curveLeanDegrees(sample.curveTilt) * settings.curveLeanIntensity
    ) * settings.modelAxisSign
    local clampedDegrees = clamp(degrees, TILT_MIN_DEGREES, TILT_MAX_DEGREES)
    return TILT_CENTRE_MS + clampedDegrees * TILT_MS_PER_DEGREE
end

local function rollAnimationTime(
    sample: SwayingWaying.MotionSample,
    settings: SwayingWaying.MotionSettings,
    profileName: SwayingWayingMotionProfile
): number
    return animationTimeFromSway(
        settings.rollIntensity > 0.0 and swayDegrees(sample, profileName) or 0.0,
        sample,
        settings
    )
end

local function animationTime(
    sample: SwayingWaying.MotionSample,
    settings: SwayingWaying.MotionSettings
): number
    return rollAnimationTime(sample, settings, settings.profile)
end

local function animationTimes(
    sample: SwayingWaying.MotionSample,
    settings: SwayingWaying.MotionSettings,
    geometry: SwayingWaying.MotionGeometry
): number, number, number
    if not hasSecondaryMotion(settings) then
        return rollAnimationTime(sample, settings, geometry.profile),
            SECONDARY_CENTRE_MS, SECONDARY_CENTRE_MS
    end
    local profile = PROFILES[geometry.profile]
    local motionScale = sample.motionScale
    local sway, heave, pitch = combinedMotionAtScale(
        sample,
        profile,
        geometry,
        motionScale,
        settings.rollIntensity > 0.0
    )
    local rollTime = animationTimeFromSway(sway, sample, settings)
    local heaveTime, pitchTime = secondaryAnimationTimes(heave, pitch, sample.swayFactor, settings)
    return rollTime, heaveTime, pitchTime
end

local function neutralAnimationTimes(): number, number, number
    return TILT_CENTRE_MS, SECONDARY_CENTRE_MS, SECONDARY_CENTRE_MS
end

local module: SwayingWaying.Motion = {
    speedFactor = speedFactor,
    hasSecondaryMotion = hasSecondaryMotion,
    hasProceduralMotion = hasProceduralMotion,
    swayDegrees = swayDegrees,
    secondaryMotion = secondaryMotion,
    secondaryAnimationTimes = secondaryAnimationTimes,
    secondaryGeometry = secondaryGeometry,
    curveLeanDegrees = curveLeanDegrees,
    animationTime = animationTime,
    animationTimes = animationTimes,
    neutralAnimationTimes = neutralAnimationTimes,
    prepareWaves = prepareWaves,
    sectionWaves = sectionWaves,
}

return module
