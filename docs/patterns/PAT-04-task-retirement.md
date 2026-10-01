# PAT-04 — Task Scheduler: вывод реаниматоров из строя + ACL

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-04 |
| `NAME` | Task Scheduler: вывод реаниматоров из строя + ACL |
| `STAGE` | 4, 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0015`, `tweaks/tasks/TaskManifest.json`, `tweaks/apply/Apply-TaskManifest.ps1`, `PAT-11` |

---

## Контекст

Телеметрические задачи планировщика (`ProgramDataUpdater`, `Consolidator`, `QueueReporting`, `DmClient` и др.) пересоздают каналы телеметрии и частично восстанавливают смежные службы. Отключение служб их не останавливает: триггеры срабатывают независимо.

## Решение

Два уровня, оба декларативны:

1. **Отключение (обратимое, по умолчанию):** `Disable-ScheduledTask` для объявленного перечня; экспорт XML каждой задачи в бэкап до изменения (AR-304).
2. **Замок записи (опция, `-ApplyTaskAcl`):** DENY на XML-файл задачи в `C:\Windows\System32\Tasks` — запрещает SYSTEM перезапись, пересоздание и удаление задачи (PAT-11).

| Задача | Путь |
|---|---|
| `ProgramDataUpdater` | `\Microsoft\Windows\Application Experience\` |
| `Consolidator` | `\Microsoft\Windows\Customer Experience Improvement Program\` |
| `DiskDiagnosticDataCollector` | `\Microsoft\Windows\DiskDiagnostic\` |
| `Proxy` | `\Microsoft\Windows\Autochk\` |
| `QueueReporting` | `\Microsoft\Windows\Windows Error Reporting\` |
| `DmClient` | `\Microsoft\Windows\Feedback\Siuf\` |

## Реализация

| Артефакт | Путь |
|---|---|
| Манифест | `tweaks/tasks/TaskManifest.json` (`retire`: `TASK-101…TASK-106`) |
| Апплейер | `tweaks/apply/Apply-TaskManifest.ps1` (`-Unregister` — только вручную) |
| Проверка | `Assert-ImmunityState.ps1` (`TR101…TR106`) |

## Проверка

| ID | Критерий |
|---|---|
| `TR<id>` | задача `State = Disabled` |
| `TR<id>.a` | XML-бэкап существует |
| (вручную) | после перезагрузки состояние `Disabled` сохраняется |

## Замечания

- Системные задачи обслуживания не удаляются: удаление необратимо и не даёт выигрыша перед `Disable` + замком.
- Перечень — только телеметрия и обслуживание; задачи, влияющие на корректность ОС (обновление сертификатов, дефрагментация), не затрагиваются.
