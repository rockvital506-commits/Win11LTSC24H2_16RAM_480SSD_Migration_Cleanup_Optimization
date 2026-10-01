# docs/artifacts/ — Отчёты и процедуры

| Документ | Содержание | Статус |
|---|---|---|
| `Stage0_Report.md` | Отчёт инициализации репозитория | **DONE** |
| `Stage1_Report.md` | Отчёт разметки NVMe (ожидает нативного прогона верификатора) | IN_PROGRESS |
| `Stage2_Report.md` | Отчёт Ventoy-контура и Audit Mode (ожидает проверок A1–A7) | IN_PROGRESS |
| `Stage3_Report.md` | Отчёт накопительных обновлений (ожидает прогона U1–U7) | IN_PROGRESS |
| `Stage4_Report.md` | Отчёт финальной санитарии Audit Mode (ожидает прогона W1–N1) | IN_PROGRESS |
| `Stage4_tweakstate.md` | Отчёт верификации состояния твиков (генерируется скриптом на хосте) | PENDING |
| `Stage5_Report.md` | Отчёт запечатывания Sysprep (ожидает прогона P0.1–S6) | IN_PROGRESS |
| `Stage5_preflight.md` | Предпролётный отчёт подготовки к Sysprep (генерируется скриптом на хосте) | PENDING |
| `Stage6_Report.md` | Отчёт контура самозащиты и окна активации (ожидает окна активации и `-VerifyOnly`) | IN_PROGRESS |
| `Stage6_preflight.md` | Предпролётный отчёт подготовки контура (генерируется скриптом на хосте) | PENDING |
| `Stage6_immunity.md` | Сквозная верификация контура: ACL, задачи, брандмауэр, DoH, активация | PENDING |
| `Stage7_Report.md` | Отчёт этапа DevOps-окружения | PLAN |
| `Recovery_Procedure.md` | Процедура восстановления (PAT-19) | PLAN |
| `Final_Report.md` | Итоговый отчёт проекта | PLAN |

Отчёт этапа генерируется скриптом с метриками §3.5 README (AR-904), а не пишется вручную.
