extends Node

func _ready():
	var size = 1024
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.3
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.seed = randi()


	for y in size:
		for x in size:
			var n = noise.get_noise_2d(x, y)
			n = n * 0.5 + 0.5  # map to 0–1
			img.set_pixel(x, y, Color(n, n, n))

	img.save_png("res://assets/Noise Textures/noise_generated.png")
	print("Noise written to res://noise_generated.png")
