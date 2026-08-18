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

## Толчок обрабатывает Main: только он знает устройство кучи, а осколок,
## улетевший сам по себе, оставлял бы в ней дыру.
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var main := get_parent()
		if main != null and main.has_method("on_shard_clicked"):
			main.on_shard_clicked(self)
