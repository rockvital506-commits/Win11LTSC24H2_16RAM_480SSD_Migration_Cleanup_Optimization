# tasks — Задачи планировщика

`TaskManifest.json` — два блока: `register` (наши задачи) и `retire` (реаниматоры: `Disable`, опционально DENY на XML). Паттерны PAT-04 и PAT-NEW-4.

| ID | Задача | Действие |
|---|---|---|
| `TASK-001` | `System_Immunity_Core` | регистрация: boot + unlock, принципал `SYSTEM`, `wscript.exe D:\GD_Tool\Launcher.vbs` |
| `TASK-101`…`TASK-106` | телеметрические задачи планировщика | `Disable` (+ `denyWriteToSystem`); `Unregister` — только явным флагом (AR-204) |

Применение: `tweaks/apply/Apply-TaskManifest.ps1`; состояние — `tweaks/apply/Assert-ImmunityState.ps1` (`TASK-001.*`, `TR101…TR106`).
