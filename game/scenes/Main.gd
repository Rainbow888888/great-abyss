extends Node2D

## T0003 — Источник материала и клик.
## T0004 — Первый Грухр: статичная фигура рядом с Источником,
## коротко подпрыгивает при клике по Источнику.
## T0005 — Бросок материала в Бездну: кнопка «Бросить» тратит весь
## накопленный материал, Бездна коротко пульсирует.
## T0006 — Пассивный Грухр: второй Грухр сам добавляет материал раз
## в фиксированный интервал, без клика игрока.
## Клик по «Источнику» даёт +1 материал (переменная состояния),
## печатает в консоль и обновляет debug-label. Без HP и анимаций.

var material_count := 0

@onready var _material_label: Label = $MaterialLabel
@onready var _gruhr: Polygon2D = $Gruhr
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _throw_button: Button = $ThrowButton
@onready var _passive_timer: Timer = $PassiveTimer

var _gruhr_base_y: float
var _gruhr_passive_base_y: float

func _ready() -> void:
	$Istochnik.input_event.connect(_on_istochnik_input_event)
	_throw_button.pressed.connect(_on_throw_button_pressed)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_gruhr_base_y = _gruhr.position.y
	_gruhr_passive_base_y = _gruhr_passive.position.y

func _on_istochnik_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		material_count += 1
		_material_label.text = "Материал: %d" % material_count
		print("Материал: ", material_count)
		_jump(_gruhr, _gruhr_base_y)

func _on_throw_button_pressed() -> void:
	if material_count <= 0:
		return
	material_count = 0
	_material_label.text = "Материал: %d" % material_count
	print("Бросок в Бездну")
	_pulse_bezdna()

func _on_passive_timer_timeout() -> void:
	material_count += 1
	_material_label.text = "Материал: %d" % material_count
	print("Материал (пассивно): ", material_count)
	_jump(_gruhr_passive, _gruhr_passive_base_y)

func _jump(node: Polygon2D, base_y: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position:y", base_y - 20.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", base_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _pulse_bezdna() -> void:
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
