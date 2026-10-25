local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local pairs = _tl_compat and _tl_compat.pairs or pairs
local table = _tl_compat and _tl_compat.table or table

local function mapped(value, tables)
	if type(value) == "table" then
		return tables[value] or value
	end
	return value
end

local function discover(value, copies, originals, pending)
	if type(value) == "table" and copies[value] == nil then
		local source = value
		local copy = {}
		copies[source] = copy
		originals[copy] = source
		pending[#pending + 1] = source
	end
end

local function authorMetatable(source)
	local meta = getmetatable(source)
	assert(meta == nil or type(meta) == "table", "Cannot prepare a model with a protected metatable")
	return meta
end

local function draftGraph(root)
	local copies = { [root] = {} }
	local originals = { [copies[root]] = root }
	local pending = { root }
	local index = 1
	while index <= #pending do
		local source = pending[index]
		index = index + 1
		for key, value in next, source do
			discover(key, copies, originals, pending)
			discover(value, copies, originals, pending)
		end
		discover(authorMetatable(source), copies, originals, pending)
	end
	for _, source in ipairs(pending) do
		local copy = copies[source]
		for key, value in next, source do
			rawset(copy, mapped(key, copies), mapped(value, copies))
		end
		local authorMeta = authorMetatable(source)
		if authorMeta ~= nil then
			setmetatable(copy, copies[authorMeta])
		end
	end
	return copies[root], originals
end

local function resolveNewTables(root, originals)
	local seen = {}
	local pending = { root }
	while #pending > 0 do
		local current = table.remove(pending)
		if not seen[current] then
			seen[current] = true
			local keys = {}
			for key in next, current do
				keys[#keys + 1] = key
			end
			for _, key in ipairs(keys) do
				local value = current[key]
				if type(key) == "table" then
					pending[#pending + 1] = key
				end
				if type(value) == "table" then
					pending[#pending + 1] = value
				end
				if originals[current] == nil then
					local resolvedKey = mapped(key, originals)
					if type(key) == "table" and originals[key] ~= nil then
						rawset(current, key, nil)
					end
					rawset(current, resolvedKey, mapped(value, originals))
				end
			end
			local meta = authorMetatable(current)
			if meta ~= nil then
				pending[#pending + 1] = meta
				if originals[current] == nil and originals[meta] ~= nil then
					setmetatable(current, originals[meta])
				end
			end
		end
	end
end

local function commit(root, originals)
	resolveNewTables(root, originals)
	for draft, original in pairs(originals) do
		local removed = {}
		for key in next, original do
			removed[#removed + 1] = key
		end
		for _, key in ipairs(removed) do
			rawset(original, key, nil)
		end
		for key, value in next, draft do
			rawset(original, mapped(key, originals), mapped(value, originals))
		end
	end
end

local function run(model, prepare)
	assert(type(model) == "table", "Model preparation requires a table")
	local draft, originals = draftGraph(model)

	if prepare(draft) then
		commit(draft, originals)
	end
	return model
end

local module = { run = run }
return module
