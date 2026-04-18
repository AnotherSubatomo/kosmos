
--!strict
--!optimize 2
--!native

local VIEW_WIDTH = 320
local VIEW_HEIGHT = 240

local kosmos = require("./kosmos")(VIEW_WIDTH, VIEW_HEIGHT)
local pengar_mesh = require("./demo/meshes/penger")
local cube_mesh = require("./demo/meshes/cube")
local diamond_plate_texture = require("./demo/textures/diamond_plate")
local skybox_texture = require("./demo/textures/skybox")

local diamond_plate = kosmos.texture(diamond_plate_texture)
local skybox = kosmos.texture(skybox_texture)
local pengar = kosmos.mesh(pengar_mesh)
local cube = kosmos.mesh(cube_mesh)

local obj1 = kosmos.object(pengar, diamond_plate)
kosmos.setObjectPosition(obj1, vector.create(0.625, 0, 1))
kosmos.setObjectRotation(obj1, math.pi, 0, 0)

local obj2 = kosmos.object(cube, diamond_plate)
kosmos.setObjectPosition(obj2, vector.create(-0.625, 0, 1))

kosmos.setSkyboxTextures(skybox, skybox, skybox, skybox, skybox, skybox)

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
	camera_yaw -= mouse_delta.x * SENSITIVITY * delta
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
	budget_consumed_percentage = (end_tick - start_tick) * 6000

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