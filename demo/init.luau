
--!strict
--!optimize 2
--!native

-- Renderer constants
local VIEW_WIDTH = 320
local VIEW_HEIGHT = 240

-- Demo constants
local SPEED = 8
local SENSITIVITY = 0.5

local CHUNKING_TICK_RATE = 1/4

local CHUNK_RENDER_RADIUS = 6
local CHUNK_TILES = 8
local CHUNK_SIZE = 8

local chunk_render_square = CHUNK_RENDER_RADIUS * CHUNK_RENDER_RADIUS

-- Require assets
local kosmos = require("./src")(VIEW_WIDTH, VIEW_HEIGHT)
local obj_parser = require("./tool/obj_parser")
local skybox_maker = require("./demo/skybox")

local chunk = require("./demo/chunk")
chunk.set_chunk_configs(CHUNK_TILES, CHUNK_SIZE / CHUNK_TILES, 0.25)
chunk.set_noise_configs(400, 20, 6, 4, 2, 0.5)

local pengar_mesh = obj_parser(require("./demo/meshes/penger"))
local cube_mesh = obj_parser(require("./demo/meshes/cube"))
local cat_texture = require("./demo/textures/cat")
local grass_texture = require("./demo/textures/grass")
local diamond_plate_texture = require("./demo/textures/diamond_plate")

local skybox_resolution_low = 128
local skybox_resolution_high = 192
local skybox_front_texture = skybox_maker.generate_face(skybox_resolution_high, vector.create(0, 0, 1))
local skybox_back_texture = skybox_maker.generate_face(skybox_resolution_high, vector.create(0, 0, -1))
local skybox_left_texture = skybox_maker.generate_face(skybox_resolution_high, vector.create(1, 0, 0))
local skybox_right_texture = skybox_maker.generate_face(skybox_resolution_high, vector.create(-1, 0, 0))
local skybox_top_texture = skybox_maker.generate_face(skybox_resolution_low, vector.create(0, 1, 0))
local skybox_bottom_texture = skybox_maker.generate_face(skybox_resolution_low, vector.create(0, -1, 0))

-- Register assets
local pengar = kosmos.mesh(pengar_mesh)
local cube = kosmos.mesh(cube_mesh)

local cat = kosmos.texture(cat_texture)
local grass = kosmos.texture(grass_texture)
local diamond_plate = kosmos.texture(diamond_plate_texture)

local skybox_front = kosmos.texture(skybox_front_texture)
local skybox_back = kosmos.texture(skybox_back_texture)
local skybox_left = kosmos.texture(skybox_left_texture)
local skybox_right = kosmos.texture(skybox_right_texture)
local skybox_top = kosmos.texture(skybox_top_texture)
local skybox_bottom = kosmos.texture(skybox_bottom_texture)

-- Instantiate objects & set-up the scene
local obj1 = kosmos.object(pengar, diamond_plate)
kosmos.setObjectPosition(obj1, vector.create(-0.625, 0, 1))
kosmos.setObjectRotation(obj1, math.pi, 0, 0)

local obj2 = kosmos.object(cube, cat)
kosmos.setObjectPosition(obj2, vector.create(0.625, 0, 1))

kosmos.setSkyboxTextures(
	skybox_front, skybox_back,
	skybox_left, skybox_right,
	skybox_top, skybox_bottom
)

-- Prepare renderer runtime
local IMAGE = kosmos.getImageBuffer()
local OBJ_ROT_SPEED = 0.5

local CAMERA_POSITION = vector.zero
local CAMERA_YAW, CAMERA_PITCH = 0, 0

local MOVE_DIRECTION = vector.zero
local MOUSE_DELTA = vector.zero
local OBJ_ROT = 0

local BUDGET_CONSUMED_PERCENT = 0

local function sync_input_events(delta: number): ()
	CAMERA_YAW += MOUSE_DELTA.x * SENSITIVITY * delta
	CAMERA_PITCH += MOUSE_DELTA.y * SENSITIVITY * delta
	kosmos.setCameraRotation(CAMERA_YAW, CAMERA_PITCH)

	local right, up, forward = kosmos.getCameraBasis()
	local movement =
		forward * MOVE_DIRECTION.z -
		right   * MOVE_DIRECTION.x +
		up      * MOVE_DIRECTION.y

	CAMERA_POSITION += movement * SPEED * delta
	kosmos.setCameraPosition(CAMERA_POSITION)
end

local function sync_object_events(delta: number): ()
	OBJ_ROT += OBJ_ROT_SPEED * delta
	local cos_obj_rot = math.cos(OBJ_ROT)
	kosmos.setObjectRotation(obj1, OBJ_ROT, 0, cos_obj_rot)
	kosmos.setObjectRotation(obj2, OBJ_ROT, 0, cos_obj_rot)
end

local chunking_rate_debounce = 0

local CHUNK_COORDS: {[vector]: number} = {}

-- The following three tables grow the same size together.
local N_CHUNK_GENERATED = 0
local CHUNK_RAW_MESHES: {chunk.raw_mesh} = {} -- Raw meshes from `chunk.generate()`
local CHUNK_MESH_IDS: {number} = {} -- IDs registered from `kosmos.mesh()`
local CHUNK_OBJECT_IDS: {number} = {} -- IDs registered from `kosmos.object()`

local FREE_CHUNK_INDEX_POOL: {number} = {} -- index that point to the mesh, mesh ID, and object ID of a freed chunk

local function sync_chunks(delta: number): ()
	chunking_rate_debounce += delta

	-- If it's not the right tick to sync, then skip
	if chunking_rate_debounce < CHUNKING_TICK_RATE then return end

	-- Find the center chunk coordinates
	local center_chunk_x = CAMERA_POSITION.x // CHUNK_SIZE
	local center_chunk_z = CAMERA_POSITION.z // CHUNK_SIZE

	-- De-commission chunks that are outside the render radius
	for chunk_coord in CHUNK_COORDS do
		local dx = chunk_coord.x - center_chunk_x
		local dz = chunk_coord.z - center_chunk_z

		-- * enforce euclidian distance
		if dx*dx + dz*dz > chunk_render_square then
			local chunk_index = CHUNK_COORDS[chunk_coord]
			table.insert(FREE_CHUNK_INDEX_POOL, chunk_index)

			CHUNK_COORDS[chunk_coord] = nil
		end
	end

	-- Retain or re-commission chunks that are within the render radius 
	for dz = -CHUNK_RENDER_RADIUS, CHUNK_RENDER_RADIUS do
		local chunk_z = dz + center_chunk_z

		for dx = -CHUNK_RENDER_RADIUS, CHUNK_RENDER_RADIUS do
			local chunk_x = dx + center_chunk_x

			-- * enforce euclidian distance
			if dx*dx + dz*dz > chunk_render_square then continue end

			local chunk_coord = vector.create(chunk_x, 0, chunk_z)

			-- * already exists, retain
			if CHUNK_COORDS[chunk_coord] then continue end

			-- * re-commission a free chunk!
			local chunk_index = table.remove(FREE_CHUNK_INDEX_POOL) :: number

			-- * `chunk_index` being nil means the pool is exhausted,
			--   which means there are fresh meshes to be generated,
			--   which is either caused by initialization, or a change
			--   to `CHUNK_RENDER_RADIUS` to something larger, in runtime.
			if chunk_index == nil then
				N_CHUNK_GENERATED += 1

				local chunk_raw_mesh = chunk.generate()
				local chunk_mesh_id = kosmos.mesh(chunk_raw_mesh)
				chunk_index = N_CHUNK_GENERATED

				CHUNK_RAW_MESHES[chunk_index] = chunk_raw_mesh
				CHUNK_MESH_IDS[chunk_index] = chunk_mesh_id
				CHUNK_OBJECT_IDS[chunk_index] = kosmos.object(chunk_mesh_id, grass)
			end

			local chunk_raw_mesh = CHUNK_RAW_MESHES[chunk_index]
			local chunk_mesh_id = CHUNK_MESH_IDS[chunk_index]
			local chunk_object_id = CHUNK_OBJECT_IDS[chunk_index]

			chunk.set_chunk_data(chunk_raw_mesh, chunk_x, chunk_z)
			kosmos.recomputeMeshBounds(chunk_mesh_id)
			kosmos.setObjectPosition(chunk_object_id, chunk_coord * CHUNK_SIZE)

			CHUNK_COORDS[chunk_coord] = chunk_index
		end
	end

	chunking_rate_debounce = 0
end

local function FRAME(delta: number): (buffer)
	sync_input_events(delta)
	sync_object_events(delta)
	sync_chunks(delta)

	local start_tick = os.clock()
	kosmos.clear()
	kosmos.render()
	local end_tick = os.clock()

	BUDGET_CONSUMED_PERCENT = ((end_tick - start_tick) / delta) * 100

	return IMAGE
end

local function INPUT(new_mouse_delta: vector, new_move_direction: vector): ()
	MOVE_DIRECTION = new_move_direction
	MOUSE_DELTA = new_mouse_delta
end

local function GET_FRAME_BUDGET_CONSUMED(): (number)
	return BUDGET_CONSUMED_PERCENT
end

return {
	width = VIEW_WIDTH,
	height = VIEW_HEIGHT,
	frame = FRAME,
	input = INPUT,
	get_frame_budget_consumed = GET_FRAME_BUDGET_CONSUMED, 
}