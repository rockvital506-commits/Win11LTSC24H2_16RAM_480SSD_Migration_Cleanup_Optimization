# algorithm/auto/ — Автоматизированные шаги

Шаги, выполняемые скриптами (оркестрация — `scripts/`, доменные модули — `tweaks/`, `packages/`, `devops/`).

| Документ | Этап | Скрипт | Содержание | Статус |
|---|---|---|---|---|
| `Stage1_DiskGenius_Partition.md` | 1 | `Stage1_DiskGenius_Partition.ps1` | Ручная разметка в DiskGenius + read-only верификация схемы (V1–V7) | DONE |
| `Stage2_Audit_Mode_Workflow.md` | 2 | (файл ответов; скрипт — не требуется) | Проверки A1–A7, валидация unattend в ВМ | DONE |
| `Stage4_Audit_Final_Clean.md` | 4 | `Stage4_Audit_Final_Clean.ps1` | Драйверы (PnP-щит), твики реестра/служб/AppX, VBS/HVCI/LSA, hiberfil, pagefile, WinSxS | DONE |
| `Stage5_Sysprep_Seal.md` | 5 | `Stage5_Sysprep_Prepare.ps1` | Второй файл ответов, CopyProfile, ловушка `0x80073cf2`, `sysprep /generalize` | DONE |
| `Stage6_AutoSetup.md` | 6 | `Stage6_AutoSetup.bat`, `Stage6_Launcher.vbs` | LGPO-слепок, брандмауэр, NTFS Deny SYSTEM | DONE |
| `Stage7_WSL_Docker_VMware.md` | 7 | `Stage7_WSL_Docker_VMware.ps1` | WSL2 + Docker Engine + VMware (WHP), P+E-политика | DONE |
| `Stage8_Runtime_Deploy.md` | 8 | `Stage8_Runtime_Deploy.ps1` | Рабочая среда `C:\Vitality\`: манифест, маркер, права, верификация (ADR-0017) | DONE |

**Правила:** AR-408 (нет документации — нет коммита), AR-501 (доменные операции только через манифесты), AR-307 (обязательный verification-блок).
