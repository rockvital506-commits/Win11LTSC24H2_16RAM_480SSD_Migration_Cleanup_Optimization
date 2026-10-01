# profiles — Профили установки

Экспорт `winget export` по профилям (STRUC_004: каталог в нижнем регистре):

| Профиль | Состав | Назначение |
|---|---|---|
| `base.winget` | 7 пакетов | Базовая станция: git, VS Code, терминал, PowerShell, VC++ Redist, 7-Zip, Notepad++ |
| `devops.winget` | base + MobaXterm, Sysinternals | Рабочий профиль (Stage 7) |
| `admin.winget` | base + Telegram, WinSCP, Rufus | Административные задачи |

Профили **не фиксируют версии** — это делает `packages/lock/Packages.lock.json` (AR-602).
Пересечение профилей: `base` является подмножеством `devops` и `admin` (AR-607 — установка профиля отдельным шагом).
