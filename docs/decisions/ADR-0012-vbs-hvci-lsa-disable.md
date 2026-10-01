# ADR-0012 — Демонтаж VBS/HVCI/LSA-изоляции

| Поле | Значение |
|---|---|
| `ADR_ID` | ADR-0012 |
| `TITLE` | Disable VBS / HVCI / LSA isolation (registry + boot loader) |
| `STATUS` | **ACCEPTED** |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `APPROVED_BY` | rockvital506-commits (контур утверждён как якорь1; реализация Stage 4 согласована) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `PAT-12`, `ADR-0002` (VMware via WHP), `ADR-0010` (P+E), README §1.4 `SC_VBS_HVCI_DISABLED`, §2.3, §4.5 |

---

## Context

VBS (Virtualization-Based Security), HVCI (Hypervisor-Enforced Code Integrity) и изоляция LSA добавляют слой гипервизорной проверки: подписывание кода, изоляция секретов, проверка целостности ядра. На гибридных процессорах (i7 6P+8E) это даёт измеримый оверхед: часть циклов уходит на проверки в Hyper-V-контуре, растут задержки прерываний (DPC), планировщик хуже использует Thread Director (`H-001` — VALIDATED: отключение не вызывает BSOD при сохранении WSL2).

Ограничения проекта:
- `SC_VBS_HVCI_DISABLED` — критерий успеха, зафиксированный в Immutable Core (README §1.4);
- §2.3 README запрещает восстановление VBS/HVCI/LSA без одобрения (`GATE_IMMUTABLE`);
- `NC_DRIVER_SIGNED` — проект не применяет механики, требующие подписанных драйверов;
- Stage 7 требует сосуществования WSL2 и VMware через WHP API (`ADR-0002`), что чувствительно к конфигурации гипервизора.

## Decision

1. **Отключение на двух уровнях** (реестр + загрузчик), поскольку одного уровня недостаточно: реестровые ключи управляют рантаймом, а `loadoptions` — конфигурацией загрузчика до старта ядра.

| ID | Объект | Значение | Артефакт |
|---|---|---|---|
| `TWK-001` | `HKLM\SYSTEM\CurrentControlSet\Control\Lsa` → `LsaCfgFlags` | `0` | `tweaks/registry/RegistryManifest.json` |
| `TWK-002` | `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` → `EnableVirtualizationBasedSecurity` | `0` | там же |
| `TWK-003` | `...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` → `Enabled` | `0` | там же |
| `BCD-001` | `bcdedit /set loadoptions DISABLE-LSA-ISOLATION,DISABLE-VBS` | строка | `tweaks/bcd/BcdManifest.json` |

2. **BCD изменяется только изолированным скриптом** `tweaks/bcd/Set-BcdVbsFlags.ps1` с обязательным `bcdedit /export` до изменения (AR-505). Оркестратор Stage 4 по умолчанию BCD не трогает (флаг `-IncludeBcd` — осознанное исключение).
3. **Последовательность обязательна:** сначала реестр, затем BCD. Скрипт BCD отказывается работать, если элементы `TWK-001`–`TWK-003` не применены (защита от рассогласованного состояния: загрузчик отключён, реестр включён), обход — только явным `-SkipRegistryPrecheck`.
4. **Целевое состояние проверяется** скриптом `Assert-TweakState.ps1`: значения реестра, `loadoptions`, `Win32_DeviceGuard.VirtualizationBasedSecurityStatus = 0` (после перезагрузки).
5. **Восстановление запрещено без нового ADR** (`GATE_IMMUTABLE`, README §2.3). Откат возможен технически (`Set-BcdVbsFlags.ps1 -Rollback` из снимка), но является нарушением утверждённого контура.
6. **Defender не восстанавливается** как активный AV (`NC_DEFENDER_REVERT`); отключение VBS/HVCI не отменяет исключений и правил, зафиксированных на Stage 6.

## Consequences

**Положительные:**

- Снят скрытый CPU-оверхед: больше ресурсов P-ядер доступно планировщику и Thread Director (ADR-0010).
- VMware через WHP и WSL2 сосуществуют без конфликта (`SC_NO_HYPERVISOR_CONFLICT`).
- Задержки прерываний ниже — критично для сборок и виртуализации.

**Отрицательные / компромиссы:**

- Система становится менее защищённой от некоторых классов атак (код-инъекции в ядро, кража секретов LSA). Компенсация: изоляция сети, `PAT-11` (NTFS Deny SYSTEM), брандмауэр-правила (`PAT-09`), отсутствие недоверенного ПО.
- `ResetBase` (PAT-18) и удаление старых компонентов делают откат обновлений невозможным — принято как целевой результат (SC_FACTORY_RESET_CAPABLE опирается на повторное развёртывание, а не на откат).
- Некоторые приложения с обязательной проверкой целостности могут требовать VBS; для целевого профиля (devops-станция) конфликтов не ожидается.

**Нейтральные:**

- Изменение вступает в силу после перезагрузки; до неё возможны ложные показания `Win32_DeviceGuard` (учитывается в верификации как `WARN`).

## Alternatives

| Вариант | Причина отклонения |
|---|---|
| Оставить VBS/HVCI включёнными | Прямое нарушение `SC_VBS_HVCI_DISABLED` и §2.3 README; оверхед на P+E-платформе |
| Отключить только через реестр | Загрузчик может сохранить конфигурацию защиты до инициализации рантайма |
| Отключить только через BCD | Рантайм-компоненты могут быть повторно включены политикой/обновлением |
| Отключить Defender вместо VBS | Нарушает `NC_DEFENDER_REVERT` и не решает задачу |

## Verification

| ID | Проверка | Команда | Критерий |
|---|---|---|---|
| `W1` | `LsaCfgFlags` | `Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'` | `0` |
| `W2` | `EnableVirtualizationBasedSecurity` | `Get-ItemProperty '...\DeviceGuard'` | `0` |
| `W3` | HVCI `Enabled` | `Get-ItemProperty '...\HypervisorEnforcedCodeIntegrity'` | `0` |
| `W4` | loadoptions | `bcdedit /enum {current}` | `DISABLE-LSA-ISOLATION,DISABLE-VBS` |
| `W5` | VBS runtime | `Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard` | `VirtualizationBasedSecurityStatus = 0` (после перезагрузки) |

Автоматизация: `tweaks/apply/Assert-TweakState.ps1` (проверки R1–R3, B1, V1). Результаты — в `docs/artifacts/Stage4_Report.md`.
