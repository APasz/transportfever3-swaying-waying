local harness = dofile("tests/support/harness.lua").new()
local nodes = harness.require("apasz_swaying_waying::/swaying_waying/model_nodes.lua")
local function validate(root)
	nodes.validate({ lods = { { node = root } } })
end
for _, root in ipairs({
	{ name = 1 },
	{ children = false },
	{ children = { [2] = {} } },
	{ children = { false } },
	{ transf = {} },
	{ transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0 / 0, 1 } },
	{ animations = false },
}) do
	assert(not pcall(validate, root), "malformed model nodes must be rejected")
end
local cyclic = {}
cyclic.children = { cyclic }
assert(not pcall(validate, cyclic), "cyclic hierarchies must be rejected")
for _, lods in ipairs({
	{ [2] = { node = {} } },
	{ { node = {} }, [3] = { node = {} } },
	{ { node = {} }, hidden = { node = {} } },
}) do
	local succeeded, failure = pcall(nodes.validate, { lods = lods })
	assert(
		not succeeded and failure:find("Model LODs must be a dense array", 1, true),
		"malformed LOD arrays must fail before entries are skipped"
	)
end
local shared = { name = "shared", authorData = { retained = true } }
validate({ children = { shared, shared } })
assert(shared.authorData.retained, "validation preserves opaque author data")
local identity = nodes.transform(nil)
assert(#identity == 16 and identity[1] == 1 and identity[16] == 1)
print("Model node checks passed")
