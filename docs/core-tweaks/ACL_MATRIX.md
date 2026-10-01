# ACL_MATRIX.md — Матрица прав доступа

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ACL-000 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | `ADR-0003`, `ADR-0015`, `PAT-10`, `PAT-11`, `PAT-NEW-2`, `tweaks/acl/AclManifest.json`, `tweaks/apply/Apply-AclManifest.ps1` |

Единая точка обзора: какие объекты получают правила доступа, чем объявлены, чем применяются и чем проверяются.
Декларации — в манифестах (AR-501); изменение состава — только через ADR и `GATE_IMMUTABLE`.

## 1. Действующие правила

| ID | Объект | Принципал | Право | Тип | Этап | Декларация | Применение | Проверка |
|---|---|---|---|---|---|---|---|---|
| `ACL-001` | `%SystemRoot%\System32\GroupPolicy` (каталог) | `SYSTEM (S-1-5-18)` | `(F)` → `(W)` | Allow → Deny | 6 | `tweaks/acl/AclManifest.json` | `Apply-AclManifest.ps1` / `ImmunityCore.ps1` | `ACL-001.1/.2`, `GACL-001` |
| `ACL-002` | `%SystemRoot%\System32\drivers\etc\hosts` (файл) | `SYSTEM (S-1-5-18)` | `(F)` → `(W)` | Allow → Deny | 6 | там же | там же | `ACL-002.1/.2`, `GACL-002` |

Режим обоих правил — `grant-then-deny` (транзакция): `(F)` выдаётся на время записи, `(W)` ставится после.
Права `WRITE_DAC` и владение не отбираются — администратор сохраняет возможность отката (ADR-0003).

## 2. Обязательная обвязка

| Требование | Правило | Реализация |
|---|---|---|
| Бэкап состояния до изменения | AR-502 | SDDL → `backups/<UTC>_stage6/<ID>_sddl.txt` |
| Предохранитель самоблокировки | AR-506 | `Guard.psm1` → `Assert-NotSelfLocking` |
| Разрешённые корни | AR-506 | `Guard.psm1` → `Assert-PathAllowed` (`GroupPolicy`, `Tasks`, `hosts`) |
| Идемпотентность | AR-303 | проверка текущего состояния до применения |
| Подтверждение результата | AR-307 | повторное чтение ACL после `icacls` |

## 3. Планируемые правила

| Объект | Принципал | Право | Этап | Паттерн | Статус |
|---|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Services\<Service>` (ключ службы-реаниматора) | `SYSTEM` | Deny `SetValue`/`WriteKey` | 6 | `PAT-10` (Freeze) | PLAN — не требуется при действующем `ACL-001`; пересмотреть после стенда |
| XML-файлы отключённых задач (`%SystemRoot%\System32\Tasks\…`) | `SYSTEM` | Deny `(W)` | 6 | `PAT-04`, `PAT-11` | опция `-ApplyTaskAcl` (применяется владельцем) |
| Ветки реестра политик, защищённые от перезаписи | — | — | — | — | **не применяются**: реестр защищается политиками LGPO, а не ACL (ADR-0003, «Альтернативы») |

## 4. Ручные операции владельца

| Операция | Команда |
|---|---|
| Снять замки перед обслуживанием | `pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Phase Grant` |
| Поставить замки обратно | `pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Phase Deny` |
| Пробный прогон | `pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Audit` |
| Восстановить SDDL из бэкапа | `Set-Acl -Path <объект> -AclObject (Get-Acl <файл_бэкапа>)` (требует ручного подтверждения) |
