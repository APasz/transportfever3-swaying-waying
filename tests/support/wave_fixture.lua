local function create(motion, profile, consist, carriage, position, sections)
	local settings = {
		rollIntensity = 1.25,
		pitchIntensity = 0.8,
		heaveIntensity = 1.1,
		curveLeanIntensity = 0.75,
		modelAxisSign = 1,
		profile = profile,
		secondaryMotionEnabled = true,
	}
	local runtimeSections = {}
	for index, lag in ipairs(sections or { 0 }) do
		runtimeSections[index] = { lag = lag, geometry = motion.secondaryGeometry(profile, 10 + index) }
	end
	return {
		model = { motion = settings, sections = runtimeSections },
		sample = {
			motionScale = 0.8,
			distance = 123,
			phaseSeed = consist + carriage,
			sharedDistance = 123 - position * 20,
			sharedPhaseSeed = consist,
			sharedAxisReversed = false,
			curveTilt = 0.65,
			swayFactor = 1.2,
			shortWeight = 0.65,
		},
		motionVelocity = 0,
		curveVelocity = 0,
	}
end

return create
