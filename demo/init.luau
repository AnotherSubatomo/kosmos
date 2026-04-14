
--!strict
--!optimize 2
--!native

local VIEW_WIDTH = 320
local VIEW_HEIGHT = 240

local kosmos = require("./kosmos")(VIEW_WIDTH, VIEW_HEIGHT)
local pengar_mesh = require("./demo/pengar")
local cube_mesh = require("./demo/cube")

local pengar = kosmos.mesh(pengar_mesh)
local cube = kosmos.mesh(cube_mesh)

local obj1 = kosmos.object(pengar)
kosmos.setObjectPosition(obj1, vector.create(0.625, 0, 1))
kosmos.setObjectRotation(obj1, math.pi, 0, 0)

local obj2 = kosmos.object(cube)
kosmos.setObjectPosition(obj2, vector.create(-0.625, 0, 1))

local IMAGE = kosmos.getImageBuffer()

local yaw = 0

local function FRAME(delta: number): (buffer)
	yaw += delta * 0.5
	local angle = math.cos(yaw)
	kosmos.setObjectRotation(obj1, yaw, 0, angle)
	kosmos.setObjectRotation(obj2, yaw, 0, angle)
	kosmos.positionCamera(vector.create(angle/2, 0, 0))
	 
	-- Clear the image buffer
	kosmos.clear()

	kosmos.render()	
	return IMAGE
end

return {
	width = VIEW_WIDTH,
	height = VIEW_HEIGHT,
	frame = FRAME
}