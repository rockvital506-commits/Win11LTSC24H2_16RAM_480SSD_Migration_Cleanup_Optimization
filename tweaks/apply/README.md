# apply — Скрипты применения твиков

| Script-ID | Файл | Назначение |
|---|---|---|
| `SCRIPT-REG-001` | `Apply-Tweaks.ps1` | Применение реестровых твиков и BCD из манифестов |
| `SCRIPT-PNP-001` | `Invoke-PnpShield.ps1` | Временный PnP-щит на время импорта INF (PAT-15) |
| `SCRIPT-ACL-001` | `Apply-AclManifest.ps1` | NTFS-замки по `tweaks/acl/AclManifest.json` (`-Phase Both\|Grant\|Deny`, PAT-11) |
| `SCRIPT-TASK-001` | `Apply-TaskManifest.ps1` | Регистрация `System_Immunity_Core` и вывод реаниматоров (PAT-04, PAT-NEW-4) |
| `SCRIPT-DEF-001` | `Invoke-DefenderAllowList.ps1` | Доверенная зона Defender (`-Remove` — откат, ADR-0015) |
| `SCRIPT-FW-001` | `Apply-FirewallManifest.ps1` | Исходящие правила брандмауэра по манифесту (`-Remove` — откат, PAT-09) |
| `SCRIPT-IMM-001` | `Assert-ImmunityState.ps1` | Сквозная верификация контура (только чтение) |
| — | `Assert-TweakState.ps1` | Верификация состояния твиков (M1/B1/V1/S-*/X0/X1) |

Обязательно: `-Audit`/`-WhatIf` по умолчанию (AR-302), идемпотентность (AR-301), бэкап-перед-изменением (AR-304), verification-блок (AR-307).
Деструктивные операции (`-Unregister`, `-Remove`) — только по явному флагу (AR-204).
