import { LuauState } from 'https://cdn.jsdelivr.net/gh/xNasuni/luau-web@main/dist/luauweb.min.js'

// Quick-n-dirty fake require function
async function require(path) {
	path = path.replace("../", "").replace("./", "")

	if (path == "kosmos") {
		path = "../../src/init.luau"
	} else if (path == "demo") {
		path = "../../demo/init.luau"
	} else {
		path = "../../" + path + ".luau"
	}

	const source = await fetch(path).then(r => r.text())
	const main = state.loadstring(source, path, true)
	const result = await main()

	return result
}

// Fetch demo program bootstrapper
const demo_source = await fetch('./init.luau').then(r => r.text())

// Initialize Luau VM, and load the bootstrap
const state = await LuauState.createAsync({ require: require })
const demo_main = state.loadstring(demo_source, "kosmos-demo", true)
const program = await demo_main()

const width = program[0]
const height = program[1]
const frame = program[2]
const input = program[3]

// Adapt the canvas to the program configurations
canvas.width = width
canvas.height = height

canvas.style.width = "100vw"
canvas.style.height = "100vh"
canvas.style.objectFit = "contain"

// Handle user inputs
let delta_x = 0, delta_y = 0, dont_record_delta = true

canvas.addEventListener("click", async () => {
	await canvas.requestPointerLock()
})

document.addEventListener('mousedown', (event) => {
	if (event.button === 2) (dont_record_delta = false)
})

document.addEventListener('mouseup', (event) => {
	if (event.button === 2) (dont_record_delta = true)
})

document.addEventListener('mousemove', (event) => {
	if (dont_record_delta) return
	delta_x = event.movementX || 0
	delta_y = event.movementY || 0
})

let forward_move = false, back_move = false
let left_move = false, right_move = false
let up_move = false, down_move = false

document.addEventListener('keydown', (event) => {
	const key = event.key.toUpperCase()
	if      (key === 'W') (forward_move = true)
	else if (key === 'S') (back_move = true)
	else if (key === 'A') (left_move = true)
	else if (key === 'D') (right_move = true)
	else if (key === 'E') (up_move = true)
	else if (key === 'Q') (down_move = true)
})

document.addEventListener('keyup', (event) => {
	const key = event.key.toUpperCase()
	if      (key === 'W') (forward_move = false)
	else if (key === 'S') (back_move = false)
	else if (key === 'A') (left_move = false)
	else if (key === 'D') (right_move = false)
	else if (key === 'E') (up_move = false)
	else if (key === 'Q') (down_move = false)
})

function get_user_inputs() {
	// Fetch mouse delta
	const dx = delta_x
	const dy = delta_y
	// * Reset after reading so we don't keep
	//  moving even when the mouse stops
	delta_x = 0
	delta_y = 0
	// Calculate move direction
    const right = (left_move ? 1 : 0) - (right_move ? 1 : 0)
    const up = (up_move ? 1 : 0) - (down_move ? 1 : 0)
    const forward = (forward_move ? 1 : 0) - (back_move ? 1 : 0)
	return { dx, dy, right, up, forward }
}

// Prepare renderer runtime
const ctx = canvas.getContext("2d")
const image_data = ctx.createImageData(width, height)
const pixels = new Uint8ClampedArray(width * height * 4)

let last_time = 0

async function loop(time) {
	let dt = (time - last_time) / 1000
	last_time = time

	const { dx, dy, right, up, forward } = get_user_inputs()
	await input(dx, dy, right, up, forward)

	let image_string = (await frame(dt))[0]

	for (let i = 0; i < pixels.length; i++) {
		pixels[i] = image_string.charCodeAt(i)
	}

	image_data.data.set(pixels)
	ctx.putImageData(image_data, 0, 0)

	requestAnimationFrame(loop)
}

// Run the renderer
requestAnimationFrame(loop)