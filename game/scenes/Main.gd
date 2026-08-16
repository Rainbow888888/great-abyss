extends Node2D

## T0003 — Источник материала и клик.
## T0004 — Первый Грухр: статичная фигура рядом с Источником,
## коротко подпрыгивает при клике по Источнику.
## T0005 — Бросок материала в Бездну: кнопка «Бросить» тратит весь
## накопленный материал, Бездна коротко пульсирует.
## T0006 — Пассивный Грухр: второй Грухр сам добавляет материал раз
## в фиксированный интервал, без клика игрока.
## T0007 — интервал и величина прироста пассивного Грухра вынесены
## в ресурс `PassiveGruhrStats.tres` (Data-Driven).
## T0007.5 — материал стал физическим объектом: добыча роняет фигуру
## на землю, счётчик не растёт (оживёт в T0007.6, когда появится
## переноска). См. `docs/05_References/DesignReferences.md`.

const MATERIAL_SCENE := preload("res://game/scenes/Material.tscn")

## Уровень «земли», на который падает добытый материал.
const GROUND_Y := 470.0

var material_count := 0

@onready var _material_label: Label = $MaterialLabel
@onready var _istochnik: Area2D = $Istochnik
@onready var _gruhr: Polygon2D = $Gruhr
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _throw_button: Button = $ThrowButton
@onready var _passive_timer: Timer = $PassiveTimer

var _gruhr_base_y: float
var _gruhr_passive_base_y: float
var _passive_stats := preload("res://game/resources/PassiveGruhrStats.tres")

## Лежащие на земле объекты-материалы. Переноской займётся T0007.6.
var _dropped_materials: Array[Polygon2D] = []

func _ready() -> void:
	_istochnik.input_event.connect(_on_istochnik_input_event)
	_throw_button.pressed.connect(_on_throw_button_pressed)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_gruhr_base_y = _gruhr.position.y
	_gruhr_passive_base_y = _gruhr_passive.position.y
	_passive_timer.wait_time = _passive_stats.interval
	_passive_timer.start()

func _on_istochnik_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_material(_istochnik.position)
		_jump(_gruhr, _gruhr_base_y)

func _on_throw_button_pressed() -> void:
	if material_count <= 0:
		return
	material_count = 0
	_material_label.text = "В Бездне: %d" % material_count
	print("Бросок в Бездну")
	_pulse_bezdna()

func _on_passive_timer_timeout() -> void:
	for i in _passive_stats.material_amount:
		_drop_material(_gruhr_passive.position)
	_jump(_gruhr_passive, _gruhr_passive_base_y)

## Роняет объект-материал из точки добычи на землю, с небольшим разбросом,
## чтобы объекты складывались в кучу, а не в столбик.
func _drop_material(from: Vector2) -> void:
	var item: Polygon2D = MATERIAL_SCENE.instantiate()
	item.position = from
	add_child(item)
	_dropped_materials.append(item)
	print("Материала на земле: ", _dropped_materials.size())
	var target_x := from.x + randf_range(-45.0, 45.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position:x", target_x, 0.35)
	tween.tween_property(item, "position:y", GROUND_Y, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _jump(node: Polygon2D, base_y: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position:y", base_y - 20.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", base_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _pulse_bezdna() -> void:
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
