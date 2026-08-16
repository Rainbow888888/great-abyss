extends Node2D

## Прототип светлого экрана.
##
## Цикл: клик по Шахте или тик пассивного Грухра роняет объект-материал
## на поверхность → Грухр-носильщик подбирает его, несёт к краю Бездны
## и сбрасывает → счётчик растёт, Бездна пульсирует.
##
## Шахта — первый источник засыпания, наземная постройка
## (`docs/03_Gameplay/FillSources.md`). Вид — разрез сбоку (ADR-003).

const MATERIAL_SCENE := preload("res://game/scenes/Material.tscn")

## Линия поверхности в разрезе (ADR-003). Всё, что стоит на земле,
## стоит на ней; ниже — массив земли и полость Бездны.
const SURFACE_Y := 280.0

## Куда ложится добытый материал: нижней гранью на поверхность.
const GROUND_Y := SURFACE_Y - 6.0

## Куда носильщик доходит, чтобы сбросить груз: у левой кромки зева.
const THROW_X := 590.0

enum CarryState { IDLE, TO_MATERIAL, TO_ABYSS }

var material_count := 0

@onready var _material_label: Label = $MaterialLabel
@onready var _shahta: Area2D = $Shahta
@onready var _gruhr: Polygon2D = $Gruhr
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _zasypka: Polygon2D = $Bezdna/Zasypka
@onready var _passive_timer: Timer = $PassiveTimer

var _gruhr_passive_base_y: float
var _passive_stats := preload("res://game/resources/PassiveGruhrStats.tres")
var _abyss_stats := preload("res://game/resources/AbyssStats.tres")
var _gruhr_stats := preload("res://game/resources/GruhrStats.tres")

## Лежащие на поверхности объекты-материалы, ждущие носильщика.
var _dropped_materials: Array[Polygon2D] = []

var _carry_state: CarryState = CarryState.IDLE
var _target_material: Polygon2D = null
var _carried: Polygon2D = null

func _ready() -> void:
	_shahta.input_event.connect(_on_shahta_input_event)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_gruhr_passive_base_y = _gruhr_passive.position.y
	_passive_timer.wait_time = _passive_stats.interval
	_passive_timer.start()
	_update_zasypka()

func _on_shahta_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_material(_shahta.position)

func _on_passive_timer_timeout() -> void:
	for i in _passive_stats.material_amount:
		_drop_material(_gruhr_passive.position)
	_jump(_gruhr_passive, _gruhr_passive_base_y)

## Роняет объект-материал из точки добычи на землю, с разбросом в сторону
## Бездны: куча складывается сбоку от постройки, а не под ней, иначе её
## не видно — а куча и есть видимый сигнал узкого места.
func _drop_material(from: Vector2) -> void:
	var item: Polygon2D = MATERIAL_SCENE.instantiate()
	item.position = from
	add_child(item)
	_dropped_materials.append(item)
	var target_x := from.x + randf_range(38.0, 105.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position:x", target_x, 0.35)
	tween.tween_property(item, "position:y", GROUND_Y, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Носильщик: один Грухр, один объект за раз, всегда самый ранний
## из лежащих. Очередь задач и выбор ближайшего — не в этом тикете.
func _process(delta: float) -> void:
	match _carry_state:
		CarryState.IDLE:
			if not _dropped_materials.is_empty():
				_target_material = _dropped_materials[0]
				_carry_state = CarryState.TO_MATERIAL
		CarryState.TO_MATERIAL:
			if not is_instance_valid(_target_material):
				_target_material = null
				_carry_state = CarryState.IDLE
			elif _step_toward(_target_material.position.x, delta):
				_dropped_materials.erase(_target_material)
				_carried = _target_material
				_target_material = null
				_carry_state = CarryState.TO_ABYSS
		CarryState.TO_ABYSS:
			if _step_toward(THROW_X, delta):
				_throw_carried()
	if _carried != null:
		_carried.position = _gruhr.position + Vector2(0, -28)

## Двигает носильщика к цели по горизонтали. true — дошёл.
func _step_toward(target_x: float, delta: float) -> bool:
	var dx := target_x - _gruhr.position.x
	var step := _gruhr_stats.carry_speed * delta
	if absf(dx) <= step:
		_gruhr.position.x = target_x
		return true
	_gruhr.position.x += signf(dx) * step
	return false

func _throw_carried() -> void:
	var item := _carried
	_carried = null
	_carry_state = CarryState.IDLE
	material_count += 1
	_material_label.text = "В Бездне: %d" % material_count
	print("Брошено в Бездну: ", material_count)
	var landing := Vector2(_bezdna.position.x - 40.0, _bezdna.position.y + _zasypka_top_y())
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position", landing, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(item, "scale", Vector2.ZERO, 0.5)
	tween.finished.connect(item.queue_free)
	_pulse_bezdna()
	_update_zasypka()

## Уровень засыпки: главный видимый прогресс игры. Форма берётся
## из самой полости Бездны, чтобы засыпка ложилась по её стенкам,
## а не торчала прямоугольником. Один цвет; слои по типам материала
## ждут появления самих типов (`docs/02_World/Abyss.md`).
func _update_zasypka() -> void:
	if material_count <= 0:
		_zasypka.polygon = PackedVector2Array()
		return
	var sides := _shaft_sides()
	var left: PackedVector2Array = sides[0]
	var right: PackedVector2Array = sides[1]
	var top_y := _zasypka_top_y()
	var poly := PackedVector2Array()
	poly.append(Vector2(_interp_x(left, top_y), top_y))
	for p in left:
		if p.y > top_y:
			poly.append(p)
	for i in range(right.size() - 1, -1, -1):
		if right[i].y > top_y:
			poly.append(right[i])
	poly.append(Vector2(_interp_x(right, top_y), top_y))
	_zasypka.polygon = poly

## Глубина верхней кромки засыпки в координатах Бездны.
func _zasypka_top_y() -> float:
	var bottom_y: float = _shaft_sides()[0][_bezdna.polygon.size() / 2 - 1].y
	var filled := clampf(float(material_count) / float(_abyss_stats.capacity), 0.0, 1.0)
	return bottom_y - bottom_y * filled

## Разбивает контур Бездны на левую и правую стенки, обе — сверху вниз.
func _shaft_sides() -> Array:
	var pts := _bezdna.polygon
	var half := pts.size() / 2
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in pts.size():
		if i < half:
			left.append(pts[i])
		else:
			right.append(pts[i])
	right.reverse()
	return [left, right]

## Горизонтальная координата стенки на заданной глубине.
func _interp_x(profile: PackedVector2Array, y: float) -> float:
	if y <= profile[0].y:
		return profile[0].x
	for i in range(1, profile.size()):
		if y <= profile[i].y:
			var a := profile[i - 1]
			var b := profile[i]
			return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
	return profile[profile.size() - 1].x

func _jump(node: Polygon2D, base_y: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position:y", base_y - 20.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", base_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _pulse_bezdna() -> void:
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
