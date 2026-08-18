extends Resource
class_name UpgradeStats

## Цены растут по экспоненте, а не плоские. Плоская цена — известная
## ошибка жанра: производители дешевеют относительно дохода, и валюта
## начинает расти экспоненциально, то есть игра ломается сама.
## Проверенный коридор множителей в жанре — 1.07–1.15 (Clicker Heroes,
## Cookie Clicker, AdVenture Capitalist). Для покупок, которых за партию
## всего несколько, множитель берём круче: иначе разницы не почувствовать.

## Первый носильщик после стартового.
@export var carrier_cost_base: int = 8

## Во сколько раз дорожает каждый следующий носильщик.
@export var carrier_cost_growth: float = 1.5

## Первый уровень «Обучить бегу».
@export var speed_cost_base: int = 5

## Во сколько раз дорожает каждый следующий уровень скорости.
@export var speed_cost_growth: float = 2.0

## На сколько увеличивается carry_speed за уровень.
@export var speed_bonus: float = 15.0

## Максимальный уровень скорости.
@export var max_level: int = 3

## Вместимость — вторая ось транспорта. В Gnorp Apologue логистику
## качают и по скорости, и по вместимости; одна ходка = один осколок
## была настоящим потолком, скорость его не снимала.
@export var capacity_cost_base: int = 12
@export var capacity_cost_growth: float = 2.0

## Сколько осколков носильщик берёт за ходку сверх одного.
@export var capacity_bonus: int = 1
@export var max_capacity_level: int = 4
