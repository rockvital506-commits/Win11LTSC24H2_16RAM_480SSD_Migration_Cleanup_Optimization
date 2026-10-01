# runtime/ — Домен 4: рабочая среда исполнения (`C:\Vitality\`)

Основание: `ADR-0017`, README §1.3 (`WORKSPACE_ROOT`), AR-206, AR-301, AR-804.

Домен разворачивает каталог рабочей среды на уже иммунизированной станции. Он не занимается ни твиками
(`tweaks/`), ни установкой ПО (`packages/`), ни DevOps-контуром (`devops/`) — только составом, правами
и проверкой `C:\Vitality\`.

| Каталог | Содержимое |
|---|---|
| `manifests/` | `RuntimeManifest.json` — единственный источник состава (директории, правила, проверки). Статус `PROPOSED` до `S8-OPEN-1` |
| `bootstrap/` | `Deploy-Runtime.ps1` (`SCRIPT-RUNTIME-001`) — идемпотентное развёртывание; `Assert-RuntimeState.ps1` (`SCRIPT-RUNTIME-002`) — верификация только на чтение |

Не путать с `tools/runtime/`: там лежат артефакты контура Stage 6, доставляемые в `D:\GD_Tool` (`ADR-0015`),
здесь — развёртывание `C:\Vitality\` (`ADR-0017`).

Оркестрация этапа — `scripts/Stage8_Runtime_Deploy.ps1` (`SCRIPT-STAGE8-001`); документация —
`docs/runtime/RUNTIME_SCHEMA.md`; отчёты — `docs/artifacts/Stage8_preflight.md`, `Stage8_runtime.md`,
`Stage8_Report.md`.

**Правила домена:** записи только в `C:\Vitality\` (allow-list AR-206); секреты — файлами в `config\`
(`STRUC_009`); крупные данные — на `D:` (`SC_SSD_LONGEVITY`); бинарники — офлайн с `F:`, не в Git (AR-804);
удаление чего-либо в рантайме автономно запрещено (AR-201).
