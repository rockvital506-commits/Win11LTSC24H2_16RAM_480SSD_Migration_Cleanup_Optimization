# SOURCES.md — Источники поставки

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | PKG-002 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | AR-604, `ADR-0016`, `packages/lock/Packages.lock.json` |

## 1. Источники winget

| Источник | Аргумент | Состояние | Примечание |
|---|---|---|---|
| `winget` (Microsoft) | `https://cdn.winget.microsoft.com/cache` | **включён** | Единственный разрешённый (AR-604) |
| `msstore` | — | **отключён** | Отключается `Invoke-PackageSync.ps1` (проверка `PKG0.3`) |

Новый источник — только через ADR (AR-604). Проверка: `winget source list`.

## 2. Офлайн-источники (носитель F:)

| Путь | Содержимое | Политика |
|---|---|---|
| `F:\WSL2\` | `ubuntu.appx`, `.wslconfig`, `docker-compose.yaml` | ADR-0016: дистрибутив вне winget |
| `F:\VM\` | Установщик VMware, шаблоны ВМ | ADR-0002 |
| `F:\TOOLS\GPO\` | `LGPO.exe`, PolicyDefinitions | PAT-06 |
| `F:\TOOLS\Audit\` | ProcessExplorer, Autoruns, coreinfo, DMDE | ADR-0010, `SC_TOOLKIT_PRESERVED` |
| `F:\TOOLS\Partitioning\` | DiskGenius Portable | ADR-0007/0011 |
| `F:\TOOLS\Backup\` | Средства резервного копирования | README §5.7.3 |

Хэши офлайн-компонентов фиксируются в `packages/hashes/PACKAGES_SHA256.txt` после проверки владельцем.

## 3. Внутридистрибутивные источники

| Источник | Что поставляет | Политика |
|---|---|---|
| apt (Ubuntu) | Пакеты дистрибутива, `docker-ce*` | Установка только скриптом `devops/containers/Install-DockerEngine.sh` |
| Репозиторий Docker | `docker-ce`, `containerd.io`, плагины | Версия фиксируется в отчёте (`S7-OPEN-2`) |

Проектные зависимости (pip/npm/cargo) внутри WSL фиксируются в lock-файлах самих проектов; на политику
`packages/` они не влияют.
