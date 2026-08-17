extends Polygon2D

## Осколок материала. Хранит target_x для расчёта высоты кучи.

var age := 0.0
var target_x := 0.0

func _process(delta: float) -> void:
	age += delta
