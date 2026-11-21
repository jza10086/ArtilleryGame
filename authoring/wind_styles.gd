extends Node2D
## Standalone art preview. Select a style in the Inspector or press 1–3.
@export_enum("飘叶", "风卷", "轻雾") var style: int = 0
@export var wind: Vector2 = Vector2(32, -12)
var elapsed: float = 0.0

func _ready() -> void:
	hide()
	attach.call_deferred()

func attach() -> void:
	var game: Control = get_parent()
	game.state.wind = Vector2.ZERO
	reparent(game.board.world, false)
	show()
	z_index = -1
	get_parent().move_child(self, get_parent().get_node("Terrain").get_index())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		style = event.keycode - KEY_1

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var strength: float = clampf(wind.length() / 38.0, 0, 1)
	var axis: Vector2 = wind.normalized()
	var side: Vector2 = axis.orthogonal()
	var bounds: Vector2 = get_parent().get_parent().view_size
	var density: int = [72, 20, 27][style]
	for i: int in ceili(density * strength):
		var t: float = elapsed * (0.8 + 0.1 * (i % 5))
		var origin: Vector2 = bounds * Vector2(fmod(0.371 + i * 0.618034, 1), fmod(0.4 + i * 0.414214, 1))
		var p: Vector2 = (origin + wind * t * 5.0 + side * sin(t * 2 + i) * 11.0).posmodv(bounds)
		var phase: float = t + i * 1.73
		match style:
			0:
				var spine: Vector2 = axis.rotated(0.8 * sin(phase * 3.4)) * (5.0 + i % 5)
				var width: Vector2 = spine.orthogonal() * (0.12 + 0.34 * absf(cos(phase * 4)))
				var tint: Color = Color("#a1d7b3").lerp(Color("#ffd08c"), (i % 4) / 3.0)
				draw_colored_polygon(PackedVector2Array([p-spine, p+width, p+spine, p-width]), Color(tint, 0.72))
			1:
				var points: PackedVector2Array = []
				var colors: PackedColorArray = []
				for j: int in 45:
					var u: float = j / 44.0
					var angle: float = TAU * smoothstep(0.22, 0.78, u)
					var curl: Vector2 = axis * (u * 148.0 + sin(angle) * 22.0) + side * ((1.0 - cos(angle)) * 14.0 + sin(u * PI + phase) * 6.0)
					points.append(p + curl)
					colors.append(Color(0.72, 0.92, 1.0, sin(PI*u) * (0.32 + 0.25*sin(phase))))
				draw_polyline_colors(points, colors, 2.4, true)
			2:
				var envelope: float = 0.5 + 0.5 * sin(phase)
				for layer: int in 5:
					var haze: PackedVector2Array = []
					for edge: int in [1, -1]:
						for j: int in 23:
							var u: float = (j if edge == 1 else 22-j) / 22.0
							var center: float = sin(u * TAU + phase) * 11.0
							var thickness: float = sin(PI*u) * (3.0 + layer * 3.0)
							haze.append(p + axis * (u * (220 + (i % 4)*35)) + side * (center + edge * thickness))
					draw_colored_polygon(haze, Color(0.53, 0.84, 1.0, envelope * 0.034))
