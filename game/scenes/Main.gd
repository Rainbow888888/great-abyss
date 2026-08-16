extends Node2D

## Прототип светлого экрана.
##
## Цикл: клик по Священному Монолиту или молитва пассивного Грухра
## выбивает осколок материала, который падает на поверхность → Грухр-
## носильщик подхватывает его силой мысли, несёт к краю Бездны
## и сбрасывает → счётчик растёт, Бездна пульсирует.
##
## Монолит — первый источник засыпания, Первокамень
## (`docs/03_Gameplay/FillSources.md`). Светлые не копают землю —
## они выбивают материал верой и молитвой. Вид — разрез сбоку (ADR-003).

const MATERIAL_SCENE := preload("res://game/scenes/Material.tscn")

## Линия поверхности в разрезе (ADR-003). Всё, что стоит на земле,
## стоит на ней; ниже — массив земли и полость Бездны.
const SURFACE_Y := 280.0

## Куда ложится выбитый молитвой осколок: нижней гранью на поверхность.
const GROUND_Y := SURFACE_Y - 6.0

## Куда носильщик доходит, чтобы сбросить груз: у левой кромки зева.
const THROW_X := 590.0

const SAVE_PATH := "user://save.json"

## Меняется, когда меняется состав сохраняемых данных. Сейв чужой
## версии отбрасывается — начинается новая игра.
const SAVE_VERSION := 1

## Интервал автосейва. Технический параметр (частота записи), а не
## баланс игры, поэтому константа в коде, а не в `.tres`.
const AUTOSAVE_INTERVAL := 10.0

enum CarryState { IDLE, TO_MATERIAL, TO_ABYSS }

var material_count := 0

@onready var _material_label: Label = $MaterialLabel
@onready var _chronicle_label: Label = $ChronicleLabel
@onready var _monolit: Area2D = $Monolit
@onready var _gruhr: Polygon2D = $Gruhr
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _zasypka: Polygon2D = $Bezdna/Zasypka
@onready var _passive_timer: Timer = $PassiveTimer
@onready var _autosave_timer: Timer = $AutosaveTimer

var _gruhr_passive_base_y: float
var _passive_stats := preload("res://game/resources/PassiveGruhrStats.tres")
var _abyss_stats := preload("res://game/resources/AbyssStats.tres")
var _gruhr_stats := preload("res://game/resources/GruhrStats.tres")
var _chronicle_entries: Resource = preload("res://game/resources/ChronicleEntries.tres")

## Лежащие на поверхности осколки, ждущие носильщика.
var _dropped_materials: Array[Polygon2D] = []

var _carry_state: CarryState = CarryState.IDLE
var _target_material: Polygon2D = null
var _carried: Polygon2D = null

func _ready() -> void:
	_monolit.input_event.connect(_on_monolit_input_event)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	_gruhr_passive_base_y = _gruhr_passive.position.y
	_passive_timer.wait_time = _passive_stats.interval
	_passive_timer.start()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.start()
	load_game()
	_material_label.text = "В Бездне: %d" % material_count
	_update_zasypka()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()

## Сохраняем два числа: сколько брошено и сколько лежит. Координаты
## лежащих объектов — косметика, при загрузке рассыпаются заново.
func save_game() -> void:
	var lying := _dropped_materials.size()
	if _carried != null:
		lying += 1
	var data := {
		"version": SAVE_VERSION,
		"material_count": material_count,
		"lying_materials": lying,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось записать сейв: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print("Сохранено: брошено ", material_count, ", лежит ", lying)

## Любая проблема с сейвом — молча начинаем новую игру, без падения.
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Сейв не открылся, начинаем заново")
		return
	var text := file.get_as_text()
	file.close()
	# JSON.parse_string на битом файле сам печатает ERROR, а битый сейв —
	# ожидаемый случай, а не сбой. Разбираем через экземпляр, молча.
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Сейв повреждён, начинаем заново")
		return
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("Версия сейва не совпадает, начинаем заново")
		return
	material_count = int(data.get("material_count", 0))
	for i in int(data.get("lying_materials", 0)):
		_drop_material(_monolit.position, false)
	print("Загружено: брошено ", material_count, ", лежит ", _dropped_materials.size())

func _on_monolit_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_material(_monolit.position)

func _on_passive_timer_timeout() -> void:
	for i in _passive_stats.material_amount:
		_drop_material(_monolit.position)
	_jump(_gruhr_passive, _gruhr_passive_base_y)

## Автосейв по таймеру: не терять прогресс при падении игры или
## выключении машины, а не только при честном закрытии окна.
func _on_autosave_timer_timeout() -> void:
	save_game()

## Роняет осколок из точки добычи (у Монолита) на землю, с разбросом в
## сторону Бездны: куча складывается сбоку от Первокамня, а не под ним,
## иначе её не видно — а куча и есть видимый сигнал узкого места.
func _drop_material(from: Vector2, animate: bool = true) -> void:
	var item: Polygon2D = MATERIAL_SCENE.instantiate()
	item.position = from
	add_child(item)
	_dropped_materials.append(item)
	var target_x := from.x + randf_range(38.0, 105.0)
	if not animate:
		item.position = Vector2(target_x, GROUND_Y)
		return
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
	_check_chronicle()
	var landing := Vector2(_bezdna.position.x - 40.0, _bezdna.position.y + _zasypka_top_y())
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position", landing, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(item, "scale", Vector2.ZERO, 0.5)
	tween.finished.connect(item.queue_free)
	_pulse_bezdna()
	_update_zasypka()

## Летописец: проходим по записям и показываем первую сработавшую.
## Пороги и текст в .tres (ChronicleEntries.tres) — не в коде.
func _check_chronicle() -> void:
	for entry in _chronicle_entries.entries:
		if _chronicle_hit(entry):
			_chronicle_label.text = entry.text
			_chronicle_label.visible = true
			return

## Числа совпадают с enum ChronicleEntry.Trigger: 0 = первое подношение,
## 1 = N-й материал, 2 = половина ёмкости. Хардкод допустим — enum и
## ресурс меняются вместе в одном файле.
func _chronicle_hit(entry: Resource) -> bool:
	match entry.trigger:
		0:
			return material_count == 1
		1:
			return material_count == entry.threshold
		2:
			return material_count == _abyss_stats.capacity / 2
	return false

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
