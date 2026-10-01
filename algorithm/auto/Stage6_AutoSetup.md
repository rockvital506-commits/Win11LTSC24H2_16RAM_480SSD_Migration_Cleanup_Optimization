# Stage 6 (auto) — Сборка контура самозащиты

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S6-AUTO |
| `STAGE` | 6 |
| `TYPE` | auto |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE (пакет) — прогон на стенде ожидает владельца |
| `RELATED` | `ADR-0003`, `ADR-0004`, `ADR-0015`, `PAT-04`, `PAT-06`, `PAT-08`, `PAT-09`, `PAT-11`, `PAT-NEW-2`, `PAT-NEW-3`, `PAT-NEW-4`, `scripts/Stage6_Immunity_Prepare.ps1` |

---

## 1. Цель этапа

Довести станцию до состояния, в котором конфигурация не откатывается самой системой: эталонный слепок политик,
закрытые каналы телеметрии, выведенные из строя задачи-реаниматоры, NTFS-замки на конфигурационные объекты и
периодическая задача `System_Immunity_Core`, повторяющая цементирование при загрузке и разблокировке.

Этап выполняется в профиле `devops` (сессия Audit Mode закрыта в Stage 5), при **физически отключённой сети**.

## 2. Предусловия

| # | Требование | Проверка |
|---|---|---|
| 1 | Stage 5 закрыт: OOBE пройден, пользователь `devops` создан, оболочка работоспособна | `Stage5_Report.md`, §9.5 |
| 2 | Сеть изолирована | `P0.1`: 0 активных адаптеров |
| 3 | Каталог `D:\GD_Tool` создан (раздел Data, ADR-0007/ADR-0011) | `P0.2` |
| 4 | `LGPO.exe` и слепок `CleanLTSCPolicy` подготовлены | `P0.3`, `P0.4` (`WARN`, если нет) |
| 5 | Права администратора; PowerShell 5.1+ | `Assert-Administrator` (AR-401) |
| 6 | Твики Stage 4 верифицированы | `Stage4_tweakstate.md` |

## 3. Порядок выполнения

```powershell
# 1. Сухой прогон: предусловия и план, без изменений (AR-201/AR-203)
pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -Audit

# 2. Подготовка: исключения Defender -> рантайм -> задача -> (опционально) замки
pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 `
     -ApplyAcl -ApplyTaskAcl `
     -VerificationReport ./docs/artifacts/Stage6_preflight.md

# 3. [ВЛАДЕЛЕЦ] Окно активации — algorithm/manual/Stage6_Ohook_Activation.md

# 4. Сквозная верификация после цементирования (только чтение)
pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -VerifyOnly `
     -VerificationReport ./docs/artifacts/Stage6_immunity.md
```

**Фазы оркестратора** (нарушение порядка запрещено, ADR-0015):

| Фаза | Действие | Артефакт |
|---|---|---|
| `P0` | предусловия: права, сеть, каталоги, инструменты | — |
| `P1` | доверенная зона Defender (до первой ACL-операции!) | `Invoke-DefenderAllowList.ps1` |
| `P2` | рантайм в `D:\GD_Tool` + SHA256 | `ImmunityCore.ps1`, `AutoSetup.bat`, `Launcher.vbs` |
| `P3` | задача `System_Immunity_Core`; реаниматоры → `Disable` | `Apply-TaskManifest.ps1` |
| `P3b` | правила брандмауэра по декларации + `D:\GD_Tool\FirewallRules.json` | `Apply-FirewallManifest.ps1` |
| `P4` | NTFS-замки `deny SYSTEM:(W)` (флаг `-ApplyAcl`) | `Apply-AclManifest.ps1` |
| `P5` | чек-лист ручного окна активации | `algorithm/manual/Stage6_Ohook_Activation.md` |
| `P6` | сквозная верификация | `Assert-ImmunityState.ps1` |

## 4. Что делает рантайм при каждой разблокировке

Транзакция `ImmunityCore.ps1` (идемпотентна, каждая операция проверяется до изменения, AR-303):

1. `grant` — SYSTEM получает полный доступ к `GroupPolicy` и файлу `hosts`;
2. `LGPO.exe /g D:\GD_Tool\CleanLTSCPolicy` — импорт эталонного слепка политик;
3. правила брандмауэра против `CompatTelRunner.exe` и `WaaSMedicAgent.exe` — состав из `FirewallRules.json` (единый источник `tweaks/firewall/FirewallManifest.json`, PAT-09);
4. `gpupdate /force` — фиксация политик в ядре;
5. `deny` — SYSTEM лишается права записи (абсолютный приоритет DENY, PAT-11/PAT-NEW-2);
6. запись результата в `D:\GD_Tool\logs\ImmunityCore.log`; код возврата ≠ 0 → FAIL в журнале задачи.

## 5. Критерии приёмки

| ID | Критерий | Где смотреть |
|---|---|---|
| `GACL-001/002` | оба объекта под DENY для SYSTEM | `Stage6_immunity.md` |
| `TASK-001.1/2` | задача зарегистрирована, принципал SYSTEM, триггеры boot+unlock | там же |
| `TR101…TR106` | реаниматоры отключены | там же |
| `F1/F2` | правила брандмауэра активны | там же |
| `D1` | `DoHPolicy = 1` (запрет DoH) | там же |
| `P1/P2` | доверенная зона = объявленный состав | там же |
| `B1/B2/L1` | артефакты рантайма и слепок политик на месте | там же |
| `A1` | лицензия — `Licensed` | там же |
| `M1/M2` | твики Stage 4 не деградировали (подкачка, hiberfil) | там же |
| — | сеть выключена, окно активации закрыто | `Stage6_Report.md` §ручной контроль |

## 6. Откат

| Что | Как |
|---|---|
| NTFS-замки | `pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Phase Grant` |
| SDDL | восстановление из `backups/<UTC>_stage6/<ID>_sddl.txt` |
| Задачи-реаниматоры | `Start-ScheduledTask` вручную или импорт XML из бэкапа |
| Исключения Defender | `pwsh -File ./tweaks/apply/Invoke-DefenderAllowList.ps1 -Remove` |
| Задача контура | `pwsh -File ./tweaks/apply/Apply-TaskManifest.ps1 -Unregister` (AR-204) |

## 7. Риски

| Риск | Митигация |
|---|---|
| Операция прав выглядит как шифровальщик для Defender | исключения ставятся фазой `P1` **до** первой ACL-операции |
| Замок ставится раньше импорта политик | жёсткая последовательность фаз в ядре: `deny` — только шаг 5 |
| Владелец забыл выключить сеть после активации | правила брандмауэра + чек-лист `P5`; проверка `F1/F2` |
| Расхождение рантайма и репозитория | SHA256-сверка `P2.*` при каждом прогоне подготовки |
