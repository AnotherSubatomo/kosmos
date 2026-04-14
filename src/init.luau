
--[=[
	kosmos - Platform-agnostic 3D renderer written in Luau
	Author: @AnotherSubatomo (GitHub)
	SPDX-License-Identifier: MPL-2.0

	* Vertex winding order is "counter-clockwise = front-facing"
]=]

--!strict
--!optimize 2
--!native

export type mesh = {vertices: {vector}, faces: {vector}}
export type object = {
	mesh_id: number,
	position: vector,
	right: vector,
	up: vector,
	forward: vector,
	render: boolean,
}

local NEAR = 0.01

local DEFAULT_RIGHT = vector.create(-1, 0, 0)
local DEFAULT_UP = vector.create(0, 1, 0)
local DEFAULT_FORWARD = vector.create(0, 0, 1)

local ERR_OBJ_DOESNT_EXIST = "Tried to change a property of a non-existant object."

local function intersect__scalar_a(ax: number, ay: number, az: number, b: vector): (vector)
	local dz = b.z - az
	if dz == 0 then
		return vector.create(ax, ay, NEAR)
	else
		local t = (NEAR - az) / dz
		return vector.create(
			ax + (b.x - ax) * t,
			ay + (b.y - ay) * t,
			NEAR
		)
	end
end

local function intersect__scalar_b(a: vector, bx: number, by: number, bz: number): (vector)
	local ax, ay, az = a.x, a.y, a.z
	local dz = bz - az
	if dz == 0 then
		return vector.create(ax, ay, NEAR)
	else
		local t = (NEAR - az) / dz
		return vector.create(
			ax + (bx - ax) * t,
			ay + (by - ay) * t,
			NEAR
		)
	end
end

return function (width: number, height: number)
	local VIEW_WIDTH = width
	local VIEW_HEIGHT = height

	local WIDTH_M_1 = width - 1
	local HEIGHT_M_1 = height - 1
	local INV_ASPECT_RATIO = VIEW_HEIGHT / VIEW_WIDTH

	local IMAGE_ROW_OFFSET = 4 * VIEW_WIDTH
	local IMAGE_MEMSIZE = IMAGE_ROW_OFFSET * VIEW_HEIGHT
	local IMAGE = buffer.create(IMAGE_MEMSIZE)

	local Z = buffer.create(IMAGE_MEMSIZE)
	local Z_CLEAR = buffer.create(IMAGE_MEMSIZE)

	for offset = 0, IMAGE_MEMSIZE - 4, 4 do
		buffer.writeu32(Z_CLEAR, offset, 0x7F800000)
	end

	local LIGHT_DIR = vector.normalize(vector.create(0.3, 1, 0.5))

	local CAMERA_DIRTY = false
	
	-- Camera settings
	local POSITION = vector.zero
	local WORLD_UP = vector.create(0, 1, 0)
	local YAW, PITCH, ROLL = 0, 0, 0
	local FOV = 90

	-- Derived camera settings
	local RIGHT = DEFAULT_RIGHT
	local UP = DEFAULT_UP
	local FORWARD = DEFAULT_FORWARD
	local SCALE = INV_ASPECT_RATIO

	local function clear_z_buffer(): ()
		buffer.copy(Z, 0, Z_CLEAR, 0, IMAGE_MEMSIZE)
	end

	local function calculate_basis(yaw: number, pitch: number, roll: number): (vector, vector, vector)
		local cy = math.cos(yaw)
		local sy = math.sin(yaw)
		local cp = math.cos(pitch)
		local sp = math.sin(pitch)

		local forward = vector.create(sy * cp, -sp, cy * cp)

		-- right = forward * world_up
		local right = vector.normalize(vector.cross(forward, WORLD_UP))

		-- recompute up to ensure orthogonality
		local up = vector.normalize(vector.cross(right, forward))

		-- apply roll (rotate right/up around forward)
		if roll ~= 0 then
			local cr = math.cos(roll)
			local sr = math.sin(roll)

			local r = right * cr + up * sr
			local u = up * cr - right * sr

			right = r
			up = u
		end

		return right, up, forward
	end

	local function POSITION_CAMERA(position: vector?): ()
		if not position or position == POSITION then return end
		POSITION = position
		CAMERA_DIRTY = true
	end

	local function ROTATE_CAMERA(yaw: number?, pitch: number?, roll: number?, world_up: vector?): ()
		if yaw      and yaw      ~= YAW      then YAW      = yaw      end
		if pitch    and pitch    ~= PITCH    then PITCH    = pitch    end
		if roll     and roll     ~= ROLL     then ROLL     = roll     end
		if world_up and world_up ~= WORLD_UP then WORLD_UP = world_up end
		RIGHT, UP, FORWARD = calculate_basis(YAW, PITCH, ROLL)
		CAMERA_DIRTY = true
	end

	local function SET_FIELD_OF_VIEW(fov: number?): ()
		if not fov or fov == FOV then return end
		FOV = fov
		SCALE = (1 / math.tan(math.rad(FOV) * 0.5)) * INV_ASPECT_RATIO
		CAMERA_DIRTY = true
	end

	local function SET_LIGHTING_DIRECTION(direction: vector): ()
		if not direction or direction == LIGHT_DIR then return end
		LIGHT_DIR = direction
		CAMERA_DIRTY = true
	end

	local function project_to_screen(v: vector): (number, number, number)
		local z = v.z
		local px = (v.x/z) * SCALE
		local py = (v.y/z) * SCALE

		return 
			((px + 1) * 0.5 * (WIDTH_M_1)) // 1,
			((1 - (py + 1) * 0.5) * (HEIGHT_M_1)) // 1,
			z
	end

	local function transform(vertices: {vector}, transforms: {vector}, object: object): ()
		-- * commented since they're implicitly overwritten, though
		--   when it makes more sense, I might uncomment this...
		--table.clear(transforms)

		local position = object.position
		local right = object.right
		local up = object.up
		local forward = object.forward

		for i, v in vertices do
			-- World-space transformations: sync rotation & position properties
			local rot_v = vector.create(
				vector.dot(v, right),
				vector.dot(v, up),
				vector.dot(v, forward)
			)
			local pos_v = rot_v + position - POSITION

			-- Camera-space transformation
			local cam_v = vector.create(
				vector.dot(pos_v, RIGHT),
				vector.dot(pos_v, UP),
				vector.dot(pos_v, FORWARD)
			)

			transforms[i] = cam_v
		end
	end

	local C1, C2, C3, C4, C5, C6
	
	local function clip_triangle(a: vector, b: vector, c: vector): (number)
		local ai = a.z >= NEAR
		local bi = b.z >= NEAR
		local ci = c.z >= NEAR

		local count = (ai and 1 or 0) + (bi and 1 or 0) + (ci and 1 or 0)

		-- Fully inside
		if count == 3 then
			C1, C2, C3 = a, b, c
			return 1
		end

		-- Fully outside
		if count == 0 then
			return 0
		end

		-- 1 inside --> 1 triangle
		if count == 1 then
			local inV, out1, out2

			if ai then
				inV, out1, out2 = a, b, c
			elseif bi then
				inV, out1, out2 = b, c, a
			else
				inV, out1, out2 = c, a, b
			end

			local inV_x, inV_y, inV_z = inV.x, inV.y, inV.z

			C1 = inV
			C2 = intersect__scalar_a(inV_x, inV_y, inV_z, out1)
			C3 = intersect__scalar_a(inV_x, inV_y, inV_z, out2)

			return 1
		end

		-- 2 inside --> quad --> 2 triangles
		local in1, in2, outV

		if not ai then
			outV, in1, in2 = a, b, c
		elseif not bi then
			outV, in1, in2 = b, c, a
		else
			outV, in1, in2 = c, a, b
		end

		local outV_x, outV_y, outV_z = outV.x, outV.y, outV.z

		local i1 = intersect__scalar_b(in1, outV_x, outV_y, outV_z)
		local i2 = intersect__scalar_b(in2, outV_x, outV_y, outV_z)

		-- First triangle
		C1, C2, C3 = in1, in2, i1

		-- Second triangle
		C4, C5, C6 = in2, i2, i1

		return 2
	end

	local function draw_triangle(a: vector, b: vector, c: vector, color: number): ()
		-- Projection
		local ax, ay, az = project_to_screen(a)
		local bx, by, bz = project_to_screen(b)
		local cx, cy, cz = project_to_screen(c)

		-- Sort points by Y (a = top, b = mid, c = bottom)
		if ay > by then ax, ay, az, bx, by, bz = bx, by, bz, ax, ay, az end
		if ay > cy then ax, ay, az, cx, cy, cz = cx, cy, cz, ax, ay, az end
		if by > cy then bx, by, bz, cx, cy, cz = cx, cy, cz, bx, by, bz end

		-- Degenerate triangle, return
		if ay == cy then return end

		local dy_ab = by - ay
		local dy_ac = cy - ay
		local dy_bc = cy - by

		-- Calculate slopes for incremental interpolation
		-- Edge slopes for each triangle edge in screen space
		local m_ab = dy_ab == 0 and 0 or (bx - ax) / dy_ab
		local m_ac = dy_ac == 0 and 0 or (cx - ax) / dy_ac
		local m_bc = dy_bc == 0 and 0 or (cx - bx) / dy_bc

		-- Depth slopes
		local mz_ab = dy_ab == 0 and 0 or (bz - az) / dy_ab
		local mz_ac = dy_ac == 0 and 0 or (cz - az) / dy_ac
		local mz_bc = dy_bc == 0 and 0 or (cz - bz) / dy_bc

		-- Discretize to get scan bounds
		local y_start  = ay // 1
		local y_end    = cy // 1

		-- Ensure correct ordering after discretization
		if y_start > y_end then y_start, y_end = y_end, y_start end

		-- Clamp to viewport height
		y_start  = math.max(0, y_start)
		y_end    = math.min(HEIGHT_M_1, y_end)

		-- Split the triangle!
		local y_middle = by // 1

		-- Clamp to scan bounds
		if y_middle < y_start then y_middle = y_start end
		if y_middle > y_end   then y_middle = y_end   end

		local row_stride = y_start * IMAGE_ROW_OFFSET

		-- Start scan loop for the top half...
		for y = y_start, y_middle - 1 do
			local lt = (y - ay)
			local rt = (y - ay)

			local xl = ax + lt * m_ab
			local xr = ax + rt * m_ac

			local zl = az + lt * mz_ab
			local zr = az + rt * mz_ac

			-- Ensure correct ordering
			if xl > xr then
				xl, xr = xr, xl
				zl, zr = zr, zl
			end

			local x_start = math.max(0, xl // 1)
			local x_end   = math.min(WIDTH_M_1, xr // 1)
			local offset  = row_stride + x_start * 4

			local dx_lr = xr - xl
			local m_zx = dx_lr == 0 and 0 or (zr - zl) / dx_lr
			local z = zl

			-- Inner fill loop
			for _ = x_start, x_end do
				if z < buffer.readf32(Z, offset) then
					buffer.writeu32(IMAGE, offset, color)
					buffer.writef32(Z, offset, z)
				end

				z += m_zx
				offset += 4
			end

			row_stride += IMAGE_ROW_OFFSET
		end

		-- Sometimes, discretization pushed `y_middle` below the true split, so we bump it up
		local y_middle_adj = y_middle + (y_middle < by and 1 or 0)

		-- Start scan loop for the bottom half...
		for y = y_middle_adj, y_end do
			local lt = (y - by)
			local rt = (y - ay)

			local xl = bx + lt * m_bc
			local xr = ax + rt * m_ac

			local zl = bz + lt * mz_bc
			local zr = az + rt * mz_ac

			-- Ensure correct ordering
			if xl > xr then
				xl, xr = xr, xl
				zl, zr = zr, zl
			end

			local x_start = math.max(0, xl // 1)
			local x_end   = math.min(WIDTH_M_1, xr // 1)
			local offset  = row_stride + x_start * 4

			local dx_lr = xr - xl
			local m_zx = dx_lr == 0 and 0 or (zr - zl) / dx_lr
			local z = zl

			-- Inner fill loop
			for _ = x_start, x_end do
				if z < buffer.readf32(Z, offset) then
					buffer.writeu32(IMAGE, offset, color)
					buffer.writef32(Z, offset, z)
				end

				z += m_zx
				offset += 4
			end

			row_stride += IMAGE_ROW_OFFSET
		end
	end

	local MESHES: {mesh} = table.create(4)
	local OBJECTS: {object} = table.create(16)
	local OBJECTS_CHANGED: {boolean} = table.create(16)
	local OBJECT_TRANSFORMS: {{vector}} = table.create(16)

	local function MESH(mesh: mesh): (number)
		table.insert(MESHES, mesh)
		return #MESHES
	end

	local function OBJECT(mesh_id: number, render: boolean?): (number)
		if not MESHES[mesh_id] then
			error "Tried to create an object for a non-existant mesh."
		end

		local object_id = #OBJECTS + 1

		local object = {
			mesh_id = mesh_id,
			position = vector.zero,
			right = DEFAULT_RIGHT,
			up = DEFAULT_UP,
			forward = DEFAULT_FORWARD,
			render = render ~= false
		}

		OBJECTS[object_id] = object
		OBJECTS_CHANGED[object_id] = false

		-- Create draw entry *once*
		local mesh = MESHES[mesh_id]
		OBJECT_TRANSFORMS[object_id] = table.create(#mesh.vertices)

		return object_id
	end

	local function SET_OBJECT_POSITION(object_id: number, position: vector): ()
		local object = OBJECTS[object_id]
		if not object then error(ERR_OBJ_DOESNT_EXIST) end
		object.position = position
		OBJECTS_CHANGED[object_id] = true
	end

	local function SET_OBJECT_ROTATION(object_id: number, yaw: number, pitch: number, roll: number): ()
		local object = OBJECTS[object_id]
		if not object then error(ERR_OBJ_DOESNT_EXIST) end
		object.right, object.up, object.forward = calculate_basis(yaw, pitch, roll)
		OBJECTS_CHANGED[object_id] = true
	end

	local function SET_OBJECT_VISIBILITY(object_id: number, is_visible: boolean): ()
		local object = OBJECTS[object_id]
		if not object then error(ERR_OBJ_DOESNT_EXIST) end
		object.render = is_visible
		OBJECTS_CHANGED[object_id] = true
	end

	local function RENDER(): ()
		for object_id, object in OBJECTS do
			if not object.render then continue end

			local mesh = MESHES[object.mesh_id]
			local transforms = OBJECT_TRANSFORMS[object_id]

			-- Resolve necessary transforms
			if CAMERA_DIRTY or OBJECTS_CHANGED[object_id] then
				local vertices = mesh.vertices
				transform(vertices, transforms, object)
				OBJECTS_CHANGED[object_id] = false
			end

			local faces = mesh.faces

			-- Actual render
			for _, face in faces do
				local a = transforms[face.x]
				local b = transforms[face.y]
				local c = transforms[face.z]

				-- Backface culling
				local ab = b - a
				local ac = c - a
				local normal = vector.cross(ab, ac)

				if vector.dot(normal, a) >= 0 then continue end

				-- Near plane triangle clipping
				local tri_count = clip_triangle(a, b, c)
				if tri_count == 0 then continue end
				
				-- Rasterizing and shading 
				local n = vector.normalize(normal)
				local intensity = math.max(0, vector.dot(n, LIGHT_DIR))
				local shade = math.floor(80 + intensity * 175)
				local color = 0xff000000 + (shade * 0x10101)

				if tri_count == 1 then
					draw_triangle(C1, C2, C3, color)
				elseif tri_count == 2 then
					draw_triangle(C1, C2, C3, color)
					draw_triangle(C4, C5, C6, color)
				end
			end
		end

		CAMERA_DIRTY = false
	end

	local function CLEAR(): ()
		clear_z_buffer()
		buffer.fill(IMAGE, 0, 255)
	end

	local function GET_IMAGE_BUFFER(): (buffer)
		return IMAGE
	end

	local function DUMP(): ()
		print(MESHES)
		print(OBJECTS)
		print(OBJECT_TRANSFORMS)
	end

	return {
		clear = CLEAR;
		mesh = MESH;
		object = OBJECT;
		setObjectPosition = SET_OBJECT_POSITION;
		setObjectRotation = SET_OBJECT_ROTATION;
		setObjectVisiblity = SET_OBJECT_VISIBILITY;

		positionCamera = POSITION_CAMERA;
		rotateCamera = ROTATE_CAMERA;
		setFieldOfView = SET_FIELD_OF_VIEW;
		setLightingDirection = SET_LIGHTING_DIRECTION;

		render = RENDER;
		getImageBuffer = GET_IMAGE_BUFFER;
		
		dump = DUMP;
	}
end