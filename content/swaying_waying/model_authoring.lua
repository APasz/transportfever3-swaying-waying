local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local math = _tl_compat and _tl_compat.math or math
local pairs = _tl_compat and _tl_compat.pairs or pairs
local string = _tl_compat and _tl_compat.string or string
local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua")
local values = ug_require("apasz_swaying_waying::/swaying_waying/values.lua")
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")

local OPTION_FIELDS = { sections = true, skipFromLod = true, wheelbase = true }
local SECTION_FIELDS = {
	group = true,
	groupsByLod = true,
	lag = true,
	wheelbase = true,
	pivot = true,
	axes = true,
}
local VECTOR_FIELDS = { x = true, y = true, z = true }

local function invalid(fileName, path, expected, value)
	logger.warnOnce(
		"author:" .. fileName .. ":" .. path,
		"Skipping sway for " .. fileName .. ": " .. path .. " " .. expected .. " (got " .. tostring(value) .. ")"
	)
end

local function knownFields(fileName, path, fields, allowed)
	local valid = true
	for key, value in pairs(fields) do
		if type(key) ~= "string" or not allowed[key] then
			invalid(fileName, path .. "." .. tostring(key), "is an unknown field", value)
			valid = false
		end
	end
	return valid
end

local function nonemptyName(value)
	return type(value) == "string" and (value):match("%S") ~= nil
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function lodIndex(value)
	return values.nonnegative(value) and value == math.floor(value)
end

local function readSection(fileName, value, index)
	local path = "swayingWaying.sections[" .. index .. "]"
	local sectionFields = values.asTable(value)
	if sectionFields == nil then
		invalid(fileName, path, "must be a section table", value)
		return nil
	end
	local entry = sectionFields
	local valid = knownFields(fileName, path, entry, SECTION_FIELDS)
	if not nonemptyName(entry.group) then
		invalid(fileName, path .. ".group", "must be a non-empty group name", entry.group)
		valid = false
	end
	if not values.nonnegative(entry.lag) then
		invalid(fileName, path .. ".lag", "must be a finite distance >= 0 metres", entry.lag)
		valid = false
	end
	if entry.wheelbase ~= nil and not values.wheelbase(entry.wheelbase) then
		invalid(
			fileName,
			path .. ".wheelbase",
			"must be between " .. constants.MIN_WHEELBASE .. " and " .. constants.MAX_WHEELBASE .. " metres",
			entry.wheelbase
		)
		valid = false
	end
	if entry.axes ~= nil and entry.axes ~= "model" and entry.axes ~= "group" then
		invalid(fileName, path .. ".axes", "must be 'model' or 'group'", entry.axes)
		valid = false
	end
	local pivot = nil
	if entry.pivot ~= nil then
		local fields = values.asTable(entry.pivot)
		if fields == nil then
			invalid(fileName, path .. ".pivot", "must be a table with x, y and z in model coordinates", entry.pivot)
			valid = false
		else
			local coordinates = fields
			valid = knownFields(fileName, path .. ".pivot", coordinates, VECTOR_FIELDS) and valid
			for axis in pairs(VECTOR_FIELDS) do
				if not finite(coordinates[axis]) then
					invalid(
						fileName,
						path .. ".pivot." .. axis,
						"must be a finite coordinate in metres",
						coordinates[axis]
					)
					valid = false
				end
			end
			if valid then
				pivot = coordinates
			end
		end
	end
	local groupsByLod = nil
	if entry.groupsByLod ~= nil then
		local fields = values.asTable(entry.groupsByLod)
		if fields == nil or next(fields) == nil then
			invalid(
				fileName,
				path .. ".groupsByLod",
				"must be a non-empty map of zero-based LOD indices to group names",
				entry.groupsByLod
			)
			valid = false
		else
			groupsByLod = {}
			for lod, group in pairs(fields) do
				if not lodIndex(lod) or not nonemptyName(group) then
					invalid(
						fileName,
						path .. ".groupsByLod[" .. tostring(lod) .. "]",
						"must map a non-negative integer LOD to a non-empty group name",
						group
					)
					valid = false
				else
					(groupsByLod)[lod] = group
				end
			end
		end
	end
	if not valid then
		return nil
	end
	return {
		group = entry.group,
		groupsByLod = groupsByLod,
		lag = entry.lag,
		wheelbase = entry.wheelbase,
		pivot = pivot,
		axes = entry.axes ~= nil and entry.axes or "model",
		index = index,
	}
end

local function authorOptions(fileName, metadata)
	local result = { valid = true }
	local rawOptions = metadata[constants.AUTHOR_METADATA_KEY]
	if rawOptions == nil then
		return result
	end
	local fields = values.asTable(rawOptions)
	if fields == nil then
		invalid(fileName, "swayingWaying", "must be a metadata table", rawOptions)
		result.valid = false
		return result
	end
	local options = fields
	result.valid = knownFields(fileName, "swayingWaying", options, OPTION_FIELDS)
	if options.wheelbase ~= nil then
		if values.wheelbase(options.wheelbase) then
			result.wheelbase = options.wheelbase
		else
			invalid(
				fileName,
				"swayingWaying.wheelbase",
				"must be between " .. constants.MIN_WHEELBASE .. " and " .. constants.MAX_WHEELBASE .. " metres",
				options.wheelbase
			)
			result.valid = false
		end
	end
	if options.skipFromLod ~= nil then
		result.skipFromLod = values.positiveInteger(options.skipFromLod)
		if result.skipFromLod == nil then
			invalid(
				fileName,
				"swayingWaying.skipFromLod",
				"must be a positive integer; use swaying_waying_none to opt out",
				options.skipFromLod
			)
			result.valid = false
		end
	end
	if options.sections ~= nil then
		local entries = values.asTable(options.sections)
		local count = entries ~= nil and values.arraySize(entries) or nil
		if count == nil or count < 1 or count > constants.MAX_SECTION_COUNT then
			invalid(
				fileName,
				"swayingWaying.sections",
				"must be a dense array of 1 to " .. constants.MAX_SECTION_COUNT .. " sections",
				options.sections
			)
			result.valid = false
			return result
		end
		local sections = {}
		result.sections = sections
		local owners = {}
		for index = 1, count do
			local section = readSection(fileName, (entries)[index], index)
			if section == nil then
				result.valid = false
			else
				local present = section
				local sectionPath = "swayingWaying.sections[" .. index .. "]"
				local names = { [present.group] = sectionPath .. ".group" }
				for lod, name in pairs(present.groupsByLod or {}) do
					names[name] = sectionPath .. ".groupsByLod[" .. lod .. "]"
				end
				for name, path in pairs(names) do
					if owners[name] ~= nil then
						invalid(fileName, path, "shares a group name with section " .. owners[name], name)
						result.valid = false
					end
					owners[name] = index
				end
				sections[#sections + 1] = present
			end
		end
	end
	return result
end

local function validateLods(fileName, options, count)
	local valid = true
	if options.skipFromLod ~= nil and options.skipFromLod > count then
		invalid(fileName, "swayingWaying.skipFromLod", "exceeds the model's " .. count .. " LODs", options.skipFromLod)
		valid = false
	end
	for _, section in ipairs(options.sections or {}) do
		for lod, group in pairs(section.groupsByLod or {}) do
			if lod >= count then
				invalid(
					fileName,
					"swayingWaying.sections[" .. section.index .. "].groupsByLod[" .. lod .. "]",
					"refers to a missing LOD; model has " .. count .. " LODs",
					group
				)
				valid = false
			end
		end
	end
	return valid
end

local function sectionGroup(section, lod)
	return section.groupsByLod ~= nil and (section.groupsByLod)[lod] or section.group
end

local module = {
	options = authorOptions,
	validateLods = validateLods,
	group = sectionGroup,
}
return module
