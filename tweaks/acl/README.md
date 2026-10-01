# acl — Права доступа (Owner / Deny)

`AclManifest.json` — матрица: объект, owner, deny/allow, паттерн. Паттерны PAT-10 (ACL Freeze) и PAT-11 (NTFS Deny SYSTEM).
Операции — только через `scripts/common/Guard.psm1` (AR-506).

| ID | Объект | Режим | Паттерн |
|---|---|---|---|
| `ACL-001` | `%SystemRoot%\System32\GroupPolicy` | `grant` → `deny SYSTEM:(W)` | `PAT-06`, `PAT-11`, `PAT-NEW-2` |
| `ACL-002` | `%SystemRoot%\System32\drivers\etc\hosts` | `grant` → `deny SYSTEM:(W)` | `PAT-08`, `PAT-11` |

Применение: `tweaks/apply/Apply-AclManifest.ps1` (репозиторий) и `templates/ImmunityCore.ps1.template` (рантайм).
Обзорная матрица с бэкапом, проверками и откатом — `docs/core-tweaks/ACL_MATRIX.md`.
