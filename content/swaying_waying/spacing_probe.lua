local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local math = _tl_compat and _tl_compat.math or math
local pcall = _tl_compat and _tl_compat.pcall or pcall
local string = _tl_compat and _tl_compat.string or string
local logger = ug_require("apasz_swaying_waying::/swaying_waying/logger.lua")

local function inspectConsist(entity)
	assert(api.engine.entityExists(entity), "Spacing probe: entity does not exist")
	local list = api.engine.getComponent(entity, api.type.ComponentType.CARRIAGE_LIST)
	if list == nil then
		local carriage = api.engine.getComponent(entity, api.type.ComponentType.CARRIAGE)
		assert(carriage ~= nil, "Spacing probe: expected a consist or carriage entity")
		entity = api.engine.system.carriageListSystem.getVehicleInfo(entity).owningVehicle
		assert(entity >= 0 and api.engine.entityExists(entity), "Spacing probe: carriage has no owning vehicle")
		list = api.engine.getComponent(entity, api.type.ComponentType.CARRIAGE_LIST)
		assert(list ~= nil, "Spacing probe: owning vehicle has no carriage list")
	end
	local carriages = (list).carriages
	local native = api.engine.system.carriageListSystem.getVehicleData(entity)
	logger.info(
		string.format(
			"Spacing probe engine: vehicle=%d count=%d length=%.6f back=%.6f front=%.6f",
			entity,
			#carriages,
			native.length,
			native.bounds.back,
			native.bounds.front
		)
	)

	local previousOffset = 0.0
	for index, carriageEntity in ipairs(carriages) do
		local info = api.engine.system.carriageListSystem.getVehicleInfo(carriageEntity)
		assert(info.owningVehicle == entity, "Spacing probe: carriage belongs to another vehicle")
		assert(info.offset > -math.huge and info.offset < math.huge, "Spacing probe: invalid native carriage offset")
		local carriage = api.engine.getComponent(carriageEntity, api.type.ComponentType.CARRIAGE)
		local gap = index > 1 and info.offset - previousOffset or 0.0
		logger.info(
			string.format(
				"Spacing probe engine carriage: vehicle=%d carriage=%d position=%d offset=%.6f delta=%.6f apiListReversed=%s apiCarriageReversed=%s",
				entity,
				carriageEntity,
				info.index,
				info.offset,
				gap,
				tostring(info.reversed),
				carriage ~= nil and tostring((carriage).reversed) or "unavailable"
			)
		)

		previousOffset = info.offset
	end
end

local function inspectRequested(entity)
	if entity ~= nil then
		inspectConsist(entity)
		return true
	end
	local entities = {}

	for _, vehicle in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)) do
		local list = api.engine.getComponent(vehicle, api.type.ComponentType.CARRIAGE_LIST)
		if list ~= nil then
			entities[#entities + 1] = vehicle
		end
	end
	logger.info("Spacing probe engine: inspecting " .. #entities .. " consists")
	for _, vehicle in ipairs(entities) do
		inspectConsist(vehicle)
	end
	return true
end

local function inspect(entity)
	logger.info("Spacing probe engine: begin")
	local succeeded, failure = pcall(inspectRequested, entity)
	if not succeeded then
		local message = "Spacing probe engine: failed: " .. tostring(failure)
		logger.warn(message)
		error(message, 0)
	end
	logger.info("Spacing probe engine: complete")
end

local module = {
	inspect = inspect,
}

return module
