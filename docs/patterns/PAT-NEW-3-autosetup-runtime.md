# PAT-NEW-3 — AutoSetup.bat как Runtime-Initializer (тонкий батник + VBS-обёртка)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-NEW-3 |
| `NAME` | AutoSetup.bat как Runtime-Initializer (тонкий батник + VBS-обёртка) |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0015`, `scripts/Stage6_AutoSetup.bat`, `scripts/Stage6_Launcher.vbs`, `templates/ImmunityCore.ps1.template` |

---

## Контекст

Цементирование должно выполняться автоматически и **скрытно** (без мигающего окна консоли), не завися от того, смонтирован ли офлайн-носитель с репозиторием: задача срабатывает при каждом запуске и разблокировке.

## Решение

Разделение ответственности:

| Слой | Файл | Ответственность |
|---|---|---|
| Точка входа задачи | `Launcher.vbs` | скрытый запуск батника (`WScript.Shell.Run …, 0, False`) |
| Оркестратор | `AutoSetup.bat` | проверка прав, наличие ядра, запуск, коды возврата, журнал `logs\AutoSetup.log` |
| Логика | `ImmunityCore.ps1` | транзакция grant→импорт→firewall→gpupdate→deny→верификация |

Ограничения, принятые сознательно:

- `.bat` — **ASCII-only** (AR-105): кодировка консоли `cmd.exe` не гарантирует корректную интерпретацию кириллицы;
- PowerShell-ядро — UTF-8 **с BOM**: иначе `powershell.exe` 5.1 читает кириллицу как ANSI;
- тяжёлая логика не дублируется в `.bat`: конструкции `if`/`for` батника небезопасны для сложных условий;
- деградация без `F:`: все нужные файлы лежат в `D:\GD_Tool`; отсутствие `LGPO.exe` → `WARN`, а не сбой.

## Реализация

| Артефакт | Путь |
|---|---|
| Батник | `scripts/Stage6_AutoSetup.bat` → `D:\GD_Tool\AutoSetup.bat` |
| Обёртка | `scripts/Stage6_Launcher.vbs` → `D:\GD_Tool\Launcher.vbs` |
| Ядро | `templates/ImmunityCore.ps1.template` → `D:\GD_Tool\ImmunityCore.ps1` |
| Развёртывание | `scripts/Stage6_Immunity_Prepare.ps1` (фаза P2, контроль SHA256) |

## Проверка

| ID | Критерий |
|---|---|
| `P2.*` | файлы развёрнуты, SHA256 совпадает с репозиторием (PAT-20) |
| `B1`/`B2` | артефакты присутствуют в `D:\GD_Tool` |
| `B3` | (вручную) окно консоли при запуске задачи не появляется |
| `B4` | в `logs\ImmunityCore.log` есть строка завершения транзакции |

## Замечания

- VBS-запуск — известный эвристический маркер для защитных средств; поэтому исключения Defender (PAT-09/ADR-0015) ставятся **до** первого запуска.
- Задача запускает `wscript.exe … Launcher.vbs`; при отключённом Windows Script Host (среда повышенной безопасности) потребуется пересмотр — проверяется `TASK-001.2`.
