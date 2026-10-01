# tweaks/ — Домен 1: твики ядра ОС и реестра

Декларативные манифесты + применение. Основание: AR-501 (никаких ad-hoc `reg add` в stage-скриптах).

## Состав

| Каталог | Содержимое | Формат |
|---|---|---|
| `registry/` | Твики реестра | `*.json` (манифест), эталонные экспорты `*.reg` |
| `bcd/` | Твики загрузчика | `*.json` + обязательный `bcdedit /export` (AR-505) |
| `services/` | Типы запуска служб и ACL | `ServiceGate.json` |
| `tasks/` | Задачи планировщика | `TaskManifest.json` |
| `acl/` | Владелец и NTFS Deny SYSTEM | `AclManifest.json` |
| `firewall/` | Исходящие правила брандмауэра | `FirewallManifest.json` |
| `appx/` | Список UWP/AppX к вырезанию | `AppxRemoval.json` |
| `apply/` | Скрипты применения | `Apply-Tweaks.ps1`, `Apply-AclManifest.ps1`, `Apply-TaskManifest.ps1`, `Invoke-DefenderAllowList.ps1`, `Assert-TweakState.ps1`, `Assert-ImmunityState.ps1` |

## Обязательные свойства скриптов применения

- `-Audit` / `-WhatIf` по умолчанию (AR-302), идемпотентность (AR-301), бэкап-перед-изменением (AR-304).
- ACL-операции — только через `scripts/common/Guard.psm1` (AR-506), с сохранением SDDL.
- Каждый твик: ID `TWK-NNN` + запись в `docs/core-tweaks/TWEAK_INDEX.md` + ссылка на паттерн (AR-503).
- Запрещено ослаблять §2.3 README (AR-504, `GATE_IMMUTABLE`).

**Маппинг паттернов:** PAT-03 (SCM + Deny WriteKey), PAT-04 (Task Scheduler), PAT-06 (LGPO-слепок), PAT-08 (hosts + DoH), PAT-09 (firewall), PAT-10 (ACL Freeze), PAT-11 (NTFS Deny SYSTEM), PAT-12 (BCD), PAT-13 (PageFile), PAT-14 (hiberfil), PAT-15 (PnP Shield), PAT-NEW-4 (задача контура).
