
-- Most logic is derived from https://github.com/tsoding/formula
-- * The greatest graphics programming video is attached in that repository btw

--!strict
--!optimize 2
--!native

--local kosmos = require(script.kosmos)
local pengar = require(script.pengar)

local CANVAS_WIDTH = 320
local CANVAS_HEIGHT = 240
local CANVAS_SIZE = Vector2.new(CANVAS_WIDTH, CANVAS_HEIGHT)

local IMAGE_ROW_OFFSET = 4 * CANVAS_WIDTH
local IMAGE_MEMSIZE = IMAGE_ROW_OFFSET * CANVAS_HEIGHT
local IMAGE = buffer.create(IMAGE_MEMSIZE)

local function texel_to_offset(x: number, y: number): (number)
	return y * IMAGE_ROW_OFFSET + x * 4
end

local function clear(): ()
	buffer.fill(IMAGE, 0, 255)
end

local function point(x: number, y: number): ()
	buffer.writeu32(IMAGE, texel_to_offset(x, y), 0xfff055f0)
end

-- Liang-Barsky line clipping algorithm (`true` when invisible)
local function clip_line(x0: number, y0: number, x1: number, y1: number): (boolean, number, number, number, number)
	local dx = x1 - x0
	local dy = y1 - y0

	local t0 = 0
	local t1 = 1

	local function clip(p: number, q: number): (boolean)
		if p == 0 then
			return q >= 0 -- parallel: accept only if inside
		end

		local r = q / p

		if p < 0 then
			if r > t1 then return false end
			if r > t0 then t0 = r end
		else
			if r < t0 then return false end
			if r < t1 then t1 = r end
		end

		return true
	end

	-- Left, Right, Top, Bottom
	if not clip(-dx, x0) then return true, 0, 0, 0, 0 end
	if not clip( dx, CANVAS_WIDTH - 1 - x0) then return true, 0, 0, 0, 0 end
	if not clip(-dy, y0) then return true, 0, 0, 0, 0 end
	if not clip( dy, CANVAS_HEIGHT - 1 - y0) then return true, 0, 0, 0, 0 end

	-- Apply clipping
	if t1 < 1 then
		x1 = x0 + t1 * dx
		y1 = y0 + t1 * dy
	end

	if t0 > 0 then
		x0 = x0 + t0 * dx
		y0 = y0 + t0 * dy
	end

	return false, x0, y0, x1, y1
end

-- Bresenham's line algorithm
local function line(x0: number, y0: number, x1: number, y1: number): ()
	local dx = math.abs(x1 - x0)
	local dy = math.abs(y1 - y0)

	local sxPixel = (x0 < x1) and 1 or -1
	local syPixel = (y0 < y1) and 1 or -1

	local sxByte = sxPixel * 4
	local syByte = syPixel * IMAGE_ROW_OFFSET

	local err = dx - dy

	local xByte = x0 * 4
	local yOffset = y0 * IMAGE_ROW_OFFSET

	while true do
		local index = yOffset + xByte
		if index >= 0 and index < IMAGE_MEMSIZE then
			buffer.writeu32(IMAGE, index, 0xfff055f0)
		end

		if x0 == x1 and y0 == y1 then break end

		local e2 = err + err

		if e2 > -dy then
			err = err - dy
			x0 = x0 + sxPixel
			xByte = xByte + sxByte
		end

		if e2 < dx then
			err = err + dx
			y0 = y0 + syPixel
			yOffset = yOffset + syByte
		end
	end
end

local function project_to_screen(vec: vector): (number, number)
	local z = vec.z
	local px = vec.x/z
	local py = vec.y/z
	return 
		((px + 1) * 0.5 * (CANVAS_WIDTH  - 1)) // 1,
		((1 - (py + 1) * 0.5) * (CANVAS_HEIGHT - 1)) // 1
end

local function translate_z(vec: vector, dz: number): (vector)
	return vector.create(vec.x, vec.y, vec.z + dz)
end

local function rotate_xz(vec: vector, angle: number): (vector)
	local c = math.cos(angle)
	local s = math.sin(angle)
	local x = vec.x
	local z = vec.z
	return vector.create(x*c-z*s, vec.y, x*s+z*c)
end

local DZ = 1
local ANGLE = 0

export type object = {vertices: {vector}, faces: {{number}}}

local function draw_object(object: object): ()
	local vertices = object.vertices
	local faces = object.faces

	for _, face in faces do
		local n_face_vertices = #face
		for i = 1, n_face_vertices do
			local a = vertices[face[i] + 1]
			local b = vertices[face[i % n_face_vertices + 1] + 1]
			local ax, ay = project_to_screen(translate_z(rotate_xz(a, ANGLE), DZ))
			local bx, by = project_to_screen(translate_z(rotate_xz(b, ANGLE), DZ))
			line(ax, ay, bx, by)
		end
	end
end

local function FRAME(delta: number): (buffer)
	ANGLE += math.pi * delta

	-- Clear the image buffer
	clear()

	-- Draw the object on the buffer
	draw_object(pengar)
	
	return IMAGE
end

return {
	width = CANVAS_WIDTH,
	height = CANVAS_HEIGHT,
	size = CANVAS_SIZE,
	frame = FRAME
}