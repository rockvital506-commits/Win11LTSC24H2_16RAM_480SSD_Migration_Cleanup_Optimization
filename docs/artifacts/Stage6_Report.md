# Stage6_Report.md — Отчёт этапа 6 (контур самозащиты и активация)

| Поле | Значение |
|---|---|
| `REPORT_ID` | SR-6 |
| `STAGE` | Stage 6 — Immunity Contour & Activation |
| `STATUS` | **IN_PROGRESS** — пакет этапа DONE; окно активации и приёмка на стенде ожидают владельца (AR-204) |
| `DATE_START` | 2026-10-01 |
| `DATE_END` | — (закрывается после окна активации и `-VerifyOnly` без FAIL) |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `PREVIOUS` | `Stage5_Report.md` |
| `NEXT` | `Stage7_Report.md` |
| `COMMIT_BASE` | `7a03b45` (Stage 5) |

> **О статусе.** Агентом собраны декларации, апплейеры, рантайм, алгоритмы и отчёт. Операции на хосте
> (`deny`-замки, регистрация задачи, окно активации) выполняет владелец: работа идёт в профиле `devops`,
> при физически отключённой сети (AR-204, AR-709). Агент мутаций на стенде не производил.

---

## 1. Контекст и цель этапа

Stage 6 закрепляет результат Stage 2–4: система лишается возможности самостоятельно вернуть телеметрию, обновления
и сетевые каналы. Спецификация (`docs/research/step5.md`, `anchor1.md` §131–147) задаёт состав контура; инженерные
решения по порядку, транзакционности и автономности рантайма зафиксированы в ADR-0015.

## 2. Выполненные операции (агент, 2026-10-01)

| # | Операция | Артефакт | Результат |
|---|---|---|---|
| 1 | Декларация ACL-замков | `tweaks/acl/AclManifest.json` (`ACL-001`, `ACL-002`, grant-then-deny) | DONE |
| 2 | Декларация задач | `tweaks/tasks/TaskManifest.json` (`TASK-001` register; `TASK-101…106` retire) | DONE |
| 3 | Реестровый твик DoH | `tweaks/registry/RegistryManifest.json` (`TWK-006`, `stage: 4, 6`) | DONE |
| 4 | Расширение allow-list Guard | `scripts/common/Guard.psm1` (`GroupPolicy`, `Tasks`, `hosts`) | DONE |
| 5 | Апплейер ACL | `tweaks/apply/Apply-AclManifest.ps1` (`SCRIPT-ACL-001`) | DONE |
| 6 | Апплейер задач | `tweaks/apply/Apply-TaskManifest.ps1` (`SCRIPT-TASK-001`) | DONE |
| 7 | Доверенная зона Defender | `tweaks/apply/Invoke-DefenderAllowList.ps1` (`SCRIPT-DEF-001`) | DONE |
| 8 | Сквозная верификация контура | `tweaks/apply/Assert-ImmunityState.ps1` (`SCRIPT-IMM-001`) | DONE |
| 9 | Рантайм-ядро транзакции | `templates/ImmunityCore.ps1.template` | DONE |
| 10 | Рантайм-оркестратор и обёртка | `scripts/Stage6_AutoSetup.bat`, `scripts/Stage6_Launcher.vbs` | DONE (ASCII, CRLF) |
| 11 | Оркестратор этапа | `scripts/Stage6_Immunity_Prepare.ps1` (`SCRIPT-STAGE6-001`) | DONE |
| 12 | Решения этапа | `ADR-0003`, `ADR-0004`, `ADR-0015` | ACCEPTED |
| 13 | Алгоритмы | `algorithm/auto/Stage6_AutoSetup.md`, `algorithm/manual/Stage6_Ohook_Activation.md` | DONE |
| 14 | Паттерны | `PAT-04`, `PAT-06`, `PAT-08`, `PAT-09`, `PAT-11`, `PAT-NEW-2`, `PAT-NEW-3`, `PAT-NEW-4` | DONE |
| 15 | Развёртывание рантайма | `tools/runtime/README.md`, `tools/README.md` (порядок поставки LGPO) | DONE |
| 16 | Прогон валидатора конвенций | — | **PASS** (141 файл, 0 нарушений) |

## 3. Состав контура (целевое состояние)

| Элемент | Объект | Механизм | Паттерн |
|---|---|---|---|
| Политики | `C:\Windows\System32\GroupPolicy` | DENY `SYSTEM:(W)` + импорт `CleanLTSCPolicy` | PAT-06, PAT-11 |
| Имена | `C:\Windows\System32\drivers\etc\hosts` | DENY `SYSTEM:(W)` + объявленный список доменов | PAT-08, PAT-11 |
| Транспорт | `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` | `DoHPolicy = 1` | PAT-08 |
| Обходчики | `CompatTelRunner.exe`, `WaaSMedicAgent.exe` | исходящие правила брандмауэра | PAT-09 |
| Автозапуск | задача `System_Immunity_Core` | boot + unlock, принципал SYSTEM | PAT-NEW-4 |
| Реаниматоры | 6 задач планировщика | `Disable` (+ опциональный DENY на XML) | PAT-04 |
| Активация | подсистема лицензирования | Ohook, один раз в окне Stage 6 | PAT-17 |

## 4. Открытые вопросы (требуют решения владельца)

| ID | Вопрос | Варианты | Влияние |
|---|---|---|---|
| `S6-OPEN-1` | Перечень доменов для `hosts` | предоставить список владельцем | блокирует финальную правку `hosts` |
| `S6-OPEN-2` | Дом декларации правил брандмауэра | (а) `tweaks/firewall/FirewallManifest.json` — требует `GATE_STRUCTURE`; (б) оставить объявление в ADR-0015 + ядре | структура репозитория |
| `S6-OPEN-3` | Исключение `sppc.dll` в Defender (`DEF-004`) | (а) сохранить — стабильность активации; (б) убрать — не ослаблять путь активации | доверенная зона |
| `S6-OPEN-4` | Поставка `LGPO.exe` | владелец кладёт бинарь на `F:\TOOLS\GPO\`, фиксируется SHA256 | `WARN` в `P0.3`, импорт политик пропускается |

**Снятые вопросы.** Корень `D:\GD_Tool` — **не** `GATE_AMBIGUITY`: раздел `D:` (Data, NTFS, 64 КБ) существует в
схеме разметки (ADR-0007, ADR-0011, строка 4) и предназначен для вспомогательных данных. Параметризация не требуется.

## 5. Ручной контроль (заполняет владелец)

| # | Пункт | Отметка |
|---|---|---|
| 1 | `Stage6_preflight.md`: `P0.1`…`P4.1` без FAIL | _заполнить_ |
| 2 | Окно активации пройдено (§1–§8 `Stage6_Ohook_Activation.md`) | _заполнить_ |
| 3 | `System_Immunity_Core` выполнена вручную, код 0 | _заполнить_ |
| 4 | Сеть выключена; 0 активных адаптеров | _заполнить_ |
| 5 | `Stage6_immunity.md`: `GACL-*`, `TASK-001.1/2`, `TR*`, `F1/F2`, `D1` — PASS | _заполнить_ |
| 6 | `A1`: `LicenseStatus = 1` на двух последовательных перезагрузках (`H-004` закрыт) | _заполнить_ |
| 7 | PIN (Windows Hello) настроен, вход выполняется | _заполнить_ |
| 8 | Твики Stage 4 не деградировали (`M1/M2`) | _заполнить_ |

## 6. Метрики (§3.5 README)

| Метрика | Цель | Факт |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | **19/28** документировано (+9 к Stage 5: PAT-04, 06, 08, 09, 11, 17, NEW-2, NEW-3, NEW-4) |
| `M_ADR_COUNT` | ≥1 на решение | ADR-0003, ADR-0004, ADR-0015 закрывают Stage 6 |
| `M_REANIMATOR_COUNT` | 0 активных | PENDING (после `TR*` на стенде) |
| `M_BSOD_INCIDENTS` | 0 | PENDING |
| `M_DOC_FRESHNESS` | актуальность | 2026-10-01 |
| `M_ACL_LOCKS` | 2 объявленных | 2 (`ACL-001`, `ACL-002`), применение — PENDING (стенд) |

## 7. Критерии выхода

Этап закрывается, когда: окно активации пройдено; замки, задача и правила подтверждены верификацией без FAIL;
сеть выключена; `H-004` подтверждён; отчёт дополнен результатами и переведён в `DONE`; следующие шаги переданы
Stage 7 (`algorithm/auto/Stage7_WSL_Docker_VMware.md`).

## 8. Риски и компромиссы

| Риск | Оценка | Митигация |
|---|---|---|
| Быстродействие системы после `deny` | Низкое: DENY затрагивает только запись в два объекта | Транзакция идемпотентна; откат — `Phase=Grant` |
| Defender помещает `AutoSetup.bat`/`Launcher.vbs` в карантин | Среднее (VBS-запуск) | Исключения `P1` ставятся до первого запуска (ADR-0015) |
| Активация не переживает обслуживание | Среднее | `A1` на двух перезагрузках; окно можно повторить (см. §2 manual) |
| Расхождение рантайма и репозитория | Низкое | SHA256-сверка `P2.*` при каждом прогоне подготовки |
| Слепок политик не создан (нет инструмента) | Среднее | `WARN` + мягкая деградация; контур работает без импорта политик |
