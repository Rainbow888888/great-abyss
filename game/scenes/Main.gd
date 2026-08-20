extends Node2D

## Прототип светлого экрана.
##
## Цикл: клик по Священному Монолиту или молитва добытчика выбивает
## осколок, который падает в кучу на поверхности → носильщик подхватывает
## его силой мысли и несёт к краю Бездны → счётчик растёт, Бездна пульсирует.
##
## Монолит — первый источник засыпания, Первокамень
## (`docs/03_Gameplay/FillSources.md`). Светлые не копают землю и не бьют
## камень руками — они выбивают материал молитвой, и переносят тоже мыслью
## (`docs/02_World/LightCivilization.md`). Вид — разрез сбоку (ADR-003).
##
## Важно: `.tres` — только значения по умолчанию, читаются и не меняются.
## Всё, что меняется по ходу партии, живёт в переменных ниже. Ресурсы
## кэшируются движком, и запись в них переживала бы «Новую игру».

const MATERIAL_SCENE := preload("res://game/scenes/Material.tscn")
const CARRIER_SCENE := preload("res://game/scenes/Carrier.tscn")

## Линия поверхности в разрезе (ADR-003). Всё, что стоит на земле,
## стоит на ней; ниже — массив земли и полость Бездны.
const SURFACE_Y := 280.0

## Куда ложится выбитый молитвой осколок: нижней гранью на поверхность.
const GROUND_Y := SURFACE_Y - 3.0

## Куда носильщик доходит, чтобы сбросить груз: у левой кромки зева.
const THROW_X := 735.0

## Правая грань Монолита — точка, куда бьёт молитва и откуда летит осколок.
## Добытчик стоит с ДАЛЬНЕЙ от Бездны стороны камня (ADR-005): Монолит
## заслоняет молящегося от волны, и это объясняется геометрией, а не
## исключением в коде.
const SHARD_ORIGIN := Vector2(295.0, 230.0)

## Куча осколков: ложится справа от добытчика, между ним и Бездной.
## Куча разбита на колонки. Осколок падает в свою колонку, но если она
## сильно выше соседней — скатывается вбок. Из этого сама собой
## получается горка с постоянным углом откоса, а не столбики.
const PILE_LEFT_X := 310.0
const PILE_COLUMNS := 84
const COLUMN_W := 2.6
const MATERIAL_H := 2.4

## На сколько колонок клик отбрасывает осколок в сторону Бездны.
const PUSH_COLUMNS := 14

## Насколько колонка может быть выше соседней, прежде чем осколок с неё
## скатится. Это и есть угол откоса горки.
const SLOPE_LIMIT := 2

## Предел высоты колонки. Выше куча не растёт — осыпается вбок.
## 80 × 2.4 px ≈ 192 px, чуть выше Монолита: горка может его перерасти.
const MAX_COLUMN := 80

## Осколки падают у подножия Монолита, а не по всей ширине — иначе
## получается ровное плато. Горка нарастает отсюда и оползает вправо.
const DROP_BAND := 10

const SAVE_PATH := "user://save.json"

## Меняется, когда меняется состав сохраняемых данных. Сейв чужой
## версии отбрасывается — начинается новая игра.
const SAVE_VERSION := 5

## Интервал автосейва. Технический параметр (частота записи), а не
## баланс игры, поэтому константа в коде, а не в `.tres`.
const AUTOSAVE_INTERVAL := 10.0

## Сколько осколков даёт один клик в режиме отладки.
const DEBUG_CLICK_BURST := 10

var material_count := 0

## Текущая скорость носильщиков. Считается из базы в `.tres` и уровня
## апгрейда — сам ресурс не трогаем.
var carry_speed := 0.0

## Сколько осколков носильщик берёт за одну ходку.
var carry_capacity := 1

@onready var _material_label: Label = $UI/MaterialLabel
@onready var _shard_label: Label = $UI/ShardLabel
@onready var _chronicle_label: Label = $UI/ChronicleLabel
@onready var _upgrade_button: Button = $UI/UpgradeButton
@onready var _carrier_button: Button = $UI/CreateCarrierButton
@onready var _capacity_button: Button = $UI/CapacityButton
@onready var _monolit: Area2D = $Monolit
@onready var _gruhr_passive: Polygon2D = $GruhrPassive
@onready var _bezdna: Polygon2D = $Bezdna
@onready var _zasypka: Polygon2D = $Bezdna/Zasypka
@onready var _passive_timer: Timer = $PassiveTimer
@onready var _autosave_timer: Timer = $AutosaveTimer
@onready var _reclaim_timer: Timer = $ReclaimTimer
@onready var _pylesos: Polygon2D = $Pylesos
@onready var _kristall: Polygon2D = $Kristall
@onready var _crystal_button: Button = $UI/CrystalButton
@onready var _rezonans: Line2D = $Rezonans
@onready var _wave_timer: Timer = $WaveTimer
@onready var _volna: Line2D = $Volna
@onready var _nozzle: Node2D = $Pylesos/Nozzle

var _passive_stats := preload("res://game/resources/PassiveGruhrStats.tres")
var _abyss_stats := preload("res://game/resources/AbyssStats.tres")
var _gruhr_stats := preload("res://game/resources/GruhrStats.tres")
var _upgrade_stats := preload("res://game/resources/UpgradeStats.tres")
var _crystal_stats := preload("res://game/resources/CrystalStats.tres")
var _chronicle_entries: Resource = preload("res://game/resources/ChronicleEntries.tres")

## Куча: массив колонок, в каждой — стопка осколков снизу вверх.
## Носильщик всегда снимает верхний осколок колонки, поэтому дыр
## внутри горки не образуется. Как только осколок выбран — он уходит
## из кучи, иначе за ним побегут двое.
var _columns: Array = []

## Тип — Node2D, а не Carrier: глобальное имя класса регистрирует
## редактор, и при запуске сцены скриптом его может не быть.
var _carriers: Array[Node2D] = []
var _carry_level := 0
var _capacity_level := 0
## Масса растущего кристалла. Чем больше — тем крупнее осколки.
var _crystal_mass := 0

## Дыхание Бездны: радиус идущей волны и кого она уже задела.
var _wave_radius := -1.0
var _wave_hit: Array = []
var _fill_at_last_wave := 0

## Замах: пока больше нуля, Бездна набирает воздух и клик пригибает племя.
var _tell_left := -1.0
var _ducked := false
var _is_debug_mode := false
var _pylesos_active := false

## Кэш размера кучи: кнопки и счётчик обновляются только когда он
## меняется, а не каждый кадр.
var _last_pile_size := -1

func _ready() -> void:
	_columns.resize(PILE_COLUMNS)
	for i in PILE_COLUMNS:
		_columns[i] = []
	_monolit.input_event.connect(_on_monolit_input_event)
	_passive_timer.timeout.connect(_on_passive_timer_timeout)
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	$UI/NewGameButton.pressed.connect(_on_new_game_button_pressed)
	$UI/UpgradeButton.pressed.connect(_on_upgrade_button_pressed)
	$UI/DebugButton.pressed.connect(_on_debug_button_pressed)
	$UI/CreateCarrierButton.pressed.connect(_on_create_carrier_button_pressed)
	$UI/DebugCarrierButton.pressed.connect(_on_debug_carrier_button_pressed)
	$UI/DebugSpeedButton.pressed.connect(_on_debug_speed_button_pressed)
	$UI/CapacityButton.pressed.connect(_on_capacity_button_pressed)
	$UI/DebugCapacityButton.pressed.connect(_on_debug_capacity_button_pressed)
	$UI/CrystalButton.pressed.connect(_on_crystal_button_pressed)
	_wave_timer.timeout.connect(_on_wave_timer_timeout)
	_arm_wave()
	_reclaim_timer.timeout.connect(_on_reclaim_timer_timeout)
	_reclaim_timer.wait_time = _abyss_stats.reclaim_interval
	_reclaim_timer.start()

	var first_carrier: Node2D = $Gruhr
	first_carrier.setup(self, THROW_X)
	_carriers.append(first_carrier)

	_passive_timer.wait_time = _passive_stats.interval
	_passive_timer.start()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.start()

	load_game()
	_apply_carry_speed()
	_start_prayer_idle()
	_material_label.text = "В Бездне: %d" % material_count
	_refresh_crystal()
	_update_zasypka()
	_update_buttons()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()

# --- Сохранение ---------------------------------------------------------

## Сохраняем только числа. Координаты осколков — косметика, при загрузке
## куча складывается заново; фаза ходьбы носильщика смысла не имеет.
func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"material_count": material_count,
		"lying_materials": get_tree().get_nodes_in_group("shards").size(),
		"carry_level": _carry_level,
		"capacity_level": _capacity_level,
		"crystal_mass": _crystal_mass,
		"carriers": _carriers.size(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось записать сейв: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()

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
	# Валидный JSON может быть не словарём (число, строка, массив) —
	# без этой проверки присваивание в Dictionary роняет игру.
	if typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Сейв не того формата, начинаем заново")
		return
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("Версия сейва не совпадает, начинаем заново")
		return
	material_count = int(data.get("material_count", 0))
	# Верхняя граница — отладочная, а не платная: уровни, накрученные
	# debug-кнопкой, тоже должны переживать перезапуск.
	_carry_level = clampi(int(data.get("carry_level", 0)), 0, DEBUG_MAX_LEVEL)
	_capacity_level = clampi(int(data.get("capacity_level", 0)), 0, DEBUG_MAX_LEVEL)
	_crystal_mass = clampi(int(data.get("crystal_mass", 0)), 0, _crystal_stats.max_mass)
	for i in int(data.get("lying_materials", 0)):
		_drop_material(SHARD_ORIGIN, false)
	for i in maxi(int(data.get("carriers", 1)) - 1, 0):
		_spawn_carrier()

# --- Добыча -------------------------------------------------------------

func _on_monolit_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_squish_monolit()
		var count := DEBUG_CLICK_BURST if _is_debug_mode else 1
		for i in count:
			_drop_material(SHARD_ORIGIN)

# --- Пробуждение Бездны и Жертвенный Дом (T0021, T0020) -----------------

## Бездна просыпается, когда её засыпали достаточно. После этого мелкие
## осколки Монолита её не двигают — нужен источник крупнее. Это и есть
## ворота к следующей ступени лестницы (`docs/03_Gameplay/FillSources.md`).
func _is_abyss_awake() -> bool:
	return material_count >= _abyss_stats.stage_threshold

## Сколько засыпки реально даст этот кусок прямо сейчас.
func _delivered_value(item: Area2D) -> int:
	if item.from_monolith and _is_abyss_awake():
		return 0
	return item.value

## Кристалл растёт сам. Игрок ростом не управляет — в этом и смысл:
## переключатель режимов сделал бы решение бухгалтерским, а растущий
## сам по себе кристалл делает его искушением («выдержу ли ещё»).
## Кристалл растёт не сам — его растит добытчик. Молитва бьёт в Монолит,
## и через резонанс между камнем и кристаллом часть силы уходит в рост.
## Поэтому после пробуждения Грухри не бездельничают: осколки больше не
## засыпают Бездну, но молитва по-прежнему растит кристалл.
func _grow_crystal_from_prayer() -> void:
	if _crystal_mass >= _crystal_stats.max_mass:
		return
	_crystal_mass = mini(_crystal_mass + _crystal_stats.grow_amount, _crystal_stats.max_mass)
	_refresh_crystal()
	_pulse_rezonans()
	_update_buttons()

## Нить резонанса между Монолитом и кристаллом. Видна всегда, пока
## кристалл есть, и вспыхивает на каждой молитве — связь между ними
## должна читаться, а не подразумеваться.
func _pulse_rezonans() -> void:
	_rezonans.visible = true
	_rezonans.points = PackedVector2Array([_monolit.position, _kristall.position + Vector2(0, -30.0)])
	var tween := create_tween()
	tween.tween_property(_rezonans, "modulate:a", 0.95, 0.1)
	tween.tween_property(_rezonans, "modulate:a", 0.3, 0.6)

## Размер на экране — прямое отражение массы. Кристалл и есть индикатор
## прогресса, пока линия засыпки стоит.
func _refresh_crystal() -> void:
	if _crystal_mass <= 0:
		_kristall.visible = false
		_rezonans.visible = false
		return
	_kristall.visible = true
	var t := float(_crystal_mass) / float(_crystal_stats.max_mass)
	var target := Vector2(0.35 + t * 0.85, 0.25 + t * 0.95)
	var tween := create_tween()
	tween.tween_property(_kristall, "scale", target, 0.35).set_trans(Tween.TRANS_SINE)

## Крупность осколка, который молитва выбивает из Монолита. Кристалл —
## усилитель, а не источник: Монолит остаётся единственным источником,
## кристалл лишь делает его отдачу крупнее.
func _shard_value() -> int:
	return 1 + int(_crystal_mass / _crystal_stats.mass_per_shard_value)

## Разбить можно в любой момент. Масса уходит в крупные блоки, усиление
## пропадает, следующий кристалл растёт с нуля — постоянного бонуса нет.
func _on_crystal_button_pressed() -> void:
	var blocks := int(_crystal_mass / _crystal_stats.mass_per_block)
	if blocks <= 0:
		return
	_crystal_mass = 0
	for i in blocks:
		_drop_material(_kristall.position + Vector2(0, -40.0), true, _crystal_stats.block_value, false)
	var tween := create_tween()
	tween.tween_property(_kristall, "scale", Vector2(1.4, 0.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_kristall.visible = false
		_refresh_crystal()
	)
	_update_buttons()

## Добытчик молится: искра летит от него к цели, и только по её прилёту
## откалывается кусок. Цепочка «кто → куда → что» должна быть видна,
## иначе материал берётся из пустоты.
func _on_passive_timer_timeout() -> void:
	var spark := Polygon2D.new()
	spark.color = Color(0.95, 0.95, 0.78, 1)
	var pts := PackedVector2Array()
	pts.push_back(Vector2(0, -10))
	pts.push_back(Vector2(6, 0))
	pts.push_back(Vector2(0, 10))
	pts.push_back(Vector2(-6, 0))
	spark.polygon = pts
	spark.position = _gruhr_passive.position + Vector2(0, -12)
	add_child(spark)
	var target := SHARD_ORIGIN
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "position", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(spark, "scale", Vector2(0.35, 0.35), 0.45)
	tween.finished.connect(func() -> void:
		spark.queue_free()
		_squish_monolit()
		for i in _passive_stats.material_amount:
			_drop_material(SHARD_ORIGIN, true, _shard_value())
		_grow_crystal_from_prayer()
	)

## Добытчик всё время в молитве — медленное дыхание на месте.
func _start_prayer_idle() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_gruhr_passive, "scale", Vector2(1.12, 0.9), 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_gruhr_passive, "scale", Vector2(1.0, 1.0), 0.9).set_trans(Tween.TRANS_SINE)

## Осколок летит дугой от Монолита и ложится в кучу. Высота места
## посадки зависит от того, сколько осколков уже лежит рядом.
func _drop_material(from: Vector2, animate: bool = true, value: int = 1, from_monolith: bool = true) -> void:
	var item: Area2D = MATERIAL_SCENE.instantiate()
	item.position = from
	item.value = value
	item.from_monolith = from_monolith
	if not from_monolith:
		# Блок Дома крупнее осколка и другого цвета: видно, что несут
		# не камень, а разобранное жильё.
		item.scale = Vector2(2.6, 2.6)
		var visual: Polygon2D = item.get_node("Visual")
		visual.color = Color(0.72, 0.62, 0.44, 1)
	add_child(item)
	var spot := _settle(item, randi_range(0, DROP_BAND))
	if not animate:
		item.position = spot
		return
	var x_tween := create_tween()
	x_tween.tween_property(item, "position:x", spot.x, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var y_tween := create_tween()
	y_tween.tween_property(item, "position:y", minf(from.y, spot.y) - 20.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(item, "position:y", spot.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

## Кладёт осколок в кучу, скатывая его вбок, пока откос слишком крут
## или колонка упёрлась в предел. Возвращает точку, где он лёг.
func _settle(item: Area2D, wanted: int) -> Vector2:
	var c := _roll_down(wanted)
	_columns[c].append(item)
	item.column = c
	return _slot_position(c, _columns[c].size() - 1)

## Ищет, куда осколок скатится: вниз по склону, пока перепад с соседом
## не станет допустимым. Ограничитель шагов — на случай, если куча
## забита целиком и катиться некуда.
func _roll_down(start: int) -> int:
	var c := clampi(start, 0, PILE_COLUMNS - 1)
	for _step in PILE_COLUMNS * 2:
		var h: int = _columns[c].size()
		# За краями кучи — стенки: скатиться туда нельзя.
		var left: int = _columns[c - 1].size() if c > 0 else h + SLOPE_LIMIT
		var right: int = _columns[c + 1].size() if c < PILE_COLUMNS - 1 else h + SLOPE_LIMIT
		if h >= MAX_COLUMN:
			# Колонка упёрлась в предел. Осыпаемся вбок даже по ровному —
			# иначе на плоской вершине скатываться некуда и она растёт
			# выше предела. При равенстве уходим в сторону Бездны.
			if c < PILE_COLUMNS - 1 and right <= left:
				c += 1
			elif c > 0:
				c -= 1
			else:
				return c
			continue
		if h - left >= SLOPE_LIMIT and left <= right:
			c -= 1
		elif h - right >= SLOPE_LIMIT:
			c += 1
		else:
			return c
	return c

## Небольшой разброс внутри ячейки: без него осколки выстраиваются
## в идеальные столбики и куча читается как штрихкод, а не как насыпь.
func _slot_position(column: int, index: int) -> Vector2:
	return Vector2(
		PILE_LEFT_X + column * COLUMN_W + randf_range(-1.6, 1.6),
		GROUND_Y - index * MATERIAL_H + randf_range(-0.8, 0.8)
	)

## Убирает осколок из его колонки. Если он был не сверху — то, что
## лежало выше, оседает вниз: дыра внутри горки недопустима.
func _remove_from_column(item: Area2D) -> bool:
	var c: int = item.column
	if c < 0 or c >= PILE_COLUMNS:
		return false
	var col: Array = _columns[c]
	var idx := col.find(item)
	if idx < 0:
		return false
	col.remove_at(idx)
	item.column = -1
	for i in range(idx, col.size()):
		var above: Area2D = col[i]
		var tween := create_tween()
		tween.tween_property(above, "position", _slot_position(c, i), 0.12).set_trans(Tween.TRANS_SINE)
	return true

## Осыпание всей кучи до устойчивого профиля. Вызывается после каждого
## изъятия: раньше откос держался только в момент укладки, поэтому
## выбитая из середины дыра так и оставалась стоять стеной.
func _avalanche() -> void:
	var guard := 0
	var moved := true
	while moved and guard < 4000:
		moved = false
		for c in PILE_COLUMNS:
			var h: int = _columns[c].size()
			if h == 0:
				continue
			var left: int = _columns[c - 1].size() if c > 0 else h + SLOPE_LIMIT
			var right: int = _columns[c + 1].size() if c < PILE_COLUMNS - 1 else h + SLOPE_LIMIT
			# При равенстве осыпаемся к Бездне — склон должен смотреть туда.
			if h - right >= SLOPE_LIMIT:
				_slide(c, c + 1)
				moved = true
				guard += 1
			elif h - left >= SLOPE_LIMIT:
				_slide(c, c - 1)
				moved = true
				guard += 1

## Один осколок съезжает с вершины колонки на соседнюю.
func _slide(from_c: int, to_c: int) -> void:
	var item: Area2D = _columns[from_c].pop_back()
	_columns[to_c].append(item)
	item.column = to_c
	var spot := _slot_position(to_c, _columns[to_c].size() - 1)
	var tween := create_tween()
	tween.tween_property(item, "position", spot, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Игрок толкает осколок к Бездне: тот выпрыгивает из кучи и падает
## ближе к зеву, а куча за ним осыпается.
func on_shard_clicked(item: Area2D) -> void:
	# Колонку надо запомнить до изъятия: оно сбрасывает её в -1.
	var from_c: int = item.column
	if not _remove_from_column(item):
		return
	var spot := _settle(item, mini(from_c + PUSH_COLUMNS, PILE_COLUMNS - 1))
	var from_y := item.position.y
	var x_tween := create_tween()
	x_tween.tween_property(item, "position:x", spot.x, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var y_tween := create_tween()
	y_tween.tween_property(item, "position:y", minf(from_y, spot.y) - 26.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(item, "position:y", spot.y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_avalanche()

func _pile_size() -> int:
	var total := 0
	for col in _columns:
		total += col.size()
	return total

## Самая высокая колонка — по ней считается давление всасывания.
func _tallest_column() -> int:
	var best := 0
	for col in _columns:
		best = maxi(best, col.size())
	return best

## Визуальный отклик Монолита на удар молитвы.
func _squish_monolit() -> void:
	if _monolit.has_meta("squish_tween"):
		var old: Variant = _monolit.get_meta("squish_tween")
		if old is Tween and old.is_valid():
			old.kill()
	var tween := create_tween()
	_monolit.set_meta("squish_tween", tween)
	_monolit.scale = Vector2(0.95, 1.05)
	tween.tween_property(_monolit, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# --- Носильщики ---------------------------------------------------------

## Выдаёт носильщику ближайший свободный осколок и сразу убирает его из
## общей кучи, чтобы за одним осколком не побежали двое.
## Снимает верхний осколок ближайшей непустой колонки: горка обгрызается
## сверху, дыр внутри неё не появляется.
func claim_nearest_material(from_x: float) -> Area2D:
	var best: Area2D = null
	var best_d := INF
	for c in PILE_COLUMNS:
		var col: Array = _columns[c]
		if col.is_empty():
			continue
		# Ищем сверху вниз первый годный: если Бездна проснулась, мелкие
		# осколки Монолита ей не нужны, и таскать их — не просто впустую,
		# а во вред: они пропадают из кучи, то есть из валюты.
		for i in range(col.size() - 1, -1, -1):
			var item: Area2D = col[i]
			if _delivered_value(item) <= 0:
				continue
			var d := absf(PILE_LEFT_X + c * COLUMN_W - from_x)
			if d < best_d:
				best_d = d
				best = item
			break
	if best == null:
		return null
	_remove_from_column(best)
	_avalanche()
	return best

## Носильщик отказался от осколка (например, исчез сам) — вернуть в кучу.
func release_material(item: Area2D) -> void:
	if not is_instance_valid(item):
		return
	item.position = _settle(item, item.column)

## Носильщик донёс осколок до зева и отпустил его.
func deliver_material(item: Area2D) -> void:
	material_count += _delivered_value(item)
	_material_label.text = "В Бездне: %d" % material_count
	_update_buttons()
	_check_chronicle()
	if is_instance_valid(item):
		var landing := Vector2(_bezdna.position.x - 40.0, _bezdna.position.y + _zasypka_top_y())
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "position", landing, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(item, "scale", Vector2.ZERO, 0.5)
		tween.finished.connect(item.queue_free)
	_pulse_bezdna()
	_update_zasypka()

func _spawn_carrier() -> void:
	var carrier: Node2D = CARRIER_SCENE.instantiate()
	var pile_mid := PILE_LEFT_X + PILE_COLUMNS * COLUMN_W * 0.5
	carrier.position = Vector2(pile_mid + randf_range(-40.0, 60.0), SURFACE_Y - 8.0)
	add_child(carrier)
	carrier.setup(self, THROW_X)
	_carriers.append(carrier)

func _on_create_carrier_button_pressed() -> void:
	if not _spend_shards(_carrier_cost()):
		return
	_spawn_carrier()
	_update_buttons()

func _update_buttons() -> void:
	_update_upgrade_button()
	var carrier_cost := _carrier_cost()
	_carrier_button.text = "Новый носильщик [%d]" % carrier_cost
	_carrier_button.disabled = _pile_size() < carrier_cost
	if _capacity_level >= _upgrade_stats.max_capacity_level:
		_capacity_button.text = "Носить больше [МАКС]"
		_capacity_button.disabled = true
	else:
		var cap_cost := _capacity_cost()
		_capacity_button.text = "Носить больше [%d]" % cap_cost
		_capacity_button.disabled = _pile_size() < cap_cost
	var blocks := int(_crystal_mass / _crystal_stats.mass_per_block)
	_crystal_button.text = "Разбить кристалл [%d блоков]" % blocks
	_crystal_button.disabled = blocks <= 0
	var awake := " — Бездна проснулась, осколки ей мало" if _is_abyss_awake() else ""
	_shard_label.text = "Осколков в куче: %d (по %d за ходку) | кристалл: %d, осколок ×%d%s" % [_pile_size(), carry_capacity, _crystal_mass, _shard_value(), awake]

## Куча меняется от многих причин — добычи, переноски, воровства, трат.
## Дёргать кнопки на каждое событие было бы россыпью вызовов, поэтому
## следим за размером кучи и обновляем UI, только когда он изменился.
func _process(delta: float) -> void:
	if _tell_left > 0.0:
		_tell_left -= delta
		if _tell_left <= 0.0:
			_launch_wave()
	_advance_wave(delta)
	var size := _pile_size()
	if size != _last_pile_size:
		_last_pile_size = size
		_update_buttons()

# --- Апгрейды и кнопки --------------------------------------------------

## Скорость выводится из базы и уровня, а не накапливается в ресурсе:
## иначе она пережила бы «Новую игру» и росла бы бесконечно.
func _apply_carry_speed() -> void:
	carry_speed = _gruhr_stats.carry_speed + _carry_level * _upgrade_stats.speed_bonus
	carry_capacity = 1 + _capacity_level * _upgrade_stats.capacity_bonus

func _capacity_cost() -> int:
	return int(round(_upgrade_stats.capacity_cost_base * pow(_upgrade_stats.capacity_cost_growth, _capacity_level)))

func _on_capacity_button_pressed() -> void:
	if _capacity_level >= _upgrade_stats.max_capacity_level:
		return
	if not _spend_shards(_capacity_cost()):
		return
	_capacity_level += 1
	_apply_carry_speed()
	_update_buttons()

func _on_debug_capacity_button_pressed() -> void:
	if _capacity_level >= DEBUG_MAX_LEVEL:
		return
	_capacity_level += 1
	_apply_carry_speed()
	_update_buttons()

## Валюта — осколки в куче, а не брошенное в Бездну. Брошенное отдано
## насовсем: доставать подношения обратно, чтобы обучить Грухра бегу,
## бессмысленно. Отсюда главный выбор игры: каждый осколок либо
## засыпает Бездну, либо идёт в рост.
func _spend_shards(count: int) -> bool:
	if _pile_size() < count:
		return false
	for i in count:
		var item := _take_shard_for_work()
		if item == null:
			return false
		_consume_shard(item)
	_avalanche()
	return true

## Берём с дальнего от Бездны края: там, где Грухри работают.
## Носильщик берёт ближайший к себе, тёмный — ближний к Бездне.
func _take_shard_for_work() -> Area2D:
	for c in PILE_COLUMNS:
		if not _columns[c].is_empty():
			var item: Area2D = _columns[c].pop_back()
			item.column = -1
			return item
	return null

## Осколок уходит в дело: поднимается и тает.
func _consume_shard(item: Area2D) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position:y", item.position.y - 34.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "modulate:a", 0.0, 0.45)
	tween.tween_property(item, "scale", Vector2(1.8, 1.8), 0.45)
	tween.finished.connect(item.queue_free)

## Цена следующего носильщика и следующего уровня скорости. Растут по
## экспоненте — плоская цена ломает экономику жанра (`UpgradeStats.gd`).
func _carrier_cost() -> int:
	var n := maxi(_carriers.size() - 1, 0)
	return int(round(_upgrade_stats.carrier_cost_base * pow(_upgrade_stats.carrier_cost_growth, n)))

func _speed_cost() -> int:
	return int(round(_upgrade_stats.speed_cost_base * pow(_upgrade_stats.speed_cost_growth, _carry_level)))

func _on_upgrade_button_pressed() -> void:
	if _carry_level >= _upgrade_stats.max_level:
		return
	if not _spend_shards(_speed_cost()):
		return
	_carry_level += 1
	_apply_carry_speed()
	_update_buttons()

func _update_upgrade_button() -> void:
	if _carry_level >= _upgrade_stats.max_level:
		_upgrade_button.text = "Обучить бегу [МАКС]"
		_upgrade_button.disabled = true
		return
	var cost := _speed_cost()
	_upgrade_button.text = "Обучить бегу [%d]" % cost
	_upgrade_button.disabled = _pile_size() < cost

## Отладочные кнопки: то же, что платные, но бесплатно — чтобы щупать
## поздние стадии сразу, не накапливая материал.
func _on_debug_carrier_button_pressed() -> void:
	_spawn_carrier()

## Отладочный предел уровней. Платная кнопка держится за `max_level`,
## отладочная — нет: ей нужно уметь загнать скорость далеко за границу,
## чтобы посмотреть, как ведёт себя игра на поздних стадиях.
const DEBUG_MAX_LEVEL := 100

func _on_debug_speed_button_pressed() -> void:
	if _carry_level >= DEBUG_MAX_LEVEL:
		return
	_carry_level += 1
	_apply_carry_speed()
	_update_buttons()

## Отладка влияет только на силу клика и ничего не меняет в экономике —
## иначе выключение режима не возвращало бы игру в исходное состояние.
func _on_debug_button_pressed() -> void:
	_is_debug_mode = not _is_debug_mode
	$UI/DebugButton.text = "Debug x%d ВКЛ" % DEBUG_CLICK_BURST if _is_debug_mode else "Debug x%d" % DEBUG_CLICK_BURST

func _on_new_game_button_pressed() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().reload_current_scene()

func _on_autosave_timer_timeout() -> void:
	save_game()

# --- Всасывание (T0013) -------------------------------------------------

## Бездна не ждёт подношений вечно. Пока горка ниже порога, она терпит;
## как только куча перерастает его — начинает утаскивать осколки сама,
## и они пропадают бесследно. Засчитывается только то, что Грухр принёс:
## взятое Бездной силой не идёт в засыпку (`docs/02_World/Abyss.md`).
func _on_reclaim_timer_timeout() -> void:
	var excess := _tallest_column() - _abyss_stats.reclaim_threshold
	if excess <= 0:
		_hide_pylesos()
		return
	_show_pylesos()
	# Держим его на уровне засыпки: она растёт — он всплывает вместе с ней.
	var perch := _pylesos_perch()
	if _pylesos.position.distance_to(perch) > 2.0:
		var move := create_tween()
		move.tween_property(_pylesos, "position", perch, 0.8).set_trans(Tween.TRANS_SINE)
	_aim_and_blast()
	var count := int(ceilf(excess * _abyss_stats.reclaim_per_excess))
	for i in count:
		var item := _steal_nearest_shard()
		if item == null:
			break
		_suck_into_pylesos(item)
	_avalanche()

## Крадёт с края кучи, ближнего к Бездне: пылесос дотягивается только
## до того, что рядом с ним, а не до вершины на другом конце насыпи.
func _steal_nearest_shard() -> Area2D:
	for c in range(PILE_COLUMNS - 1, -1, -1):
		if not _columns[c].is_empty():
			var item: Area2D = _columns[c].pop_back()
			item.column = -1
			return item
	return null

## Пока простая анимация втягивания. На будущее: осколки должны катиться
## к пылесосу по земле и подпрыгивать, медленно.
func _suck_into_pylesos(item: Area2D) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position", _pylesos.position, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(item, "scale", Vector2.ZERO, 0.6)
	tween.finished.connect(item.queue_free)

## Тёмный вылезает из Бездны, когда куча перерастает порог, и вытягивает
## осколки пылесосом. Это снимает противоречие: осколки не «падают в
## Бездну сами собой» — их уносит враг, поэтому в засыпку они и не идут
## (`docs/02_World/DarkCivilization.md`).
const PYLESOS_HIDDEN_Y := 660.0

## Тёмный цепляется за правую стенку Бездны на уровне засыпки. Пока
## Бездна пуста, он в самом низу — не достать. Чем выше поднимается
## засыпка, тем выше всплывает и он: игрок сам подтягивает его к себе.
## Что с этим делать дальше — `docs/02_World/DarkCivilization.md`.
func _pylesos_perch() -> Vector2:
	var right: PackedVector2Array = _shaft_sides()[1]
	var depth := _zasypka_top_y()
	return _bezdna.position + Vector2(_interp_x(right, depth) - 16.0, depth - 10.0)

func _show_pylesos() -> void:
	if _pylesos_active:
		return
	_pylesos_active = true
	_pylesos.visible = true
	var tween := create_tween()
	tween.tween_property(_pylesos, "position", _pylesos_perch(), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_pylesos() -> void:
	if not _pylesos_active:
		return
	_pylesos_active = false
	var tween := create_tween()
	tween.tween_property(_pylesos, "position:y", PYLESOS_HIDDEN_Y, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _pylesos.visible = false)

## Струя показывает, куда он нацелен: без неё воровство выглядит как
## случайное исчезновение осколков, а не как чужое действие.
## Сколько струек воздуха пускать за один тик воровства.
const AIR_STREAKS := 6

## Направление показывает короткий раструб у сопла, а сам факт воровства —
## потоки воздуха, летящие от кучи к тёмному. Длинный луч через полэкрана
## забирал на себя всё внимание и загораживал наблюдение за кучей.
func _aim_and_blast() -> void:
	var from := Vector2(PILE_LEFT_X + PILE_COLUMNS * COLUMN_W * 0.4, GROUND_Y - 20.0)
	var to_pile := from - _pylesos.position
	_nozzle.rotation = to_pile.angle()
	var struya: Polygon2D = _nozzle.get_node("Struya")
	var tween := create_tween()
	tween.tween_property(struya, "modulate:a", 0.3, 0.12)
	tween.tween_property(struya, "modulate:a", 0.12, 0.5)
	_spawn_air_flow(from, _pylesos.position)

## Тонкие штрихи летят от кучи к тёмному. Они мелкие и живут доли
## секунды, поэтому показывают направление кражи, ничего не загораживая.
func _spawn_air_flow(from: Vector2, to: Vector2) -> void:
	var dir := (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	for i in AIR_STREAKS:
		var streak := Polygon2D.new()
		streak.color = Color(0.85, 0.45, 0.45, 1)
		streak.modulate.a = 0.0
		var pts := PackedVector2Array()
		pts.push_back(Vector2(-6.0, -0.7))
		pts.push_back(Vector2(6.0, -0.7))
		pts.push_back(Vector2(6.0, 0.7))
		pts.push_back(Vector2(-6.0, 0.7))
		streak.polygon = pts
		streak.rotation = dir.angle()
		var off := perp * randf_range(-14.0, 14.0)
		streak.position = from + off + dir * randf_range(0.0, 70.0)
		add_child(streak)
		var delay := randf_range(0.0, 0.4)
		var move := create_tween()
		move.tween_interval(delay)
		move.tween_property(streak, "position", to + off * 0.25, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		move.tween_callback(streak.queue_free)
		var fade := create_tween()
		fade.tween_interval(delay)
		fade.tween_property(streak, "modulate:a", 0.6, 0.12)
		fade.tween_interval(0.4)
		fade.tween_property(streak, "modulate:a", 0.0, 0.18)

# --- Дыхание Бездны (T0018 + T0019) -------------------------------------

## Дуга перестраивается по реальному радиусу, а не масштабируется:
## `Line2D` масштабирует и толщину линии, и волна превращалась в купол.
## Полукруг вверх — волна идёт по поверхности, не под землёй.
func _build_wave_arc(radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := PI + PI * float(i) / 32.0
		pts.push_back(Vector2(cos(a) * radius, sin(a) * radius * 0.55))
	_volna.points = pts

## Чем больше засыпали с прошлой волны, тем скорее следующая. Бездна
## огрызается на жадность, а не по расписанию.
func _arm_wave() -> void:
	var gained := material_count - _fill_at_last_wave
	_fill_at_last_wave = material_count
	var interval: float = _abyss_stats.wave_base_interval / (1.0 + gained * _abyss_stats.wave_greed)
	_wave_timer.wait_time = maxf(interval, _abyss_stats.wave_floor_interval)
	_wave_timer.start()

## Волна начинается не сразу: сначала Бездна видимо набирает воздух.
## Полторы секунды — окно, в которое игрок может ответить (ADR-005).
func _on_wave_timer_timeout() -> void:
	_tell_left = _abyss_stats.tell_duration
	_ducked = false
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(0.9, 0.94), _abyss_stats.tell_duration).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_bezdna, "modulate", Color(2.6, 1.1, 2.4, 1), _abyss_stats.tell_duration)
	_arm_wave()

## Клик в любом месте во время замаха — всё племя разом пригибается.
## Именно всё, а не по одному: при дюжине носильщиков дюжина кликов за
## полторы секунды невозможна, и защита слабела бы с прогрессом игрока.
func _input(event: InputEvent) -> void:
	if _tell_left <= 0.0 or _ducked:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_ducked = true
	for c in _carriers:
		if is_instance_valid(c):
			c.duck(_abyss_stats.duck_duration)

func _launch_wave() -> void:
	_tell_left = -1.0
	_wave_radius = 0.0
	_wave_hit.clear()
	# Успевшие пригнуться волну пропускают над собой.
	if _ducked:
		for c in _carriers:
			_wave_hit.append(c)
	_volna.visible = true
	_volna.modulate.a = 0.9
	var back := create_tween()
	back.tween_property(_bezdna, "scale", Vector2(1.12, 1.06), 0.12).set_trans(Tween.TRANS_BACK)
	back.parallel().tween_property(_bezdna, "modulate", Color(1, 1, 1, 1), 0.3)
	back.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_SINE)

## Волна расходится из зева. Кого накрыло — того сбивает: груз падает
## обратно в кучу, носильщик стоит оглушённый. Носильщики и есть узкое
## место, поэтому кара летит именно в них.
func _advance_wave(delta: float) -> void:
	if _wave_radius < 0.0:
		return
	_wave_radius += _abyss_stats.wave_speed * delta
	_build_wave_arc(_wave_radius)
	_volna.modulate.a = maxf(0.0, 0.9 - _wave_radius / 900.0)
	for c in _carriers:
		if not is_instance_valid(c) or c in _wave_hit:
			continue
		if absf(c.position.x - _volna.position.x) <= _wave_radius:
			_wave_hit.append(c)
			c.stun(_abyss_stats.stun_duration)
	if _wave_radius > 900.0:
		_wave_radius = -1.0
		_volna.visible = false

# --- Летописец ----------------------------------------------------------

## Проходим по записям и показываем первую сработавшую.
## Пороги и текст в `ChronicleEntries.tres` — не в коде.
func _check_chronicle() -> void:
	for entry in _chronicle_entries.entries:
		if _chronicle_hit(entry):
			_chronicle_label.text = entry.text
			_chronicle_label.visible = true
			return

## Числа совпадают с enum ChronicleEntry.Trigger: 0 = первое подношение,
## 1 = N-й материал, 2 = половина ёмкости.
func _chronicle_hit(entry: Resource) -> bool:
	match entry.trigger:
		0:
			return material_count == 1
		1:
			return material_count == entry.threshold
		2:
			return material_count == _abyss_stats.capacity / 2
	return false

# --- Бездна -------------------------------------------------------------

## Уровень засыпки: главный видимый прогресс игры. Форма берётся
## из самой полости Бездны, чтобы засыпка ложилась по её стенкам,
## а не торчала прямоугольником.
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
	var left: PackedVector2Array = _shaft_sides()[0]
	var bottom_y: float = left[left.size() - 1].y
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

func _pulse_bezdna() -> void:
	var tween := create_tween()
	tween.tween_property(_bezdna, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bezdna, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
