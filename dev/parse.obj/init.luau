
-- OBJ to Luau parser CLI

--!strict
--!optimize 2
--!native

local net = require('@std/net')
local fs = require('@std/fs')
local parse_OBJ = require('./parse.obj/parser')

local HEADER = "\n--!strict\n--!optimize 2\n--!native\n\nlocal vec = vector.create\n\n"

local function warn(message: string): ()
	print ("\x1b[33m" .. message .. "\x1b[39m")
end

local function throw(message: string): ()
	error ("\x1b[31m" .. message .. "\x1b[39m")
end

local function http_get_OBJ_file_source(url: string): (string)
	local obj_request_response = net.request(url)
	if not obj_request_response.ok then
		throw (`{obj_request_response.status}: {obj_request_response.body}`)
	end
	return obj_request_response.body
end

local function parse_OBJ_source_into_luau_source(sourcename: string, source: string): (string)
	local obj = parse_OBJ(source)
	local VERTICES = ''
	local UVS = ''
	local FACES = ''
	
	for _, vertex in next, obj.vertices do
		VERTICES ..= `\t\tvec({vertex.x}, {vertex.y}, {vertex.z}),\n`
	end
	
	for _, uv in next, obj.uvs do
		UVS ..= `\t\tvec({uv.x}, {uv.y}),\n`
	end
	
	for _, index in next, obj.faces do
		FACES ..= `\t\tvec({index.x}, {index.y}, {index.z}),\n`
	end

	return `--From: {sourcename}\n{HEADER}return \{\n\tvertices = \{\n{VERTICES}\t};\n\n\tuvs = \{\n{UVS}\t};\n\n\tfaces = \{\n{FACES}\t};\n}`
end

local function main(OBJ_path: string, output_path: string): ()
	if not OBJ_path then
		throw "No path or link towards an OBJ file was given."
	end

	if not output_path then
		throw "No output path was given."
	end

	warn ("`This is an quick and dirty parser; expect possibly erroneous outputs.")

	local is_url = string.find(OBJ_path, 'https://')
	local OBJ_source = if is_url
		then http_get_OBJ_file_source(OBJ_path)
		else fs.readfiletostring(OBJ_path)
	
	local luau_source = parse_OBJ_source_into_luau_source(OBJ_path, OBJ_source)
	fs.writestringtofile(output_path, luau_source)

	print (`Successfully transpiled .obj file ({OBJ_path}) to .luau ({output_path})!`)
end

main(select(2, ...))