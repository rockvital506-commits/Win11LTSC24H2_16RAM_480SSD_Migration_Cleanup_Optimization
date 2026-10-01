# PAT-06 — GPO/LGPO-импорт (эталонный слепок политик)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-06 |
| `NAME` | GPO/LGPO-импорт (эталонный слепок политик) |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0003`, `ADR-0015`, `tweaks/acl/AclManifest.json`, `templates/ImmunityCore.ps1.template`, `tools/runtime/README.md` |

---

## Контекст

Политики локальной группы (LGP) применяются ядром из `C:\Windows\System32\GroupPolicy`. По умолчанию система свободно перезаписывает этот каталог, а инструмент `secedit`/GUI не даёт воспроизводимого слепка. Нужен перенос эталонного набора политик на хост без сети и без домена.

## Решение

Политики формируются один раз в изолированной среде и переносятся утилитой **LGPO.exe** (Microsoft Security Compliance Toolkit):

```cmd
LGPO.exe /b D:\GD_Tool\            :: создать слепок (GUID-каталог с {GUID}\Machine\registry.pol, GptTmpl.inf, gpt.ini)
LGPO.exe /g D:\GD_Tool\CleanLTSCPolicy  :: импорт слепка на хосте-цели
```

Порядок и правила:

- переименование GUID-каталога в `CleanLTSCPolicy` — косметическая операция: LGPO читает содержимое, а не имя;
- импорт выполняется **внутри окна grant** ACL-транзакции: SYSTEM должен иметь полный доступ к `GroupPolicy`;
- после импорта — `gpupdate /force` (фиксация в ядре), затем замок `deny` (PAT-11);
- без `LGPO.exe` шаг пропускается с `WARN`, контур не разрушается (мягкая деградация).

## Реализация

| Артефакт | Путь |
|---|---|
| Ядро транзакции | `templates/ImmunityCore.ps1.template` (шаги 1–5) |
| Декларация объекта | `tweaks/acl/AclManifest.json` (`ACL-001`) |
| Инструкция развёртывания | `tools/runtime/README.md` |

## Проверка

| ID | Критерий |
|---|---|
| `P0.3` | `LGPO.exe` присутствует (`WARN`, если нет) |
| `P0.4` | `CleanLTSCPolicy\gpt.ini` присутствует |
| `L1` | `gpt.ini` под защищённым `GroupPolicy` доступен на чтение |

## Замечания

- `LGPO.exe` в Git не хранится (AR-804): носитель `F:\TOOLS\GPO\`.
- Импорт политик = массовая запись в `GroupPolicy`; выполняется до постановки замка, иначе `Access Denied`.
