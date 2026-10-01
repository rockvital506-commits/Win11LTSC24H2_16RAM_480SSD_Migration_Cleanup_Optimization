# scripts/ — Слой оркестрации

Здесь размещаются скрипты, которые инженер запускает на этапах (`Stage<N>_<PURPOSE>.<ext>`). Предметная логика (реестр, ACL, winget, WSL) живёт в доменах `tweaks/`, `packages/`, `devops/` — правило AR-501.

| Элемент | Назначение |
|---|---|
| `Stage1_DiskGenius_Partition.ps1` … `Stage7_WSL_Docker_VMware.ps1` | Оркестрация этапов (см. §5.6 README) |
| `Stage4_Audit_Final_Clean.ps1`, `Stage5_Sysprep_Prepare.ps1` | Оркестрация санитарии и запечатывания (Stage 4–5); предпролётные проверки и верификация |
| `Stage6_AutoSetup.bat`, `Stage6_Launcher.vbs` | Контур самозащиты Stage 6 (ASCII-only, AR-105) |
| `common/` | Общие модули: логирование, бэкап, верификация, guard (без предметной логики) |
| `rules/` | `Test-RepositoryConventions.ps1` — исполняемые правила репозитория |

**Требования:** AR-401…AR-409 (PowerShell 5.1, шапка скрипта, идемпотентность, `-Audit`/`-WhatIf`), AR-408 (у каждого скрипта есть документ в `algorithm/` и строка в §5.6 README).
