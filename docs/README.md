# docs/ — Нормативно-справочный слой

Реестр документации проекта (README §3.2). Любое решение, паттерн, схема или отчёт хранятся только здесь.

| Подкаталог | Назначение | Ключевые документы |
|---|---|---|
| `rules/` | Свод правил автоматизации | `AUTOMATION_RULES.md`, `RULES_CHANGELOG.md` |
| `decisions/` | Architecture Decision Records | `ADR-NNNN-<TITLE>.md` |
| `patterns/` | Верифицированные паттерны | `PAT-INDEX.md`, `PAT-NN-*.md` |
| `artifacts/` | Отчёты этапов и процедуры | `Stage<N>_Report.md`, `Final_Report.md`, `Recovery_Procedure.md` |
| `storage/` | Схемы накопителей и исследования разметки | `C_drive_schema.md`, `D_drive_schema.md`, `F_drive_schema.md`, `partitioning_research.md` |
| `research/` | Исследовательские материалы (якорь1, step1–step5) | `anchor1.md`, `step1.md` … `step5.md` |
| `core-tweaks/` | Карта твиков ядра и реестра | `TWEAK_INDEX.md`, `REGISTRY_MAP.md`, `BCD_REFERENCE.md`, `ACL_MATRIX.md` |
| `packages/` | Реестр пакетов winget | `PACKAGE_INDEX.md`, `WINGET_POLICY.md`, `SOURCES.md` |
| `devops/` | Схемы гипервизорного контура | `WSL2_SCHEMA.md`, `HYPERVISOR_MATRIX.md`, `P_E_CORE_AFFINITY.md` |

**Правила:** STRUC_003 (у каждого каталога README.md), §3.3 README (обязательные поля документов), AR-801 (коммит = документ + код).
