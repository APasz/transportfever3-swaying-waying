local type RawTable = SwayingWaying.RawTable
local type TableMap = {RawTable: RawTable}

local function mapped(value: any, tables: TableMap): any
    if type(value) == "table" then
        return tables[value as RawTable] or value
    end
    return value
end

local function discover(value: any, copies: TableMap, originals: TableMap, pending: {RawTable},
    scope: {RawTable: boolean} | nil, opaque: {RawTable: boolean})
    if type(value) == "table" and copies[value as RawTable] == nil then
        local source = value as RawTable
        if scope ~= nil and not (scope as {RawTable: boolean})[source] then
            opaque[source] = true
            return
        end
        local copy: RawTable = {}
        copies[source] = copy
        originals[copy] = source
        pending[#pending + 1] = source
    end
end

local function authorMetatable(source: RawTable): RawTable | nil
    local meta = getmetatable(source)
    assert(meta == nil or type(meta) == "table", "Cannot prepare a model with a protected metatable")
    return meta as RawTable | nil
end

local function draftGraph(root: RawTable, scope: {RawTable: boolean} | nil): RawTable, TableMap, {RawTable: boolean}
    local copies: TableMap = { [root] = {} }
    local originals: TableMap = { [copies[root]] = root }
    local pending: {RawTable} = { root }
    local opaque: {RawTable: boolean} = {}
    local index = 1
    while index <= #pending do
        local source = pending[index]
        index = index + 1
        for key, value in next, source do
            discover(key, copies, originals, pending, scope, opaque)
            discover(value, copies, originals, pending, scope, opaque)
        end
        discover(authorMetatable(source), copies, originals, pending, scope, opaque)
    end
    for _, source in ipairs(pending) do
        local copy = copies[source]
        for key, value in next, source do
            rawset(copy, mapped(key, copies), mapped(value, copies))
        end
        local authorMeta = authorMetatable(source)
        if authorMeta ~= nil then
            assert(scope == nil, "Scoped model preparation requires plain tables")
            setmetatable(copy, copies[authorMeta as RawTable] as metatable<RawTable>)
        end
    end
    return copies[root], originals, opaque
end

local function resolveNewTables(originals: TableMap, opaque: {RawTable: boolean})
    local seen: {RawTable: boolean} = {}
    local pending: {RawTable} = {}
    -- Detached author tables are committed too; their new values must not retain
    -- references to the temporary draft graph.
    for draft in pairs(originals) do
        pending[#pending + 1] = draft
    end
    while #pending > 0 do
        local current = table.remove(pending)
        if not seen[current] and not opaque[current] then
            seen[current] = true
            local keys: {any} = {}
            for key in next, current do
                keys[#keys + 1] = key
            end
            for _, key in ipairs(keys) do
                -- next supplied a stored key, so this lookup cannot invoke __index.
                local value = current[key]
                if type(key) == "table" then
                    pending[#pending + 1] = key as RawTable
                end
                if type(value) == "table" then
                    pending[#pending + 1] = value as RawTable
                end
                if originals[current] == nil then
                    local resolvedKey = mapped(key, originals)
                    if type(key) == "table" and originals[key as RawTable] ~= nil then
                        rawset(current, key, nil)
                    end
                    rawset(current, resolvedKey, mapped(value, originals))
                end
            end
            local meta = authorMetatable(current)
            if meta ~= nil then
                pending[#pending + 1] = meta as RawTable
                if originals[current] == nil and originals[meta as RawTable] ~= nil then
                    setmetatable(current, originals[meta as RawTable] as metatable<RawTable>)
                end
            end
        end
    end
end

local function commit(originals: TableMap, opaque: {RawTable: boolean})
    resolveNewTables(originals, opaque)
    -- Apply metatable changes before their contents: a removed metatable may
    -- acquire __metatable protection when its own fields are committed.
    for draft, original in pairs(originals) do
        local meta = authorMetatable(draft)
        if meta ~= nil or getmetatable(original) ~= nil then
            setmetatable(original, mapped(meta, originals) as metatable<RawTable>)
        end
    end
    for draft, original in pairs(originals) do
        local removed: {any} = {}
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

local function run(model: any, prepare: function(any): boolean, scope: {RawTable: boolean} | nil): any
    -- A scope must include every writable table; omitted data is shared read-only.
    assert(type(model) == "table", "Model preparation requires a table")
    local draft, originals, opaque = draftGraph(model as RawTable, scope)
    -- The source remains untouched on rejection or an exception. Existing author
    -- tables retain their identity when the complete draft is committed.
    if prepare(draft) then
        commit(originals, opaque)
    end
    return model
end

local module: SwayingWaying.ModelTransaction = { run = run }
return module
