local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local string = _tl_compat and _tl_compat.string or string
local function ownerOf(resourceName)
	return resourceName:match("^([%w_%-%.]*::)") or "::"
end

local function folderOf(resourceName)
	local path = resourceName:gsub("^[%w_%-%.]*::", "")
	return path:match("^(.*/)") or "/"
end

local function withLuaExtension(resourceName)
	if resourceName:match("%.lua$") then
		return resourceName
	end
	return resourceName .. ".lua"
end

local function trfCandidates(name, modelFile)
	local candidates
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

local function scriptCandidates(reference, transformatorFile)
	local file, memberPath = reference:match("^(.-)@(.+)$")
	if file == nil then
		file = reference
	end

	local bases
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

	local files = {}
	for _, base in ipairs(bases) do
		if base:match("%.lua$") or base:match("%.tl$") then
			files[#files + 1] = base
		else
			files[#files + 1] = base .. ".lua"
			files[#files + 1] = base .. ".tl"
		end
	end

	local members = {}
	if memberPath ~= nil then
		for member in memberPath:gmatch("[^%.]+") do
			members[#members + 1] = member
		end
	end
	return files, members
end

local module = {
	trfCandidates = trfCandidates,
	scriptCandidates = scriptCandidates,
}

return module
