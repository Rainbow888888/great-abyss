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
const GROUND_Y := SURFACE_Y - 3.0

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

@onready var _material_label: Label = $UI/MaterialLabel
@onready var _chronicle_label: Label = $UI/ChronicleLabel
@onready var _monolit: Area2D = $Monolit
@onready var _gruhr: Polygon2D = $Gruhr
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _kyrka: Node2D = $GruhrPassive/Kyrka
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _zasypka: Polygon2D = $Bezdna/Zasypka
@onready var _passive_timer: Timer = $PassiveTimer
@onready var _autosave_timer: Timer = $AutosaveTimer

var _gruhr_passive_base_y: float
var _passive_stats := preload("res://game/resources/PassiveGruhrStats.tres")
var _abyss_stats := preload("res://game/resources/AbyssStats.tres")
var _gruhr_stats := preload("res://game/resources/GruhrStats.tres")
var _upgrade_stats := preload("res://game/resources/UpgradeStats.tres")
var _chronicle_entries: Resource = preload("res://game/resources/ChronicleEntries.tres")

## Лежащие на поверхности осколки, ждущие носильщика.
var _dropped_materials: Array[Area2D] = []

var _carry_state: CarryState = CarryState.IDLE
var _target_material: Area2D = null
var _carried: Area2D = null
var _carry_level := 0

func _ready() -> void:
	_monolit.input_event.connect(_on_monolit_input_event)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	var new_game_btn: Button = $UI/NewGameButton
	new_game_btn.pressed.connect(_on_new_game_button_pressed)
	var upgrade_btn: Button = $UI/UpgradeButton
	upgrade_btn.pressed.connect(_on_upgrade_button_pressed)
	_gruhr_passive_base_y = _gruhr_passive.position.y
	_passive_timer.wait_time = _passive_stats.interval
	_passive_timer.start()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.start()
	load_game()
	_start_kyrka_animation()
	_material_label.text = "В Бездне: %d" % material_count
	_update_zasypka()

func _start_kyrka_animation() -> void:
	if _kyrka == null:
		return
	var tween := create_tween().set_loops()
	# Замах назад (медленно)
	tween.tween_property(_kyrka, "rotation", -0.8, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Удар вперед (быстро)
	tween.tween_property(_kyrka, "rotation", 0.8, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Плавный возврат в дефолтное положение
	tween.tween_property(_kyrka, "rotation", -0.5, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
	if json.parse(text) != OK:
		return
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("Версия сейва не совпадает, начинаем заново")
		return
	material_count = int(data.get("material_count", 0))
	for i in int(data.get("lying_materials", 0)):
		_drop_material(Vector2(335.0, 230.0), false)
	print("Загружено: брошено ", material_count, ", лежит ", _dropped_materials.size())

func _on_monolit_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_material(Vector2(335.0, 230.0))
		_squish_monolit()

func _on_passive_timer_timeout() -> void:
	for i in _passive_stats.material_amount:
		_drop_material(Vector2(335.0, 230.0))
	_jump(_gruhr_passive, _gruhr_passive_base_y)

## Автосейв по таймеру: не терять прогресс при падении игры или
## выключении машины, а не только при честном закрытии окна.
func _on_autosave_timer_timeout() -> void:
	save_game()

func _on_new_game_button_pressed() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().reload_current_scene()

func _on_upgrade_button_pressed() -> void:
	if _carry_level >= _upgrade_stats.max_level:
		return
	var cost := _upgrade_stats.cost_per_level
	if material_count < cost:
		return
	material_count -= cost
	_carry_level += 1
	_gruhr_stats.carry_speed += _upgrade_stats.speed_bonus
	_material_label.text = "В Бездне: %d" % material_count
	_update_upgrade_button()
	print("UPGRADE lv=%d speed=%.1f" % [_carry_level, _gruhr_stats.carry_speed])

## Роняет осколок из точки добычи (у Монолита) на землю.
## Куча-пирамида: осколки идут в случайный столбец с вероятностью
## по центру (ближе к Монолиту), высота считается per-столбец.
const PILE_BASE_X := 280.0
const PILE_SLOT_W := 3.0
const PILE_MAX_COLS := 40
const MATERIAL_H := 4.8
var _column_counts: Dictionary = {}
const MAX_COLUMN_HEIGHT := 5

func _pick_column() -> int:
	var col := int(randf() * randf() * float(PILE_MAX_COLS))
	return clampi(col, 0, PILE_MAX_COLS - 1)

func _drop_material(from: Vector2, animate: bool = true) -> void:
	var item: Area2D = MATERIAL_SCENE.instantiate()
	item.position = from
	var col := _pick_column()
	var h := _column_counts.get(col, 0) as int
	_column_counts[col] = h + 1
	var target_x := PILE_BASE_X + col * PILE_SLOT_W + randf_range(-0.5, 0.5)
	item.target_x = target_x
	var target_y := GROUND_Y - h * MATERIAL_H
	add_child(item)
	_dropped_materials.append(item)
	if not animate:
		item.position = Vector2(target_x, target_y)
		_settle_column(col)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position:x", target_x, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var y_tween := create_tween()
	var peak_y := minf(from.y, target_y) - 20.0
	y_tween.tween_property(item, "position:y", peak_y, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(item, "position:y", target_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(_settle_column.bind(col))

func _settle_column(col: int) -> void:
	var h: int = _column_counts.get(col, 0)
	if h <= MAX_COLUMN_HEIGHT:
		return
	_column_counts[col] = MAX_COLUMN_HEIGHT
	var spilled := h - MAX_COLUMN_HEIGHT
	for i in spilled:
		var best_col := col
		var best_h := MAX_COLUMN_HEIGHT
		for offset: int in [-1, 1]:
			var nc := col + offset
			if nc < 0 or nc >= PILE_MAX_COLS:
				continue
			var nh: int = _column_counts.get(nc, 0)
			if nh < best_h:
				best_h = nh
				best_col = nc
		_column_counts[best_col] = best_h + 1
		var nearest: Area2D = null
		var nearest_dist := INF
		var target_x := PILE_BASE_X + best_col * PILE_SLOT_W
		for item in _dropped_materials:
			if absf(item.target_x - (PILE_BASE_X + col * PILE_SLOT_W)) < 1.0:
				var d := absf(item.position.y - (GROUND_Y - (h - 1) * MATERIAL_H))
				if d < nearest_dist:
					nearest_dist = d
					nearest = item
					break
		if nearest != null:
			var new_x := PILE_BASE_X + best_col * PILE_SLOT_W + randf_range(-0.5, 0.5)
			var new_y := GROUND_Y - best_h * MATERIAL_H
			nearest.target_x = new_x
			var st := create_tween()
			st.tween_property(nearest, "position:x", new_x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			st.parallel().tween_property(nearest, "position:y", new_y, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

## Визуальный сочный отклик на клик по Монолиту (сжатие-растяжение).
func _squish_monolit() -> void:
	if _monolit == null:
		return
	if _monolit.has_meta("squish_tween"):
		var old_tween = _monolit.get_meta("squish_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	var tween := create_tween()
	_monolit.set_meta("squish_tween", tween)
	_monolit.scale = Vector2(0.95, 1.05)
	tween.tween_property(_monolit, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Носильщик: один Грухр, один объект за раз, хватает ближайший.
func _process(delta: float) -> void:
	match _carry_state:
		CarryState.IDLE:
			if not _dropped_materials.is_empty():
				_target_material = _find_nearest_material()
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
		_carried.position = _gruhr.position + Vector2(0, -12)

## Двигает носильщика к цели по горизонтали. true — дошёл.
func _step_toward(target_x: float, delta: float) -> bool:
	var dx := target_x - _gruhr.position.x
	var step := _gruhr_stats.carry_speed * delta
	if absf(dx) <= step:
		_gruhr.position.x = target_x
		return true
	_gruhr.position.x += signf(dx) * step
	return false

func _find_nearest_material() -> Area2D:
	var best: Area2D = null
	var best_dist := INF
	for item in _dropped_materials:
		if not is_instance_valid(item):
			continue
		var d := absf(item.position.x - _gruhr.position.x)
		if d < best_dist:
			best_dist = d
			best = item
	return best

func _throw_carried() -> void:
	var item := _carried
	_carried = null
	_carry_state = CarryState.IDLE
	material_count += 1
	_material_label.text = "В Бездне: %d" % material_count
	_update_upgrade_button()
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
func _update_upgrade_button() -> void:
	var btn: Button = $UI/UpgradeButton
	if _carry_level >= _upgrade_stats.max_level:
		btn.text = "Обучить бегу [МАКС]"
		btn.disabled = true
	else:
		var cost := _upgrade_stats.cost_per_level
		btn.text = "Обучить бегу [%d]" % cost
		btn.disabled = material_count < cost

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
	tween.tween_property(node, "position:y", base_y - 8.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", base_y, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _pulse_bezdna() -> void:
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
