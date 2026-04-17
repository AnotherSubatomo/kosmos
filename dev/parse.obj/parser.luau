
-- Quick and dirty .OBJ parser and de-indexer for Luau
-- SPDX-License-Identifier: CC0-1.0

--!strict
--!optimize 2
--!native

local NAN = 0/0 -- to represent `nil` in vectors
local match = string.match
local talloc = table.create
local tclear = table.clear
local make_vec = vector.create
local iter_codes = utf8.codes ''

local function number(str: string?): (number)
	return tonumber(str) or NAN
end

local function parse_index(i: string?, len: number): (number)
	local idx = tonumber(i)
	if not idx then return NAN end
	if idx < 0 then idx = len + idx + 1 end
	if idx < 1 or idx > len then return NAN end
	return idx
end

export type vectors = {vector} -- dense array
-- opinionated representation of an OBJ file
export type LuauOBJ = {
	vertices: vectors,
	uvs: vectors,
	normals: vectors,
	faces: vectors
}

local function load_OBJ(source: string): (LuauOBJ)
	local total_faces = 0
	local total_vertices = 0
	local total_uvs_listed = 0
	local total_normals_listed = 0

	local curr_offset, curr_code = iter_codes(source, 0)

	while curr_code do
		local next_offset, next_code = iter_codes(source, curr_offset)
		if curr_code == 118 then
			if next_code == 32 then
				total_vertices += 1
			elseif next_code == 116 then
				total_uvs_listed += 1
			elseif next_code == 110 then
				total_normals_listed += 1
			end
		elseif curr_code == 102 and next_code == 32 then
			total_faces += 1
		end
		curr_offset, curr_code = next_offset, next_code
	end

	local faces = talloc(total_faces)
	local vertices = talloc(total_vertices)
	local uvs = talloc(total_vertices)
	local normals = talloc(total_vertices)

	local vertex_list = talloc(total_vertices)
	local uv_list = talloc(total_uvs_listed)
	local normal_list = talloc(total_normals_listed)

	local n_faces = 0
	local n_unique_vertices = 0

	local n_vertices = 0
	local n_uvs = 0
	local n_normals = 0

	--> Yes, the vector datatype actually has stable hashing semantics for all correct Luau runtimes!
	local point_lookup: {[vector]: number} = {}
	local index_tuples = talloc(3)
	
	local function get_vertex_index(index_tuple: vector): (number)
		local existing_idx = point_lookup[index_tuple]
		if existing_idx then return existing_idx end

		n_unique_vertices += 1
		local idx = n_unique_vertices
		point_lookup[index_tuple] = idx

		vertices[idx] = vertex_list[index_tuple.x]
		uvs[idx] = uv_list[index_tuple.y]
		normals[idx] = normal_list[index_tuple.z]

		return idx
	end

	for line in string.gmatch(source, "([^\r\n]+)") do
		local prefix, body = match(line, "^(%S+)%s*(.*)")
		if not body then continue end

		if prefix == "v" then
			n_vertices += 1
			local x, y, z = match(body, "([%-%d%.eE]+)%s+([%-%d%.eE]+)%s+([%-%d%.eE]+)")
			vertex_list[n_vertices] = make_vec(number(x), number(y), tonumber(z))

		elseif prefix == "vt" then
			n_uvs += 1
			local u, v = match(body, "([%-%d%.eE]+)%s+([%-%d%.eE]+)")
			uv_list[n_uvs] = make_vec(number(u), tonumber(v) or 0)

		elseif prefix == "vn" then
			n_normals += 1
			local x, y, z = match(body, "([%-%d%.eE]+)%s+([%-%d%.eE]+)%s+([%-%d%.eE]+)")
			normal_list[n_normals] = make_vec(number(x), number(y), tonumber(z))

		elseif prefix == "f" then
			local n_index_tuples = 0
			tclear(index_tuples)

			for index_tuple in string.gmatch(body, "%S+") do
				-- formats: v; v/vt; v//vn; v/vt/vn
				local a, b, c = match(index_tuple, "([^/]*)/?([^/]*)/?([^/]*)")
				n_index_tuples += 1
				index_tuples[n_index_tuples] = make_vec(
					parse_index(a, n_vertices),
					parse_index(b, n_uvs),
					parse_index(c, n_normals)
				)
			end

			-- Fan triangulation: 1,2,3 / 1,3,4 / ...
			for i = 2, n_index_tuples - 1 do
				local i_1 = i + 1
				local pa, pb, pc = index_tuples[1], index_tuples[i], index_tuples[i_1]

				local a = get_vertex_index(pa)
				local b = get_vertex_index(pb)
				local c = get_vertex_index(pc)

				n_faces += 1
				faces[n_faces] = make_vec(a, b, c)
			end
		end
	end

	return { vertices = vertices, uvs = uvs, normals = normals, faces = faces }
end

return load_OBJ