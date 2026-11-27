extends Control
## Lightweight 2D stand-in for the final physical 3D Mimir lever.
signal pulled
var dragging: bool = false
var travel: float = 0.0
var origin_y: float = 0.0
var enabled: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(54, 122)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func set_enabled(value: bool) -> void:
	enabled = value
	dragging = false
	travel = 0.0
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			origin_y = event.position.y
		else:
			var fired := dragging and travel >= 0.6
			dragging = false
			travel = 0.0
			queue_redraw()
			if fired:
				pulled.emit()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		travel = clampf((event.position.y - origin_y) / 65.0, 0.0, 1.0)
		queue_redraw()
		accept_event()

func _draw() -> void:
	var base := Vector2(size.x * 0.5, 94)
	var knob := Vector2(size.x * 0.5 + 8.0 * travel, 18 + 65 * travel)
	draw_rect(Rect2(base - Vector2(19, 15), Vector2(38, 30)), Color("514539"))
	draw_circle(base, 13, Color("bd9358"))
	draw_line(base, knob, Color("302822"), 12.0, true)
	draw_line(base, knob, Color("d6b77c"), 6.0, true)
	draw_circle(knob, 14, Color("b74335") if enabled else Color("695b57"))
	draw_circle(knob - Vector2(4, 5), 4, Color("f1b08b") if enabled else Color("96847b"))
