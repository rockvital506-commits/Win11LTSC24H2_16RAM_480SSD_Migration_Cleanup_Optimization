# PAT-09 — Исходящие правила брандмауэра для процессов-обходчиков

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-09 |
| `NAME` | Исходящие правила брандмауэра для процессов-обходчиков |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0015`, `templates/ImmunityCore.ps1.template`, `tweaks/apply/Assert-ImmunityState.ps1` (`F1/F2`) |

---

## Контекст

Часть служб-обходчиков восстанавливается планировщиком и ходит в сеть независимо от `hosts` и DNS-политик. Доменные блокировки их не останавливают: соединение устанавливается по IP или через уже разрешённые каналы.

## Решение

Блокировка по **программе**, а не по адресу — правило исходящего трафика для конкретного исполняемого файла:

| Правило | Программа | Направление | Действие |
|---|---|---|---|
| `Block Telemetry Core` | `%SystemRoot%\System32\CompatTelRunner.exe` | Outbound | Block |
| `Block WaaSMedic Outbound Agent` | `%SystemRoot%\System32\WaaSMedicAgent.exe` | Outbound | Block |

Правила создаются идемпотентно (`Get-NetFirewallRule` → `Set-NetFirewallRule -Enabled True`, иначе `New-NetFirewallRule -Profile Any -Enabled True`), применяются **до** финального `deny`, чтобы сеть закрывалась до цементирования конфигурации.

## Реализация

| Артефакт | Путь |
|---|---|
| Декларация состава | `tweaks/firewall/FirewallManifest.json` (`FW-001`, `FW-002`) |
| Апплейер | `tweaks/apply/Apply-FirewallManifest.ps1` (`SCRIPT-FW-001`) |
| Рантайм | `templates/ImmunityCore.ps1.template` — читает `D:\GD_Tool\FirewallRules.json` (встроенный набор — резерв) |
| Верификация | `tweaks/apply/Assert-ImmunityState.ps1` (`F1`, `F2`) |

## Проверка

| ID | Критерий |
|---|---|
| `F1` | правило `Block Telemetry Core` включено, Action = Block |
| `F2` | правило `Block WaaSMedic Outbound Agent` включено, Action = Block |
| `F3` | (вручную) `Test-NetConnection` из процесса-обходчика недоступен |

## Замечания

- **GATE_STRUCTURE закрыт** (2026-10-01): дом `tweaks/firewall/` создан по решению владельца; манифест — единый источник, апплейер `Apply-FirewallManifest.ps1`.
- Правила создаются на уровне Windows Firewall и переживают перезапуск; цементирование их не затрагивает.
