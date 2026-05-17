
-- kosmos renderer, for the web
-- * can be ran by running `lute renderer/web`
-- * works by serving the image data through a websocket,
--   NOT by running Luau on the web through a VM nor
--   compiling it to WASM (though, that would be lovely)

--!strict
--!optimize 2
--!native

type JS_InputData = {
	dx: number,
	dy: number,
	right: number,
	up: number,
	forward: number,
}

local json = require("@std/json")
local task = require("@std/task")
local net = require("@lute/net")
local fs = require("@std/fs")

local program = require("../demo")
local frame = program.frame
local input = program.input
local get_frame_budget_consumed = program.get_frame_budget_consumed

local FPS_DELTA = 1/60
local SITE_PORT = 8000
local WEBSOCKET_PORT = 8080

local function on_server_ws_open(ws: net.ServerWebSocket): ()
	print("[Server]: Websocket opened!")

	-- Initially send the set-up data...
	ws:send( json.serialize {
		case = "init",
		width = program.width,
		height = program.height,
	})

	task.wait(1)

	-- ...then, continuously feed the image data.
	while true do
		task.wait(FPS_DELTA)

		local image = frame(FPS_DELTA)
		local budget = get_frame_budget_consumed() * 1000 // 1 / 1000

		ws:send(image)
		ws:send( json.serialize {
			case = "debug",
			budget = budget,
		})
	end
end

local function on_server_ws_message(ws: net.ServerWebSocket, message: string | buffer): ()
	if type(message) == "buffer" then return end
	local input_data = json.deserialize(message) :: JS_InputData

	input(
		vector.create(input_data.dx, input_data.dy),
		vector.create(input_data.right, input_data.up, input_data.forward)
	)
end

local function on_server_ws_close(ws: net.ServerWebSocket, code: number, message: string): ()
	print("[Server]: Websocket closed!")
end

local function handler(request: net.ReceivedRequest, server: net.Server): (net.ServerResponse)
	return fs.readFileToString('./renderer/web/index.html')
end

-- Start the site server
net.server.serve({
	port = SITE_PORT,
	handler = handler,
})

print(`[Server]: Site is now being hosted at {SITE_PORT}!`)

-- Start the server websocket
net.server.serve({
	port = WEBSOCKET_PORT,
	websocket = {
		open = on_server_ws_open,
		message = on_server_ws_message,
		close = on_server_ws_close,
	}
})

print(`[Server]: Websocket is now being hosted at {WEBSOCKET_PORT}!`)