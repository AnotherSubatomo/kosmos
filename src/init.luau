
--[=[
	kosmos - Platform-agnostic 3D renderer written in Luau
	Author: @AnotherSubatomo (GitHub)
	SPDX-License-Identifier: MPL-2.0
]=]

--[=[
	SUPPLEMENTARY INFORMATION ABOUT THE IMPLEMENTATION
	==================================================

	# Vertex winding order: counter-clockwise = front-facing

	# Currently, the rendering pipeline looks like this:
	meshdata -> world transforms -> camera transforms ->
	culling -> clipping -> rasterization -> output image

	# Depth interpolation conventions:
		This renderer operates in camera space where:
		z = forward distance from the camera (linear in 3D space)

		During rasterization, we use:
		w = 1 / z

		Reason:
		Perspective projection (x/z, y/z) makes attributes non-linear in screen space.
		However, 1/z varies linearly across the screen, so we interpolate w instead of z.

		Notes for experienced readers:
		- This "w" is NOT clip-space homogeneous w from a full graphics pipeline.
		- It is simply the reciprocal of camera-space z.
		- The depth buffer stores w (i.e., a w-buffer), not z.
		- Depth test uses: larger w = closer pixel.

		This matches the behavior of perspective-correct interpolation used in GPUs,
		without implementing a full homogeneous clip-space pipeline.
]=]

--!strict
--!optimize 2
--!native

export type mesh = {
	vertices: {vector},
	uvs: {vector},
	faces: {vector}
}

export type texture = {
	width: number,
	height: number,
	data: buffer
}

export type object = {
	mesh_id: number,
	texture_id: number,
	position: vector,
	right: vector,
	up: vector,
	forward: vector,
}

local NEAR = 0.01
local NO_TEXTURE_ID = 0xffff

local DEFAULT_RIGHT = vector.create(-1, 0, 0)
local DEFAULT_UP = vector.create(0, 1, 0)
local DEFAULT_FORWARD = vector.create(0, 0, 1)

local ERR_OBJ_DOESNT_EXIST = "Tried to change a property of a non-existant object."

local SBv1 = vector.create(2048, 2048, 2048)
local SBv2 = vector.create(-2048, 2048, 2048)
local SBv3 = vector.create(-2048, -2048, 2048)
local SBv4 = vector.create(2048, -2048, 2048)
local SBv5 = vector.create(2048, 2048, -2048)
local SBv6 = vector.create(-2048, 2048, -2048)
local SBv7 = vector.create(-2048, -2048, -2048)
local SBv8 = vector.create(2048, -2048, -2048)

local SBt11 = vector.create(1, 1)
local SBt01 = vector.create(0, 1)
local SBt00 = vector.create(0, 0)
local SBt10 = vector.create(1, 0)

local DEFAULT_SKYBOX_TEXTURES = {
	NO_TEXTURE_ID,
	NO_TEXTURE_ID,
	NO_TEXTURE_ID,
	NO_TEXTURE_ID,
	NO_TEXTURE_ID,
	NO_TEXTURE_ID,
}
local SKYBOX_VERTICES = {
	SBv1, SBv2, SBv3, SBv4, -- Front
	SBv5, SBv6, SBv7, SBv8, -- Back
	SBv2, SBv6, SBv7, SBv3, -- Left
	SBv1, SBv5, SBv8, SBv4, -- Right
	SBv1, SBv2, SBv6, SBv5, -- Top
	SBv4, SBv3, SBv7, SBv8, -- Bottom
}
local SKYBOX_UVS = {
	SBt11, SBt01, SBt00, SBt10, -- Front
	SBt11, SBt01, SBt00, SBt10, -- Back
	SBt11, SBt01, SBt00, SBt10, -- Left
	SBt11, SBt01, SBt00, SBt10, -- Right
	SBt11, SBt01, SBt00, SBt10, -- Top
	SBt11, SBt01, SBt00, SBt10, -- Bottom
}
local SKYBOX_FACES = {
	{1, 2, 3, 4}, -- Front
	{5, 6, 7, 8}, -- Back
	{9, 10, 11, 12}, -- Left
	{13, 14, 15, 16}, -- Right
	{17, 18, 19, 20}, -- Top
	{21, 22, 23, 24}, -- Bottom
}

local function intersect(a: vector, auv: vector, b: vector, buv: vector): (vector, vector)
	local ax, ay, az = a.x, a.y, a.z
	local dz = b.z - az
	if dz == 0 then
		return vector.create(ax, ay, NEAR), auv
	else
		local t = (NEAR - az) / dz
		return vector.create(
			ax + (b.x - ax) * t,
			ay + (b.y - ay) * t,
			NEAR
		), vector.lerp(auv, buv, t)
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

	local AMBIENT = 0.4 -- base light (0–1)
	local LIGHT_DIR = vector.normalize(vector.one)

	local SKYBOX_TEXTURES = table.clone(DEFAULT_SKYBOX_TEXTURES)
	local SKYBOX_TRANSFORMS = table.create(24)

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

	-- Recomputes the orthogonal bases according to the euler rotations given.
	local function calculate_basis(yaw: number, pitch: number, roll: number): (vector, vector, vector)
		local cy = math.cos(yaw)
		local sy = math.sin(yaw)
		local cp = math.cos(pitch)
		local sp = math.sin(pitch)

		local forward = vector.create(sy * cp, -sp, cy * cp)

		local right = vector.normalize(vector.cross(forward, WORLD_UP))

		-- Recompute up to ensure orthogonality
		local up = vector.normalize(vector.cross(right, forward))

		-- Apply roll (rotate right/up around forward)
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

	local function GET_CAMERA_BASIS(): (vector, vector, vector)
		return RIGHT, UP, FORWARD
	end

	local function SET_CAMERA_POSITION(position: vector?): ()
		if not position or position == POSITION then return end
		POSITION = position
		CAMERA_DIRTY = true
	end

	local function SET_CAMERA_ROTATION(yaw: number?, pitch: number?, roll: number?, world_up: vector?): ()
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

	local function SET_LIGHTING_AMBIENT(ambient: number): ()
		if not ambient or ambient == AMBIENT then return end
		AMBIENT = ambient
	end

	local function SET_LIGHTING_DIRECTION(direction: vector): ()
		if not direction or direction == LIGHT_DIR then return end
		LIGHT_DIR = vector.normalize(direction)
	end

	local function SET_SKYBOX_TEXTURES(
		front_id: number?, back_id: number?,
		left_id: number?, right_id: number?,
		top_id: number?, bottom_id: number?
	): ()
		if front_id  and front_id  ~= SKYBOX_TEXTURES[1] then SKYBOX_TEXTURES[1] = front_id  end	
		if back_id   and back_id   ~= SKYBOX_TEXTURES[2] then SKYBOX_TEXTURES[2] = back_id   end
		if left_id   and left_id   ~= SKYBOX_TEXTURES[3] then SKYBOX_TEXTURES[3] = left_id   end
		if right_id  and right_id  ~= SKYBOX_TEXTURES[4] then SKYBOX_TEXTURES[4] = right_id  end
		if top_id    and top_id    ~= SKYBOX_TEXTURES[5] then SKYBOX_TEXTURES[5] = top_id    end
		if bottom_id and bottom_id ~= SKYBOX_TEXTURES[6] then SKYBOX_TEXTURES[6] = bottom_id end
	end

	-- Projects the vertex into screen space. (the unmodified `z` is also returned)
	local function project_to_screen(v: vector): (number, number, number)
		local z = v.z
		local px = (v.x/z) * SCALE
		local py = (v.y/z) * SCALE

		return 
			((px + 1) * 0.5 * (WIDTH_M_1)) // 1,
			((1 - (py + 1) * 0.5) * (HEIGHT_M_1)) // 1,
			z
	end

	-- Transforms the set of vertices into world + camera space.
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

	local CV1, CV2, CV3, CV4, CV5, CV6
	local CT1, CT2, CT3, CT4, CT5, CT6

	-- Clips triangles near the camera plane into y-monotone triangle/s. (or none, where the triangle gets skipped)
	local function clip_triangle(a: vector, b: vector, c: vector, at: vector, bt: vector, ct: vector): (number)
		local ai = a.z >= NEAR
		local bi = b.z >= NEAR
		local ci = c.z >= NEAR

		local count = (ai and 1 or 0) + (bi and 1 or 0) + (ci and 1 or 0)

		-- Fully inside
		if count == 3 then
			CV1, CV2, CV3 = a, b, c
			CT1, CT2, CT3 = at, bt, ct
			return 1
		end

		-- Fully outside
		if count == 0 then
			return 0
		end

		-- 1 inside --> 1 triangle
		if count == 1 then
			local inV, outV1, outV2
			local inT, outT1, outT2

			if ai then
				inV, outV1, outV2 = a, b, c
				inT, outT1, outT2 = at, bt, ct
			elseif bi then
				inV, outV1, outV2 = b, c, a
				inT, outT1, outT2 = bt, ct, at
			else
				inV, outV1, outV2 = c, a, b
				inT, outT1, outT2 = ct, at, bt
			end

			CV1, CT1 = inV, inT
			CV2, CT2 = intersect(inV, inT, outV1, outT1)
			CV3, CT3 = intersect(inV, inT, outV2, outT2)

			return 1
		end

		-- 2 inside --> quad --> 2 triangles
		local outV, inV1, inV2
		local outT, inT1, inT2

		if not ai then
			outV, inV1, inV2 = a, b, c
			outT, inT1, inT2 = at, bt, ct
		elseif not bi then
			outV, inV1, inV2 = b, c, a
			outT, inT1, inT2 = bt, ct, at
		else
			outV, inV1, inV2 = c, a, b
			outT, inT1, inT2 = ct, at, bt
		end

		local iV1, iT1 = intersect(inV1, inT1, outV, outT)
		local iV2, iT2 = intersect(inV2, inT2, outV, outT)

		-- First triangle
		CV1, CV2, CV3 = inV1, inV2, iV1
		CT1, CT2, CT3 = inT1, inT2, iT1

		-- Second triangle
		CV4, CV5, CV6 = inV2, iV2, iV1
		CT4, CT5, CT6 = inT2, iT2, iT1

		return 2
	end

	-- Rasterizes a triangle.
	local function draw_triangle(
		a: vector, b: vector, c: vector,
		at: vector, bt: vector, ct: vector,
		tw: number, th: number, trs: number, td: buffer,
		shade_factor: number
	): ()
		-- Screen-space projection
		local ax, ay, az = project_to_screen(a)
		local bx, by, bz = project_to_screen(b)
		local cx, cy, cz = project_to_screen(c)

		-- Sort vertices (along with their UV) by ascending Y [c (bottom) -> b -> a (top)]
		if ay > by then ax, ay, az, at, bx, by, bz, bt = bx, by, bz, bt, ax, ay, az, at end
		if ay > cy then ax, ay, az, at, cx, cy, cz, ct = cx, cy, cz, ct, ax, ay, az, at end
		if by > cy then bx, by, bz, bt, cx, cy, cz, ct = cx, cy, cz, ct, bx, by, bz, bt end

		-- Reject degenerate triangle
		if ay == cy then return end

		-- Precompute vertical distances for interpolation along triangle edges
		local dy_ab = by - ay
		local dy_ac = cy - ay
		local dy_bc = cy - by

		-- Compute reciprocal depth (w = 1/z) for perspective-correct interpolation
		local aw = 1/az
		local bw = 1/bz
		local cw = 1/cz

		-- Pre-multiply UVs by `w` so they interpolate linearly in screen space
		local auw = at.x * aw
		local avw = at.y * aw

		local buw = bt.x * bw
		local bvw = bt.y * bw

		local cuw = ct.x * cw
		local cvw = ct.y * cw

		-- Calculate slopes for incremental interpolation
		-- Edge slopes:
		local m_ab, m_ac, m_bc = 0, 0, 0
		-- Depth slopes:
		local mw_ab, mw_ac, mw_bc = 0, 0, 0
		-- UV slopes:
		local muw_ab, mvw_ab = 0, 0
		local muw_ac, mvw_ac = 0, 0
		local muw_bc, mvw_bc = 0, 0

		-- (the if statements guard against division by zero for flat edges)
		if dy_ab ~= 0 then
			m_ab = (bx - ax) / dy_ab
			mw_ab = (bw - aw) / dy_ab
			muw_ab = (buw - auw) / dy_ab
			mvw_ab = (bvw - avw) / dy_ab
		end

		if dy_ac ~= 0 then
			m_ac = (cx - ax) / dy_ac
			mw_ac = (cw - aw) / dy_ac
			muw_ac = (cuw - auw) / dy_ac
			mvw_ac = (cvw - avw) / dy_ac
		end

		if dy_bc ~= 0 then
			m_bc = (cx - bx) / dy_bc
			mw_bc = (cw - bw) / dy_bc
			muw_bc = (cuw - buw) / dy_bc
			mvw_bc = (cvw - bvw) / dy_bc
		end

		-- Discretize to get scan bounds
		local y_start = ay // 1
		local y_end   = cy // 1

		-- Ensure correct ordering after discretization
		if y_start > y_end then y_start, y_end = y_end, y_start end

		-- Clamp to viewport height (prevents OOB buffer errors)
		y_start = math.max(0, y_start)
		y_end   = math.min(HEIGHT_M_1, y_end)

		-- Split the triangle!
		local y_middle = by // 1

		-- Clamp to scan bounds
		if y_middle < y_start then y_middle = y_start end
		if y_middle > y_end   then y_middle = y_end   end

		-- Precompute row offset into image buffer
		local row_stride = y_start * IMAGE_ROW_OFFSET

		-- Rasterize the top half of triangle (a --> b)
		for y = y_start, y_middle - 1 do
			-- Compute the general blend factor
			local lt = (y - ay)
			local rt = (y - ay)

			-- Compute left/right X positions of the scanline
			local lx = ax + lt * m_ab
			local rx = ax + rt * m_ac

			-- Interpolate depth along edges
			local lw = aw + lt * mw_ab
			local rw = aw + rt * mw_ac

			-- Interpolate UV along edges
			local luw = auw + lt * muw_ab
			local ruw = auw + rt * muw_ac

			local lvw = avw + lt * mvw_ab
			local rvw = avw + rt * mvw_ac

			-- Ensure left-to-right ordering
			if lx > rx then
				lx, rx = rx, lx
				lw, rw = rw, lw
				luw, ruw = ruw, luw
				lvw, rvw = rvw, lvw
			end

			-- Clamp horizontal span to screen bounds
			local x_start = math.max(0, (lx + 0.5) // 1)
			local x_end   = math.min(WIDTH_M_1, rx // 1)
			local offset  = row_stride + x_start * 4

			-- Compute per-pixel slopes across scanline
			local dx_lr = rx - lx
			local m_wx, m_uwx, m_vwx = 0, 0, 0

			if dx_lr ~= 0 then
				m_wx = (rw - lw) / dx_lr
				m_uwx = (ruw - luw) / dx_lr
				m_vwx = (rvw - lvw) / dx_lr
			end

			-- Adjust starting values (prevents distortion)
			local dx = x_start - lx
			local w = lw + dx * m_wx
			local uw = luw + dx * m_uwx
			local vw = lvw + dx * m_vwx

			-- Fill pixels across scanline
			for _ = x_start, x_end do
				if w > buffer.readf32(Z, offset) then
					-- Recover perspective-correct UVs
					local inv_w = 1 / w
					local u = math.clamp(uw * inv_w, 0, 1)
					local v = math.clamp(vw * inv_w, 0, 1)

					-- Map to texture
					local s = (u * tw) // 1
					local t = (v * th) // 1
					local texture_color = buffer.readu32(td, t * trs + s * 4)

					-- Blend the texture to the shading
					local rb = bit32.band(texture_color, 0x00FF00FF) * shade_factor
					local g = bit32.band(texture_color, 0x0000FF00) * shade_factor

					rb = bit32.band(bit32.rshift(rb, 8), 0x00FF00FF)
					g = bit32.band(bit32.rshift(g, 8), 0x0000FF00)

					local color = 0xFF000000 + rb + g

					-- Gradient debug pattern for UV
					-- local s = (u * 255) // 1
					-- local t = (v * 255) // 1
					-- local color = texture_id * 0x10000 + t * 0x100 + s * 0x1

					buffer.writeu32(IMAGE, offset, color)
					buffer.writef32(Z, offset, w)
				end

				-- Step interpolants (& byte offset) across X
				w += m_wx
				uw += m_uwx
				vw += m_vwx
				offset += 4
			end

			row_stride += IMAGE_ROW_OFFSET
		end

		-- Adjust the split if discretization misses the true middle scanline
		local y_middle_adj = y_middle + (y_middle < by and 1 or 0)

		-- Rasterize bottom half of triangle (b --> c)
		for y = y_middle_adj, y_end do
			-- Compute the general blend factor
			local lt = (y - by)
			local rt = (y - ay)

			-- Compute left/right X positions of the scanline
			local lx = bx + lt * m_bc
			local rx = ax + rt * m_ac

			-- Interpolate depth along edges
			local lw = bw + lt * mw_bc
			local rw = aw + rt * mw_ac

			-- Interpolate UV along edges
			local luw = buw + lt * muw_bc
			local ruw = auw + rt * muw_ac

			local lvw = bvw + lt * mvw_bc
			local rvw = avw + rt * mvw_ac

			-- Ensure left-to-right ordering
			if lx > rx then
				lx, rx = rx, lx
				lw, rw = rw, lw
				luw, ruw = ruw, luw
				lvw, rvw = rvw, lvw
			end

			-- Clamp horizontal span to screen bounds
			local x_start = math.max(0, (lx + 0.5) // 1)
			local x_end   = math.min(WIDTH_M_1, rx // 1)
			local offset  = row_stride + x_start * 4

			-- Compute per-pixel slopes across scanline
			local dx_lr = rx - lx
			local m_wx, m_uwx, m_vwx = 0, 0, 0

			if dx_lr ~= 0 then
				m_wx = (rw - lw) / dx_lr
				m_uwx = (ruw - luw) / dx_lr
				m_vwx = (rvw - lvw) / dx_lr
			end

			-- Adjust starting values (prevents distortion)
			local dx = x_start - lx
			local w = lw + dx * m_wx
			local uw = luw + dx * m_uwx
			local vw = lvw + dx * m_vwx

			-- Fill pixels across scanline
			for _ = x_start, x_end do
				if w > buffer.readf32(Z, offset) then
					-- Recover perspective-correct UVs
					local inv_w = 1 / w
					local u = math.clamp(uw * inv_w, 0, 1)
					local v = math.clamp(vw * inv_w, 0, 1)

					-- Map to texture
					local s = (u * tw) // 1
					local t = (v * th) // 1
					local texture_color = buffer.readu32(td, t * trs + s * 4)

					-- Blend the texture to the shading
					local rb = bit32.band(texture_color, 0x00FF00FF) * shade_factor
					local g = bit32.band(texture_color, 0x0000FF00) * shade_factor

					rb = bit32.band(bit32.rshift(rb, 8), 0x00FF00FF)
					g = bit32.band(bit32.rshift(g, 8), 0x0000FF00)

					local color = 0xFF000000 + rb + g

					-- Gradient debug pattern for UV
					-- local s = (u * 255) // 1
					-- local t = (v * 255) // 1
					-- local color = texture_id * 0x10000 + t * 0x100 + s * 0x1

					buffer.writeu32(IMAGE, offset, color)
					buffer.writef32(Z, offset, w)
				end

				-- Step interpolants (& byte offset) across X
				w += m_wx
				uw += m_uwx
				vw += m_vwx
				offset += 4
			end

			row_stride += IMAGE_ROW_OFFSET
		end
	end

	local MESHES: {mesh} = table.create(4)
	local TEXTURES: {texture} = table.create(4)
	local OBJECTS: {object} = table.create(16)
	local OBJECTS_CHANGED: {boolean} = table.create(16)
	local OBJECT_TRANSFORMS: {{vector}} = table.create(16)

	local function MESH(mesh: mesh): (number)
		table.insert(MESHES, mesh)
		return #MESHES
	end

	local function TEXTURE(texture: texture): (number)
		table.insert(TEXTURES, texture)
		return #TEXTURES
	end

	local function OBJECT(mesh_id: number, texture_id: number?): (number)
		if not MESHES[mesh_id] then
			error "Tried to create an object for a non-existant mesh."
		end

		local object_id = #OBJECTS + 1

		local object = {
			mesh_id = mesh_id,
			texture_id = texture_id or NO_TEXTURE_ID,
			position = vector.zero,
			right = DEFAULT_RIGHT,
			up = DEFAULT_UP,
			forward = DEFAULT_FORWARD,
		}

		OBJECTS[object_id] = object
		OBJECTS_CHANGED[object_id] = false

		-- Create draw entry *once*
		local mesh = MESHES[mesh_id]
		OBJECT_TRANSFORMS[object_id] = table.create(#mesh.vertices)

		return object_id
	end

	local function SET_OBJECT_MESH(object_id: number, mesh_id: number): ()
		local object = OBJECTS[object_id]
		if not object then error(ERR_OBJ_DOESNT_EXIST) end
		object.mesh_id = mesh_id
		OBJECTS_CHANGED[object_id] = true
	end

	local function SET_OBJECT_TEXTURE(object_id: number, texture_id: number): ()
		local object = OBJECTS[object_id]
		if not object then error(ERR_OBJ_DOESNT_EXIST) end
		object.texture_id = texture_id
		OBJECTS_CHANGED[object_id] = true
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

	local function RENDER(): ()
		-- Transform light direction
		local light_direction = vector.create(
			vector.dot(LIGHT_DIR, RIGHT),
			vector.dot(LIGHT_DIR, UP),
			vector.dot(LIGHT_DIR, FORWARD)
		)

		-- Render objects
		for object_id, object in OBJECTS do
			local texture_id = object.texture_id
			if texture_id == NO_TEXTURE_ID then continue end

			local mesh = MESHES[object.mesh_id]
			local transforms = OBJECT_TRANSFORMS[object_id]

			-- Resolve necessary transforms
			if CAMERA_DIRTY or OBJECTS_CHANGED[object_id] then
				local vertices = mesh.vertices
				transform(vertices, transforms, object)
				OBJECTS_CHANGED[object_id] = false
			end

			local faces = mesh.faces
			local uvs = mesh.uvs
			local texture = TEXTURES[texture_id]

			local tw = texture.width - 1
			local th = texture.height - 1
			local trs = texture.width * 4
			local td = texture.data

			-- Actual render
			for _, face in faces do
				local ai = face.x
				local bi = face.y
				local ci = face.z

				local a = transforms[ai]
				local b = transforms[bi]
				local c = transforms[ci]

				-- Backface culling
				local ab = b - a
				local ac = c - a
				local normal = vector.cross(ab, ac)

				if vector.dot(normal, a) >= 0 then continue end

				local at = uvs[ai]
				local bt = uvs[bi]
				local ct = uvs[ci]

				-- Near plane triangle clipping
				local tri_count = clip_triangle(a, b, c, at, bt, ct)
				if tri_count == 0 then continue end
				
				-- Rasterizing and shading
				local NdotL = math.max(0, vector.dot(vector.normalize(normal), light_direction))
				local intensity = AMBIENT + (1 - AMBIENT) * NdotL
				local shade_factor = intensity * 255 // 1

				if tri_count == 1 then
					draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, shade_factor)
				elseif tri_count == 2 then
					draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, shade_factor)
					draw_triangle(CV4, CV5, CV6, CT4, CT5, CT6, tw, th, trs, td, shade_factor)
				end
			end
		end

		-- Transform skybox
		for i, v in SKYBOX_VERTICES do
			-- Position the skybox at the camera
			local pos_v = v - POSITION

			-- Camera-space transformation
			local cam_v = vector.create(
				vector.dot(pos_v, RIGHT),
				vector.dot(pos_v, UP),
				vector.dot(pos_v, FORWARD)
			)

			SKYBOX_TRANSFORMS[i] = cam_v
		end

		-- Render skybox
		for index, face in SKYBOX_FACES do
			local texture_id = SKYBOX_TEXTURES[index]
			if texture_id == NO_TEXTURE_ID then continue end

			local texture = TEXTURES[texture_id]
			local tw = texture.width - 1
			local th = texture.height - 1
			local trs = texture.width * 4
			local td = texture.data

			local ai = face[1]
			local bi = face[2]
			local ci = face[3]
			local di = face[4]

			local a = SKYBOX_TRANSFORMS[ai]
			local b = SKYBOX_TRANSFORMS[bi]
			local c = SKYBOX_TRANSFORMS[ci]
			local d = SKYBOX_TRANSFORMS[di]

			local at = SKYBOX_UVS[ai]
			local bt = SKYBOX_UVS[bi]
			local ct = SKYBOX_UVS[ci]
			local dt = SKYBOX_UVS[di]

			local tri_count = 0

			-- Triangle one:
			tri_count = clip_triangle(a, c, b, at, ct, bt)
			if tri_count == 1 then
				draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, 255)
			elseif tri_count == 2 then
				draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, 255)
				draw_triangle(CV4, CV5, CV6, CT4, CT5, CT6, tw, th, trs, td, 255)
			end

			-- Triangle two:
			tri_count = clip_triangle(a, d, c, at, dt, ct)
			if tri_count == 1 then
				draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, 255)
			elseif tri_count == 2 then
				draw_triangle(CV1, CV2, CV3, CT1, CT2, CT3, tw, th, trs, td, 255)
				draw_triangle(CV4, CV5, CV6, CT4, CT5, CT6, tw, th, trs, td, 255)
			end
		end
	
		CAMERA_DIRTY = false
	end

	local function CLEAR(): ()
		buffer.fill(Z, 0, 0)
		buffer.fill(IMAGE, 0, 255)
	end

	local function GET_IMAGE_BUFFER(): (buffer)
		return IMAGE
	end

	return {
		mesh = MESH;
		texture = TEXTURE;
		object = OBJECT;

		setObjectMesh = SET_OBJECT_MESH;
		setObjectTexture = SET_OBJECT_TEXTURE;
		setObjectPosition = SET_OBJECT_POSITION;
		setObjectRotation = SET_OBJECT_ROTATION;

		getCameraBasis = GET_CAMERA_BASIS;
		setCameraPosition = SET_CAMERA_POSITION;
		setCameraRotation = SET_CAMERA_ROTATION;
		setFieldOfView = SET_FIELD_OF_VIEW;

		setLightingAmbient = SET_LIGHTING_AMBIENT;
		setLightingDirection = SET_LIGHTING_DIRECTION;
		setSkyboxTextures = SET_SKYBOX_TEXTURES;

		clear = CLEAR;
		render = RENDER;
		getImageBuffer = GET_IMAGE_BUFFER;
	}
end