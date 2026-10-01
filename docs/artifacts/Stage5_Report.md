# Stage5_Report.md — Отчёт этапа 5 (запечатывание Sysprep)

| Поле | Значение |
|---|---|
| `REPORT_ID` | SR-5 |
| `STAGE` | Stage 5 — Sysprep Seal |
| `STATUS` | **IN_PROGRESS** — пакет этапа DONE; прогон на стенде ожидает выполнения (необратимая операция, AR-204) |
| `DATE_START` | 2026-10-01 |
| `DATE_END` | — (закрывается после OOBE и создания пользователя `devops`) |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `PREVIOUS` | `Stage4_Report.md` |
| `NEXT` | `Stage6_Report.md` |
| `COMMIT_BASE` | `6ab87e2` (Stage 4) |

> **О статусе.** Запечатывание — деструктивная необратимая операция (AR-204). Агентом подготовлены скрипт, шаблон и документация; сам `sysprep.exe /generalize` выполняет владелец на стенде. Агент мутаций не производил.

---

## 1. Контекст и цель этапа

Stage 5 завершает сессию Audit Mode: generalize снимает уникальные идентификаторы оборудования, `CopyProfile` переносит настроенный профиль Администратора в `Default User`, ноутбук выключается. Следующий запуск — «тихий» OOBE, где создаётся локальный пользователь `devops`.

## 2. Исходное состояние (заполняется инженером)

| Параметр | Значение | Примечание |
|---|---|---|
| Audit Mode активен | _подтвердить_ | `SystemSetupInProgress = 1` |
| Сеть изолирована | _подтвердить_ | 0 активных адаптеров (AR-709) |
| Остаток перевооружений (rearm) | _заполнить_ | `slmgr /dlv` → «Remaining Windows rearm count» |
| Свободное место на `C:\` | _≥ 5 ГБ_ | generalize требует места под журналы |
| `Stage4_tweakstate.md` | _приложить_ | все проверки PASS |

## 3. Выполненные операции (агент, 2026-10-01)

| # | Операция | Артефакт | Результат |
|---|---|---|---|
| 1 | Второй файл ответов (шаблон) | `templates/unattend.xml.template` | DONE (XML валиден, без BOM, CRLF) |
| 2 | Предпролётный скрипт | `scripts/Stage5_Sysprep_Prepare.ps1` | DONE |
| 3 | Расширение allow-list под каталог Sysprep | `scripts/common/Guard.psm1` | DONE (ADR-0014 п.1) |
| 4 | Решение этапа | `ADR-0014-sysprep-seal.md` | ACCEPTED |
| 5 | Алгоритм этапа | `algorithm/auto/Stage5_Sysprep_Seal.md` | DONE |
| 6 | Паттерн Audit Mode | `PAT-NEW-1-audit-mode-workflow.md` | DONE |
| 7 | Прогон валидатора конвенций | — | **PASS** |

## 4. Изменения и мутации (заполняется после прогона)

| Объект | Было | Стало | Источник |
|---|---|---|---|
| `C:\Windows\System32\Sysprep\unattend.xml` | _нет/предыдущий_ | шаблон Stage 5 | ADR-0005, ADR-0014 |
| Политики `specialize` (WU, Edge, поиск, OneDrive, телеметрия, MSRT) | _до_ | значения из файла № 2 | `templates/unattend.xml.template` |
| Provisioned AppX (ловушка `0x80073cf2`) | _нарушений: N_ | 0 | `-FixSysprepValidation` (AR-507) |
| Кэши профиля (`WebCache`/`INetCache`) | _до_ | очищены (или `WARN`) | ADR-0014 п.3 |
| Профиль `Default User` | твики Audit Mode | перенесены (`CopyProfile`) | `H-003`, PAT-NEW-1 |
| Состояние машины | настроенный монолит | обобщённый образ, выключен | `sysprep /generalize` |

## 5. Верификация

| ID | Проверка | Ожидание | Статус |
|---|---|---|---|
| `P0.1` | Audit Mode | `SystemSetupInProgress = 1` | PENDING |
| `P0.2` | Сеть изолирована | 0 активных адаптеров | PENDING |
| `P0.3` | Шаблон существует | `templates/unattend.xml.template` | DONE (файл в репозитории) |
| `P2.1` | `unattend.xml` без BOM | `False` | PENDING |
| `P2.2` | XML разбирается | `valid` | PENDING |
| `P3.1` | Ловушка `0x80073cf2` | 0 нарушений | PENDING |
| `P4.1` | Гигиена кэшей профиля | выполнено / `WARN` | PENDING |
| `S1` | `sysprep_succeeded.tag` | существует | PENDING |
| `S2` | Ноутбук выключился | полное выключение | PENDING |
| `S3` | OOBE остановился на создании локальной учётной записи | экран создания пользователя | PENDING |
| `S4` | Пользователь `devops` создан | вход выполнен | PENDING |
| `S5` | Твики в профиле (`H-003`) | IFEO ASUS, `DiagTrack=4`, нет `hiberfil.sys` | PENDING |
| `S6` | Дефект оболочки не проявился | нет мигающей панели задач | PENDING |

Автоматическая часть: `scripts/Stage5_Sysprep_Prepare.ps1` → `docs/artifacts/Stage5_preflight.md` (генерируется на хосте).

## 6. Метрики (§3.5 README)

| Метрика | Цель | Факт |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | 10/28 документировано (PAT-01, 12–16, 18, PAT-NEW-1, NEW-6, NEW-7) |
| `M_ADR_COUNT` | ≥1 на решение | ADR-0014 закрывает Stage 5 |
| `M_REANIMATOR_COUNT` | 0 активных | PENDING (после OOBE) |
| `M_BSOD_INCIDENTS` | 0 | PENDING |
| `M_DOC_FRESHNESS` | актуальность | 2026-10-01 |

## 7. Отклонения, открытые пункты, waivers

| ID | Тип | Описание | Требуемое действие |
|---|---|---|---|
| `S5-DEV-1` | Отступление | `<HideLocalAccountScreen>` удалён (применим только к Windows Server) | Принято ADR-0014 п.5 |
| `S5-DEV-2` | Отступление | `Microsoft-Windows-MPR` заменён политиками `Policies\Microsoft\MRT` | Принято ADR-0014 п.5 |
| `S5-DEV-3` | Отступление | Удаление AppX вне unattend (Stage 4 + предпролётная проверка) | Принято ADR-0014 п.4 |
| `S5-DEV-4` | Отступление | Атомарные `reg add` вместо PowerShell-однострочников | Принято ADR-0014 п.5 |
| `S5-OPEN-1` | Параметр | Часовой пояс `Russian Standard Time` (из исследования); при ином фактическом поясе — одна строка в шаблоне | Подтвердить перед прогоном |
| `S5-OPEN-2` | Риск | Остаток перевооружений (`rearm`) не зафиксирован | Внести в §2 перед generalize |
| `S5-OPEN-3` | Гигиена | Если кэши профиля заперты, очистка переносится в Stage 6 (первичная инициализация) | Контроль в `Stage6_Report.md` |
| `S5-OPEN-4` | Гипотеза | `H-004` (Ohook переживает generalize) проверяется после Stage 6 | Закрыть в `Stage6_Report.md` |
| `LIM-1` | Инструментальное | Нативный прогон PowerShell в песочнице агента невозможен | Выполнить на хосте Windows |

Waivers: нет.

## 8. Артефакты этапа

| Артефакт | Путь | Статус |
|---|---|---|
| Второй файл ответов | `templates/unattend.xml.template` | DONE |
| Предпролётный скрипт | `scripts/Stage5_Sysprep_Prepare.ps1` | DONE |
| Расширение allow-list | `scripts/common/Guard.psm1` | DONE |
| Решение | `docs/decisions/ADR-0014-sysprep-seal.md` | DONE |
| Алгоритм | `algorithm/auto/Stage5_Sysprep_Seal.md` | DONE |
| Паттерн | `docs/patterns/PAT-NEW-1-audit-mode-workflow.md` | DONE |
| Отчёт предпролёта | `docs/artifacts/Stage5_preflight.md` | PENDING (генерируется на хосте) |
| Бэкапы | `backups/<UTC>_stage5/` | PENDING (вне Git) |

## 9. Следующий шаг

1. На хосте: `-Audit` → прогон с `-FixSysprepValidation -PurgeProfileCaches` → CMD `sysprep.exe /oobe /generalize /shutdown /unattend:...`.
2. После OOBE: создать `devops`, внести §2/§4/§5, перевести отчёт в `DONE`.
3. Stage 6 — первичная инициализация и цементирование (`algorithm/manual/Stage6_Ohook_Activation.md`, `algorithm/auto/Stage6_AutoSetup.md`); проверить `H-004`.

---

<!-- AR-904: отчёт содержит метрики §3.5; файл UTF-8 без BOM, LF. -->
