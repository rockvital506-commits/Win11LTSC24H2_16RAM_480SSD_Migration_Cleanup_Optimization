# PAT-13 — Fixed PageFile (монолитная подкачка)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-13 |
| `NAME` | Fixed PageFile (монолитная подкачка) |
| `STAGE` | 4 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0013`, `AR-706` (VBS/HVCI), `tweaks/apply/Assert-TweakState.ps1`, README §6.3.4 |

---

## Контекст

Динамический файл подкачки на SSD при нагрузках контейнеров и сборок расширяется и фрагментируется, что даёт рост WAF и непредсказуемый I/O. Для станции с 16 ГБ ОЗУ и лимитами WSL2 (`PAT-21`) размер подкачки можно зафиксировать.

## Решение

`AutomaticManagedPagefile = False`; `InitialSize = MaximumSize = 4096 МБ`. Значение монотонно и не меняется со временем: ядро не тратит циклы на расширение/сжатие/перемещение секторов. Параметризовано (`-PageFileMb`); изменение значения — через ADR-0013.

## Реализация

| Артефакт | Путь |
|---|---|
| Реализация | `scripts/Stage4_Audit_Final_Clean.ps1` (фаза P4, `Invoke-MemoryConfiguration`) |
| Верификация | `tweaks/apply/Assert-TweakState.ps1` (M1) |

```powershell
$cs = Get-CimInstance Win32_ComputerSystem
$cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false }
Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' } |
    Set-CimInstance -Property @{ InitialSize = 4096; MaximumSize = 4096 }
```

## Верификация

Критерий `M1`: `AutomaticManagedPagefile = False` и `InitialSize = MaximumSize = 4096`. При отсутствии настройки создаётся новый экземпляр `Win32_PageFileSetting`.

## Ограничения и риски

- При экстремальных пиках возможны ошибки выделения памяти — компенсируется лимитами WSL2 и возможностью поднять значение до 8192 МБ через ADR.
- Перенос подкачки на `D:\` не даёт выигрыша: тот же физический носитель.

## Альтернативы

| Вариант | Причина отклонения |
|---|---|
| Динамический/системный размер | Фрагментация и рост WAF |
| Отключить подкачку полностью | Риск отказов при пиковых нагрузках контейнеров и сборок |
| 8192 МБ по умолчанию | Избыточно при 16 ГБ ОЗУ и лимите WSL2 в 6 ГБ |

---

<!-- Файл UTF-8 без BOM, LF. -->
