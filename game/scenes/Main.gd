extends Node2D

## T0003 — Источник материала и клик.
## Клик по «Источнику» даёт +1 материал (переменная состояния),
## печатает в консоль и обновляет debug-label. Без HP и анимаций.

var material_count := 0

@onready var _material_label: Label = $MaterialLabel

func _ready() -> void:
	$Istochnik.input_event.connect(_on_istochnik_input_event)

func _on_istochnik_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		material_count += 1
		_material_label.text = "Материал: %d" % material_count
		print("Материал: ", material_count)
