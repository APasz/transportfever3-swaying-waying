local function ownerOf(resourceName: string): string
    return resourceName:match("^([%w_%-%.]*::)") or "::"
end

local function folderOf(resourceName: string): string
    local path = resourceName:gsub("^[%w_%-%.]*::", "")
    return path:match("^(.*/)") or "/"
end

local function withLuaExtension(resourceName: string): string
    if resourceName:match("%.lua$") then
        return resourceName
    end
    return resourceName .. ".lua"
end

local function trfCandidates(name: string, modelFile: string): {string}
    local candidates: {string}
    if name:find("::", 1, true) then
        candidates = { name }
    elseif name:sub(1, 1) == "/" then
        candidates = {
            ownerOf(modelFile) .. name,
            "::" .. name,
        }
    else
        candidates = {
            ownerOf(modelFile) .. folderOf(modelFile) .. name,
            ownerOf(modelFile) .. "/" .. name,
        }
    end
    for index, candidate in ipairs(candidates) do
        candidates[index] = withLuaExtension(candidate)
    end
    return candidates
end

local function scriptCandidates(
    reference: string,
    transformatorFile: string
): {string}, {string}
    local file, memberPath = reference:match("^(.-)@(.+)$")
    if file == nil then
        file = reference
    end

    local bases: {string}
    if file:find("::", 1, true) then
        bases = { file }
    elseif file:sub(1, 1) == "/" then
        bases = {
            ownerOf(transformatorFile) .. file,
            "::" .. file,
        }
    else
        bases = {
            ownerOf(transformatorFile) .. folderOf(transformatorFile) .. file,
            "::" .. folderOf(transformatorFile) .. file,
        }
    end

    local files: {string} = {}
    for _, base in ipairs(bases) do
        if base:match("%.lua$") or base:match("%.tl$") then
            files[#files + 1] = base
        else
            files[#files + 1] = base .. ".lua"
            files[#files + 1] = base .. ".tl"
        end
    end

    local members: {string} = {}
    if memberPath ~= nil then
        for member in memberPath:gmatch("[^%.]+") do
            members[#members + 1] = member
        end
    end
    return files, members
end

local module: SwayingWaying.ResourcePaths = {
    trfCandidates = trfCandidates,
    scriptCandidates = scriptCandidates,
}

return module
