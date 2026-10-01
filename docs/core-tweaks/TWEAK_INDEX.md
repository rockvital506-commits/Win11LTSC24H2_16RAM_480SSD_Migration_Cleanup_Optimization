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

## 4. Временные (транзитные) состояния

| Элемент | Управление | Паттерн | Примечание |
|---|---|---|---|
| PnP-щит (`DenyDeviceIDs`, `DisableCoInstallers`) | `tweaks/apply/Invoke-PnpShield.ps1` | `PAT-15` | активен только на время импорта INF; снимается в `finally` |

## 5. Запланированные твики

| ID | Имя | Этап | Паттерн |
|---|---|---|---|
| — | ACL Freeze (Owner=SYSTEM) | 2, 4 | `PAT-10` |
| — | NTFS Deny SYSTEM (цементирование) | 6 | `PAT-11`, `PAT-NEW-2` |
| — | Task Scheduler Unregister + ACL | 4, 6 | `PAT-04` |
| — | WMI Event Consumer Removal + ACL | 4 | `PAT-05` |
| — | GPO/LGPO-импорт | 6 | `PAT-06` |
| — | Hosts + DoH=0 | 6 | `PAT-08` |
| — | Firewall outbound rule | 6 | `PAT-09` |

## 6. Верификация

Состояние всех твиков проверяется единой точкой: `pwsh -File ./tweaks/apply/Assert-TweakState.ps1 -ExportReport ./docs/artifacts/Stage4_tweakstate.md`.
