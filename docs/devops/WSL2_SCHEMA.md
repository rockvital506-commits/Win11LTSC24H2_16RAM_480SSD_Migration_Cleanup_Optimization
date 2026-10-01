# WSL2_SCHEMA.md — Схема WSL2-контура

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | DEVOPS-WSL |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | `ADR-0016`, `PAT-21`, `devops/wsl/*`, `devops/containers/*`, AR-703, AR-707 |

## 1. Компоненты

| Элемент | Источник | Размещение | Примечание |
|---|---|---|---|
| Дистрибутив | `F:\WSL2\ubuntu.appx` (офлайн) | `C:\DevOps\WSL\Ubuntu` | AR-804: в Git не коммитится; исключение из AR-601 (ADR-0016 п.1) |
| Лимиты | `devops/wsl/.wslconfig.template` | `%USERPROFILE%\.wslconfig` | Единственный источник (AR-703) |
| systemd | `devops/wsl/wsl.conf.template` | `/etc/wsl.conf` внутри дистрибутива | Обязателен для нативного Docker (AR-707) |
| Docker Engine | apt-репозиторий Docker | внутри дистрибутива | Без Docker Desktop |
| Каталог данных Docker | `daemon.json` | `/mnt/d/Docker` | Тома на `C:` запрещены (AR-707) |

## 2. Лимиты

| Параметр | Значение | Обоснование |
|---|---|---|
| `processors` | 4 | Половина логических процессоров хоста (20 логических, 6P+8E); оставляет ресурс хосту и ВМ |
| `memory` | 6GB | Из 16 ГБ ОЗУ: 6 ГБ дистрибутиву, остаток — Windows, VMware, кэш |
| `pageReporting` | false | Устранение паразитного I/O и износа SSD (`SC_SSD_LONGEVITY`) |
| `swap` | не задан | Используется файл дистрибутива на `D:` |

## 3. Порядок развёртывания

```powershell
pwsh -File ./devops/hypervisor/Enable-HypervisorPlatform.ps1      # компоненты + hypervisorlaunchtype auto
pwsh -File ./devops/wsl/Install-WslDistro.ps1 -ConfigureDistro    # дистрибутив + лимиты + systemd
# Docker — внутри дистрибутива (сеть уже открыта владельцем):
Get-Content ./devops/containers/Install-DockerEngine.sh -Raw | wsl -d Ubuntu -u root -- bash -s
wsl --shutdown                                                    # перечитать .wslconfig
```

## 4. Верификация

| ID | Проверка | Критерий |
|---|---|---|
| `W1.4` | `wsl -l -v` | дистрибутив в списке, версия 2 |
| `W1.5` | `.wslconfig` | `processors=4`, `memory=6GB`, `pageReporting=false` |
| `P7.2` | `docker info --format '{{.DockerRootDir}}'` | `/mnt/d/Docker` |
| — | `systemctl is-system-running` | `running` |
| `P7.2a` | `docker compose -f dev-stack.yaml up -d` | сервисы поднимаются, тома на `D:` |

## 5. Откат

| Действие | Команда |
|---|---|
| Остановить подсистему | `wsl --shutdown` |
| Удалить дистрибутив (необратимо, только владелец, AR-204) | `wsl --unregister Ubuntu` |
| Снять компоненты | `Disable-WindowsOptionalFeature -Online -FeatureName …` (через ADR) |
