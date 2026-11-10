local ACTIVE_HISTORY_MILLISECONDS = 1000
local EXPIRATIONS_PER_TICK = 8

local function unlink<K, V>(cache: SwayingWaying.BoundedCache<K, V>, entry: SwayingWaying.CacheEntry<K, V>)
    local before = entry.previous
    local after = entry.next
    if before ~= nil then
        (before as SwayingWaying.CacheEntry<K, V>).next = after
    else
        cache.newest = after
    end
    if after ~= nil then
        (after as SwayingWaying.CacheEntry<K, V>).previous = before
    else
        cache.oldest = before
    end
end

local function remove<K, V>(cache: SwayingWaying.BoundedCache<K, V>, entry: SwayingWaying.CacheEntry<K, V>)
    unlink(cache, entry)
    cache.entries[entry.key] = nil
    cache.count = cache.count - 1
end

local function configure<K, V>(cache: SwayingWaying.BoundedCache<K, V>, capacity: integer, retention: integer)
    assert(capacity >= 1 and capacity % 1 == 0, "Cache capacity must be a positive integer")
    assert(retention >= ACTIVE_HISTORY_MILLISECONDS and retention < math.huge and retention % 1 == 0,
        "Cache retention must be whole milliseconds covering active history protection")
    cache.capacity, cache.retention = capacity, retention
    while cache.count > capacity do
        remove(cache, cache.oldest as SwayingWaying.CacheEntry<K, V>)
    end
end

local function advance<K, V>(cache: SwayingWaying.BoundedCache<K, V>, time: integer)
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
        if oldest == nil or (oldest as SwayingWaying.CacheEntry<K, V>).lastSeen == nil
            or time - ((oldest as SwayingWaying.CacheEntry<K, V>).lastSeen as integer) < retention
        then
            break
        end
        remove(cache, oldest as SwayingWaying.CacheEntry<K, V>)
    end
end

local function canPut<K, V>(cache: SwayingWaying.BoundedCache<K, V>): boolean
    if cache.count < cache.capacity or cache.time == nil then
        return true
    end
    local oldest = cache.oldest as SwayingWaying.CacheEntry<K, V>
    return oldest.lastSeen == nil
        or (cache.time as integer) - (oldest.lastSeen as integer) >= ACTIVE_HISTORY_MILLISECONDS
end

local function promote<K, V>(cache: SwayingWaying.BoundedCache<K, V>, entry: SwayingWaying.CacheEntry<K, V>)
    entry.previous = nil
    entry.next = cache.newest
    if cache.newest ~= nil then
        (cache.newest as SwayingWaying.CacheEntry<K, V>).previous = entry
    end
    cache.newest = entry
    if cache.oldest == nil then
        cache.oldest = entry
    end
end

local function create<K, V>(capacity: integer): SwayingWaying.BoundedCache<K, V>
    assert(capacity >= 1 and capacity % 1 == 0, "Cache capacity must be a positive integer")
    return { capacity = capacity, count = 0, entries = {}, newest = nil, oldest = nil }
end

local function get<K, V>(cache: SwayingWaying.BoundedCache<K, V>, key: K): V | nil
    local entry = cache.entries[key]
    if entry == nil then
        return nil
    end
    local present = entry as SwayingWaying.CacheEntry<K, V>
    local time = cache.time
    if time ~= nil then
        if cache.retention ~= nil and present.lastSeen ~= nil
            and time - (present.lastSeen as integer) >= (cache.retention as integer)
        then
            remove(cache, present)
            return nil
        end
        present.lastSeen = time
    end
    if present ~= cache.newest then
        local before = present.previous as SwayingWaying.CacheEntry<K, V>
        local after = present.next
        before.next = after
        if after ~= nil then
            (after as SwayingWaying.CacheEntry<K, V>).previous = before
        else
            cache.oldest = before
        end
        local newest = cache.newest as SwayingWaying.CacheEntry<K, V>
        present.previous = nil
        present.next = newest
        newest.previous = present
        cache.newest = present
    end
    return present.value
end

local function put<K, V>(cache: SwayingWaying.BoundedCache<K, V>, key: K, value: V): boolean
    local entry = cache.entries[key]
    if entry ~= nil then
        local present = entry as SwayingWaying.CacheEntry<K, V>
        present.value = value
        present.lastSeen = cache.time
        get(cache, key)
        return true
    end
    if not canPut(cache) then
        return false
    end
    local inserted: SwayingWaying.CacheEntry<K, V>
    if cache.count == cache.capacity then
        inserted = cache.oldest as SwayingWaying.CacheEntry<K, V>
        unlink(cache, inserted)
        cache.entries[inserted.key] = nil
        -- Reuse the link when evicting; a full cache allocates no new entries.
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

local module: SwayingWaying.Cache = {
    create = create, get = get, put = put, advance = advance, configure = configure, canPut = canPut,
}
return module
