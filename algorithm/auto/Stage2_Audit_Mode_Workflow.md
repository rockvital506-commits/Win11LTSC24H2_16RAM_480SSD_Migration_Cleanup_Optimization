# Stage 2 (auto) — Что делает файл ответов и как это проверить

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S2-AUTO |
| `STAGE` | 2 |
| `TYPE` | auto |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE |
| `RELATED` | `ADR-0005`, `PAT-16`, `PAT-01`, `PAT-NEW-1`, `templates/u_w11_ltsc_iot.xml.template`, `docs/artifacts/Stage2_Report.md` |

---

## Состав автоматизации

Автоматика Stage 2 реализуется **файлом ответов** (не скриптом): Ventoy подменяет `unattend.xml` на этапе `windowsPE`, дальнейшие проходы выполняет `setup.exe`. Разметка диска автоматизации не подлежит (ADR-0007, AR-204).

| Проход | Элемент | Действие | Паттерн |
|---|---|---|---|
| `windowsPE` | `Microsoft-Windows-Setup` | `AcceptEula=true` — установка без экрана лицензии | — |
| `specialize` | `Microsoft-Windows-Deployment` | `RunSynchronousCommand` 1–2: IFEO-заглушки `AsusUpdateCheck.exe`, `AsusAppService.exe` | `PAT-01` |
| `specialize` | — | `RunSynchronousCommand` 3: `DiagTrack` → `Start=4` | — |
| `specialize` | — | `RunSynchronousCommand` 4: `SearchOrderConfig=0` (нет подтяжки драйверов из интернета) | — |
| `oobeSystem` | `Microsoft-Windows-Shell-Setup` | Скрытие экранов OOBE (`HideEULAPage`, `HideOnlineAccountScreens`, `HideWirelessSetupInOOBE`), `ProtectYourPC=3` | — |
| `oobeSystem` | `OOBE` | Вход в Audit Mode: вариант A (`Mode=Audit`, отключён) / вариант B (`Ctrl+Shift+F3`) | `PAT-NEW-1` |

## Проверки (выполняются в Audit Mode)

| ID | Проверка | Команда | Критерий |
|---|---|---|---|
| `A1` | Файл ответов принят установщиком | журнал `C:\Windows\Panther\setupact.log`, поиск `unattend` | ошибок парсинга нет |
| `A2` | IFEO: `AsusUpdateCheck.exe` | `reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AsusUpdateCheck.exe" /v Debugger` | `ntsd -d` |
| `A3` | IFEO: `AsusAppService.exe` | `reg query "...\Image File Execution Options\AsusAppService.exe" /v Debugger` | `ntsd -d` |
| `A4` | Телеметрия | `reg query HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack /v Start` | `0x4` (Disabled) |
| `A5` | Поиск драйверов | `reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v SearchOrderConfig` | `0x0` |
| `A6` | Audit Mode активен | `whoami`; окно Sysprep; `Get-ComputerInfo` | пользователь-администратор, окно Sysprep открыто, система в состоянии аудита |
| `A7` | Вендорские процессы не запущены | `Get-Process | Where-Object { $_.Path -like '*\Asus*' }` | пусто |

Скрипт-обёртка для этих проверок не создаётся на этом этапе: проверки читают состояние и выполняются вручную в Audit Mode; автоматизация появится в составе `tweaks/apply/Assert-TweakState.ps1` (Stage 4), где эти же ключи войдут в манифест.

## Проверка в виртуальной машине (обязательная до боевого применения)

Валидация unattend надёжна только прогоном. Порядок:

1. Создать ВМ (VMware Workstation / Hyper-V) с 2 vCPU, 4 ГБ ОЗУ, диск 60 ГБ.
2. Подключить ISO и подменить файл ответов (Ventoy не требуется: файл можно указать вручную на этапе выбора).
3. Прогнать установку, проверить `A1`–`A7`.
4. **Отдельно проверить вариант A** (`<Mode>Audit</Mode>`): если `setup.exe` отклоняет файл ответов или Audit Mode не включается — оставить вариант B и зафиксировать результат в `Stage2_Report.md`.

## Ограничения и риски

| ID | Риск | Митигация |
|---|---|---|
| `R1` | Имя ISO в `ventoy.json` не совпало → файл ответов не применён | Сверка байт-в-байт (шаг 1 алгоритма); имя зафиксировано (`S2-OPEN-1` закрыт) |
| `R2` | BOM в XML → отказ `setup.exe` | Проверка первых байт (шаг 2 алгоритма) |
| `R3` | Элемент `<Mode>Audit</Mode>` не поддержан схемой | Отключён; действует `Ctrl+Shift+F3`. Включение — по результату ВМ-теста (`S2-ACT-1`) |
| `R4` | Автоматический подбор драйверов с интернета при первой инициализации | `SearchOrderConfig=0` + физически отключённая сеть |
| `R5` | Разметка «по умолчанию» установщиком | Раздел выбирается вручную; `DiskConfiguration` отсутствует в файле ответов |

## Артефакты

| Артефакт | Путь |
|---|---|
| Шаблон файла ответов | `templates/u_w11_ltsc_iot.xml.template` |
| Шаблон конфигурации Ventoy | `templates/ventoy.json.template` |
| Решение | `docs/decisions/ADR-0005-dual-stage-unattend.md` |
| Паттерны | `docs/patterns/PAT-16-dual-stage-unattend.md`, `PAT-01-ifeo-stub.md` |
| Скрипт валидации и рендера | `scripts/Stage2_Ventoy_Template_Setup.ps1` (`SCRIPT-STAGE2-001`) |
| Отчёт | `docs/artifacts/Stage2_Report.md`, `docs/artifacts/Stage2_preflight.md` |

---

<!-- Файл UTF-8 без BOM, LF. -->
