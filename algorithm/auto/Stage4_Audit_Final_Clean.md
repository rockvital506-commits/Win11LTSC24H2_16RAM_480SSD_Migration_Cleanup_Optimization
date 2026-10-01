# Stage 4 (auto) — Финальная санитария Audit Mode

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S4-AUTO |
| `STAGE` | 4 |
| `TYPE` | auto |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE |
| `RELATED` | `ADR-0012`, `ADR-0013`, `PAT-12`–`PAT-15`, `PAT-18`, `PAT-20`, `scripts/Stage4_Audit_Final_Clean.ps1` |

---

## Предусловия

| # | Требование |
|---|---|
| 1 | Система в Audit Mode, сеть физически отключена (Stage 3 завершён) |
| 2 | «Голые» INF-драйверы распакованы в `C:\Drivers\` (без вендорских exe-панелей) |
| 3 | Права администратора; PowerShell 5.1+ |
| 4 | Свободное место на `C:\` для операций обслуживания (≥ 10 ГБ) |

## Состав

| Фаза | Действие | Артефакт |
|---|---|---|
| P0 | Проверки: права, изоляция сети, наличие `C:\Drivers` | оркестратор |
| P1 | Сессия бэкапа + снимок BCD (AR-505) + список INF | `scripts/common/Backup.psm1` |
| P2 | Временный щит PnP → импорт INF (`pnputil /add-driver /install`) → **гарантированное снятие щита** | `PAT-15`, `tweaks/apply/Invoke-PnpShield.ps1` |
| P3 | Твики: реестр (TWK-001…005), службы (ServiceGate), AppX | `tweaks/apply/Apply-Tweaks.ps1` |
| P4 | Память: `powercfg /hibernate off`; фиксация подкачки 4096/4096 | `PAT-14`, `PAT-13` |
| P5 | Обслуживание: `dism /StartComponentCleanup /ResetBase`; очистка `SoftwareDistribution\Download` | `PAT-18` |
| P6 | NTFS: `fsutil behavior set disablelastaccess 1` | — |
| P8 | BCD: `loadoptions DISABLE-LSA-ISOLATION,DISABLE-VBS` — **отдельный изолированный шаг** | `PAT-12`, `tweaks/bcd/Set-BcdVbsFlags.ps1`, AR-505 |
| P7 | Верификация состояния | `tweaks/apply/Assert-TweakState.ps1` |

## Порядок выполнения

```powershell
# 1. Сухой прогон (ничего не меняет)
pwsh -File ./scripts/Stage4_Audit_Final_Clean.ps1 -Audit

# 2. Основной прогон (без BCD)
pwsh -File ./scripts/Stage4_Audit_Final_Clean.ps1 `
     -DriversPath C:\Drivers `
     -PageFileMb 4096 `
     -VerificationReport ./docs/artifacts/Stage4_tweakstate.md

# 3. BCD — отдельно и осознанно (AR-505)
pwsh -File ./tweaks/bcd/Set-BcdVbsFlags.ps1 -Audit
pwsh -File ./tweaks/bcd/Set-BcdVbsFlags.ps1

# 4. Контрольная верификация
pwsh -File ./tweaks/apply/Assert-TweakState.ps1 -ExportReport ./docs/artifacts/Stage4_tweakstate.md
```

Допускается объединение шагов 2 и 3 флагом `-IncludeBcd` — только при понимании, что нарушается принцип изоляции BCD-изменения.

## Ограничения и риски

| ID | Риск | Митигация |
|---|---|---|
| `R1` | Щит PnP оставлен активным → устройства с ошибками 28/48 (тачпад, аудио) | Снятие в `finally` + явный контроль состояния; отдельный `-Disable` прогон безопасен и идемпотентен |
| `R2` | `ResetBase` необратим | Принято ADR-0013; выполняется после успешной верификации стабильности системы |
| `R3` | Изменение BCD может сделать систему незагружаемой | `bcdedit /export` обязателен; откат `-Rollback`; разделение шагов (AR-505) |
| `R4` | Импорт драйверов подтягивает вендорский софт | Щит Co-инсталляторов + «голые» INF без exe-панелей |
| `R5` | Службы-реаниматоры возвращают тип запуска позже | Ожидаемо: окончательное цементирование — Stage 6 (`PAT-11`); здесь — фиксация и верификация |
| `R6` | Нехватка места при `ResetBase` | Проверка свободного места в предусловиях |

## Проверки этапа (свод)

| ID | Проверка | Источник |
|---|---|---|
| `W1`–`W5` | TWK-001…003, loadoptions, VBS runtime | ADR-0012 |
| `L1`–`L5` | hiberfil, pagefile, WSearch, WinSxS | ADR-0013 |
| `S-*` | Типы запуска служб | `ServiceGate.json` |
| `X1` | Отсутствие provisioned Xbox/Cortana/Bing и др. | `AppxRemoval.json` |
| `F1` | Щит PnP снят (значения отсутствуют) | `Invoke-PnpShield.ps1 -Audit` |

## Артефакты этапа

| Артефакт | Путь |
|---|---|
| Оркестратор | `scripts/Stage4_Audit_Final_Clean.ps1` |
| Общие модули | `scripts/common/{Logging,Backup,Verification,Guard}.psm1` |
| Домен | `tweaks/{registry,services,appx,bcd,apply}/` |
| Отчёт верификации | `docs/artifacts/Stage4_tweakstate.md` (генерируется) |
| Отчёт этапа | `docs/artifacts/Stage4_Report.md` |
| Бэкапы | `backups/<UTC>_stage4/`, `backups/<UTC>_bcd/` (вне Git) |

## Переход

Stage 5 — `unattend.xml` и `sysprep /oobe /generalize /shutdown` (`algorithm/auto/Stage5_Sysprep_Seal.md`, ADR-0005).

---

<!-- Источник: docs/research/step3.md; README §5.6. Файл UTF-8 без BOM, LF. -->
