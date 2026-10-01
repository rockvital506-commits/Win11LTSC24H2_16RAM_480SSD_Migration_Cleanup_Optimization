# HYPERVISOR_MATRIX.md — Матрица гипервизорного сосуществования

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | DEVOPS-HV |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | `ADR-0002`, `ADR-0012`, `ADR-0016`, `PAT-07`, `PAT-22`, AR-701, AR-702, AR-708 |

## 1. Состояние компонентов

| Компонент | Состояние | Обоснование |
|---|---|---|
| `Microsoft-Windows-Subsystem-Linux` | **Enabled** | WSL2 (AR-701) |
| `VirtualMachinePlatform` | **Enabled** | Подсистема виртуальных машин WSL2 |
| `HypervisorPlatform` (WHP) | **Enabled** | API для VMware Workstation Pro (ADR-0002) |
| `Microsoft-Hyper-V-All` | **Disabled** | Управляющий стек не требуется (AR-701) |
| Гипервизор Windows | **активен** | `hypervisorlaunchtype = auto` (AR-702, фиксируется ADR-0002) |
| VBS / HVCI / LSA Isolation | **отключены** | ADR-0012; предусловие AR-706 |

## 2. Как работает сосуществование

```
┌──────────────────────── Windows 11 IoT LTSC (хост) ────────────────────────┐
│  Hyper-V гипервизор (hypervisorlaunchtype=auto)                            │
│    ├── VirtualMachinePlatform → WSL2 (дистрибутив Ubuntu, Docker Engine)    │
│    └── HypervisorPlatform (WHP API) → VMware Workstation Pro (гости)        │
└────────────────────────────────────────────────────────────────────────────┘
```

- VMware **не** требует отключения гипервизора: используется WHP;
- вложенная виртуализация гостей включается `vhv.enable = "TRUE"` (Docker внутри ВМ);
- VBS/HVCI отключены: их включение возвращает накладные расходы и мешает политике P+E (AR-706).

## 3. Верификация

| ID | Проверка | Критерий | Инструмент |
|---|---|---|---|
| `C0.1` | WHP включён | `Enabled` | `Get-WindowsOptionalFeature` |
| `C0.2` | Режим загрузчика | `auto` | `bcdedit /enum {current}` |
| `C0.3` | Hyper-V роль | `Disabled/NotFound` | `Get-WindowsOptionalFeature` |
| `C1.*` | Директивы `.vmx` | полный набор | `Configure-WhpCoexistence.ps1` |
| `P7.3` | Совместный запуск (вручную) | ВМ грузится при активном WSL2 | VMware + `wsl -l -v` |

## 4. Типовые отказы

| Симптом | Вероятная причина | Действие |
|---|---|---|
| VMware требует отключить Hyper-V | WHP-компонент выключен или старая сборка VMware | `Enable-HypervisorPlatform.ps1`; обновить VMware (внешнее требование) |
| WSL не стартует после правок BCD | `hypervisorlaunchtype=off` | Вернуть `auto` (ADR-0002), перезагрузка |
| Гость тормозит, `*.vmem` пишется | Директивы `.vmx` не применены | `Configure-WhpCoexistence.ps1` |
| BSOD/нестабильность при нагрузке | Включены VBS/HVCI в обход ADR-0012 | Проверить `H0.1`, восстановить ADR-0012 (`GATE_IMMUTABLE`) |
