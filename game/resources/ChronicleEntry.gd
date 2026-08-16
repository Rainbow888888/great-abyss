extends Resource
class_name ChronicleEntry

## Одна запись Летописца: на какой триггер показывается и какой текст.
## Тексты живут в .tres, не в коде (T0011). Тон — docs/04_Content/Chronicle.md.

enum Trigger { FIRST_THROW, NTH_MATERIAL, HALF_ABYSS }

@export var trigger: Trigger = Trigger.FIRST_THROW

## Для NTH_MATERIAL — номер броска. Для остальных не используется.
@export var threshold: int = 10

@export var text: String = ""
