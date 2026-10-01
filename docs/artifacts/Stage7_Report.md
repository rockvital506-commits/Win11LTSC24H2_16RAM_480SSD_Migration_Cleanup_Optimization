# Stage7_Report.md — Отчёт этапа 7 (DevOps-контур)

| Поле | Значение |
|---|---|
| `REPORT_ID` | SR-7 |
| `STAGE` | Stage 7 — WSL2 / Docker / VMware / P+E |
| `STATUS` | **IN_PROGRESS** — пакет этапа DONE; прогон на стенде и окно сети ожидают владельца (AR-204, AR-709) |
| `DATE_START` | 2026-10-01 |
| `DATE_END` | — (закрывается после установки профиля `devops` и закрытия окна сети) |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `PREVIOUS` | `Stage6_Report.md` |
| `NEXT` | `Final_Report.md` |
| `COMMIT_BASE` | `9bde37c` (Stage 6) |

> **О статусе.** Агентом собраны декларации, скрипты и документация. Операции на хосте (включение компонентов,
> установка дистрибутива, Docker, ВМ, пакеты) выполняет владелец в окне сети: установка ПО и работа с
> виртуальными машинами отнесены к действиям, требующим явного одобрения (AR-204). Агент мутаций не производил.

---

## 1. Контекст и цель этапа

Stage 7 собирает рабочий DevOps-контур поверх иммунизированной станции: WSL2 с нативным Docker Engine,
VMware Workstation Pro через WHP API (сосуществование без конфликта гипервизоров), политика P+E-ядер
и фиксированный набор пакетов профиля `devops`.

## 2. Выполненные операции (агент, 2026-10-01)

| # | Операция | Артефакт | Результат |
|---|---|---|---|
| 1 | Компоненты виртуализации и режим гипервизора | `devops/hypervisor/Enable-HypervisorPlatform.ps1` (`SCRIPT-HV-001`) | DONE |
| 2 | Сосуществование WHP + директивы `.vmx` | `devops/hypervisor/Configure-WhpCoexistence.ps1` (`SCRIPT-HV-002`), `vmware/VM.vmx.template` | DONE |
| 3 | Дистрибутив WSL2 и лимиты | `devops/wsl/Install-WslDistro.ps1` (`SCRIPT-WSL-001`), `.wslconfig.template`, `wsl.conf.template` | DONE |
| 4 | Нативный Docker Engine | `devops/containers/Install-DockerEngine.sh`, `compose/dev-stack.yaml.template` | DONE |
| 5 | Политика P+E | `devops/cpu-policy/Get-PerformanceCoreMask.ps1` (`SCRIPT-CPU-001`), `Set-WorkloadAffinity.ps1` (`SCRIPT-CPU-002`), `power-plan.json` | DONE |
| 6 | Оркестратор этапа | `scripts/Stage7_WSL_Docker_VMware.ps1` (`SCRIPT-STAGE7-001`) | DONE |
| 7 | Расширение allow-list Guard | `scripts/common/Guard.psm1` (`C:\DevOps`, `D:\VM`, `D:\Docker`) | DONE |
| 8 | Решения этапа | `ADR-0002` (WHP), `ADR-0016` (контур Stage 7) | ACCEPTED |
| 9 | Алгоритм этапа | `algorithm/auto/Stage7_WSL_Docker_VMware.md` | DONE |
| 10 | Схемы DevOps-контура | `docs/devops/WSL2_SCHEMA.md`, `HYPERVISOR_MATRIX.md`, `P_E_CORE_AFFINITY.md` | DONE |
| 11 | Паттерны | `PAT-07`, `PAT-21`, `PAT-22` | DONE |
| 12 | Прогон валидатора конвенций | — | **PASS** (166 файлов, 0 нарушений) |

## 3. Состав контура (целевое состояние)

| Элемент | Параметр | Источник | Паттерн |
|---|---|---|---|
| WSL2 | дистрибутив Ubuntu 2.x, `systemd=true` | `F:\WSL2\ubuntu.appx` | PAT-21 |
| Лимиты WSL2 | `processors=4`, `memory=6GB`, `pageReporting=false` | `.wslconfig.template` | PAT-21 |
| Docker | нативный Engine, `data-root=/mnt/d/Docker` | `Install-DockerEngine.sh` | PAT-21 |
| VMware | WHP API + директивы изоляции | `VM.vmx.template` | PAT-07, PAT-22 |
| Гипервизор | 3 компонента, `launchtype auto`, Hyper-V выключен | `Enable-HypervisorPlatform.ps1` | PAT-07 |
| P+E | динамическая маска + привязка ≤ `Normal` | `cpu-policy/*` | ADR-0010 |
| Пакеты | профиль `devops`, версии из lock-файла | `packages/*` | AR-601…AR-607 |

## 4. Открытые вопросы

| ID | Вопрос | Решение (2026-10-01) | Состояние |
|---|---|---|---|
| `S7-OPEN-1` | Версии пакетов в `Packages.lock.json` | заполняются в окне сети командой `Invoke-PackageSync.ps1 -ResolveVersions` (запрос `winget show`); до заполнения установка блокируется | OPEN |
| `S7-OPEN-2` | Пиннинг Docker Engine (apt) | версия фиксируется в отчёте по факту установки; пофайловый хэш-пиннинг apt не даёт | OPEN (принято) |
| `S7-OPEN-3` | Sysinternals `coreinfo` для перекрёстной проверки P/E | поставляется офлайн в `F:\TOOLS\Audit\`; при отсутствии проверка помечается `not-available` | OPEN |
| `S7-OPEN-4` | Схема питания (`power-plan.json`) | по умолчанию сверка (WARN); применение — `-ApplyPowerPlan` | OPEN (решение владельца) |

## 5. Ручной контроль (заполняет владелец)

| # | Пункт | Отметка |
|---|---|---|
| 1 | `Stage7_preflight.md`: `P0.*`, `C0.*`, `W1.*` без FAIL | _заполнить_ |
| 2 | Дистрибутив установлен, Linux-пользователь создан | _заполнить_ |
| 3 | `docker info` → `DockerRootDir=/mnt/d/Docker`; dev-стек поднимается | _заполнить_ |
| 4 | ВМ создана, директивами `.vmx` применены, гость загружается при активном WSL2 (`P7.3`) | _заполнить_ |
| 5 | Драйверы/ПО из `packages/` установлены профилем `devops`; lock-файл заполнен | _заполнить_ |
| 6 | `A0.1/A1.1`: маска P-ядер выведена, привязка применена | _заполнить_ |
| 7 | Окно сети закрыто; повторный прогон верификации без FAIL | _заполнить_ |
| 8 | `Stage6_immunity` подтверждён после этапа (замки и задача не пострадали) | _заполнить_ |

## 6. Метрики (§3.5 README)

| Метрика | Цель | Факт |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | **22/28** документировано (+3 к Stage 6: PAT-07, PAT-21, PAT-22) |
| `M_ADR_COUNT` | ≥1 на решение | ADR-0002, ADR-0016 закрывают Stage 7 |
| `M_BSOD_INCIDENTS` | 0 | PENDING |
| `M_DOC_FRESHNESS` | актуальность | 2026-10-01 |
| `M_PACKAGE_PINNING` | 100 % версий зафиксировано | 0 % до окна сети (`S7-OPEN-1`) |

## 7. Критерии выхода

Этап закрывается, когда: компоненты включены и проверены; дистрибутив установлен с лимитами; Docker Engine
работает с томами на `D:`; директивы `.vmx` применены; пакеты профиля `devops` установлены и зафиксированы в
lock-файле; окно сети закрыто; отчёт переведён в `DONE`, а `Final_Report.md` — заполнен.

## 8. Риски

| Риск | Оценка | Митигация |
|---|---|---|
| Требуется перезагрузка после включения компонентов | Высокая (штатно) | `RestartNeeded` фиксируется; прогон продолжается после перезагрузки |
| apt-репозиторий Docker недоступен | Средняя | Идемпотентный скрипт, повторный прогон в окне сети |
| VMware старой сборки | Средняя | Обновление VMware — внешнее требование (PAT-07) |
| Пакеты без версий | Высокая до окна сети | Установка блокируется до заполнения lock-файла |
