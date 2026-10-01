# scripts/rules/ — Исполняемые правила

| Скрипт | Назначение | Правила |
|---|---|---|
| `Test-RepositoryConventions.ps1` | Проверка конвенций репозитория перед коммитом | AR-101, AR-102, AR-103, AR-105, AR-106, AR-207, STRUC_003…STRUC_010 |

**Использование:**

```powershell
pwsh -File ./scripts/rules/Test-RepositoryConventions.ps1
# или
powershell.exe -ExecutionPolicy Bypass -File .\scripts\rules\Test-RepositoryConventions.ps1
```

**Коды возврата:** `0` — PASS, `10` — обнаружены нарушения (AR-306). Коммит при `FAIL` запрещён (AR-903).
