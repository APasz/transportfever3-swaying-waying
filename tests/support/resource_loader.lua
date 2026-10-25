local function new(roots, ownRequire)
	local loaded, loading = {}, {}
	local function resolve(name, importer)
		local namespace, relative = name:match("^(.-)::/?(.*)$")
		if not namespace then
			namespace = importer:match("^(.-)::")
			relative = name:sub(1, 1) == "/" and name:sub(2) or ((importer:match("::/(.*/)") or "") .. name)
		end
		local parts = {}
		for part in relative:gmatch("[^/]+") do
			if part == ".." then
				assert(#parts > 0, "Resource escapes its namespace: " .. name)
				table.remove(parts)
			elseif part ~= "." then
				parts[#parts + 1] = part
			end
		end
		return namespace, table.concat(parts, "/")
	end
	local function resourceRequire(name, importer)
		if name:match("^apasz_swaying_waying::") then
			return ownRequire(name)
		end
		local namespace, relative = resolve(name, importer or "::/")
		local key = namespace .. "::/" .. relative
		if loaded[key] ~= nil then
			return loaded[key]
		end
		assert(not loading[key], "Cyclic resource import: " .. key)
		local root = assert(
			roots[namespace],
			"Missing resource namespace '" .. namespace .. "'; supply its mod with --dependency"
		)
		local path = root .. "/" .. relative
		local function relativeRequire(dependency)
			return resourceRequire(dependency, key)
		end
		local environment = setmetatable({ require = relativeRequire, ug_require = relativeRequire }, { __index = _G })
		local chunk, message = loadfile(path, "t", environment)
		if not chunk and relative:match("%.tl$") then
			local file = io.open(path)
			if file then
				local source = file:read("*a")
				file:close()
				local available, teal = pcall(require, "tl")
				assert(available, "Reading " .. key .. " requires Teal; install tl or set LUA_PATH to its modules")
				local generated = teal.gen(source)
				assert(generated, "Could not compile Teal resource: " .. key)
				chunk, message = load(generated, "@" .. path, "t", environment)
			end
		end
		assert(chunk, message)
		loading[key] = true
		local succeeded, result = pcall(function()
			local value = chunk()
			if value == nil and type(rawget(environment, "data")) == "function" then
				return environment.data()
			end
			return value
		end)
		loading[key] = nil
		assert(succeeded, result)
		loaded[key] = result
		return result
	end
	return resourceRequire
end
return { new = new }
