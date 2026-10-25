local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local function unlink(cache, entry)
	local before = entry.previous
	local after = entry.next
	if before ~= nil then
		(before).next = after
	else
		cache.newest = after
	end
	if after ~= nil then
		(after).previous = before
	else
		cache.oldest = before
	end
end

local function promote(cache, entry)
	entry.previous = nil
	entry.next = cache.newest
	if cache.newest ~= nil then
		(cache.newest).previous = entry
	end
	cache.newest = entry
	if cache.oldest == nil then
		cache.oldest = entry
	end
end

local function create(capacity)
	assert(capacity >= 1 and capacity % 1 == 0, "Cache capacity must be a positive integer")
	return { capacity = capacity, count = 0, entries = {}, newest = nil, oldest = nil }
end

local function get(cache, key)
	local entry = cache.entries[key]
	if entry == nil then
		return nil
	end
	local present = entry
	if present ~= cache.newest then
		local before = present.previous
		local after = present.next
		before.next = after
		if after ~= nil then
			(after).previous = before
		else
			cache.oldest = before
		end
		local newest = cache.newest
		present.previous = nil
		present.next = newest
		newest.previous = present
		cache.newest = present
	end
	return present.value
end

local function put(cache, key, value)
	local entry = cache.entries[key]
	if entry ~= nil then
		local present = entry
		present.value = value
		get(cache, key)
		return
	end
	local inserted
	if cache.count == cache.capacity then
		inserted = cache.oldest
		unlink(cache, inserted)
		cache.entries[inserted.key] = nil

		inserted.key = key
		inserted.value = value
	else
		inserted = { key = key, value = value, previous = nil, next = nil }
		cache.count = cache.count + 1
	end
	cache.entries[key] = inserted
	promote(cache, inserted)
end

local module = { create = create, get = get, put = put }
return module
