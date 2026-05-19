--!strict
--!optimize 2
--!native

local abs = math.abs
local cos = math.cos
local sin = math.sin
local writeu8 = buffer.writeu8

local TWO_PI = math.pi * 2

local BASE_BRIGHTNESS = 0.5
local BASE_TINT = vector.create(0.55, 0.8, 0.35)

local SCALE = 12
local WARP = 0.16
local BLADES = 10
local BLADE_INTENSITY = 0.25
local MACRO_SCALE = 4
local MACRO_STRENGTH = 0.15

-- Fast deterministic hash -> [0,1)
local function hash(x: number, y: number): (number)
	local n = x * 127.1 + y * 311.7
	return n - n // 1
end

local function grass(x: number, y: number, resolution: number): (vector)
	local wx = x * SCALE
	local wy = y * SCALE

	local n1 = hash(wx, wy)
	local n2 = hash(wx + 19.7, wy + 27.3)

	x += (n1 - 0.5) * WARP
	y += (n2 - 0.5) * WARP

	-- secondary macro warp (separate from blade warp)
	local mx = x
	local my = y

	local mn1 = hash(mx * 6.3, my * 6.3)
	local mn2 = hash(mx * 6.3 + 17.2, my * 6.3 + 9.4)

	mx += (mn1 - 0.5) * 0.08
	my += (mn2 - 0.5) * 0.08

	local macro = hash(mx * MACRO_SCALE, my * MACRO_SCALE) * MACRO_STRENGTH

	local gx = x * resolution * SCALE
	local gy = y * resolution * SCALE

	local ix = gx // 1
	local iy = gy // 1

	local fx = gx - ix - 0.5
	local fy = gy - iy - 0.5

	local h = hash(ix, iy) * TWO_PI
	local rx = cos(h)
	local ry = sin(h)

	local d = abs(fx * ry - fy * rx)

	local blade = 1 - d * BLADES
	if blade > 0 then
		blade = blade * blade
	else
		blade = 0
	end

	local g = BASE_BRIGHTNESS + macro + blade * BLADE_INTENSITY

	return BASE_TINT * g
end

local function generate_grass_texture(resolution: number)
	local image = buffer.create(resolution * resolution * 4)

	local inv = 1 / (resolution - 1)
	local i = 0

	for y = 0, resolution - 1 do
		local v = y * inv

		for x = 0, resolution - 1 do
			local u = x * inv

			local c = grass(u, v, resolution)

			writeu8(image, i,     (c.x * 255) // 1)
			writeu8(image, i + 1, (c.y * 255) // 1)
			writeu8(image, i + 2, (c.z * 255) // 1)
			writeu8(image, i + 3, 255)

			i += 4
		end
	end

	return {
		width = resolution,
		height = resolution,
		data = image
	}
end

return generate_grass_texture(192)