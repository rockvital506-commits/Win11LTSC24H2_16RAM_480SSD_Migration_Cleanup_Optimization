# ADR-0002 — VMware Workstation Pro через WHP API вместо отключения гипервизора

| Поле | Значение |
|---|---|
| `ADR_ID` | ADR-0002 |
| `TITLE` | Сосуществование WSL2 и VMware Workstation Pro через Windows Hypervisor Platform |
| `STATUS` | **ACCEPTED** (Stage 7; ранее — PLAN) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `APPROVED_BY` | rockvital506-commits (топология варианта A, `1-A`; домены `devops/` согласованы; команда «стартуй Stage 7») |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0010`, `ADR-0012`, `ADR-0016`, AR-701/AR-702, `SC_NO_HYPERVISOR_CONFLICT`, `SC_TOOLKIT_PRESERVED`, `PAT-07` |

---

## Context

Целевой контур включает два гипервизорных потребителя одновременно:

- **WSL2** (Linux-дистрибутив + нативный Docker Engine) — требует компонент `VirtualMachinePlatform` и работающего гипервизора Windows;
- **VMware Workstation Pro** — по историческим причинам отказывается работать при активном Hyper-V и предлагает либо отключить его, либо использовать режим совместимости.

Критерий `SC_NO_HYPERVISOR_CONFLICT` требует, чтобы оба работали. Дополнительно `SC_TOOLKIT_PRESERVED` запрещает «переезд» на другой гипервизор, а ADR-0012 уже отключил VBS/HVCI/LSA (это предусловие производительности Thread Director, AR-706).

Варианты, которые рассматривались:

| Вариант | Суть |
|---|---|
| A. `hypervisorlaunchtype off` + WSL1 | Гипервизор выключен, VMware работает «нативно», WSL переводится в версию 1 |
| B. **hypervisorlaunchtype auto + WHP API** | Гипервизор работает, VMware подключается через Windows Hypervisor Platform, WSL2 работает штатно |
| C. Полноценный Hyper-V (`Microsoft-Hyper-V-All`) + WSL2 + VMware | Управляющий стек Hyper-V включён целиком |
| D. Виртуальные машины Hyper-V вместо VMware | Отказ от VMware как инструмента |

## Decision

Принят **вариант B**:

1. Компоненты включаются точечно (AR-701): `Microsoft-Windows-Subsystem-Linux`, `VirtualMachinePlatform`, `HypervisorPlatform`. Полноценный Hyper-V (вариант C) — не включается: управляющий стек не нужен, расширяет поверхность и обслуживание.
2. `hypervisorlaunchtype` фиксируется в значении **auto** (AR-702) и проверяется верификацией `C0.2`. Значение является частью неизменяемого контура: смена — только через новый ADR (`GATE_IMMUTABLE` не затрагивается, но правило AR-702 привязывает режим к ADR).
3. VMware использует WHP API; для каждой ВМ включается вложенная виртуализация Intel VT-x/EPT (`vhv.enable = "TRUE"`), что даёт работающий Docker внутри гостя.
4. Директивы изоляции кэша каждой ВМ (`mainMem.useNamedFile`, `sched.mem.pshare.enable`, приоритеты) объявлены шаблоном `devops/hypervisor/vmware/VM.vmx.template` и применяются идемпотентно (PAT-22, AR-708).
5. Предусловие результативности: VBS/HVCI/LSA остаются отключёнными (ADR-0012, AR-706). При их включении скрипт контура завершается FAIL, а политика P+E не применяется.

## Consequences

**Положительные:**

- WSL2, Docker Engine и VMware Workstation Pro сосуществуют без ручного переключения режимов (`SC_NO_HYPERVISOR_CONFLICT`).
- Контур минимален: включены ровно три компонента, Hyper-V роль и её службы отсутствуют.
- Вложенная виртуализация доступна: Docker внутри гостевой ВМ работает.

**Отрицательные / компромиссы:**

- VMware работает через прослойку WHP: часть низкоуровневых функций (например, некоторые сценарии с вложенными снапшотами) ведёт себя иначе, чем при «нативном» запуске.
- Появляется зависимость от корректности `HypervisorPlatform`; при обновлении Windows компонент может потребовать повторной проверки — покрывается повторным прогоном верификации.
- Отключённый вариант A остаётся невозможным без нового ADR: перевод WSL в версию 1 нарушил бы AR-707.

**Нейтральные:**

- Управление ВМ остаётся в VMware Workstation Pro; обучение и шаблоны не меняются.

## Alternatives

| Вариант | Причина отклонения |
|---|---|
| A. `hypervisorlaunchtype off` + WSL1 | WSL1 не поддерживает нативный Docker Engine (AR-707) и systemd; деградация контейнерного контура |
| C. Полноценный Hyper-V | Не требуется для WHP; добавляет службы и точки обслуживания, конфликтует с политикой минимизации |
| D. ВМ Hyper-V вместо VMware | Нарушает `SC_TOOLKIT_PRESERVED`; лишает совместимости с существующими шаблонами ВМ |

## Verification

| ID | Проверка | Команда | Критерий |
|---|---|---|---|
| `C0.1` | WHP API включён | `Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform` | `Enabled` |
| `C0.2` | Режим гипервизора | `bcdedit /enum {current}` | `hypervisorlaunchtype auto` |
| `C0.3` | Полноценный Hyper-V не включён | `Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All` | `Disabled/NotFound` |
| `C1.*` | Директивы ВМ | `Configure-WhpCoexistence.ps1` | все ключи шаблона присутствуют в каждом `.vmx` |
| `P7.3` | (вручную) запуск ВМ при активном WSL2 | VMware → старт ВМ | гость загружается, `docker info` внутри гостя работает |

Автоматизация: `devops/hypervisor/Enable-HypervisorPlatform.ps1`, `Configure-WhpCoexistence.ps1`. Результаты — в `docs/artifacts/Stage7_Report.md`.
