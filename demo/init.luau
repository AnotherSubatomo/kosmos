
--!strict
--!optimize 2
--!native

-- Renderer constants
local VIEW_WIDTH = 320
local VIEW_HEIGHT = 240

-- Require assets
local kosmos = require("./kosmos")(VIEW_WIDTH, VIEW_HEIGHT)
local obj_parser = require("./tool/obj_parser")
local heightmap_maker = require("./demo/heightmap")
local skybox_maker = require("./demo/skybox")

local pengar_mesh = obj_parser(script.meshes["penger.obj"].Value)
local cube_mesh = obj_parser(script.meshes["cube.obj"].Value)
local heightmap_mesh = heightmap_maker(25, 1, 0.25, 200, 20, 2)

local cat_texture = require("./demo/textures/cat")
local cobble_texture = require("./demo/textures/cobble")
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
local heightmap = kosmos.mesh(heightmap_mesh)

local cat = kosmos.texture(cat_texture)
local cobble = kosmos.texture(cobble_texture)
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

local obj3 = kosmos.object(heightmap, cobble)
kosmos.setObjectPosition(obj3, vector.create(-10, -1, -10))

kosmos.setSkyboxTextures(
	skybox_front, skybox_back,
	skybox_left, skybox_right,
	skybox_top, skybox_bottom
)

-- Prepare renderer runtime
local IMAGE = kosmos.getImageBuffer()

local SPEED = 4
local SENSITIVITY = 0.5
local OBJ_ROT_SPEED = 0.5

local camera_position = vector.zero
local camera_yaw, camera_pitch = 0, 0

local move_direction = vector.zero
local mouse_delta = vector.zero
local obj_rot = 0

local budget_consumed_percentage = 0

local function FRAME(delta: number): (buffer)
	camera_yaw += mouse_delta.x * SENSITIVITY * delta
	camera_pitch += mouse_delta.y * SENSITIVITY * delta
	kosmos.setCameraRotation(camera_yaw, camera_pitch)

	local right, up, forward = kosmos.getCameraBasis()
	local movement =
		forward * move_direction.z -
		right   * move_direction.x +
		up      * move_direction.y

	camera_position += movement * SPEED * delta
	kosmos.setCameraPosition(camera_position)

	obj_rot += OBJ_ROT_SPEED * delta
	local cos_obj_rot = math.cos(obj_rot)
	kosmos.setObjectRotation(obj1, obj_rot, 0, cos_obj_rot)
	kosmos.setObjectRotation(obj2, obj_rot, 0, cos_obj_rot)

	local start_tick = os.clock()
	kosmos.clear()
	kosmos.render()
	local end_tick = os.clock()
	budget_consumed_percentage = ((end_tick - start_tick) / delta) * 100

	return IMAGE
end

local function INPUT(new_mouse_delta: vector, new_move_direction: vector): ()
	move_direction = new_move_direction
	mouse_delta = new_mouse_delta
end

local function GET_FRAME_BUDGET_CONSUMED(): (number)
	return budget_consumed_percentage
end

return {
	width = VIEW_WIDTH,
	height = VIEW_HEIGHT,
	frame = FRAME,
	input = INPUT,
	get_frame_budget_consumed = GET_FRAME_BUDGET_CONSUMED, 
}