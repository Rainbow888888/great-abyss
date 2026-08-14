extends Node2D

## T0003 — Источник материала и клик.
## T0004 — Первый Грухр: статичная фигура рядом с Источником,
## коротко подпрыгивает при клике по Источнику.
## Клик по «Источнику» даёт +1 материал (переменная состояния),
## печатает в консоль и обновляет debug-label. Без HP и анимаций.

var material_count := 0

@onready var _material_label: Label = $MaterialLabel
@onready var _gruhr: Polygon2D = $Gruhr

var _gruhr_base_y: float

func _ready() -> void:
	$Istochnik.input_event.connect(_on_istochnik_input_event)
	_gruhr_base_y = _gruhr.position.y

func _on_istochnik_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		material_count += 1
		_material_label.text = "Материал: %d" % material_count
		print("Материал: ", material_count)
		_jump_gruhr()

func _jump_gruhr() -> void:
	var tween := create_tween()
	tween.tween_property(_gruhr, "position:y", _gruhr_base_y - 20.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_gruhr, "position:y", _gruhr_base_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
