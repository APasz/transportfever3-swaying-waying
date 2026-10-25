local constants = ug_require("apasz_swaying_waying::/swaying_waying/constants.lua") as SwayingWaying.Constants
local type DynamicTable = SwayingWaying.RawTable

local function dynamicTable(value: any): DynamicTable | nil
    if type(value) == "table" then
        return value as DynamicTable
    end
    return nil
end

local function dynamicArray(value: any): {any} | nil
    if type(value) == "table" then
        return value as {any}
    end
    return nil
end

local function safeNodeSuffix(name: string): string
    return (name:gsub("[^%w_]", "_"))
end

local function validLag(value: any): boolean
    return type(value) == "number"
        and (value as number) >= 0.0
        and (value as number) < math.huge
end

local function validWheelbase(value: any): boolean
    return type(value) == "number"
        and (value as number) >= constants.MIN_WHEELBASE
        and (value as number) <= constants.MAX_WHEELBASE
end

local function positiveInteger(value: any): integer | nil
    if type(value) == "number"
        and (value as number) >= 1.0
        and (value as number) < math.huge
        and (value as number) == math.floor(value as number)
    then
        return value as integer
    end
    return nil
end

local function denseArraySize(value: DynamicTable): integer | nil
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number"
            or (key as number) < 1.0
            or (key as number) ~= math.floor(key as number)
        then
            return nil
        end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then
            return nil
        end
    end
    return count
end

local function clamp(value: number, minimum: number, maximum: number): number
    if value ~= value or value <= minimum then
        return minimum
    elseif value >= maximum then
        return maximum
    end
    return value
end

local module: SwayingWaying.Values = {
    asTable = dynamicTable,
    clamp = clamp,
    asArray = dynamicArray,
    nodeSuffix = safeNodeSuffix,
    nonnegative = validLag,
    wheelbase = validWheelbase,
    positiveInteger = positiveInteger,
    arraySize = denseArraySize,
}
return module
