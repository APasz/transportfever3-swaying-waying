local function new()
	-- Lua 5.2 supplies bit32; newer standalone runtimes supply native operators instead.
	if not bit32 then
		_G.bit32 = assert(load(
			[[
			return {
				band = function(a, b) return (a & b) & 0xffffffff end,
				bxor = function(a, b) return (a ~ b) & 0xffffffff end,
				rshift = function(a, b) return (a & 0xffffffff) >> b end,
			}
		]],
			"bit32 test compatibility"
		))()
	end
	-- The game supplies tanh; standalone Lua 5.3+ omits the hyperbolic functions.
	math.tanh = math.tanh
		or function(value)
			local decay = math.exp(-2 * math.abs(value))
			local result = (1 - decay) / (1 + decay)
			return value < 0 and -result or result
		end
	local harness = { modules = {}, overrides = {}, messages = {}, warnings = {}, verbose = {}, errors = {} }
	-- Keep standalone-only globals out of mod code; model loading in TPF3 omits these.
	local environment = setmetatable({}, {
		__index = function(_, key)
			if key ~= "rawget" and key ~= "rawequal" then
				return _G[key]
			end
		end,
		__newindex = _G,
	})
	_G.log = {
		message = function(message)
			harness.messages[#harness.messages + 1] = message
		end,
		warning = function(message)
			harness.warnings[#harness.warnings + 1] = message
		end,
		verbose = function(message)
			harness.verbose[#harness.verbose + 1] = message
		end,
		error = function(message, details)
			harness.errors[#harness.errors + 1] = { message = message, details = details }
		end,
	}
	harness.overrides["apasz_swaying_waying::/swaying_waying/logging_config.lua"] = false
	harness.overrides["apasz_swaying_waying::/swaying_waying/curvature_probe_config.lua"] = false
	harness.overrides["apasz_swaying_waying::/swaying_waying/lod_probe_config.lua"] = false
	harness.overrides["apasz_swaying_waying::/swaying_waying/motion_config.lua"] = dofile("tests/motion_config.lua")
	function harness.require(name)
		if harness.overrides[name] ~= nil then
			return harness.overrides[name]
		end
		if harness.modules[name] ~= nil then
			return harness.modules[name]
		end
		local relative = name:match("^apasz_swaying_waying::/(.+%.lua)$")
		assert(relative, "Unexpected resource: " .. name)
		local module = assert(loadfile("content/" .. relative, "t", environment))()
		harness.modules[name] = module
		return module
	end
	_G.ug_require = harness.require
	return harness
end

return { new = new }
