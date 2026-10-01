# Stage7_DevOps_Install.md — Ручной прогон DevOps-контура (Stage 7)

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-MANUAL-S7 |
| `STAGE` | 7 — WSL2 / Docker / VMware / P+E / пакеты |
| `STATUS` | ACTIVE (инструкция; прогон — владелец) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `RELATED` | `algorithm/auto/Stage7_WSL_Docker_VMware.md`, `ADR-0002`, `ADR-0010`, `ADR-0016`, README §4.5, §9.7 |

Этап выполняется **в окне сети** (стык Stage 6→7, §4.5 README) и руками владельца: установка ПО и операции
с виртуальными машинами требуют явного одобрения (AR-204). Скрипты домена сеть не поднимают (AR-709).

## 0. Предусловия

1. Stage 6 закрыт: задача `System_Immunity_Core` активна, замок `GroupPolicy` (Deny SYSTEM) установлен,
   активация Ohook выполнена, `Stage6_immunity.md` без FAIL.
2. Окно сети **открыто владельцем** и будет закрыто сразу после этапа.
3. Носитель `F:` содержит: `F:\WSL2\ubuntu.appx`, установщик VMware Workstation Pro, `F:\TOOLS\*`.
4. Свободно ≥ 10 GiB на `C:` и `D:` (проверка `P0.5`).
5. Рабочая станция в состоянии «до установки ПО»: `winget` доступен (LTSC 24H2 — App Installer).

## 1. Последовательность

| # | Шаг | Команда / действие | Проверка |
|---|---|---|---|
| 1 | Компоненты виртуализации | `pwsh -File ./devops/hypervisor/Enable-HypervisorPlatform.ps1` | `H0.1/H0.2`, перезагрузка по `RestartNeeded` |
| 2 | BCD-режим гипервизора | там же: `hypervisorlaunchtype auto`; снимок BCD сохранён | `C0.2` |
| 3 | Дистрибутив WSL2 | `pwsh -File ./devops/wsl/Install-WslDistro.ps1` (по умолчанию — из `F:\WSL2\ubuntu.appx`) | `W1.4`, `wsl -l -v` |
| 4 | Лимиты и systemd | `.wslconfig` + `/etc/wsl.conf` разворачиваются скриптом; перезапуск дистрибутива | `W1.5`, `wsl --shutdown` |
| 5 | Docker Engine | `wsl -d Ubuntu -u root -- bash -s < ./devops/containers/Install-DockerEngine.sh` | `docker info` → `DockerRootDir=/mnt/d/Docker` (`P7.2`) |
| 6 | VMware Workstation Pro | Установка с `F:` вручную (мастер), затем `pwsh -File ./devops/hypervisor/Configure-WhpCoexistence.ps1` | `C1.*`, загрузка ВМ при активном WSL2 (`P7.3`) |
| 7 | P+E-политика | `pwsh -File ./devops/cpu-policy/Set-WorkloadAffinity.ps1 -ApplyPowerPlan` (или без флага — только сверка) | `A0.1`, `A1.*`, `A2.*` |
| 8 | Пакеты профиля | `pwsh -File ./packages/bootstrap/Invoke-PackageSync.ps1 -ResolveVersions` → `pwsh -File ./packages/bootstrap/Bootstrap-Packages.ps1 -Profile devops` | `PKG-P0`, `B1.1`, `docs/artifacts/Stage7_packages.md` |
| 9 | Сводный отчёт | `pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1` | `Stage7_preflight.md` без FAIL |

Вместо шагов 1–8 допускается один прогон оркестратора `scripts/Stage7_WSL_Docker_VMware.ps1`
(последовательность P1–P6); шаг 6 (установка VMware мастером) всегда выполняется человеком.

## 2. Критерии приёмки

- `wsl -l -v` — дистрибутив в версии 2; `docker info` — `DockerRootDir=/mnt/d/Docker`, тома пишутся на `D:`;
- ВМ загружается при работающем WSL2; в каталоге ВМ нет `*.vmem`, `priority.grabbed` применён (PAT-22);
- `A0.1` — маска выведена динамически, `P=6/E=8` для i5-12400F либо расхождение зафиксировано;
- `Packages.lock.json` без записей `UNPINNED`; профиль `devops` установлен;
- замки Stage 6 не пострадали: `pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -VerifyOnly` — без FAIL;
- окно сети закрыто владельцем, `Stage7_Report.md` переведён в DONE.

## 3. Откат

| Ситуация | Действие |
|---|---|
| Конфликт гипервизора (ВМ не стартует) | `bcdedit /set hypervisorlaunchtype off` (точечная правка, снимок BCD уже сохранён) |
| Ошибка установки дистрибутива | Повторный прогон идемпотентен; файл-артефакт на `F:` не удаляется (AR-201) |
| Docker не поднимается | Проверить `docker info`, затем повторный прогон `Install-DockerEngine.sh` (идемпотентен) |
| Деградация компиляции/ВМ после привязки P-ядер | Снять привязку вручную (вернуть приоритет процессов на `Normal`, маску — по умолчанию ОС); спор о приоритетах — `GATE_AMBIGUITY` |

## 4. Ограничения

- **GATE_AMBIGUITY** (`S7-OPEN-5`): контракт AR-708/ADR-0002 не определяет директиву `.vmx` для привязки
  виртуальных машин к P-ядрам. Агент не изобретает ключ: привязка выполняется на уровне процессов
  (`Set-WorkloadAffinity.ps1`), либо вопрос выносится владельцу отдельным решением.
- Офлайн-компоненты (VMware, `coreinfo64.exe`, дистрибутив) в Git не коммитятся (AR-804); их SHA256
  фиксируются в `packages/hashes/PACKAGES_SHA256.txt`.
- Обновление VMware до сборки с поддержкой WHP — внешнее требование (PAT-07).
