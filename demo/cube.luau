
--!strict
--!optimize 2
--!native

return {
	vertices = { 
		vector.create(0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, 0.25),
		vector.create(-0.25, -0.25, 0.25),
		vector.create(0.25, -0.25, 0.25),

		vector.create(0.25, 0.25, -0.25),
		vector.create(-0.25, 0.25, -0.25),
		vector.create(-0.25, -0.25, -0.25),
		vector.create(0.25, -0.25, -0.25),
	};

	faces = {
		vector.create(1, 2, 3),
		vector.create(1, 3, 4),
		vector.create(5, 7, 6),
		vector.create(5, 8, 7),
		vector.create(1, 6, 2),
		vector.create(1, 5, 6),
		vector.create(4, 3, 7),
		vector.create(4, 7, 8),
		vector.create(1, 4, 8),
		vector.create(1, 8, 5),
		vector.create(2, 6, 7),
		vector.create(2, 7, 3),
	};
}