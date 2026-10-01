# PAT-07 — VMware Workstation Pro через WHP API

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-07 |
| `NAME` | VMware Workstation Pro через WHP API |
| `STAGE` | 7 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0002`, `ADR-0016`, `devops/hypervisor/Enable-HypervisorPlatform.ps1`, `devops/hypervisor/Configure-WhpCoexistence.ps1` |

---

## Контекст

WSL2 требует работающего гипервизора Windows. VMware Workstation Pro исторически конфликтует с ним и предлагает
либо отключение Hyper-V, либо режим совместимости через **Windows Hypervisor Platform (WHP) API**. Критерий
`SC_NO_HYPERVISOR_CONFLICT` требует одновременной работы обоих, а `SC_TOOLKIT_PRESERVED` запрещает замену
инструментов (например, на Hyper-V-ВМ).

## Решение

```powershell
# 1. точечные компоненты (AR-701): Hyper-V роль НЕ включается
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform, HypervisorPlatform
# 2. режим гипервизора фиксируется ADR-0002 (AR-702)
bcdedit /set hypervisorlaunchtype auto
# 3. вложенная виртуализация внутри гостя (Docker в ВМ)
vhv.enable = "TRUE"
```

Ключевые свойства:

- гипервизор остаётся загруженным (`auto`) — иначе WSL2 не работает;
- WHP даёт VMware доступ к аппаратной виртуализации поверх гипервизора Windows;
- отключённые VBS/HVCI/LSA (ADR-0012) — предусловие и производительности, и вложенной виртуализации (AR-706);
- полноценный `Microsoft-Hyper-V-All` не включается: WHP достаточно.

## Реализация

| Артефакт | Путь |
|---|---|
| Компоненты и режим загрузчика | `devops/hypervisor/Enable-HypervisorPlatform.ps1` (`SCRIPT-HV-001`) |
| Совместимость и директивы ВМ | `devops/hypervisor/Configure-WhpCoexistence.ps1` (`SCRIPT-HV-002`) |
| Шаблон конфигурации ВМ | `devops/hypervisor/vmware/VM.vmx.template` |

## Проверка

| ID | Критерий |
|---|---|
| `C0.1` | `HypervisorPlatform = Enabled` |
| `C0.2` | `hypervisorlaunchtype = auto` |
| `C0.3` | `Microsoft-Hyper-V-All` не включён |
| `C1.*` | все директивы шаблона присутствуют в каждом `.vmx` |
| `P7.3` | (вручную) ВМ загружается при работающем WSL2 |

## Замечания

- Изменение `hypervisorlaunchtype` выполняется с обязательным снимком BCD (`bcdedit /export`, AR-505).
- Дата центральная поддержка WHP в VMware появилась в ветке 17.x; на более старых сборках потребуется обновление
  (это внешнее требование, проверяется `P7.3`).
