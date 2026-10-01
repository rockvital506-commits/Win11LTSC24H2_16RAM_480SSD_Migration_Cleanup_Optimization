# docs/artifacts/ — Отчёты и процедуры

| Документ | Содержание | Статус |
|---|---|---|
| `Stage0_Report.md` | Отчёт инициализации репозитория | **DONE** |
| `Stage1_Report.md` | Отчёт разметки NVMe (ожидает нативного прогона верификатора) | IN_PROGRESS |
| `Stage1_partition_verify.md` | Верификация разметки (генерируется `Stage1_DiskGenius_Partition.ps1`) | PENDING |
| `Stage2_Report.md` | Отчёт Ventoy-контура и Audit Mode (ожидает проверок A1–A7) | IN_PROGRESS |
| `Stage2_preflight.md` | Проверка шаблонов Ventoy и файла ответов (генерируется `Stage2_Ventoy_Template_Setup.ps1`) | PENDING |
| `Stage3_Report.md` | Отчёт накопительных обновлений (ожидает прогона U1–U7) | IN_PROGRESS |
| `Stage4_Report.md` | Отчёт финальной санитарии Audit Mode (ожидает прогона W1–N1) | IN_PROGRESS |
| `Stage4_tweakstate.md` | Отчёт верификации состояния твиков (генерируется скриптом на хосте) | PENDING |
| `Stage5_Report.md` | Отчёт запечатывания Sysprep (ожидает прогона P0.1–S6) | IN_PROGRESS |
| `Stage5_preflight.md` | Предпролётный отчёт подготовки к Sysprep (генерируется скриптом на хосте) | PENDING |
| `Stage6_Report.md` | Отчёт контура самозащиты и окна активации (ожидает окна активации и `-VerifyOnly`) | IN_PROGRESS |
| `Stage6_preflight.md` | Предпролётный отчёт подготовки контура (генерируется скриптом на хосте) | PENDING |
| `Stage6_immunity.md` | Сквозная верификация контура: ACL, задачи, брандмауэр, DoH, активация | PENDING |
| `Stage7_Report.md` | Отчёт DevOps-окружения (ожидает окна сети и установки профиля `devops`) | IN_PROGRESS |
| `Stage7_preflight.md` | Предпролётный отчёт Stage 7 (генерируется скриптом на хосте) | PENDING |
| `Stage7_packages.md` | Отчёт установки профиля пакетов (генерируется `Bootstrap-Packages.ps1`) | PENDING |
| `Stage8_Report.md` | Отчёт рабочей среды `C:\Vitality\` (ожидает ратификации состава и развёртывания) | IN_PROGRESS |
| `Stage8_preflight.md` | Предпролётный отчёт Stage 8 (генерируется `Deploy-Runtime.ps1`) | PENDING |
| `Stage8_runtime.md` | Верификация рабочей среды (генерируется `Assert-RuntimeState.ps1`) | PENDING |
| `Stand_Runbook.md` | Ранбук прогонов на стенде: порядок этапов, формы фиксации, правила при FAIL | **DONE** |
| `Audit_Report.md` | Системный аудит репозитория: находки, коррекции, положительные подтверждения, рекомендации | **DONE** |
| `Final_Report.md` | Итоговый отчёт проекта (метрики §3.5, критерии §1.4) | IN_PROGRESS |
| `Recovery_Procedure.md` | Процедура восстановления: откат по этапам, замки, полный перезапуск (PAT-19) | **DONE** |
| `Final_Acceptance.md` | Сводная приёмка §9.9 (генерируется `scripts/Final_Acceptance.ps1`) | PENDING |

Отчёт этапа генерируется скриптом с метриками §3.5 README (AR-904), а не пишется вручную.
