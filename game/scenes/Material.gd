extends Area2D

## Осколок материала. Хранит target_x для расчёта высоты кучи.
## По клику прыгает дугой к Бездне и приземляется на землю.

var age := 0.0
var target_x := 0.0

## Колонка кучи, в которой лежит осколок. -1 — не в куче (несут или крадут).
var column := -1

func _ready() -> void:
	add_to_group("shards")
	input_event.connect(_on_input_event)

func _process(delta: float) -> void:
	age += delta

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_toward_abyss()

func _jump_toward_abyss() -> void:
	var target_x := position.x + randf_range(80.0, 140.0)
	var ground_y := 277.0
	var peak_y := ground_y - 40.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:x", target_x, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var y_tween := create_tween()
	y_tween.tween_property(self, "position:y", peak_y, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(self, "position:y", ground_y, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
