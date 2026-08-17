extends Resource
class_name UpgradeStats

## Стоимость каждого уровня апгрейда (в материале, брошенном в Бездну).
@export var cost_per_level: int = 5

## На сколько увеличивается carry_speed за уровень.
@export var speed_bonus: float = 15.0

## Максимальный уровень.
@export var max_level: int = 3
