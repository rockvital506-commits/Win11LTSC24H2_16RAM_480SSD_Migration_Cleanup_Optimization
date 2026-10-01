# firewall — Правила брандмауэра

`FirewallManifest.json` — декларация исходящих правил против процессов-обходчиков (PAT-09, ADR-0015).
Домен создан решением владельца (`GATE_STRUCTURE`, 2026-10-01).

| ID | Правило | Программа | Действие |
|---|---|---|---|
| `FW-001` | `Block Telemetry Core` | `%SystemRoot%\System32\CompatTelRunner.exe` | Outbound → Block |
| `FW-002` | `Block WaaSMedic Outbound Agent` | `%SystemRoot%\System32\WaaSMedicAgent.exe` | Outbound → Block |

## Поток данных

```
tweaks/firewall/FirewallManifest.json        (единый источник)
        ├── Apply-FirewallManifest.ps1       → применение в сеансе подготовки (SCRIPT-FW-001)
        └── Stage6_Immunity_Prepare.ps1      → D:\GD_Tool\FirewallRules.json
                                                └── ImmunityCore.ps1 (рантайм, PAT-NEW-3)
```

Ядро содержит встроенный аварийный набор на случай отсутствия `FirewallRules.json`; расхождение состава
ловится верификацией `Assert-ImmunityState.ps1` (`F1`, `F2`).

## Правила

- Блокировка по **программе**, а не по IP/домену: адресные правила обходятся сменой адреса.
- Профиль `Any`, направление только `Outbound`: входящий трафик станции не нужен.
- Снятие правил — только `-Remove` явным флагом (AR-204); повторное применение идемпотентно (AR-301).
- Расширение состава — через новый ADR (`GATE_IMMUTABLE` не затрагивается, но состав правил декларативен).
