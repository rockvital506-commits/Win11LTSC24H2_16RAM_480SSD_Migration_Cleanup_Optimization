# tests/ — Тесты и валидаторы

| Файл | Назначение | Правила |
|---|---|---|
| `RepoConventions.Tests.ps1` | Pester-набор проверки конвенций (обёртка над `scripts/rules/Test-RepositoryConventions.ps1`) | AR-902 |
| `fixtures/` | Тестовые данные | — |

**Плановые наборы:** `Tweaks.Tests.ps1` (идемпотентность, отказ при предусловиях, отсутствие записи вне allow-list), `Packages.Tests.ps1` (lock-файл, фиксация версий).

Запуск: `Invoke-Pester ./tests` (Pester 5.x).
