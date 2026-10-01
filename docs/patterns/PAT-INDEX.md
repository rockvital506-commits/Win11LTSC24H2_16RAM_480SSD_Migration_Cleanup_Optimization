# PAT-INDEX.md — Реестр паттернов

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | PAT-000 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SOURCE` | README §3.4 |
| `STATUS` | ACTIVE |

Статусы: **DONE** — документ создан; **PLAN** — запланирован к созданию на соответствующем этапе.

## 1. Паттерны реализации

| PAT | Имя | Этап | Статус (README) | Документ | Связано |
|---|---|---|---|---|---|
| `PAT-01` | IFEO Debugger → NoOp-stub | 2 | ✅ | PLAN | `tweaks/tasks`, ADR-0008 |
| `PAT-02` | IFEO Debugger → Wrapper-Decorator | 2 | ✅ | PLAN | `tweaks/tasks` |
| `PAT-03` | SCM Disabled + ACL Deny WriteKey | 4 | ✅ | PLAN | `tweaks/services` |
| `PAT-04` | Task Scheduler Unregister + ACL | 4 | ✅ | PLAN | `tweaks/tasks` |
| `PAT-05` | WMI Event Consumer Removal + ACL | 4 | ✅ | PLAN | `tweaks/services` |
| `PAT-06` | GPO/LGPO-импорт | 6 | ✅ | PLAN | ADR-0003, `tweaks/acl` |
| `PAT-07` | VMware via WHP API | 7 | ✅ | PLAN | ADR-0002, `devops/hypervisor` |
| `PAT-08` | Hosts + DoH=0 | 6 | ✅ | PLAN | ADR-0003 |
| `PAT-09` | Firewall outbound rule | 6 | ✅ | PLAN | Stage 6 AutoSetup |
| `PAT-10` | ACL Freeze (Owner=SYSTEM) | 2, 4 | ✅ | PLAN | `tweaks/acl` |
| `PAT-11` | NTFS Deny SYSTEM (цементирование) | 6 | ✅ | PLAN | ADR-0003, `tweaks/acl` |
| `PAT-12` | bcdedit Disable VBS/HVCI/LSA Isolation | 4 | ✅ | PLAN | AR-505, `tweaks/bcd` |
| `PAT-13` | Fixed PageFile (InitialSize=MaximumSize) | 4 | ✅ | PLAN | `tweaks/registry` |
| `PAT-14` | hiberfil.sys elimination | 4 | ✅ | PLAN | SC_SSD_LONGEVITY |
| `PAT-15` | Temporary PnP Shield (DisableCoInstallers) | 4 | ✅ | PLAN | `tweaks/registry` |
| `PAT-16` | Dual-Stage Unattend (Ventoy + Sysprep) | 2, 5 | ✅ | PLAN | ADR-0005, `templates/` |
| `PAT-17` | Ohook Permanent Activation | 6 | ✅ | PLAN | ADR-0004, `tools/ohook` |
| `PAT-18` | Audit_Final_Clean.ps1 | 4 | ✅ | PLAN | `scripts/Stage4_*` |
| `PAT-19` | Atomic Stage + Restore-FromBackup | All | ✅ | PLAN | AR-308, `scripts/common/Backup.psm1` |
| `PAT-20` | Hash-First Verification | All | ✅ | PLAN | AR-304, `packages/hashes` |
| `PAT-21` | WSL2 Isolated Memory (.wslconfig) | 7 | ✅ | PLAN | AR-703, `devops/wsl` |
| `PAT-22` | VMware Isolated Cache (mainMem.useNamedFile=FALSE) | 7 | ✅ | PLAN | AR-708, `devops/hypervisor` |
| `PAT-NEW-1` | Audit Mode Workflow | 2, 5 | ✅ | PLAN | ADR-0005 |
| `PAT-NEW-2` | NTFS Deny SYSTEM (icacls) | 6 | ✅ | PLAN | AR-506, `scripts/common/Guard.psm1` |
| `PAT-NEW-3` | AutoSetup.bat as Runtime-Initializer | 6 | ✅ | PLAN | `scripts/Stage6_AutoSetup.bat` |
| `PAT-NEW-4` | System_Immunity_Core Scheduled Task | 6 | ✅ | PLAN | `tweaks/tasks` |
| `PAT-NEW-5` | Ohook Activation (sppc.dll replace) | 6 | ✅ | PLAN | ADR-0004 |
| `PAT-NEW-6` | 1 MiB Partition Alignment (NVMe SSD) | 1 | ✅ | **DONE** | ADR-0007, `Stage1_DiskGenius_Partition.ps1` |
| `PAT-NEW-7` | Partition Scheme Documentation | 1 | ✅ | **DONE** | ADR-0007, `docs/storage/*` |

## 2. Запрещённые механики

Требуют подписанных драйверов и не применяются (SC_ZERO_BSOD_RISK, `NC_DRIVER_SIGNED`):

- minifilter driver;
- registry callback driver;
- WFP callout driver.

## 3. Метрика

`M_PATTERN_COVERAGE` (§3.5 README) — целевое значение **28/28**; на Stage 1 документировано 2 паттерна (индекс ведётся непрерывно).
