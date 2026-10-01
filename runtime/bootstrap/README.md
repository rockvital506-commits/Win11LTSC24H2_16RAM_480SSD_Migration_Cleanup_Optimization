# runtime/bootstrap/ — Развёртывание и верификация рабочей среды

| Скрипт | Script-ID | Назначение |
|---|---|---|
| `Deploy-Runtime.ps1` | `SCRIPT-RUNTIME-001` | Идемпотентное развёртывание каталогов и маркера; права — по флагу `-ApplyAcl` |
| `Assert-RuntimeState.ps1` | `SCRIPT-RUNTIME-002` | Верификация только на чтение: состав, маркер, дрейф, права, объём |

Оркестрация этапа — `scripts/Stage8_Runtime_Deploy.ps1`. Отчёты: `docs/artifacts/Stage8_preflight.md`,
`docs/artifacts/Stage8_runtime.md`. Сеть скрипты не поднимают (AR-709), записи — только в `C:\Vitality\` (AR-206).
