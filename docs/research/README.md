# docs/research/ — Исследовательские материалы

Содержит стенограммы и исследования, на которых построен проект. Материалы **не редактируются** — это исторический слой (append-only).

| Файл | Происхождение | Содержание |
|---|---|---|
| `anchor1.md` | Якорь1 | Исходная архитектура, хронологический план 7 этапов, обоснования решений |
| `step1.md` | Шаг 1 | Ventoy-контур, первый файл ответов `u_w11_ltsc_iot.xml` (UTF-8 **без BOM**) |
| `step2.md` | Шаг 2 | Audit Mode, накат накопительных обновлений |
| `step3.md` | Шаг 3 | `Audit_Final_Clean.ps1`: драйверы, VBS/HVCI, hyberfil, pagefile, WinSxS |
| `step4.md` | Шаг 4 | `unattend.xml`, CopyProfile, `sysprep /generalize` |
| `step5.md` | Шаг 5 | `AutoSetup.bat`, `Launcher.vbs`, NTFS Deny SYSTEM, Ohook (что уже выполнено на хосте) |

**Примечание:** каталог `research1/` перенесён сюда как `docs/research/*.md` (решение ADR-0008, 2026-10-01). Содержимое сохранено байт-в-байт, история Git сохранена (rename).
