local RESPONSE_SECONDS = 0.15
local ANGULAR_RATE = 2.0 / RESPONSE_SECONDS
local MILLISECONDS_PER_SECOND = 1000.0
local SETTLE_EPSILON = 0.00001

local function damp(
    value: number,
    velocity: number,
    target: number,
    elapsed: number,
    decay: number
): number, number
    if value == target and velocity == 0.0 then
        return target, 0.0
    end
    local offset = value - target
    local impulse = velocity + ANGULAR_RATE * offset
    local position = target + (offset + impulse * elapsed) * decay
    local rate = (velocity - ANGULAR_RATE * impulse * elapsed) * decay
    if math.abs(position - target) <= SETTLE_EPSILON and math.abs(rate) <= SETTLE_EPSILON then
        return target, 0.0
    end
    return position, rate
end

local function update(
    state: SwayingWaying.CarriageState,
    time: integer,
    motionScale: number,
    curveTilt: number
)
    assert(time > -math.huge and time < math.huge, "Invalid motion response time")
    assert(motionScale >= 0.0 and motionScale <= 1.0, "Invalid motion response amplitude")
    assert(curveTilt >= 0.0 and curveTilt <= 1.0, "Invalid motion response tilt")
    local sample = state.sample
    local previous = state.responseTime
    state.responseTime = time
    if previous == nil or time < previous then
        sample.motionScale = motionScale
        sample.curveTilt = curveTilt
        state.motionVelocity = 0.0
        state.curveVelocity = 0.0
        return
    end
    if time == previous
        or (sample.motionScale == motionScale and state.motionVelocity == 0.0
            and sample.curveTilt == curveTilt and state.curveVelocity == 0.0)
    then
        return
    end
    local elapsed = (time - previous) / MILLISECONDS_PER_SECOND
    -- The exact critically damped solution stays stable over long render gaps.
    -- Both responses share its decay; wave phase remains a function of distance.
    local decay = math.exp(-ANGULAR_RATE * elapsed)
    sample.motionScale, state.motionVelocity = damp(sample.motionScale, state.motionVelocity, motionScale, elapsed, decay)
    sample.curveTilt, state.curveVelocity = damp(sample.curveTilt, state.curveVelocity, curveTilt, elapsed, decay)
end

local function neutral(state: SwayingWaying.CarriageState): boolean
    return state.sample.motionScale == 0.0 and state.sample.curveTilt == 0.5
        and state.motionVelocity == 0.0 and state.curveVelocity == 0.0
end

local module: SwayingWaying.MotionResponse = { update = update, neutral = neutral }
return module
