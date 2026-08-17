extends Area2D

## Осколок материала. Хранит target_x для расчёта высоты кучи.
## По клику получает горизонтальный импульс вправо (T0015).

var age := 0.0
var target_x := 0.0
var velocity := Vector2.ZERO

const PUSH_FORCE := 60.0
const DRAG := 0.92

func _ready() -> void:
	input_event.connect(_on_input_event)

func _process(delta: float) -> void:
	age += delta
	if velocity.x > 0.1:
		position.x += velocity.x * delta
		velocity.x *= DRAG
	else:
		velocity.x = 0.0

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		velocity.x = PUSH_FORCE
