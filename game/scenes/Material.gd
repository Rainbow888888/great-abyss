extends Area2D

## Осколок материала. Хранит target_x для расчёта высоты кучи.
## По клику прыгает дугой в сторону Бездны.

var age := 0.0
var target_x := 0.0
var velocity := Vector2.ZERO

const PUSH_FORCE_X := 180.0
const PUSH_FORCE_Y := -120.0
const DRAG := 0.95

func _ready() -> void:
	input_event.connect(_on_input_event)

func _process(delta: float) -> void:
	age += delta
	if velocity.length() > 0.1:
		position += velocity * delta
		velocity.x *= DRAG
		velocity.y += 400.0 * delta

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		velocity = Vector2(PUSH_FORCE_X, PUSH_FORCE_Y)
