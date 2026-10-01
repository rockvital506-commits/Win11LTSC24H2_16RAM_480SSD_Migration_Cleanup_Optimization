# WINGET_POLICY.md — Политика установки ПО

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | PKG-001 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | AR-601…AR-607, `ADR-0016`, `packages/bootstrap/*.ps1` |

## 1. Единственный разрешённый путь

```powershell
winget install --id <ID> --exact --version <V> --accept-source-agreements `
               --accept-package-agreements --silent --disable-interactivity --source winget
```

Обязательные свойства (AR-602/AR-603):

- `--id … --exact` — только точный идентификатор, без нечётких совпадений;
- `--version <V>` — версия из `packages/lock/Packages.lock.json`; плавающие «последние» запрещены;
- `--accept-source-agreements --accept-package-agreements --disable-interactivity --silent` — неинтерактивный запуск;
- перед установкой — `winget list --id <ID> --exact`; повторный запуск ничего не меняет (AR-301).

## 2. Запреты

| Запрет | Правило |
|---|---|
| Сценарий «скачал exe → запустил» | AR-601 |
| Ручные `winget upgrade` / `winget uninstall` | AR-606 |
| Плавающие версии, `latest` | AR-602 |
| Источники, кроме зафиксированных; `msstore` | AR-604 |
| Хардкод секретов и токенов в манифестах | `NC_HARDCODED_SECRETS` |
| Установка при закрытом окне сети «на авось» | AR-709 |

## 3. Режимы `Invoke-PackageSync.ps1`

| Режим | Назначение | Изменяет систему |
|---|---|---|
| (по умолчанию) | Привести установленное к lock-файлу | да |
| `-ResolveVersions` | Заполнить версии/хэши через `winget show` (окно сети) | нет (правит lock-файл) |
| `-Verify` | Только чтение: сравнение с lock-файлом | нет |
| `-Remove` | Точное удаление версий профиля (AR-204) | да |
| `-Audit` | Печать команд без выполнения | нет |

## 4. Профили (AR-607)

| Профиль | Состав | Когда |
|---|---|---|
| `base` | 7 пакетов | Сразу после этапа 7 (рабочая станция) |
| `devops` | base + MobaXterm, Sysinternals | Рабочий профиль владельца |
| `admin` | base + Telegram, WinSCP, Rufus | Сервисные задачи |

Установка профиля — отдельный шаг с отчётом: `packages/bootstrap/Bootstrap-Packages.ps1 -Profile devops`
→ `docs/artifacts/Stage7_packages.md`.

## 5. Отступления

| Отступление | Основание |
|---|---|
| Дистрибутив WSL2 и VMware — не через winget, а с офлайн-носителя | ADR-0016 п.1/п.7 (не являются Windows-приложениями winget) |
| Docker Engine — apt-репозиторий внутри WSL2 | AR-707, ADR-0016 п.4 (версия фиксируется в отчёте, `S7-OPEN-2`) |
