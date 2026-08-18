extends Polygon2D
class_name Carrier

## Носильщик. Сам находит ближайший осколок, идёт к нему, поднимает
## силой мысли и несёт к краю Бездны.
##
## Состояние у каждого носильщика своё, поэтому их может быть много.
## Осколок «застолблён» с момента выбора цели: Main выдаёт его из общей
## кучи и сразу убирает оттуда, так что двое за одним не побегут.

enum State { IDLE, TO_MATERIAL, TO_ABYSS }

## Осколок висит над носильщиком, а не в руках: Светлые переносят
## мыслью (`docs/02_World/LightCivilization.md`).
const CARRY_OFFSET := Vector2(0, -14)

var _state: State = State.IDLE
var _target: Area2D = null
var _carried: Area2D = null
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
		State.TO_MATERIAL:
			if not is_instance_valid(_target):
				_target = null
				_state = State.IDLE
			elif _step_toward(_target.position.x, delta):
				_carried = _target
				_target = null
				_state = State.TO_ABYSS
		State.TO_ABYSS:
			if _step_toward(_throw_x, delta):
				var item := _carried
				_carried = null
				_state = State.IDLE
				_main.deliver_material(item)
	if _carried != null:
		_carried.position = position + CARRY_OFFSET

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
## иначе осколок повиснет ничей и его никто не заберёт.
func _exit_tree() -> void:
	if _main == null:
		return
	if is_instance_valid(_target):
		_main.release_material(_target)
	if is_instance_valid(_carried):
		_main.release_material(_carried)
