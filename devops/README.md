# devops/ — Домен 3: WSL2 / Hyper-V / VMware / P+E

Основание: AR-701 … AR-710. Целевой контур: WSL2 + нативный Docker Engine + VMware Workstation Pro через WHP API, без конфликта гипервизоров.

## Состав

| Каталог | Содержимое |
|---|---|
| `wsl/` | `.wslconfig.template`, `wsl.conf.template`, `Install-WslDistro.ps1` |
| `hypervisor/` | `Enable-HypervisorPlatform.ps1`, `Configure-WhpCoexistence.ps1`, `vmware/VM.vmx.template` |
| `cpu-policy/` | `Get-PerformanceCoreMask.ps1`, `Set-WorkloadAffinity.ps1`, `power-plan.json` |
| `containers/` | `Install-DockerEngine.sh`, `compose/*.yaml` |

## Ключевые ограничения

- Компоненты: только `Microsoft-Windows-Subsystem-Linux`, `VirtualMachinePlatform`, `HypervisorPlatform` (AR-701). Полноценный Hyper-V — только с ADR.
- VMware — через WHP API; `hypervisorlaunchtype` фиксируется ADR-0002 (AR-702).
- `.wslconfig` — единственный источник лимитов, хранится как шаблон (AR-703): `processors=4`, `memory=6GB`, `pageReporting=false` (PAT-21).
- **P+E:** маска P-ядер определяется динамически, хардкод запрещён (AR-704, ADR-0010). Тяжёлые сборки и `vmmemWSL` — на P-ядрах с приоритетом не выше `Normal` (AR-705).
- Docker Engine — нативно в WSL2 (`systemd=true`), без Docker Desktop; тома на `D:\Docker` (AR-707).
- VMware: `mainMem.useNamedFile=FALSE`, `sched.mem.pshare.enable=FALSE`; диски/снапшоты только на `D:\VM` (AR-708).
