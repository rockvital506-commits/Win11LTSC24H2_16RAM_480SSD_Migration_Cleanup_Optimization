# PAT-12 — BCD-демонтаж VBS/HVCI/LSA

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-12 |
| `NAME` | BCD-демонтаж VBS/HVCI/LSA |
| `STAGE` | 4 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0012`, `ADR-0002`, `ADR-0010`, `tweaks/bcd/BcdManifest.json`, `tweaks/bcd/Set-BcdVbsFlags.ps1`, `tweaks/registry/RegistryManifest.json` |

---

## Контекст

Гипервизорные защиты (VBS/HVCI/изоляция LSA) дают скрытый CPU-оверхед и мешают планировщику использовать Thread Director (§1.4 `SC_VBS_HVCI_DISABLED`). Отключение только через реестр неполно: загрузчик может сохранить конфигурацию защиты до инициализации рантайма.

## Решение

Двухуровневый демонтаж:
1. реестр — `LsaCfgFlags=0`, `EnableVirtualizationBasedSecurity=0`, `HypervisorEnforcedCodeIntegrity\Enabled=0` (TWK-001…TWK-003);
2. загрузчик — `bcdedit /set loadoptions DISABLE-LSA-ISOLATION,DISABLE-VBS` (BCD-001).

Порядок обязателен: реестр → BCD. Обратный порядок создаёт рассогласованное состояние и блокируется скриптом.

## Реализация

| Артефакт | Путь |
|---|---|
| Манифест реестра | `tweaks/registry/RegistryManifest.json` |
| Манифест BCD | `tweaks/bcd/BcdManifest.json` |
| Применение твиков | `tweaks/apply/Apply-Tweaks.ps1` |
| Изолированное изменение BCD | `tweaks/bcd/Set-BcdVbsFlags.ps1` (AR-505) |
| Верификация | `tweaks/apply/Assert-TweakState.ps1` (R1–R3, B1, V1) |

## Верификация

```powershell
# Предпроверка состояния (read-only)
pwsh -File ./tweaks/apply/Assert-TweakState.ps1

# Изменение BCD — только так (снимок создаётся автоматически)
pwsh -File ./tweaks/bcd/Set-BcdVbsFlags.ps1
```

Критерии: `LsaCfgFlags=0`; `EnableVirtualizationBasedSecurity=0`; HVCI `Enabled=0`; `loadoptions` содержит обе строки; после перезагрузки `Win32_DeviceGuard.VirtualizationBasedSecurityStatus = 0`.

## Ограничения и риски

- Флаги вступают в силу только после перезагрузки; до неё `Win32_DeviceGuard` может показывать старое состояние (`WARN`, не `FAIL`).
- Изменение BCD — операция с риском незагружаемой системы: обязательны `bcdedit /export` и возможность отката (`-Rollback`).
- Восстановление защит без ADR запрещено (`GATE_IMMUTABLE`, README §2.3).

## Альтернативы

| Вариант | Причина отклонения |
|---|---|
| Только реестр | Загрузчик сохраняет конфигурацию защиты до старта ядра |
| Только BCD | Рантайм может быть реактивирован политикой/обновлением |
| Драйверные механики | Запрещены (`NC_DRIVER_SIGNED`, `SC_ZERO_BSOD_RISK`) |

## Результат отработки на стенде

Отключение защит не вызывает BSOD и не ломает WSL2 (`H-001` — VALIDATED).

---

<!-- Файл UTF-8 без BOM, LF. -->
