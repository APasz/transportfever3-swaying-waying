local harness = dofile("tests/support/harness.lua").new()
local equal = dofile("tests/assertions.lua").equal
local fixture = dofile("tests/support/model_fixture.lua")
local policy = harness.require("apasz_swaying_waying::/swaying_waying/camera_hud_policy.lua")
local constants = harness.require("apasz_swaying_waying::/swaying_waying/constants.lua")

local function point(x, y, z)
	return { x = x, y = y, z = z }
end

local function camera(index, kind, x)
	local pose = fixture.identity()
	pose[13], pose[15] = x, 2
	return { index = index, kind = kind, crewSeat = 1, pose = pose }
end

local stable = camera(1, "Stable", 5)
local metadata = { schema = constants.CAMERA_HUD_SCHEMA, count = 1, positions = { stable } }
equal(policy.read(nil), nil, "models without published camera data remain supported")
equal(policy.read(metadata), metadata, "supported metadata retains its identity")
equal(policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2)), stable, "a unique nearby view can be labelled")
equal(
	policy.cameraAt(metadata, point(3, 0, 2), point(7, 0, 2)),
	stable,
	"simulation interpolation does not require an estimated clock"
)
equal(policy.cameraAt(metadata, point(50, 0, 2), point(51, 0, 2)), nil, "moving away from a view hides its label")
local sway = camera(2, "Sway", 5)
metadata.positions[2], metadata.count = sway, 2
equal(policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2)), nil, "coincident Stable and Sway views stay ambiguous")
local cameraMatch, nearby = policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2))
equal(cameraMatch, nil, "ambiguous cameras do not provide a specific label")
equal(nearby, true, "ambiguous cameras can still identify their owning carriage")
sway.pose[13] = 12
equal(policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2)), stable, "well separated views can be identified")
equal(
	policy.cameraAt(metadata, point(12, 0, 2), point(12, 0, 2)),
	sway,
	"matching follows the actual viewpoint rather than an input counter"
)
equal(
	policy.cameraAt(metadata, point(4, 0, 2), point(13, 0, 2)),
	nil,
	"fast movement crossing two viewpoints is ambiguous"
)
metadata.count = 3
cameraMatch, nearby = policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2))
equal(nearby, false, "incomplete metadata cannot identify a carriage from its cameras")
equal(
	policy.cameraAt(metadata, point(5, 0, 2), point(5, 0, 2)),
	nil,
	"incomplete camera metadata cannot produce a confident label"
)
metadata.count = 2

local transform = fixture.identity()
transform[1], transform[2], transform[5], transform[6] = 0, 2, -3, 0
transform[11], transform[13], transform[14], transform[15] = 4, 100, 200, 300
local localEye = assert(policy.localEye(transform, point(94, 202, 312)))
equal(localEye.x, 1, "world-to-model handles rotated and scaled instances")
equal(localEye.y, 2, "world-to-model accounts for non-uniform scale")
equal(localEye.z, 3, "world-to-model accounts for translation")
transform[11] = 0
equal(policy.localEye(transform, point(0, 0, 0)), nil, "singular transforms are ignored")
transform[11] = math.huge
equal(policy.localEye(transform, point(0, 0, 0)), nil, "nonfinite transforms are ignored")
for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
	equal(policy.finitePoint(point(invalid, 0, 0)), false, "transient invalid camera coordinates are rejected")
	equal(
		policy.cameraAt(metadata, point(5, invalid, 2), point(5, 0, 2)),
		nil,
		"invalid live positions cannot identify a camera"
	)
end

local minimum, maximum = point(-10, -2, 0), point(10, 2, 5)
equal(
	policy.contains(point(-20, 0, 2), point(20, 0, 2), minimum, maximum),
	true,
	"an interpolated viewpoint can cross the body between simulation steps"
)
equal(
	policy.contains(point(0, 0, 2), point(0, 0, 2), minimum, maximum),
	true,
	"a stopped camera remains inside its carriage"
)
equal(
	policy.contains(point(-20, 8, 2), point(20, 8, 2), minimum, maximum),
	false,
	"nearby parallel tracks do not identify a carriage"
)
equal(
	policy.contains(point(0, 0, 20), point(0, 0, 21), minimum, maximum),
	false,
	"a high free camera is outside the body"
)

for _, corrupt in ipairs({
	false,
	{ schema = 99 },
	{ schema = 1, count = 0, positions = {} },
	{ schema = 1, count = 1, positions = { [2] = stable } },
	{ schema = 1, count = 2, positions = { stable, stable } },
	{ schema = 1, count = 1, positions = { camera(2, "Stable", 5) } },
	{ schema = 1, count = 1, positions = { camera(1, "unknown", 5) } },
	{ schema = 1, count = 1, positions = { { index = 1, kind = "Stable", pose = {} } } },
}) do
	assert(not pcall(policy.read, corrupt), "invalid HUD metadata must fail explicitly")
end

print("Camera HUD policy checks passed")
