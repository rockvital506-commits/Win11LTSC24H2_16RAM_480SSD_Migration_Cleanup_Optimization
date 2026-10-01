# tools/runtime/ — Рантайм контура самозащиты (`D:\GD_Tool`)

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | TOOLS-RUNTIME |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `RELATED` | `ADR-0015`, `PAT-NEW-3`, `PAT-NEW-4`, `scripts/Stage6_Immunity_Prepare.ps1`, `tweaks/tasks/TaskManifest.json` |

Бинарники в Git не хранятся (AR-804). Этот каталог описывает **развёртывание рантайма** на хост — файлы-исходники лежат
в репозитории, рабочие копии — на разделе `D:` (Data, NTFS, ADR-0007/ADR-0011, строка 4).

## 1. Целевое расположение

```
D:\GD_Tool\
├── ImmunityCore.ps1      ← templates/ImmunityCore.ps1.template (UTF-8 BOM, CRLF)
├── AutoSetup.bat         ← scripts/Stage6_AutoSetup.bat      (ASCII, CRLF)
├── Launcher.vbs          ← scripts/Stage6_Launcher.vbs       (ASCII, CRLF)
├── LGPO.exe              ← F:\TOOLS\GPO\ (поставка владельца, AR-804)
├── CleanLTSCPolicy\      ← слепок LGPO (/b + переименование GUID-каталога)
└── logs\
    ├── AutoSetup.log     ← журнал оркестратора (ASCII)
    └── ImmunityCore.log  ← журнал транзакции (UTF-8)
```

## 2. Развёртывание

Автоматически (рекомендуется), из корня репозитория в профиле `devops`, при отключённой сети:

```powershell
pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -Audit      # план, без изменений
pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1              # развёртывание + задача + верификация
```

Оркестратор копирует файлы, сверяет SHA256 (PAT-20) и регистрирует задачу `System_Immunity_Core` (PAT-NEW-4).

Вручную (если автоматизация недоступна): скопировать три файла из таблицы выше, затем

```cmd
rem слепок политик (один раз, из изолированной среды)
LGPO.exe /b D:\GD_Tool\
ren D:\GD_Tool\{XXXXXXXX-XXXX-...} CleanLTSCPolicy
```

## 3. Эксплуатация

| Действие | Команда |
|---|---|
| Ручной запуск транзакции | Планировщик → `System_Immunity_Core` → «Выполнить» |
| Прямой запуск ядра | `powershell -File D:\GD_Tool\ImmunityCore.ps1` |
| Пробный прогон (без изменений) | `powershell -File D:\GD_Tool\ImmunityCore.ps1 -Audit` |
| Верификация контура | `pwsh -File ./tweaks/apply/Assert-ImmunityState.ps1 -ExportReport ./docs/artifacts/Stage6_immunity.md` |
| Снятие замков (откат) | `pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Phase Grant` |

## 4. Правила

- Файлы рантайма — производные: правка разрешена **только в репозитории** с повторным развёртыванием;
  расхождение ловится проверкой SHA256 (`P2.*`).
- Ядро никогда не поднимает и не опускает сетевой интерфейс (AR-709).
- Удаление файлов запрещено (AR-201): ротация журналов — только усечение/переименование с явного одобрения владельца.
- `LGPO.exe` и слепок политик — поставка владельца; их отсутствие не блокирует счёт, а даёт `WARN` (мягкая деградация, AR-306).
