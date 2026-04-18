
-- Heightmap mesh generator

--!strict
--!optimize 2
--!native

return function (
	point_per_dim: number, spacing: number,
	resolution: number, frequency: number, amplitude: number
)
	local face_per_dim = point_per_dim - 1
	local total_vertices = point_per_dim * point_per_dim

	local uvs = table.create(total_vertices)
	local vertices = table.create(total_vertices)
	local faces = table.create(face_per_dim * face_per_dim * 2)

	local n_vertices = 0
	local n_faces = 0

	for z = 0, face_per_dim do
		local row_stride = z * point_per_dim
	
		for x = 0, face_per_dim do
			-- Generate vertices
			local height = math.noise(x/resolution * frequency, z/resolution * frequency) * amplitude
			local vertex = vector.create(x * spacing, height, z * spacing)

			n_vertices += 1
			vertices[n_vertices] = vertex
			uvs[n_vertices] = vector.create(x / face_per_dim, z / face_per_dim)

			if x == 0 or z == 0 then continue end

			-- Generate faces
			local ai = row_stride + x + 1
			local bi = ai - 1
			local ci = ai - point_per_dim
			local di = ci - 1

			n_faces += 2
			faces[n_faces - 1] = vector.create(ai, ci, bi)
			faces[n_faces] = vector.create(bi, ci, di)
		end
	end

	return { vertices = vertices, uvs = uvs, faces = faces }
end