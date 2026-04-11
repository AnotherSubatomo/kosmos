
-- kosmos: A toy 3D renderer

--!strict
--!optimize 2
--!native

export type mesh = {vertices: {vector}, faces: {{number}}}
export type object = {
	mesh_id: number,
	position: vector,
	right: vector,
	up: vector,
	forward: vector,
	render: boolean,
}

local DEFAULT_RIGHT = vector.create(-1, 0, 0)
local DEFAULT_UP = vector.create(0, 1, 0)
local DEFAULT_FORWARD = vector.create(0, 0, 1)

local ERR_OBJ_DOESNT_EXIST = "Tried to change a property of a non-existant object."

return function (width: number, height: number)
	local VIEW_WIDTH = width
	local VIEW_HEIGHT = height
	local INV_ASPECT_RATIO = VIEW_HEIGHT / VIEW_WIDTH

	local IMAGE_ROW_OFFSET = 4 * VIEW_WIDTH
	local IMAGE_MEMSIZE = IMAGE_ROW_OFFSET * VIEW_HEIGHT
	local IMAGE = buffer.create(IMAGE_MEMSIZE)

	local CAMERA_DIRTY = false

	local function CLEAR(): ()
		buffer.fill(IMAGE, 0, 255)
	end
	
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

	local function project_to_screen(v: vector): (number, number)
		local z = v.z
		local px = (v.x/z) * SCALE
		local py = (v.y/z) * SCALE

		return 
			((px + 1) * 0.5 * (VIEW_WIDTH  - 1)) // 1,
			((1 - (py + 1) * 0.5) * (VIEW_HEIGHT - 1)) // 1
	end

	-- Liang-Barsky line clipping algorithm
	-- * `true` when invisible; point coordinates are rounded
	local function clip_line(x0: number, y0: number, x1: number, y1: number): (boolean, number, number, number, number)
		local dx = x1 - x0
		local dy = y1 - y0

		local t0 = 0
		local t1 = 1

		local function not_clip(p: number, q: number): (boolean)
			if p == 0 then -- Parallel and outside
				return q < 0
			end

			local r = q / p

			if p < 0 then
				if r > t1 then return true end -- Entering and outside
				if r > t0 then t0 = r end -- Update entering t
			else
				if r < t0 then return true end -- Leaving and outside
				if r < t1 then t1 = r end -- Update exiting t
			end

			return false
		end

		-- Check if line is out of the left, right, top, & bottom lines respectively
		if not_clip(-dx, x0) then return true, 0, 0, 0, 0 end
		if not_clip( dx, VIEW_WIDTH - 1 - x0) then return true, 0, 0, 0, 0 end
		if not_clip(-dy, y0) then return true, 0, 0, 0, 0 end
		if not_clip( dy, VIEW_HEIGHT - 1 - y0) then return true, 0, 0, 0, 0 end

		-- Apply clipping
		if t1 < 1 then
			x1 = (x0 + t1 * dx + 0.5) // 1
			y1 = (y0 + t1 * dy + 0.5) // 1
		end

		if t0 > 0 then
			x0 = (x0 + t0 * dx + 0.5) // 1
			y0 = (y0 + t0 * dy + 0.5) // 1
		end

		return false, x0, y0, x1, y1
	end

	-- Bresenham's line algorithm
	local function line(x0: number, y0: number, x1: number, y1: number): ()
		local is_invisible = false

		is_invisible, x0, y0, x1, y1 = clip_line(x0, y0, x1, y1)
		if is_invisible then return end

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
			buffer.writeu32(IMAGE, index, 0xfff055f0)

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

	local function transform(vertices: {vector}, transforms: {vector}, object: object): ()
		-- * commented since they're implicitly overwritten, though
		--   when it makes more sense, I might uncomment this...
		--table.clear(transforms)

		local position = object.position
		local right = object.right
		local up = object.up
		local forward = object.forward

		for i, v in vertices do
			local rot_v = vector.create(
				vector.dot(v, right),
				vector.dot(v, up),
				vector.dot(v, forward)
			)
			local pos_v = rot_v + position - POSITION
			local cam_v = vector.create(
				vector.dot(pos_v, RIGHT),
				vector.dot(pos_v, UP),
				vector.dot(pos_v, FORWARD)
			)

			transforms[i] = cam_v
		end
	end

	local NEAR = 0.01

	-- Near plane clipping algorithm
	-- * `true` when line is to be kept
	local function clip_near(a: vector, b: vector): (boolean, vector, vector)
		local az, bz = a.z, b.z
		-- Fully behind --> reject
		if az < NEAR and bz < NEAR then
			return false, a, b
		end

		-- Only clip if needed
		if az < NEAR or bz < NEAR then
			local t = (NEAR - az) / (bz - az)
			local ax, bx = a.x, b.x
			local ay, by = a.y, b.y

			if az < NEAR then
				-- Move A --> intersection
				local new_ax = ax + (bx - ax) * t
				local new_ay = ay + (by - ay) * t
				a = vector.create(new_ax, new_ay, NEAR)
			else
				-- Move B --> intersection
				local new_bx = bx + (ax - bx) * t
				local new_by = by + (ay - by) * t
				b = vector.create(new_bx, new_by, NEAR)
			end
		end

		return true, a, b
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
				local a = transforms[face[1] + 1]
				local b = transforms[face[2] + 1]
				local c = transforms[face[3] + 1]

				-- Backface culling (skip hidden faces)
				local ab = b - a
				local ac = c - a
				local normal = vector.cross(ab, ac)

				if vector.dot(normal, a) >= 0 then continue end

				local ax, ay
				local bx, by
				local cx, cy

				local accept_i = false
				accept_i, a, b = clip_near(a, b)

				local accept_j = false
				accept_j, b, c = clip_near(b, c)

				local accept_k = false
				accept_k, c, a = clip_near(c, a)

				if accept_i or accept_k then
					ax, ay = project_to_screen(a)
				end

				if accept_i or accept_j then
					bx, by = project_to_screen(b)
				end

				if accept_j or accept_k then
					cx, cy = project_to_screen(c)
				end

				if accept_i then line(ax, ay, bx, by) end
				if accept_j then line(bx, by, cx, cy) end
				if accept_k then line(cx, cy, ax, ay) end
			end
		end

		CAMERA_DIRTY = false
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

		render = RENDER;
		getImageBuffer = GET_IMAGE_BUFFER;
		
		dump = DUMP;
	}
end