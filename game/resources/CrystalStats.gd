extends Resource
class_name CrystalStats

## Кристалл растёт сам, по времени — игрок ростом не управляет
## (`docs/decisions/ADR-004-crystal-instead-of-house.md`).
@export var grow_interval: float = 3.0
@export var grow_amount: int = 1
@export var max_mass: int = 48

## Сколько массы нужно, чтобы осколки от молитвы стали крупнее на единицу.
@export var mass_per_shard_value: int = 8

## Сколько массы уходит в один крупный блок при разбивании.
@export var mass_per_block: int = 4

## Сколько засыпки даёт один блок разбитого кристалла.
@export var block_value: int = 5
