# devops/ — Домен 3: WSL2 / Hyper-V / VMware / P+E

Основание: AR-701 … AR-710. Целевой контур: WSL2 + нативный Docker Engine + VMware Workstation Pro через WHP API, без конфликта гипервизоров.

## Состав

| Каталог | Содержимое |
|---|---|
| `wsl/` | `.wslconfig.template`, `wsl.conf.template`, `Install-WslDistro.ps1` |
| `hypervisor/` | `Enable-HypervisorPlatform.ps1`, `Configure-WhpCoexistence.ps1`, `vmware/VM.vmx.template` |
| `cpu-policy/` | `Get-PerformanceCoreMask.ps1`, `Set-WorkloadAffinity.ps1`, `power-plan.json` |
| `containers/` | `Install-DockerEngine.sh`, `compose/*.yaml` |

## Реализация (Stage 7)

| Скрипт | Script-ID | Назначение |
|---|---|---|
| `wsl/Install-WslDistro.ps1` | `SCRIPT-WSL-001` | Установка дистрибутива из офлайн-пакета + `.wslconfig` + `/etc/wsl.conf` |
| `hypervisor/Enable-HypervisorPlatform.ps1` | `SCRIPT-HV-001` | Компоненты виртуализации и `hypervisorlaunchtype auto` (ADR-0002) |
| `hypervisor/Configure-WhpCoexistence.ps1` | `SCRIPT-HV-002` | Сосуществование WHP и директивы `.vmx` (PAT-07, PAT-22) |
| `cpu-policy/Get-PerformanceCoreMask.ps1` | `SCRIPT-CPU-001` | Динамическая маска P-ядер (ADR-0010, AR-704) |
| `cpu-policy/Set-WorkloadAffinity.ps1` | `SCRIPT-CPU-002` | Привязка нагрузок и сверка схемы питания (AR-705) |
| `containers/Install-DockerEngine.sh` | — | Нативный Docker Engine в WSL2, `data-root=/mnt/d/Docker` (AR-707) |
| `../../scripts/Stage7_WSL_Docker_VMware.ps1` | `SCRIPT-STAGE7-001` | Оркестратор этапа (фазы P0–P7) |

Документация: `docs/devops/{WSL2_SCHEMA,HYPERVISOR_MATRIX,P_E_CORE_AFFINITY}.md`; решения — `ADR-0002`, `ADR-0010`, `ADR-0016`.

## Ключевые ограничения

- Компоненты: только `Microsoft-Windows-Subsystem-Linux`, `VirtualMachinePlatform`, `HypervisorPlatform` (AR-701). Полноценный Hyper-V — только с ADR.
- VMware — через WHP API; `hypervisorlaunchtype` фиксируется ADR-0002 (AR-702).
- `.wslconfig` — единственный источник лимитов, хранится как шаблон (AR-703): `processors=4`, `memory=6GB`, `pageReporting=false` (PAT-21).
- **P+E:** маска P-ядер определяется динамически, хардкод запрещён (AR-704, ADR-0010). Тяжёлые сборки и `vmmemWSL` — на P-ядрах с приоритетом не выше `Normal` (AR-705).
- Docker Engine — нативно в WSL2 (`systemd=true`), без Docker Desktop; тома на `D:\Docker` (AR-707).
- VMware: `mainMem.useNamedFile=FALSE`, `sched.mem.pshare.enable=FALSE`; диски/снапшоты только на `D:\VM` (AR-708).
