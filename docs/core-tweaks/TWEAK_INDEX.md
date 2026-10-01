# TWEAK_INDEX.md — Реестр твиков

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | TWEAK-000 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |

Каждый твик декларируется манифестом (`tweaks/`), имеет ID `TWK-NNN` и ссылку на паттерн (AR-503).

## 1. Твики реестра (`tweaks/registry/RegistryManifest.json`)

| ID | Имя | Ветка | Значение | Паттерн | Статус |
|---|---|---|---|---|---|
| `TWK-001` | LSA Protection off | `Control\Lsa` | `LsaCfgFlags = 0` | `PAT-12` | DONE (Stage 4) |
| `TWK-002` | VBS off | `Control\DeviceGuard` | `EnableVirtualizationBasedSecurity = 0` | `PAT-12` | DONE (Stage 4) |
| `TWK-003` | HVCI off | `DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` | `Enabled = 0` | `PAT-12` | DONE (Stage 4) |
| `TWK-004` | DriverSearching off (re-assert) | `DriverSearching` | `SearchOrderConfig = 0` | `PAT-15` | DONE (Stage 4) |
| `TWK-005` | DiagTrack disabled (re-assert) | `Services\DiagTrack` | `Start = 4` | `PAT-03` | DONE (Stage 4) |
| `TWK-006` | DNS over HTTPS запрещён | `SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` | `DoHPolicy = 1` | `PAT-08` | DONE (Stage 6, декларация) |

## 2. Флаги загрузчика (`tweaks/bcd/BcdManifest.json`)

| ID | Настройка | Значение | Паттерн | Статус |
|---|---|---|---|---|
| `BCD-001` | `loadoptions` | `DISABLE-LSA-ISOLATION,DISABLE-VBS` | `PAT-12` | DONE (Stage 4, AR-505) |

## 3. Службы (`tweaks/services/ServiceGate.json`)

| Служба | Целевой «Start» | Паттерн | Примечание |
|---|---|---|---|
| `WaaSMedicSvc` | 4 | `PAT-03` | реаниматор; окончательно цементируется на Stage 6 |
| `UsoSvc` | 4 | `PAT-03` | оркестратор обновлений |
| `DiagTrack` | 4 | `PAT-03` | телеметрия |
| `WSearch` | 4 | `PAT-03` | индекс поиска (SC_SSD_LONGEVITY) |
| `edgeupdate`, `edgeupdatem` | 4 | `PAT-03` | автообновление Edge |

## 4. Задачи планировщика (`tweaks/tasks/TaskManifest.json`)

| ID | Задача | Действие | Паттерн | Статус |
|---|---|---|---|---|
| `TASK-001` | `System_Immunity_Core` | регистрация: boot + unlock, принципал `SYSTEM`, действие `wscript.exe D:\GD_Tool\Launcher.vbs` | `PAT-NEW-4` | DONE (Stage 6, декларация) |
| `TASK-101` | `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | `Disable` (+ опция DENY на XML) | `PAT-04` | DONE (Stage 6, декларация) |
| `TASK-102` | `\…\Customer Experience Improvement Program\Consolidator` | `Disable` | `PAT-04` | DONE |
| `TASK-103` | `\…\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | `Disable` | `PAT-04` | DONE |
| `TASK-104` | `\…\Autochk\Proxy` | `Disable` | `PAT-04` | DONE |
| `TASK-105` | `\…\Windows Error Reporting\QueueReporting` | `Disable` | `PAT-04` | DONE |
| `TASK-106` | `\…\Feedback\Siuf\DmClient` | `Disable` | `PAT-04` | DONE |

Удаление задач (`-Unregister`) не автоматизируется: только явный флаг (AR-204); XML выгружается в бэкап (AR-304).

## 5. Объекты ACL (`tweaks/acl/AclManifest.json`)

| ID | Объект | Правило | Паттерн | Статус |
|---|---|---|---|---|
| `ACL-001` | `%SystemRoot%\System32\GroupPolicy` | `SYSTEM:(F)` (окно) → `SYSTEM:(W)` Deny | `PAT-11`, `PAT-NEW-2` | DONE (Stage 6, декларация) |
| `ACL-002` | `%SystemRoot%\System32\drivers\etc\hosts` | `SYSTEM:(F)` (окно) → `SYSTEM:(W)` Deny | `PAT-11`, `PAT-08` | DONE (Stage 6, декларация) |

Обзорная матрица: `docs/core-tweaks/ACL_MATRIX.md`. Предохранитель самоблокировки — `Guard.psm1` (AR-506).

## 6. Правила брандмауэра (`tweaks/firewall/FirewallManifest.json`)

| ID | Правило | Программа | Действие | Паттерн | Статус |
|---|---|---|---|---|---|
| `FW-001` | `Block Telemetry Core` | `%SystemRoot%\System32\CompatTelRunner.exe` | Outbound → Block | `PAT-09` | DONE (Stage 6, декларация) |
| `FW-002` | `Block WaaSMedic Outbound Agent` | `%SystemRoot%\System32\WaaSMedicAgent.exe` | Outbound → Block | `PAT-09` | DONE (Stage 6, декларация) |

Применение: `tweaks/apply/Apply-FirewallManifest.ps1` (`SCRIPT-FW-001`); тот же состав разворачивается в
`D:\GD_Tool\FirewallRules.json` для рантайма. Снятие — только `-Remove` (AR-204).

## 7. Временные (транзитные) состояния

| Элемент | Управление | Паттерн | Примечание |
|---|---|---|---|
| PnP-щит (`DenyDeviceIDs`, `DisableCoInstallers`) | `tweaks/apply/Invoke-PnpShield.ps1` | `PAT-15` | активен только на время импорта INF; снимается в `finally` |
| ACL-транзакция `grant` | `Apply-AclManifest.ps1 -Phase Grant` | `PAT-NEW-2` | окно импорта политик; завершается фазой `Deny` |

## 8. Запланированные твики

| ID | Имя | Этап | Паттерн |
|---|---|---|---|
| — | ACL Freeze (Owner=SYSTEM) — пересмотреть после стенда | 6 | `PAT-10` |
| — | WMI Event Consumer Removal + ACL | 4 | `PAT-05` |

## 9. Верификация

| Контур | Точка входа | Отчёт |
|---|---|---|
| Твики этапов 2–6 (реестр, BCD, службы, AppX) | `pwsh -File ./tweaks/apply/Assert-TweakState.ps1 -ExportReport ./docs/artifacts/Stage4_tweakstate.md` | `Stage4_tweakstate.md` |
| Контур самозащиты (ACL, задачи, брандмауэр, DoH, Defender, рантайм, активация) | `pwsh -File ./tweaks/apply/Assert-ImmunityState.ps1 -ExportReport ./docs/artifacts/Stage6_immunity.md` | `Stage6_immunity.md` |
