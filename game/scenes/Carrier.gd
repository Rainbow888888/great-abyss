extends Polygon2D
class_name Carrier

## Носильщик. Сам находит ближайшие осколки, поднимает их силой мысли
## и несёт к краю Бездны. За ходку берёт столько, сколько позволяет
## вместимость — вторая ось транспорта наравне со скоростью.
##
## Состояние у каждого носильщика своё, поэтому их может быть много.
## Осколок «застолблён» с момента выбора цели: Main выдаёт его из общей
## кучи и сразу убирает оттуда, так что двое за одним не побегут.

enum State { IDLE, TO_MATERIAL, TO_ABYSS }

## Осколки висят над носильщиком дугой, а не лежат в руках: Светлые
## переносят мыслью (`docs/02_World/LightCivilization.md`).
const ORBIT_RADIUS := 17.0
const ORBIT_SPREAD := 0.5

var _state: State = State.IDLE
var _target: Area2D = null
var _carried: Array[Area2D] = []
var _main: Node = null
var _throw_x := 0.0

## Сколько секунд носильщик ещё оглушён волной Бездны.
var _stun_left := 0.0

## Пригибание по команде игрока: короткий простой, но груз при себе.
var _duck_left := 0.0

## Фигура: ноги, туника, рука, голова, борода. Позы живут в ней,
## носильщик только говорит, какую встать.
var _figura: GruhrBody = null

## Обесцвечивание при оглушении. Живёт отдельно от позы: поза двигает
## части, цвет красит всю фигуру разом через `modulate` носильщика.
var _fade_tween: Tween = null

## Носильщик — бывший кружок радиусом 8. Полигон гасится, на его место
## встаёт фигура: так не пришлось трогать ни `Carrier.tscn`, ни
## `Main.tscn`, где первый Грухр лежит отдельным узлом со своим цветом.
func _ready() -> void:
	_figura = GruhrBody.new()
	_figura.build(color)
	add_child(_figura)
	polygon = PackedVector2Array()

func _fade_to(c: Color, secs: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate", c, secs)

## Игрок успел скомандовать «ложись»: носильщик приникает к земле,
## теряет секунду работы и волну пропускает над собой. Груз остаётся —
## платим временем, а не работой (ADR-005).
func duck(duration: float) -> void:
	if _stun_left > 0.0:
		return
	_duck_left = maxf(_duck_left, duration)
	# Присел: цвет свой, ноги подогнуты почти до земли. Он в порядке.
	_figura.set_pose("duck", duration)

## Волна Бездны сбивает носильщика: он роняет груз обратно в кучу и
## какое-то время не может идти. Кара бьёт по транспорту — по узкому
## месту игры (`docs/05_References/DesignReferences.md`).
func stun(duration: float) -> void:
	_stun_left = maxf(_stun_left, duration)
	_duck_left = 0.0
	if is_instance_valid(_target):
		_main.release_material(_target)
		_target = null
	for item in _carried:
		if is_instance_valid(item):
			_main.release_material(item)
	_carried.clear()
	_state = State.IDLE
	# Сбит: лежит поперёк и обесцвечен. От присевшего его отличает уже
	# не только цвет — лежащий занимает пять пикселей высоты вместо
	# двенадцати, и это видно без всякого сравнения.
	_figura.set_pose("down", duration)
	_fade_to(Color(0.6, 0.62, 0.66, 1), 0.12)
	var back := create_tween()
	back.tween_interval(maxf(duration - 0.34, 0.0))
	back.tween_callback(func() -> void: _fade_to(Color(1, 1, 1, 1), 0.22))

## Волна докатилась, но носильщик устоял — согнуло, не свалило.
## Груз при себе, простой короткий. Отличается от «присел» и «сбит»
## именно ростом: он остаётся высоко, те двое лежат (ADR-005 — состояния
## различаются высотой над землёй, а не деталью позы).
func withstand(duration: float) -> void:
	if _stun_left > 0.0:
		return
	_duck_left = maxf(_duck_left, duration)
	_figura.set_pose("withstand", duration)

func is_stunned() -> bool:
	return _stun_left > 0.0

func is_ducking() -> bool:
	return _duck_left > 0.0

## Точку сброса передаём значением, а не читаем константу с чужого
## скрипта: так носильщик не зависит от устройства Main.
func setup(main: Node, throw_x: float) -> void:
	_main = main
	_throw_x = throw_x

func _process(delta: float) -> void:
	if _main == null:
		return
	if _duck_left > 0.0:
		_duck_left -= delta
		# Груз пригибается вместе с носильщиком, а не висит в воздухе.
		_hold_carried()
		return
	if _stun_left > 0.0:
		_stun_left -= delta
		return
	match _state:
		State.IDLE:
			_target = _main.claim_nearest_material(position.x)
			if _target != null:
				_state = State.TO_MATERIAL
			elif not _carried.is_empty():
				# Осколков больше нет — несём то, что уже набрали,
				# иначе носильщик простоит с грузом в руках.
				_state = State.TO_ABYSS
		State.TO_MATERIAL:
			if not is_instance_valid(_target):
				_target = null
				_state = State.IDLE
			elif _step_toward(_target.position.x, delta):
				_carried.append(_target)
				_target = null
				_state = State.TO_ABYSS if _is_full() else State.IDLE
		State.TO_ABYSS:
			if _step_toward(_throw_x, delta):
				for item in _carried:
					_main.deliver_material(item)
				_carried.clear()
				_state = State.IDLE
	_figura.set_walking(_state != State.IDLE)
	_hold_carried()

func _is_full() -> bool:
	return _carried.size() >= maxi(int(_main.carry_capacity), 1)

## Раскладывает груз дугой над головой — по одному осколку видно, что
## носильщик несёт один, по пяти видно, что пять.
func _hold_carried() -> void:
	# Груз опускается вместе с позой: раньше это выходило само, потому
	# что позу играл сам носильщик, теперь двигается фигура внутри.
	var sag := Vector2(0.0, _figura.pose_offset())
	for i in _carried.size():
		var item: Area2D = _carried[i]
		if not is_instance_valid(item):
			continue
		var offset := (i - (_carried.size() - 1) * 0.5) * ORBIT_SPREAD
		var angle := -PI * 0.5 + offset
		item.position = position + sag + Vector2(cos(angle), sin(angle)) * ORBIT_RADIUS

## Двигает носильщика к цели по горизонтали. true — дошёл.
func _step_toward(target_x: float, delta: float) -> bool:
	var dx := target_x - position.x
	var step: float = _main.carry_speed * delta
	if absf(dx) <= step:
		position.x = target_x
		return true
	position.x += signf(dx) * step
	return false

## Носильщик исчезает (перезапуск сцены) — вернуть груз в общую кучу,
## иначе осколки повиснут ничьи и их никто не заберёт.
func _exit_tree() -> void:
	if _main == null:
		return
	if is_instance_valid(_target):
		_main.release_material(_target)
	for item in _carried:
		if is_instance_valid(item):
			_main.release_material(item)
