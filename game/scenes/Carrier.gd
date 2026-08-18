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

## Точку сброса передаём значением, а не читаем константу с чужого
## скрипта: так носильщик не зависит от устройства Main.
func setup(main: Node, throw_x: float) -> void:
	_main = main
	_throw_x = throw_x

func _process(delta: float) -> void:
	if _main == null:
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
	_hold_carried()

func _is_full() -> bool:
	return _carried.size() >= maxi(int(_main.carry_capacity), 1)

## Раскладывает груз дугой над головой — по одному осколку видно, что
## носильщик несёт один, по пяти видно, что пять.
func _hold_carried() -> void:
	for i in _carried.size():
		var item: Area2D = _carried[i]
		if not is_instance_valid(item):
			continue
		var offset := (i - (_carried.size() - 1) * 0.5) * ORBIT_SPREAD
		var angle := -PI * 0.5 + offset
		item.position = position + Vector2(cos(angle), sin(angle)) * ORBIT_RADIUS

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
