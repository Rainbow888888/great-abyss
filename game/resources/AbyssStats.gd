extends Resource
class_name AbyssStats

## Сколько объектов-материалов заполняет Бездну целиком.
## Прототипное число: подбирается на глаз, чтобы движение уровня
## было заметно с каждого броска и при этом было куда расти.
@export var capacity: int = 60

## Через сколько секунд лежащий на земле осколок начинает
## притягиваться к Бездне и уничтожаться (реклейм, T0013).
@export var reclaim_time: float = 20.0

## С какой скоростью (px/с) притягивается к Бездне.
@export var reclaim_speed: float = 40.0

## Насколько высота кучи ускоряет реклейм (T0014).
## Порог = reclaim_time / (1 + pile_surge_factor * pile_height).
@export var pile_surge_factor: float = 0.05
