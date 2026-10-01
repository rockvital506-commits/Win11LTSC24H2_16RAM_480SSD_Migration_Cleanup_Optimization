# PAT-11 — NTFS Deny SYSTEM — цементирование конфигурации

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-11 |
| `NAME` | NTFS Deny SYSTEM — цементирование конфигурации |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0003`, `ADR-0015`, `tweaks/acl/AclManifest.json`, `tweaks/apply/Apply-AclManifest.ps1` |

---

## Контекст

Реаниматоры Windows (`WaaSMedicSvc`, `UsoSvc`, обслуживание обновлений) работают от SYSTEM и способны вернуть конфигурационные объекты к исходному виду: перезаписать политики, `hosts`, обновить задачи. Твики этапов 2–4 обратимы для SYSTEM.

## Решение

Запрет записи для SYSTEM через явное правило DENY (`W`) на объявленных объектах — **после** того, как все записи выполнены (транзакция grant → работа → deny):

```
icacls "C:\Windows\System32\GroupPolicy" /deny "SYSTEM:(W)"
icacls "C:\Windows\System32\drivers\etc\hosts" /deny "SYSTEM:(W)"
```

Ключевые свойства:

- DENY имеет абсолютный приоритет в `ntfs.sys` и перекрывает членство SYSTEM в Administrators;
- права WRITE_DAC и владение сохраняются → откат возможен;
- предохранитель `Assert-NotSelfLocking` (AR-506) запрещает применять аналогичные правила к Administrators/текущему пользователю;
- SDDL каждого объекта выгружается в бэкап до изменения (AR-502).

## Реализация

| Артефакт | Путь |
|---|---|
| Апплейер (репозиторий) | `tweaks/apply/Apply-AclManifest.ps1` |
| Ядро (рантайм) | `templates/ImmunityCore.ps1.template` |
| Декларация | `tweaks/acl/AclManifest.json` (`ACL-001`, `ACL-002`, `mode: grant-then-deny`) |

## Проверка

| ID | Критерий |
|---|---|
| `GACL-001` | DENY Write для SYSTEM на `GroupPolicy` |
| `GACL-002` | DENY Write для SYSTEM на `hosts` |
| `GACL-003` | администратор сохраняет возможность смены ACL (`Get-Acl` без ошибки) |
| `GACL-004` | повторный прогон изменений не вносит |

## Замечания

- Замок защищает целиком — включая политики, которые система могла бы добавить позже; для управляемой офлайн-станции это целевое поведение.
- Ошибки доступа в журналах служб — не дефект, а ожидаемый рапорт о блокировке.
