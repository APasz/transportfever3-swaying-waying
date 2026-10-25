local function equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
	end
end

local function finite(value)
	return type(value) == "number" and value > -math.huge and value < math.huge
end

local function near(actual, expected, tolerance, message)
	if not finite(actual) or not finite(expected) or not finite(tolerance) or tolerance < 0 then
		error(message .. ": expected finite numbers and a non-negative tolerance", 2)
	end
	if math.abs(actual - expected) > tolerance then
		error(string.format("%s: expected %.6f, got %.6f", message, expected, actual), 2)
	end
end

return { equal = equal, near = near }
