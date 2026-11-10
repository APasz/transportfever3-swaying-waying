local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local math = _tl_compat and _tl_compat.math or math
local ACTIVE_HISTORY_MILLISECONDS = 1000
local EXPIRATIONS_PER_TICK = 8

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

local function remove(cache, entry)
	unlink(cache, entry)
	cache.entries[entry.key] = nil
	cache.count = cache.count - 1
end

local function configure(cache, capacity, retention)
	assert(capacity >= 1 and capacity % 1 == 0, "Cache capacity must be a positive integer")
	assert(
		retention >= ACTIVE_HISTORY_MILLISECONDS and retention < math.huge and retention % 1 == 0,
		"Cache retention must be whole milliseconds covering active history protection"
	)
	cache.capacity, cache.retention = capacity, retention
	while cache.count > capacity do
		remove(cache, cache.oldest)
	end
end

local function advance(cache, time)
	local previous = cache.time
	if previous == time then
		return
	end
	assert(time > -math.huge and time < math.huge, "Invalid cache clock")
	if previous ~= nil and time < previous then
		cache.entries, cache.newest, cache.oldest, cache.count = {}, nil, nil, 0
	end
	cache.time = time
	local retention = cache.retention
	if retention == nil then
		return
	end
	for _ = 1, EXPIRATIONS_PER_TICK do
		local oldest = cache.oldest
		if oldest == nil or (oldest).lastSeen == nil or time - (oldest).lastSeen < retention then
			break
		end
		remove(cache, oldest)
	end
end

local function canPut(cache)
	if cache.count < cache.capacity or cache.time == nil then
		return true
	end
	local oldest = cache.oldest
	return oldest.lastSeen == nil or cache.time - oldest.lastSeen >= ACTIVE_HISTORY_MILLISECONDS
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
	local time = cache.time
	if time ~= nil then
		if cache.retention ~= nil and present.lastSeen ~= nil and time - present.lastSeen >= cache.retention then
			remove(cache, present)
			return nil
		end
		present.lastSeen = time
	end
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
		present.lastSeen = cache.time
		get(cache, key)
		return true
	end
	if not canPut(cache) then
		return false
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
	inserted.lastSeen = cache.time
	promote(cache, inserted)
	return true
end

local module = {
	create = create,
	get = get,
	put = put,
	advance = advance,
	configure = configure,
	canPut = canPut,
}
return module
