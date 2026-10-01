# templates/ — Шаблоны

| Шаблон | Назначение | Статус |
|---|---|---|
| `ADR-template.md` | Заготовка Architecture Decision Record (§3.2 README) | DONE |
| `Pattern-template.md` | Заготовка паттерна (`PAT-NN`) | DONE |
| `Stage-Report-template.md` | Заготовка отчёта этапа (§3.3 README) | DONE |
| `Script-template.ps1` | Эталон шапки скрипта (AR-401/AR-402/AR-403) | DONE |
| `rules-template.md` | Заготовка новой группы правил для `AUTOMATION_RULES.md` | DONE |
| `u_w11_ltsc_iot.xml.template` | Первый файл ответов (Ventoy, Audit Mode) — UTF-8 **без BOM**, CRLF | DONE (Stage 2) |
| `unattend.xml.template` | Второй файл ответов (Sysprep, CopyProfile) — UTF-8 **без BOM** | PLAN (Stage 5) |
| `ventoy.json.template` | Конфигурация Ventoy `auto_install` | DONE (Stage 2) |

**Правила:** STRUC_010 (XML-шаблоны с расширением `.template`); кодировка XML-шаблонов — UTF-8 без BOM (AR-101, `docs/research/step1.md`).
