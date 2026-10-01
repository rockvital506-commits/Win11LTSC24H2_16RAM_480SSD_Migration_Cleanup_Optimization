# PACKAGE_INDEX.md — Реестр пакетов

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | PKG-000 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | `ADR-0016`, AR-601…AR-607, `packages/lock/Packages.lock.json`, `docs/packages/WINGET_POLICY.md` |

Каждый пакет описан отдельным манифестом `packages/manifests/<PackageId>.json` (AR-605). Версия и SHA256 —
единственный источник: `packages/lock/Packages.lock.json`; до заполнения lock-файла установка блокируется (AR-602).

## 1. Пакеты winget

| ID | Профиль | Назначение | Лицензия | Источник | Версия | SHA256 | Статус |
|---|---|---|---|---|---|---|---|
| `Git.Git` | base | Система контроля версий | GPL-2.0 | winget | _из lock_ | _из lock_ | PENDING |
| `Microsoft.VisualStudioCode` | base | Среда разработки | MIT (с компонентами Microsoft) | winget | _из lock_ | _из lock_ | PENDING |
| `Microsoft.WindowsTerminal` | base | Терминал для PowerShell/WSL | MIT | winget | _из lock_ | _из lock_ | PENDING |
| `Microsoft.PowerShell` | base | PowerShell 7 (pwsh) | MIT | winget | _из lock_ | _из lock_ | PENDING |
| `Microsoft.VCRedist.2015+.x64` | base | Visual C++ Redistributable x64 | Microsoft (перераспространяемый) | winget | _из lock_ | _из lock_ | PENDING |
| `7zip.7zip` | base | Архиватор | LGPL-2.1 | winget | _из lock_ | _из lock_ | PENDING |
| `Notepad++.Notepad++` | base | Текстовый редактор | GPL-3.0 | winget | _из lock_ | _из lock_ | PENDING |
| `MobaXterm.MobaXterm` | devops | SSH/терминальный клиент | Проприетарная (free edition) | winget | _из lock_ | _из lock_ | PENDING |
| `Microsoft.Sysinternals` | devops | Sysinternals Suite (coreinfo, procexp) | Microsoft EULA | winget | _из lock_ | _из lock_ | PENDING |
| `Telegram.TelegramDesktop` | admin | Мессенджер | GPL-3.0 (клиент) | winget | _из lock_ | _из lock_ | PENDING |
| `WinSCP.WinSCP` | admin | SFTP/SCP-клиент | GPL-3.0 | winget | _из lock_ | _из lock_ | PENDING |
| `Rufus.Rufus` | admin | Запись USB-носителей | GPL-3.0 | winget | _из lock_ | _из lock_ | PENDING |

Профили (AR-607): `base` ⊂ `devops`, `base` ⊂ `admin`; объявления — `packages/winget/profiles/*.winget`.

## 2. Офлайн-компоненты (не winget)

| Компонент | Источник | Назначение | Основание |
|---|---|---|---|
| Дистрибутив WSL2 (Ubuntu) | `F:\WSL2\ubuntu.appx` | WSL2-контур | ADR-0016 п.1 (исключение из AR-601) |
| VMware Workstation Pro | `F:\VM\VMware-Workstation-Pro.exe` | Гипервизор (WHP) | ADR-0002, `SC_TOOLKIT_PRESERVED` |
| Sysinternals `coreinfo64.exe` | `F:\TOOLS\Audit\` | Перекрёстная проверка P/E | ADR-0010 |
| DiskGenius Portable | `F:\TOOLS\Partitioning\` | Разметка (Stage 1) | ADR-0007/0011 |
| DMDE | `F:\TOOLS\Audit\` | Восстановление данных | `SC_TOOLKIT_PRESERVED` |
| Средства резервного копирования | `F:\TOOLS\Backup\` | Бэкапы | README §5.7.3 |
| LGPO.exe | `F:\TOOLS\GPO\` | Политики (Stage 6) | PAT-06 |

Правило: офлайн-компоненты в Git не коммитятся (AR-804); их хэши фиксируются в `packages/hashes/PACKAGES_SHA256.txt`
после проверки носителя владельцем.

## 3. Верификация

| ID | Проверка | Критерий |
|---|---|---|
| `PKG0.1` | winget доступен | найден |
| `PKG0.3` | msstore отключён | источник отсутствует (AR-604) |
| `PKG0.5` | окно сети открыто | ≥ 1 адаптер (AR-709) |
| `PKG-<id>` | установленная версия | совпадает с lock-файлом (AR-602/AR-603) |
| `B1.1` | профиль установлен | `Bootstrap-Packages.ps1` код 0 (AR-607) |

Отчёты: `docs/artifacts/Stage7_packages.md`, `Stage7_Report.md`.
