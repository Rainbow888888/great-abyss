extends Node2D
class_name GruhrBody

## Фигура Грухра: ноги, туника, рука, голова, борода. Раньше Грухр был
## кружком радиусом 8, и все позы делались сжатием по вертикали.
##
## Сжатый кружок читается. Сжатая фигура — нет: гном, ужатый до трети
## роста, превращается в мазок. Поэтому поза больше не сжатие, а
## положение частей: ноги подгибаются, корпус наклоняется, сбитый
## лежит на боку.
##
## Это не украшение, а условие работы волны. ADR-005 требует, чтобы
## состояния после удара различались ВЫСОТОЙ над землёй. Теперь высоты
## настоящие, а не масштаб:
##
##   стоит     16 px
##   устоял    ~15 px, но заметно наклонён
##   пригнулся ~12 px
##   сбит       ~5 px, лежит поперёк
##
## Силуэт держится на бороде: на шестнадцати пикселях ни лицо, ни поза
## рук не читаются, а широкий белый клин под головой читается всегда.

## Ноги растут вниз от бедра, поэтому и подгибаются от него же.
const HIP_Y := 4.0
const LEG_LEN := 4.0

## Низ фигуры. Совпадает с линией земли, на которой стоит носильщик.
const FOOT_Y := HIP_Y + LEG_LEN

const SKIN := Color(0.93, 0.83, 0.66, 1)
const BEARD := Color(0.94, 0.95, 0.91, 1)
## Сапоги светлее земли намеренно. Первая версия была (0.26, 0.23, 0.2)
## — почти в цвет `Zemlya` (0.24, 0.2, 0.17), и ноги пропадали ровно в
## тот момент, когда касались грунта. Ноги — единственное, чем читается
## шаг, поэтому им нужен контраст и с землёй, и с небом.
const BOOT := Color(0.5, 0.4, 0.28, 1)

## Позы: сдвиг фигуры вниз, наклон корпуса, остаток длины ног.
## «Лежит» — это поворот на четверть оборота, а не сплющивание, и
## сдвиг вниз ровно такой, чтобы лежащий касался земли боком.
const POSES := {
	"stand": {"y": 0.0, "rot": 0.0, "legs": 1.0},
	"withstand": {"y": 1.0, "rot": 0.26, "legs": 0.8},
	"duck": {"y": 4.0, "rot": 0.4, "legs": 0.15},
	"down": {"y": 3.0, "rot": -PI * 0.5, "legs": 1.0},
}

var _nogi: Node2D
var _leg_l: Polygon2D
var _leg_r: Polygon2D
var _pose := "stand"
var _pose_tween: Tween = null
var _walking := false
var _walk_phase := 0.0

## Собирает фигуру. Цвет туники приходит снаружи: им же различаются
## носильщик (зелёный) и добытчик (бирюзовый), как различались кружки.
func build(tunic: Color) -> void:
	_nogi = Node2D.new()
	_nogi.position = Vector2(0.0, HIP_Y)
	add_child(_nogi)
	_leg_l = _part(_rect(-3.4, 0.0, -0.8, LEG_LEN), BOOT, _nogi)
	_leg_r = _part(_rect(0.8, 0.0, 3.4, LEG_LEN), BOOT, _nogi)

	_part(PackedVector2Array([
		Vector2(-4.2, -4.2), Vector2(4.2, -4.2),
		Vector2(5.0, HIP_Y + 0.5), Vector2(-5.0, HIP_Y + 0.5),
	]), tunic)
	_part(_rect(3.8, -2.5, 5.8, 2.0), tunic.darkened(0.18))

	_part(PackedVector2Array([
		Vector2(-3.2, -8.2), Vector2(0.0, -8.6), Vector2(3.2, -8.2),
		Vector2(3.4, -4.6), Vector2(0.0, -3.8), Vector2(-3.4, -4.6),
	]), SKIN)
	# Борода узкая намеренно. В первой версии она закрывала тунику
	# целиком, и цвет, которым различаются носильщик и добытчик,
	# пропадал — силуэт выигрывал, а работающее различие терялось.
	_part(PackedVector2Array([
		Vector2(-3.6, -4.8), Vector2(3.6, -4.8), Vector2(2.8, -1.0),
		Vector2(1.4, 1.6), Vector2(0.0, 2.4), Vector2(-1.4, 1.6),
		Vector2(-2.8, -1.0),
	]), BEARD)

func _rect(x1: float, y1: float, x2: float, y2: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x1, y1), Vector2(x2, y1), Vector2(x2, y2), Vector2(x1, y2),
	])

func _part(pts: PackedVector2Array, c: Color, parent: Node = null) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = c
	if parent == null:
		add_child(p)
	else:
		parent.add_child(p)
	return p

## Встать в позу и, если задано время, самому вернуться в «стоит».
## Твин один на всю фигуру и гасится перед новым: две анимации,
## тянущие одни и те же части, уже давали растянутую кляксу.
func set_pose(pose: String, hold: float = 0.0) -> void:
	if not POSES.has(pose):
		return
	_pose = pose
	var p: Dictionary = POSES[pose]
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.set_parallel(true)
	_pose_tween.tween_property(self, "position:y", p["y"], 0.1)
	_pose_tween.tween_property(self, "rotation", p["rot"], 0.1)
	_pose_tween.tween_property(_nogi, "scale:y", p["legs"], 0.1)
	if hold <= 0.0:
		return
	var back: Dictionary = POSES["stand"]
	_pose_tween.chain().tween_interval(maxf(hold - 0.32, 0.0))
	_pose_tween.chain().tween_property(self, "position:y", back["y"], 0.22)
	_pose_tween.parallel().tween_property(self, "rotation", back["rot"], 0.22)
	_pose_tween.parallel().tween_property(_nogi, "scale:y", back["legs"], 0.22)
	_pose_tween.chain().tween_callback(func() -> void: _pose = "stand")

## На сколько груз должен опуститься вместе с носильщиком. Раньше это
## получалось само: позу играл сам носильщик, и груз висел от него.
## Теперь двигается фигура внутри, и груз надо опускать явно.
func pose_offset() -> float:
	return position.y

func set_walking(on: bool) -> void:
	_walking = on

## Шаг рисуется только когда Грухр действительно стоит на ногах.
## В любой другой позе ноги заняты позой.
func _process(delta: float) -> void:
	if _pose != "stand":
		return
	if not _walking:
		_leg_l.position.x = 0.0
		_leg_r.position.x = 0.0
		return
	_walk_phase += delta * 9.0
	var s := sin(_walk_phase)
	_leg_l.position.x = s * 1.6
	_leg_r.position.x = -s * 1.6
	position.y = -absf(s) * 0.6
