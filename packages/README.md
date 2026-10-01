# packages/ — Домен 2: установка ПО (winget-first)

Основание: AR-601 … AR-607. Единственный разрешённый способ установки — winget с фиксацией версии.

## Состав

| Каталог | Содержимое | Формат |
|---|---|---|
| `winget/` | Базовые списки и профили | `Baseline_Win11LTSC.winget`, `Profiles/{base,devops,admin}.winget` |
| `lock/` | Зафиксированные версии | `Packages.lock.json` (id, version, sha256, source, date) |
| `manifests/` | Описание пакета | `<PackageId>.json` |
| `bootstrap/` | Скрипты синхронизации | `Bootstrap-Packages.ps1`, `Invoke-PackageSync.ps1` |
| `hashes/` | Контрольные суммы | `PACKAGES_SHA256.txt` |

## Обязательные свойства

- Запуск: `--id <ID> --exact --version <V> --accept-source-agreements --accept-package-agreements --silent --disable-interactivity` (AR-602/AR-603).
- Перед установкой — проверка `winget list`; повторный запуск не должен ничего менять (AR-301).
- Источники фиксированы, msstore отключён (AR-604). Ручные `upgrade`/`uninstall` вне `Invoke-PackageSync.ps1` запрещены (AR-606).
- Каждый пакет описан в `docs/packages/PACKAGE_INDEX.md` (AR-605).
- Скрипты не поднимают сеть самостоятельно (AR-709, §4.5 README).
