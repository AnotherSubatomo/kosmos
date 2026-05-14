
-- Skybox face generator

--!strict
--!optimize 2
--!native

export type texture = {
	width: number,
	height: number,
	data: buffer
}

local WORLD_RIGHT = vector.create(-1, 0, 0)
local WORLD_UP = vector.create(0, 1, 0)

local SUN_DIR = vector.normalize(vector.create(0.6, 0.35, 0.7))
local SUN_COLOR = vector.create(1.0, 0.95, 0.85)

local SKY_ZENITH = vector.create(0.25, 0.45, 1.0)
local SKY_HORIZON = vector.create(0.85, 0.9, 1.0)
local ZENITH_DISTANCE = SKY_ZENITH - SKY_HORIZON

local CLOUD_HEIGHT = 1000
local CLOUD_SCALE = 0.002
local CLOUD_COLOR = vector.one

local function saturate(x: number): (number)
	return math.clamp(x, 0, 1)
end

local function smoothstep(a: number, b: number, x: number): (number)
	x = saturate((x - a) / (b - a))
	return x * x * (3 - 2 * x)
end

-- Maps 0-1 floating point RGB representations to discrete 0-255 integers.
-- * Should be inlined by the compiler.
local function norm_to_u8_rgb(norm_rgb_vector: vector): (number, number, number)
	local u8_rgb_vector = (norm_rgb_vector * 255) // 1
	return u8_rgb_vector.x, u8_rgb_vector.y, u8_rgb_vector.z
end



local function hash(x: number, z: number): (number)
	local n = x * 157 + z * 313
	n = math.sin(n) * 43758.5453
	return n - n // 1
end

local function noise2(x: number, z: number): (number)
	local xi = x // 1
	local zi = z // 1

	local xf = x - xi
	local zf = z - zi

	local xi1 = xi + 1
	local zi1 = zi + 1

	local c00 = hash(xi,  zi)
	local c10 = hash(xi1, zi)
	local c01 = hash(xi,  zi1)
	local c11 = hash(xi1, zi1)

	local x1 = c00 + (c10 - c00) * xf
	local x2 = c01 + (c11 - c01) * xf

	return x1 + (x2 - x1) * zf
end

local function sample_clouds(dir: vector): (number)
	local y = dir.y
	-- below horizon = no clouds
	if y <= 0.001 then return 0 end
	-- project ray into cloud layer
	local distance = CLOUD_HEIGHT / y
	local p = dir * distance
	-- world-space cloud coordinates
	local nx = p.x * CLOUD_SCALE
	local nz = p.z * CLOUD_SCALE
	-- layered noise
	local n1 = noise2(nx, nz)
	local n2 = noise2(nx * 2, nz * 2) * 0.5
	local n3 = noise2(nx * 4, nz * 4) * 0.25
	local cloud = (n1 + n2 + n3) / 1.75
	-- shape clouds
	cloud = saturate((cloud - 0.55) * 3)
	-- soften horizon
	cloud *= smoothstep(0.02, 0.08, y)
	return cloud
end

-- Calculates the sky color as a basic gradient.
local function physics_based_sky_color(dir: vector): (vector)
	-- Normalize once
	dir = vector.normalize(dir)

	-- Sky gradient (Rayleigh-ish approximation)
	local t = saturate(dir.y * 0.5 + 0.5)
	local bare_sky = SKY_HORIZON + ZENITH_DISTANCE * t * t

	-- Sun factor
	local sun_dot = math.max(vector.dot(dir, SUN_DIR), 0)
	-- Sun glow (broad halo)
	local sun_glow = math.pow(sun_dot, 32)
	-- Sharpen sun disk
	local sun_disk = math.pow(sun_glow, 16) -- orginally: math.pow(sun_dot, 512)
	-- Mie scattering (horizon glow around sun)
	local mie = sun_glow * 0.35
	local sun_sky = bare_sky + SUN_COLOR * (sun_disk * 8 + mie)
	
	-- Clouds (very cheap, animated via direction only)
	local cloud = sample_clouds(dir)
	-- Light clouds by sun angle
	local cloud_light = 0.7 + sun_glow * 0.3
	local lit_cloud = CLOUD_COLOR * cloud_light
	local cloud_sky = sun_sky + (lit_cloud - sun_sky) * cloud * 0.85

	return vector.clamp(cloud_sky, vector.zero, vector.one)
end

-- Calculates the sky color as a basic gradient.
local function gradient_sky_color(dir: vector): (vector)
	-- Normalize once
	dir = vector.normalize(dir)
	-- Sky gradient (Rayleigh-ish approximation)
	local t = math.clamp(dir.y * 0.5 + 0.5, 0, 1)
	local sky = SKY_HORIZON + ZENITH_DISTANCE * t
	return sky
end

local sky_color = physics_based_sky_color

-- Generates a side of a cubemap given a forward vector, representing the side's normal.
local function generate_face(resolution: number, forward: vector): (texture)
	local image = buffer.create(resolution * resolution * 4)
	local offset = resolution - 1
	local row_stride = 0

	local up_reference = WORLD_UP
	forward = vector.normalize(forward)

	-- Prevent degeneracy
	if math.abs(vector.dot(forward, up_reference)) > 0.999 then
		up_reference = WORLD_RIGHT
	end

	local right = vector.normalize(vector.cross(forward, up_reference))
	local up = vector.normalize(vector.cross(right, forward))

	for y = 0, offset do
		-- Construct signed UV
		local v = (y / offset) * 2 - 1

		for x = 0, offset do
			local u = (x / offset) * 2 - 1

			-- +Z face mapping (forward)
			local direction = forward + right * u + up * v
			local sky = sky_color(direction)
			local R, G, B = norm_to_u8_rgb(sky)

			local i = (row_stride + x) * 4
			buffer.writeu8(image, i    , R)
			buffer.writeu8(image, i + 1, G)
			buffer.writeu8(image, i + 2, B)
			buffer.writeu8(image, i + 3, 255)
		end

		row_stride += resolution
	end

	return {
		width = resolution,
		height = resolution,
		data = image
	}
end

return generate_face