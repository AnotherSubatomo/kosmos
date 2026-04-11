
--!strict
--!optimize 2
--!native

local VIEW_WIDTH = 320
local VIEW_HEIGHT = 240
local VIEW_SIZE = Vector2.new(VIEW_WIDTH, VIEW_HEIGHT)

local kosmos = require(script.kosmos)(VIEW_WIDTH, VIEW_HEIGHT)
local pengar_mesh = require(script.pengar)
local cube_mesh = require(script.cube)

local pengar = kosmos.mesh(pengar_mesh)
local cube = kosmos.mesh(cube_mesh)

local obj1 = kosmos.object(pengar)
kosmos.setObjectPosition(obj1, vector.create(0.625, 0, 1))

local obj2 = kosmos.object(cube)
kosmos.setObjectPosition(obj2, vector.create(-0.625, 0, 1))

local IMAGE = kosmos.getImageBuffer()

local yaw = 0

local function FRAME(delta: number): (buffer)
	yaw += delta * 0.5
	kosmos.rotateCamera(math.sin(yaw))
	 
	-- Clear the image buffer
	kosmos.clear()

	kosmos.render()	
	return IMAGE
end

return {
	width = VIEW_WIDTH,
	height = VIEW_HEIGHT,
	size = VIEW_SIZE,
	frame = FRAME
}