# Stage 7 (auto) — Развёртывание DevOps-контура

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S7-AUTO |
| `STAGE` | 7 |
| `TYPE` | auto |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE (пакет) — прогон на стенде ожидает владельца |
| `RELATED` | `ADR-0002`, `ADR-0010`, `ADR-0016`, `PAT-07`, `PAT-21`, `PAT-22`, `scripts/Stage7_WSL_Docker_VMware.ps1` |

---

## 1. Цель этапа

Финальный этап: собрать рабочий контур (WSL2 + нативный Docker Engine + VMware Workstation Pro через WHP API),
применить политику P+E-ядер и установить пакеты профиля `devops`. После этапа станция переходит в режим
долгосрочной офлайн-эксплуатации.

Этап выполняется в одном окне сети (стык Stage 6 → 7, README §4.5): оконечная изоляция уже построена, а контуру
нужен доступ к apt-репозиторию Docker и к установщикам winget.

## 2. Предусловия

| # | Требование | Проверка |
|---|---|---|
| 1 | Stage 6 закрыт: задача `System_Immunity_Core` зарегистрирована, замки на месте | `P0.2`, `P0.3` |
| 2 | Окно сети открыто владельцем | `P0.1`: ≥ 1 активный адаптер |
| 3 | Офлайн-пакет дистрибутива `F:\WSL2\ubuntu.appx` | `P0.4` (WARN, если отсутствует) |
| 4 | Свободное место: `C:` ≥ 10 GiB, `D:` ≥ 10 GiB | `P0.5.*` |
| 5 | Права администратора; PowerShell 5.1+ | `Assert-Administrator` (AR-401) |
| 6 | VBS/HVCI/LSA отключены (ADR-0012) | `H0.1` |

## 3. Порядок выполнения

```powershell
# 1. Сухой прогон: предусловия и план, без изменений (AR-302)
pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1 -Audit

# 2. Основной прогон (окно сети открыто владельцем)
pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1 `
     -VerificationReport ./docs/artifacts/Stage7_preflight.md

# 3. [ВЛАДЕЛЕЦ] создать ВМ в VMware и запустить апплейер директив заново
pwsh -File ./devops/hypervisor/Configure-WhpCoexistence.ps1

# 4. [ВЛАДЕЛЕЦ] закрыть окно сети и выполнить итоговую проверку
pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1 -SkipHypervisor -SkipWsl -SkipDocker -SkipVmware -SkipPackages
```

**Фазы оркестратора:**

| Фаза | Действие | Артефакт |
|---|---|---|
| `P0` | предусловия: права, окно сети, замки Stage 6, пакет дистрибутива, место | — |
| `P1` | компоненты виртуализации + `hypervisorlaunchtype auto` | `Enable-HypervisorPlatform.ps1` |
| `P2` | дистрибутив WSL2 + `.wslconfig` + `/etc/wsl.conf` | `Install-WslDistro.ps1` |
| `P3` | нативный Docker Engine, `data-root=/mnt/d/Docker` | `Install-DockerEngine.sh` |
| `P4` | совместимость WHP + директивы `.vmx` | `Configure-WhpCoexistence.ps1` |
| `P5` | P+E: маска P-ядер, привязка, схема питания | `Set-WorkloadAffinity.ps1` |
| `P6` | пакеты профиля `devops` | `packages/bootstrap/Bootstrap-Packages.ps1` |
| `P7` | сводная верификация | `Stage7_preflight.md` |

## 4. Критерии приёмки

| ID | Критерий | Где смотреть |
|---|---|---|
| `C0.1–C0.3` | WHP включён, `launchtype auto`, Hyper-V не включён | `Stage7_preflight.md` |
| `W1.4/W1.5` | дистрибутив установлен, лимиты совпадают с шаблоном | там же |
| `P7.2` | `DockerRootDir = /mnt/d/Docker` | там же |
| `C1.*` | директивы `.vmx` во всех ВМ | там же |
| `A0.1/A1.1` | маска P-ядер выведена, процессы привязаны | там же |
| `A2.*` | схема питания совпадает с декларацией (или WARN) | там же |
| — | профиль `devops` установлен, lock-файл заполнен | `Stage7_Report.md` |
| — | окно сети закрыто, станция офлайн | `Stage7_Report.md` §ручной контроль |

## 5. Откат

| Что | Как |
|---|---|
| Компоненты виртуализации | `Disable-WindowsOptionalFeature` (только через ADR; ломает WSL2 и WHP) |
| Дистрибутив | `wsl --unregister Ubuntu` (необратимо: подтверждение владельца, AR-204) |
| Лимиты WSL2 | правка `%USERPROFILE%\.wslconfig` + `wsl --shutdown` |
| Директивы `.vmx` | восстановление из `backups/<UTC>_stage7-vmx/` |
| Привязка P-ядер | снятие маски у процесса или его перезапуск |
| Пакеты | только через `Invoke-PackageSync.ps1 -Remove` (ручной `winget uninstall` запрещён, AR-606) |

## 6. Риски

| Риск | Митигация |
|---|---|
| Перезагрузка требуется после включения компонентов | флаг `RestartNeeded` в журнале; прогон P2–P4 продолжается после перезагрузки |
| apt-репозиторий Docker недоступен в окне сети | `Install-DockerEngine.sh` завершается ошибкой, ничего не меняя (идемпотентность) |
| VMware старой сборки не поддерживает WHP | `P7.3` (ручная проверка), обновление VMware — внешнее требование |
| Маска P/E определена неверно | скрипт не применяет эвристику при неопределённости (AR-906) |
| Пакеты без зафиксированных версий | установка блокируется до заполнения lock-файла (`S7-OPEN-1`) |
