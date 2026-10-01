# PAT-NEW-2 — NTFS Deny SYSTEM через icacls (механика уровня CLI)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-NEW-2 |
| `NAME` | NTFS Deny SYSTEM через icacls (механика уровня CLI) |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0003`, `PAT-11`, `tweaks/apply/Apply-AclManifest.ps1`, `scripts/common/Guard.psm1` |

---

## Контекст

PAT-11 описывает *что* защищается; PAT-NEW-2 — *как*: примитив, доступный на любом хосте без PowerShell-модулей (нужен и в `.bat`-рантайме), с воспроизводимым поведением на `ntfs.sys`.

## Решение

`icacls.exe` как единственный исполнитель изменения прав (тот же бинарь доступен внутри `ImmunityCore.ps1`), с обвязкой:

```powershell
& icacls.exe $Path /grant 'SYSTEM:(F)'   # фаза Grant: окно импорта
& icacls.exe $Path /deny  'SYSTEM:(W)'   # фаза Deny: цементирование
```

Обвязка в PowerShell: проверка существования объекта → проверка уже-применённого состояния (идемпотентность, AR-303) → `Assert-PathAllowed` (Guard, AR-506) → вызов → контроль `$LASTEXITCODE` → повторное чтение ACL для подтверждения.

## Реализация

| Артефакт | Путь |
|---|---|
| Модуль-апплейер | `tweaks/apply/Apply-AclManifest.ps1` (`Set-EntryAcl`) |
| Рантайм | `templates/ImmunityCore.ps1.template` (`Set-SystemAccess`, `Test-DenyWriteForSystem`) |

## Проверка

| ID | Критерий |
|---|---|
| `ACL-00x.1` | grant: `SYSTEM:(F)` присутствует |
| `ACL-00x.2` | deny: `SYSTEM:(W)` присутствует и подтверждён чтением ACL |
| `EX1` | код возврата `icacls` ≠ 0 → FAIL, объект не считается защищённым |

## Замечания

- Использование `icacls` (а не `Set-Acl` с SDDL) выбрано ради прозрачности и совпадения с документацией Microsoft; SDDL-бэкап выгружается отдельно.
- Детекция deny кириллическими/локализованными представлениями прав не используется — проверяются флаги объекта `FileSystemAccessRule`.
