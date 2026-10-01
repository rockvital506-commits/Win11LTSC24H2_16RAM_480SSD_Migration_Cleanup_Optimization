# PAT-21 — Изоляция ресурсов WSL2 (.wslconfig) и нативный Docker

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-21 |
| `NAME` | Изоляция ресурсов WSL2 (.wslconfig) и нативный Docker |
| `STAGE` | 7 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0016`, `devops/wsl/.wslconfig.template`, `devops/wsl/Install-WslDistro.ps1`, `devops/containers/Install-DockerEngine.sh` |

---

## Контекст

WSL2 по умолчанию забирает до 50 % оперативной памяти и до половины ядер, а механизм `pageReporting` возвращает
хост-страницы, порождая паразитный ввод-вывод (износ SSD, `SC_SSD_LONGEVITY`). Docker Desktop добавляет второй
демон и собственные автообновления. Нужен предсказуемый, ограниченный контур.

## Решение

```ini
# %USERPROFILE%\.wslconfig  — единственный источник лимитов (AR-703)
[wsl2]
processors=4
memory=6GB
pageReporting=false
```

```ini
# /etc/wsl.conf внутри дистрибутива
[boot]
systemd=true
```

- лимиты задаются **только** шаблоном `devops/wsl/.wslconfig.template`; скрипты их не дублируют;
- Docker Engine ставится нативно в дистрибутив (`docker-ce` из официального apt-репозитория), без Docker Desktop;
- `data-root` и тома — `/mnt/d/Docker` (AR-707): размещение на `C:` запрещено;
- после изменения `.wslconfig` обязателен `wsl --shutdown` — параметры читаются при старте подсистемы.

## Реализация

| Артефакт | Путь |
|---|---|
| Лимиты (шаблон) | `devops/wsl/.wslconfig.template` |
| systemd (шаблон) | `devops/wsl/wsl.conf.template` |
| Установка дистрибутива | `devops/wsl/Install-WslDistro.ps1` (`SCRIPT-WSL-001`) |
| Docker Engine | `devops/containers/Install-DockerEngine.sh` |
| Dev-стек для проверки | `devops/containers/compose/dev-stack.yaml.template` |

## Проверка

| ID | Критерий |
|---|---|
| `W1.4` | дистрибутив присутствует в `wsl -l -v` |
| `W1.5` | значения `.wslconfig` совпадают с шаблоном |
| `P7.2` | `docker info` → `DockerRootDir = /mnt/d/Docker` |
| `P7.2a` | (вручную) `docker compose -f dev-stack.yaml up -d` поднимает оба сервиса |
| — | `systemctl is-system-running` внутри дистрибутива → `running` |

## Замечания

- Ограничение `memory=6GB` относится к 16 ГБ ОЗУ хоста; пересмотр — при изменении объёма памяти или при
  регулярном OOM внутри дистрибутива (это решение уровня ADR).
- `swap` не задаётся специально: используется файл дистрибутива на `D:`, что соответствует AR-707.
