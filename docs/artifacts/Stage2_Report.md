# Stage2_Report.md — Отчёт этапа 2 (Ventoy-контур и Audit Mode)

| Поле | Значение |
|---|---|
| `REPORT_ID` | SR-2 |
| `STAGE` | Stage 2 — Ventoy Contour / Audit Mode Install |
| `STATUS` | **IN_PROGRESS** — пакет автоматизации DONE; аппаратная проверка ожидает прогона на стенде/в ВМ |
| `DATE_START` | 2026-10-01 |
| `DATE_END` | — (закрывается после проверок A1–A7) |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `PREVIOUS` | `Stage1_Report.md` |
| `NEXT` | `Stage3_Report.md` |
| `COMMIT_BASE` | `3d1900d` (исправление единиц Stage 1) |

> **О статусе.** Установка на стенде выполнена владельцем ранее (`docs/research/step2.md`). Данный отчёт закрывает воспроизводимость Stage 2: шаблоны, решение (ADR-0005), паттерны и перечень проверок. Проверки A1–A7 агентом не выполнялись — требуют прогона на стенде или в ВМ.

---

## 1. Контекст и цель этапа

Stage 2 должен: (а) обеспечить автоматический проход установки без интерактивных экранов, (б) нейтрализовать вендорские компоненты ASUS на самом раннем проходе, (в) привести систему в Audit Mode с физически отключённой сетью, (г) не допустить автоматической разметки диска установщиком.

## 2. Исходное состояние (заполняется инженером)

| Параметр | Значение | Примечание |
|---|---|---|
| Разметка (Stage 1) | _верификация W1, V1–V6_ | требуется прогон `Stage1_DiskGenius_Partition.ps1` |
| Носитель F: | _модель, ёмкость, раскладка_ | `F-OPEN-1`, `docs/storage/F_drive_schema.md` |
| Фактическое имя ISO | _заполнить_ | критично для `auto_install` (`S2-OPEN-1`) |
| Версия Ventoy | 1.1.10 (заявлена) | протоколировать |
| Состояние сети | отключена физически | `NC_INTERNET_DURING_TWEAKS` |
| Вариант входа в Audit Mode | A (`Mode=Audit`) / B (`Ctrl+Shift+F3`) | `S2-OPEN-2` |

## 3. Выполненные операции (агент, 2026-10-01)

| # | Операция | Артефакт | Результат |
|---|---|---|---|
| 1 | Оформлено решение о двухэтапном unattend | `docs/decisions/ADR-0005-dual-stage-unattend.md` | ACCEPTED |
| 2 | Создан шаблон конфигурации Ventoy | `templates/ventoy.json.template` | DONE (валидный JSON, LF, без BOM) |
| 3 | Создан шаблон первого файла ответов | `templates/u_w11_ltsc_iot.xml.template` | DONE (XML валиден, CRLF, **без BOM**) |
| 4 | Оформлены паттерны Stage 2 | `PAT-01-ifeo-stub.md`, `PAT-16-dual-stage-unattend.md`, обновлён `PAT-INDEX.md` | DONE |
| 5 | Оформлена схема носителя F: | `docs/storage/F_drive_schema.md` | IN_PROGRESS (ожидает протоколирования) |
| 6 | Оформлены алгоритмы этапа | `algorithm/manual/Stage2_Ventoy_Install.md`, `algorithm/auto/Stage2_Audit_Mode_Workflow.md` | DONE |
| 7 | Расширен валидатор: `*.template` проверяются по целевому расширению | `scripts/rules/Test-RepositoryConventions.ps1` | DONE |
| 8 | Прогон валидатора конвенций | — | **PASS** |

### Исправления относительно исследовательских материалов

| Что | Было (в `docs/research/step1.md`, markdown-транскрипт) | Стало (шаблон) | Причина |
|---|---|---|---|
| Пространства имён | `xmlns:wcm="http://microsoft.com"`, `xmlns:xsi="http://w3.org"` | `http://schemas.microsoft.com/WMIConfig/2002/State`, `http://www.w3.org/2001/XMLSchema-instance` | Транскрипция исказила URL; неверные пространства имён → отказ схемы |
| Элемент команды | `<CommandLine>` | `<Path>` | В `RunSynchronousCommand` используется `Path`; `CommandLine` схемой не предусмотрен |
| Вход в Audit Mode | безусловный `<Mode>Audit</Mode>` | элемент отключён, документирована альтернатива `Ctrl+Shift+F3` | Поддержка элемента схемой не подтверждена; см. `S2-OPEN-2` |

## 4. Изменения и мутации

| Объект | Было | Стало | Паттерн | Бэкап |
|---|---|---|---|---|
| Система стенда | — | — | — | — |

**Мутации стенда не производились.** Файл ответов применяется инженером на этапе установки; агент подготовил шаблоны и процедуры. Носитель F: не изменялся (запись на него требует `GATE_FDRIVE_MODIFICATION`).

## 5. Верификация

### 5.1 Проверки шаблонов (выполнены агентом)

| ID | Проверка | Результат |
|---|---|---|
| `T1` | `u_w11_ltsc_iot.xml.template` — валидный XML | **PASS** (парсится, корневой элемент `unattend`) |
| `T2` | `u_w11_ltsc_iot.xml.template` — UTF-8 без BOM | **PASS** (первые байты не `EF BB BF`) |
| `T3` | `u_w11_ltsc_iot.xml.template` — CRLF | **PASS** |
| `T4` | `ventoy.json.template` — валидный JSON, LF, без BOM | **PASS** |
| `T5` | Комментарии XML не содержат недопустимой последовательности `--` | **PASS** |
| `T6` | Валидатор конвенций (расширен на `.template`) | **PASS** |

### 5.2 Проверки на стенде / в ВМ (ожидают прогона)

| ID | Проверка | Ожидание | Статус |
|---|---|---|---|
| `A1` | Файл ответов принят установщиком | нет ошибок парсинга в `setupact.log` | PENDING |
| `A2` | IFEO `AsusUpdateCheck.exe` | `Debugger = ntsd -d` | PENDING |
| `A3` | IFEO `AsusAppService.exe` | `Debugger = ntsd -d` | PENDING |
| `A4` | `DiagTrack` | `Start = 0x4` | PENDING |
| `A5` | `SearchOrderConfig` | `0x0` | PENDING |
| `A6` | Audit Mode | рабочий стол Администратора, окно Sysprep | PENDING |
| `A7` | Процессы ASUS не запущены | пусто | PENDING |
| `F1`–`F6` | Схема носителя F: | см. `F_drive_schema.md` §6 | PENDING |

## 6. Метрики (§3.5 README)

| Метрика | Цель | Факт |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | 4/28 документировано (PAT-01, PAT-16, PAT-NEW-6, PAT-NEW-7) |
| `M_ADR_COUNT` | ≥1 на решение | ADR-0005 закрыт |
| `M_DRIVER_CLEANLINESS` | 0 ASUS OEM панелей | PENDING (проверка A7 на Stage 2/6) |
| `M_BSOD_INCIDENTS` | 0 | 0 |

## 7. Отклонения, открытые пункты, waivers

| ID | Тип | Описание | Требуемое действие |
|---|---|---|---|
| `S2-OPEN-1` | Риск конфигурации | Расхождение имени ISO: README §5.7.2/§8.4 — `Windows_11_IoT_Enterprise_LTSC_24H2.iso`; `docs/research/step1.md` — `/ISO/Windows_11_LTSC_IoT_24H2.iso`. При несовпадении `auto_install` молча не срабатывает | Подтвердить фактическое имя файла; шаблон использует имя из README. Исправление — правка `templates/ventoy.json.template` |
| `S2-OPEN-2` | Схема unattend | Поддержка `<Mode>Audit</Mode>` в проходе `oobeSystem` не подтверждена документацией схемы | Элемент отключён; альтернатива `Ctrl+Shift+F3`. Проверить вариант A в ВМ, результат внести сюда |
| `F-OPEN-1` | Единицы/раскладка | Размеры разделов F: без указания системы; фактический размер VTOYEFI зависит от версии Ventoy | Протоколировать `Get-Partition`/`Get-Volume`; переразметку не выполнять; при отклонении — ADR + `GATE_FDRIVE_MODIFICATION` |
| `LIM-1` | Инструментальное | Нативный прогон PowerShell в песочнице агента невозможен | Выполнить на хосте Windows |
| `W-1` | Процесс | Запись на носитель F: агентом не выполнялась и не автоматизируется без `GATE_FDRIVE_MODIFICATION` | При необходимости скрипта-развёртывания — сначала ADR о расширении allow-list (AR-206) |

Waivers: нет.

## 8. Артефакты этапа

| Артефакт | Путь | Статус |
|---|---|---|
| Решение | `docs/decisions/ADR-0005-dual-stage-unattend.md` | DONE |
| Шаблон конфигурации Ventoy | `templates/ventoy.json.template` | DONE |
| Шаблон файла ответов | `templates/u_w11_ltsc_iot.xml.template` | DONE |
| Паттерны | `docs/patterns/PAT-01-ifeo-stub.md`, `PAT-16-dual-stage-unattend.md` | DONE |
| Схема носителя | `docs/storage/F_drive_schema.md` | IN_PROGRESS |
| Алгоритмы | `algorithm/manual/Stage2_Ventoy_Install.md`, `algorithm/auto/Stage2_Audit_Mode_Workflow.md` | DONE |
| Рендеры на носителе | `F:\ventoy\ventoy.json`, `F:\ventoy\templates\u_w11_ltsc_iot.xml` | PENDING (вне Git) |

## 9. Следующий шаг

1. Закрыть `S2-OPEN-1` (имя ISO) и `S2-OPEN-2` (Audit Mode) — требуется ответ владельца/проверка в ВМ.
2. Выполнить проверки A1–A7, заполнить §2, перевести отчёт в `DONE`.
3. Stage 3 — накопительные обновления: `algorithm/manual/Stage3_Windows_Update.md` (кратковременное подключение сети, затем обязательная изоляция).

---

<!-- AR-904: отчёт содержит метрики §3.5; файл UTF-8 без BOM, LF. -->
