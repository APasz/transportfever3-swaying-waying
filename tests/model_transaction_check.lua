local assertions = dofile("tests/assertions.lua")
local harness = dofile("tests/support/harness.lua").new()
local transaction = harness.require("apasz_swaying_waying::/swaying_waying/model_transaction.lua")
local child = { value = 1 }
local children = { child }
local model = { children = children, alias = child, retained = true }
model.self = model
local succeeded, failure = pcall(transaction.run, model, function(draft)
	local child = draft.alias
	local children = draft.children
	assert(model.alias.value == 1, "preparation must not mutate the source")
	child.value = 2
	child.added = true
	draft.retained = nil
	draft.children = { { replacement = true } }
	table.insert(children, { new = true })
	error("transaction failure")
end)
assert(not succeeded and tostring(failure):find("transaction failure", 1, true))
assertions.equal(model.self, model, "cycles survive rollback")
assertions.equal(model.children, children, "child-array identity survives rollback")
assertions.equal(model.alias, child, "aliases survive rollback")
assertions.equal(children[1], child, "node identity survives rollback")
assertions.equal(#children, 1, "insertions are rolled back")
assertions.equal(child.value, 1, "values are restored")
assertions.equal(child.added, nil, "added keys are removed")
assertions.equal(model.retained, true, "deleted keys are restored")
assertions.equal(
	transaction.run(model, function(draft)
		draft.alias.value = 3
		return true
	end),
	model,
	"successful updates retain model identity"
)
assertions.equal(child.value, 3, "successful updates are committed")
transaction.run(model, function(draft)
	draft.alias.value = 4
	return false
end)
assertions.equal(child.value, 3, "rejected plans preserve the source")
local tableKey = {}
model[tableKey] = child
transaction.run(model, function(draft)
	assert(draft.self == draft, "draft cycles remain connected")
	draft.added = { reference = draft.alias }
	return true
end)
assertions.equal(model[tableKey], child, "table keys retain their identities")
assertions.equal(model.added.reference, child, "new tables reference committed author nodes")
local detached = { value = 1 }
model.detached = detached
transaction.run(model, function(draft)
	local removed = draft.detached
	draft.detached = nil
	removed.added = { owner = draft, alias = draft.alias }
	return true
end)
assertions.equal(model.detached, nil, "detached author tables remain detached")
assertions.equal(detached.added.owner, model, "detached author tables cannot retain the draft graph")
assertions.equal(detached.added.alias, child, "new references in detached tables resolve to author identities")

local inherited = { metadata = { value = 1 } }
local authorMeta = { __index = inherited }
local inheritedModel = setmetatable({}, authorMeta)
inherited.owner = inheritedModel
for _, throws in ipairs({ false, true }) do
	local ok = pcall(transaction.run, inheritedModel, function(draft)
		assert(draft.owner == draft, "metatable cycles remain connected")
		draft.metadata.value = 2
		if throws then
			error("inherited transaction failure")
		end
		return false
	end)
	assertions.equal(ok, not throws, "inherited transaction result")
	assertions.equal(inherited.metadata.value, 1, "inherited values survive rejected and failed plans")
	assertions.equal(getmetatable(inheritedModel), authorMeta, "rollback retains the authored metatable")
end
transaction.run(inheritedModel, function(draft)
	draft.metadata.value = 3
	draft.added = setmetatable({}, getmetatable(draft))
	return true
end)
assertions.equal(inherited.metadata.value, 3, "successful inherited changes are committed")
assertions.equal(getmetatable(inheritedModel), authorMeta, "commit retains the authored metatable")
assertions.equal(getmetatable(inheritedModel.added), authorMeta, "new tables reuse the original metatable")
assertions.equal(inheritedModel.added.metadata, inherited.metadata, "new inherited aliases resolve to original tables")

model.key = setmetatable({}, {
	__eq = function()
		error("committing a transaction must not invoke authored equality hooks")
	end,
})
transaction.run(model, function(draft)
	draft.keyed = setmetatable({ [draft] = draft.alias, [draft.key] = draft.alias }, {
		__newindex = function()
			error("committing a transaction must not invoke authored assignment hooks")
		end,
	})
	return true
end)
assertions.equal(model.keyed[model], child, "table keys and values commit without assignment hooks")
assertions.equal(model.keyed[model.key], child, "table keys commit using identity rather than authored equality")
local keyCount = 0
for _ in pairs(model.keyed) do
	keyCount = keyCount + 1
end
assertions.equal(keyCount, 2, "committed tables retain no draft keys")
local replacementMeta = { __index = { marker = "replacement" } }
local changingMeta = setmetatable(
	{ replacement = replacementMeta, alias = child },
	{ __index = { marker = "original" } }
)
transaction.run(changingMeta, function(draft)
	setmetatable(draft, draft.replacement)
	return true
end)
assertions.equal(getmetatable(changingMeta), replacementMeta, "metatable replacements resolve to author identities")
assertions.equal(changingMeta.marker, "replacement", "commits retain changed inherited behaviour")
transaction.run(changingMeta, function(draft)
	setmetatable(draft, nil)
	draft.replacement.__metatable = "protected after removal"
	return true
end)
assertions.equal(getmetatable(changingMeta), nil, "metatable removals are committed")
assertions.equal(replacementMeta.__metatable, "protected after removal", "metatable contents commit with removal")
transaction.run(changingMeta, function(draft)
	setmetatable(draft, { __index = { alias = draft.alias } })
	return true
end)
assertions.equal(getmetatable(changingMeta).__index.alias, child, "new metatables cannot retain draft references")
local cameras = harness.require("apasz_swaying_waying::/swaying_waying/model_cameras.lua")
local fixture = dofile("tests/support/model_fixture.lua")
local cameraModel = fixture.railModel()
local scope = assert(cameras.scope(cameraModel))
local root = cameraModel.lods[1].node
assert(scope[root] and scope[root.children], "camera transactions copy writable hierarchy links")
assert(not scope[root.transf] and not scope[root.materials], "camera transactions share read-only geometry")
transaction.run(cameraModel, function(draft)
	assert(draft.lods[1].node.transf == root.transf, "scoped drafts avoid copying immutable transforms")
	draft.lods[1].node.children[#draft.lods[1].node.children + 1] = { name = "camera" }
	draft.metadata.cameraConfig.positions[#draft.metadata.cameraConfig.positions + 1] = { group = "camera" }
	return false
end, scope)
assert(
	#root.children == 1 and #cameraModel.metadata.cameraConfig.positions == 1,
	"scoped rejection rolls back camera writes"
)
transaction.run(cameraModel, function(draft)
	local anchor = { name = "camera" }
	draft.lods[1].node.children[#draft.lods[1].node.children + 1] = anchor
	draft.metadata.cameraConfig.positions[#draft.metadata.cameraConfig.positions + 1] = { group = anchor.name }
	return true
end, scope)
assert(root.children[2].name == "camera", "scoped commits preserve hierarchy identity")
assert(cameraModel.metadata.cameraConfig.positions[2].group == "camera", "scoped camera metadata commits together")
local inheritedRoot = setmetatable(root, { __index = {} })
assert(
	cameras.scope(cameraModel) == nil and inheritedRoot == root,
	"inherited hierarchy tables use full graph isolation"
)
print("Model transaction checks passed")
