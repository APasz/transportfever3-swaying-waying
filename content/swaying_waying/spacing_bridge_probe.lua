local function disabled(_entity)
	error("Spacing bridge probe disabled: updating missing custom state causes a fatal engine assertion", 0)
end

local module = {
	test = disabled,
	clear = disabled,
}

return module
