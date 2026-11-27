# Lesson 08 — статус

- Lesson 01–07: пользователь подтвердил работу боевой системы и исправления границы ближней атаки.
- Lesson 08: реализация первого событийного движка, 9 правил (4 классовых и 5 тестовых реликвий), 2 пары стихийных реакций и повторное охлаждение. Состояние: реализовано, статическая проверка, ожидает запуска и приёмки в Godot.
- Сохранены ресурсы классов пользователя, тестовые модели, исправления HP и ближнего боя, поддержка лечения и R.
- Следующий этап после приёмки: рунный автомат.

## CHANGELOG
- Added effect_catalog.gd, effect_engine.gd, tests/test_effects.gd.
- Added effects to resource schema (default effects by class and extra rule IDs).
- Added runtime status state, shield, labels, freeze handling to units.
- Added test relic configuration and RNG seed to Main.
- No changes to assets or existing scene/resource files.
