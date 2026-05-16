
-- Physics-based skybox generator.
-- SPDX-License-Identifier: CC0-1.0

--!strict
--!optimize 2
--!native

export type texture = {
	width: number,
	height: number,
	data: buffer
}

-- Coordinate system
local WORLD_RIGHT = vector.create(1, 0, 0)
local WORLD_UP = vector.create(0, 1, 0)

-- Sun
local SUN_DIRECTION = vector.normalize(vector.create(0.6, 0.35, 0.7))
local SUN_COLOR = vector.create(1.0, 0.95, 0.85)

-- Sky
local SKY_ZENITH = vector.create(0.25, 0.45, 1.0)
local SKY_HORIZON = vector.create(0.85, 0.9, 1.0)
local ZENITH_DISTANCE = SKY_ZENITH - SKY_HORIZON

-- Noise
local FBM_OCTAVES = 4
local FBM_LACUNARITY = 2
local FBM_PERSISTENCE = 0.5

-- Clouds
local CLOUD_HEIGHT = 1000
local CLOUD_SCALE = 0.002
local CLOUD_COLOR = vector.create(1, 1, 1)
local CLOUD_SHARPNESS = 1 / 0.8 -- the latter is the "cloud density" factor
local CLOUD_THRESHOLD = 1.0 - 0.8 -- the latter is the "cloud coverage" factor
local CLOUD_WARP_STRENGTH = 2.0
local CLOUD_HORIZON_FADE_START = 0.02
local CLOUD_HORIZON_FADE_END = 0.08

-- Cloud erosion
local CLOUD_EROSION = 0.25
local CLOUD_EROSION_SCALE = 8

-- Clouds lighting
local CLOUD_AMBIENT_LIGHT = 0.55
local CLOUD_DIRECT_LIGHT = 0.45
local CLOUD_SUN_TINT_STRENGTH = 0.5
local CLOUD_LIGHTING_EPSILON = 0.03

local SUN_DIRECTION_EPSILON = SUN_DIRECTION * CLOUD_LIGHTING_EPSILON

-- Sun rendering
local SUN_GLOW_POWER = 32
local SUN_DISK_POWER = 16
local SUN_MIE_INTENSITY = 0.35
local SUN_DISK_INTENSITY = 8

-- * Should be inlined by the compiler.
local function saturate(x: number): (number)
	return math.clamp(x, 0, 1)
end

-- * Should be inlined by the compiler.
local function fade(t: number): (number)
	return t * t * (3 - 2 * t)
end

-- * Should be inlined by the compiler.
local function smoothstep(a: number, b: number, x: number): (number)
	local t = saturate((x - a) / (b - a))
	return fade(t)
end

-- Maps 0-1 floating point RGB representations to discrete 0-255 integers.
-- * Should be inlined by the compiler.
local function norm_to_u8_rgb(norm_rgb_vector: vector): (number, number, number)
	local u8_rgb_vector = (norm_rgb_vector * 255) // 1
	return u8_rgb_vector.x, u8_rgb_vector.y, u8_rgb_vector.z
end

-- Hash function for noise generation.
local function hash(x: number, z: number): (number)
	local n = x * 157 + z * 313
	n = math.sin(n) * 43758.5453
	return n - n // 1
end

-- Simple hash noise.
local function noise2(x: number, z: number): (number)
	local xi = x // 1
	local zi = z // 1

	local xf = fade(x - xi)
	local zf = fade(z - zi)

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

local function fbm(x: number, z: number): (number)
	local value = 0
	local amplitude = 0.5
	local frequency = 1
	local amplitude_sum = 0

	for _ = 1, FBM_OCTAVES do
		value += noise2(x * frequency, z * frequency) * amplitude
		amplitude_sum += amplitude

		frequency *= FBM_LACUNARITY
		amplitude *= FBM_PERSISTENCE
	end

	return value / amplitude_sum
end

-- Calculates the 2D coordinates to be used by cloud sampling functions.
local function cloud_noise_uv(direction: vector): (number, number)
	-- project ray into cloud layer
	local distance = CLOUD_HEIGHT / direction.y
	local p = direction * distance
	-- world-space cloud coordinates
	local nx = p.x * CLOUD_SCALE
	local nz = p.z * CLOUD_SCALE
	-- layered noise + domain warping
	local cloud_warp_x = fbm(nx, nz)
	local cloud_warp_z = fbm(nx + 4.2, nz + 7.3)

	nx += (cloud_warp_x - 0.5) * CLOUD_WARP_STRENGTH
	nz += (cloud_warp_z - 0.5) * CLOUD_WARP_STRENGTH

	return nx, nz
end

-- Cloud density calculator.
local function sample_clouds(dy: number, nx: number, nz: number): (number)
	-- base cloud density
	local base = fbm(nx, nz)
	-- cloud erosion
	local erosion = fbm(nx * CLOUD_EROSION_SCALE, nz * CLOUD_EROSION_SCALE)
	base -= erosion * CLOUD_EROSION
	-- puffier clouds
	local density = smoothstep(CLOUD_THRESHOLD, CLOUD_THRESHOLD + 0.5, base)
	density = math.pow(density, CLOUD_SHARPNESS)
	-- soften horizon
	local cloud = density * smoothstep(CLOUD_HORIZON_FADE_START, CLOUD_HORIZON_FADE_END, dy)
	return cloud
end

-- Calculate the directional cloud lighting coefficient, faked using a density gradient.
local function sample_cloud_lighting(nx: number, nz: number): (number)
	return fbm(nx + SUN_DIRECTION_EPSILON.x, nz + SUN_DIRECTION_EPSILON.z)
end

-- Calculates the sky color with a sun and clouds that respects sunlight.
local function physics_based_sky_color(dir: vector): (vector)
	-- Normalize once
	dir = vector.normalize(dir)

	-- Sky gradient (Rayleigh-ish approximation)
	local t = saturate(dir.y * 0.5 + 0.5)
	local bare_sky = SKY_HORIZON + ZENITH_DISTANCE * t * t

	-- Sun factor
	local sun_dot = math.max(vector.dot(dir, SUN_DIRECTION), 0)
	-- Sun glow (broad halo)
	local sun_glow = math.pow(sun_dot, SUN_GLOW_POWER)
	-- Sharpen sun disk
	local sun_disk = math.pow(sun_glow, SUN_DISK_POWER)
	-- Mie scattering (horizon glow around sun)
	local mie = sun_glow * SUN_MIE_INTENSITY
	local sun_sky = bare_sky + SUN_COLOR * (sun_disk * SUN_DISK_INTENSITY + mie)
	
	local final_sky = sun_sky

	-- below horizon = no clouds
	local y = dir.y

	if y > 0.001 then
		-- Clouds (very cheap, animated via direction only)
		local nx, nz = cloud_noise_uv(dir)
		local cloud_density = sample_clouds(y, nx, nz)
		local cloud_light = sample_cloud_lighting(nx, nz)
		-- Light clouds by sun angle
		local direct = cloud_light * CLOUD_DIRECT_LIGHT
		local lighting = CLOUD_AMBIENT_LIGHT + direct
		local sun_tint = vector.one + (SUN_COLOR - vector.one) * cloud_light * CLOUD_SUN_TINT_STRENGTH
		local lit_cloud = CLOUD_COLOR * lighting * sun_tint

		final_sky = sun_sky + (lit_cloud - sun_sky) * cloud_density
	end

	return vector.clamp(final_sky, vector.zero, vector.one)
end

-- Sets the global coordinate system's basis, which the face generator depends on.
local function SET_GLOBAL_BASIS(right: vector?, up: vector?): ()
	if typeof(right) == "vector" then SUN_DIRECTION = right end
	if typeof(up) == "vector" then SUN_DIRECTION = up end
end

-- Sets the sun's direction (the direction vector is expected to already be normalized).
local function SET_SUN_DIRECTION(direction: vector?): ()
	if typeof(direction) == "vector" then SUN_DIRECTION = direction end
end

-- Sets the sun's color.
local function SET_SUN_COLOR(color: vector?): ()
	if typeof(color) == "vector" then SUN_COLOR = color end
end

-- Sets the height where clouds should virtually be at.
local function SET_CLOUD_HEIGHT(height: number?): ()
	if typeof(height) == "number" then CLOUD_HEIGHT = height end
end

-- Sets the scale of the clouds.
local function SET_CLOUD_SCALE(scale: number?): ()
	if typeof(scale) == "number" then CLOUD_SCALE = scale end
end

-- Sets the color of the clouds.
local function SET_CLOUD_COLOR(color: vector?): ()
	if typeof(color) == "vector" then CLOUD_COLOR = color end
end

-- Sets the degree that dictates how much of the sky should clouds cover.
local function SET_CLOUD_COVERAGE(coverage: number?): ()
	if typeof(coverage) == "number" then CLOUD_THRESHOLD = 1 - saturate(coverage) end
end

-- Sets the degree that dictates how "full" the cloud feels.
local function SET_CLOUD_DENSITY(density: number?): ()
	if typeof(density) == "number" then CLOUD_SHARPNESS = 1 / density end
end

-- Generates a side of a cubemap given a forward vector, representing the side's normal.
local function GENERATE_FACE(resolution: number, forward: vector): (texture)
	local image = buffer.create(resolution * resolution * 4)
	local offset = resolution - 1
	local row_stride = 0

	local up_reference = WORLD_UP
	forward = vector.normalize(forward)

	-- Prevent degeneracy
	if math.abs(vector.dot(forward, up_reference)) > 0.999 then
		up_reference = WORLD_RIGHT
	end

	local right = vector.normalize(vector.cross(up_reference, forward))
	local up = vector.normalize(vector.cross(forward, right))

	for y = 0, offset do
		-- Construct signed UV
		local v = (y / offset) * 2 - 1

		for x = 0, offset do
			local u = (x / offset) * 2 - 1

			-- +Z face mapping (forward)
			local direction = forward + right * u + up * v
			local sky = physics_based_sky_color(direction)
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

return {
	set_global_basis = SET_GLOBAL_BASIS,
	set_sun_direction = SET_SUN_DIRECTION,
	set_sun_color = SET_SUN_COLOR,

	set_cloud_height = SET_CLOUD_HEIGHT,
	set_cloud_scale = SET_CLOUD_SCALE,
	set_cloud_color = SET_CLOUD_COLOR,
	set_cloud_coverage = SET_CLOUD_COVERAGE,
	set_cloud_density = SET_CLOUD_DENSITY,

	generate_face = GENERATE_FACE,
}