extends Polygon2D

## Осколок материала. Считает возраст и начинает притягиваться
## к Бездне, если лежит на земле дольше reclaim_time (T0013).

var age := 0.0
var reclaiming := false

var _abyss_stats: Resource = preload("res://game/resources/AbyssStats.tres")

signal reclaimed(item: Polygon2D)

func _process(delta: float) -> void:
	age += delta
	if not reclaiming and age >= _abyss_stats.reclaim_time:
		reclaiming = true
	if reclaiming:
		var target := Vector2(760.0, 280.0)
		var dir := (target - position).normalized()
		position += dir * _abyss_stats.reclaim_speed * delta
		if position.distance_to(target) < 12.0:
			reclaimed.emit(self)
			queue_free()
