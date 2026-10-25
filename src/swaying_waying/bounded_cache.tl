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

local function put<K, V>(cache: SwayingWaying.BoundedCache<K, V>, key: K, value: V)
    local entry = cache.entries[key]
    if entry ~= nil then
        local present = entry as SwayingWaying.CacheEntry<K, V>
        present.value = value
        get(cache, key)
        return
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
    promote(cache, inserted)
end

local module: SwayingWaying.Cache = { create = create, get = get, put = put }
return module
