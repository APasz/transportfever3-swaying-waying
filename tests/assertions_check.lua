local assertions = dofile("tests/assertions.lua")
for _, value in ipairs({ 0 / 0, math.huge, -math.huge }) do
	assert(not pcall(assertions.near, value, 1, 0.001, "invalid actual"))
	assert(not pcall(assertions.near, 1, value, 0.001, "invalid expected"))
	assert(not pcall(assertions.near, 1, 1, value, "invalid tolerance"))
end
assert(not pcall(assertions.near, 1, 1, -0.001, "negative tolerance"))
assert(not pcall(assertions.near, 2, 1, 0.001, "finite mismatch"))
assertions.near(1, 1.0001, 0.001, "within tolerance")
assertions.near(0, 0, 0, "exact comparison")
print("Assertion checks passed")
