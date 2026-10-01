# Stage 5 (auto) — Запечатывание Sysprep

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S5-AUTO |
| `STAGE` | 5 |
| `TYPE` | auto |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE |
| `RELATED` | `ADR-0005`, `ADR-0014`, `PAT-16`, `PAT-NEW-1`, `scripts/Stage5_Sysprep_Prepare.ps1`, `templates/unattend.xml.template` |

---

## 1. Цель этапа

Перевести настроенный в Audit Mode монолит в шаблон: `sysprep /oobe /generalize /shutdown` сносит уникальные идентификаторы оборудования, переносит профиль Администратора в `Default User` (`CopyProfile`) и выключает ноутбук. Следующий запуск — «тихий» OOBE, где создаётся локальный пользователь `devops`.

Этап закрывает сессию встроенного Администратора и завершает первый отрезок проекта (Stage 1–5). Всё, что после — работа в пользовательском профиле.

## 2. Предусловия

| # | Требование | Проверка |
|---|---|---|
| 1 | Сеть физически отключена (AR-709) | `P0.2`: 0 активных адаптеров |
| 2 | Audit Mode активен | `P0.1`: `SystemSetupInProgress = 1` |
| 3 | Stage 4 завершён и верифицирован | `Stage4_Report.md`, `Stage4_tweakstate.md` |
| 4 | Каталог `C:\Windows\System32\Sysprep` доступен для записи | `P0.3`, `P2.1` |
| 5 | Журналы Sysprep не содержат незакрытых ошибок прошлых прогонов | `setuperr.log` в бэкапе |
| 6 | Права администратора; PowerShell 5.1+ | `Assert-Administrator` (AR-401) |

## 3. Порядок выполнения

```powershell
# 1. Сухой прогон: только проверки, без изменений
pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 -Audit

# 2. Основная подготовка: размещение файла ответов, ловушка AppX, гигиена кэшей
pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 `
     -FixSysprepValidation `
     -PurgeProfileCaches `
     -VerificationReport ./docs/artifacts/Stage5_preflight.md
```

```bat
:: 3. Запечатывание — ТОЛЬКО из CMD от Администратора (не PowerShell), AR-204
cd /d C:\Windows\System32\Sysprep
sysprep.exe /oobe /generalize /shutdown /unattend:C:\Windows\System32\Sysprep\unattend.xml
```

Альтернатива шага 3 (осознанно, только при понимании необратимости):

```powershell
pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 -ExecuteSysprep -Confirm:$false
```

Дождаться полного выключения ноутбука. Затем включить, пройти OOBE и создать пользователя `devops`; сеть по-прежнему держать отключённой (AR-709).

## 4. Отступления от docs/research/step4.md

| ID | Отступление | Причина |
|---|---|---|
| `S5-DEV-1` | Удалён `<HideLocalAccountScreen>` | Элемент применим только к Windows Server; на клиенте поведение по умолчанию и так показывает экран создания локальной учётной записи |
| `S5-DEV-2` | Компонент `Microsoft-Windows-MPR` заменён политиками `HKLM\SOFTWARE\Policies\Microsoft\MRT` | Существование компонента не подтверждено справочником unattend; политики MSRT документированы |
| `S5-DEV-3` | Удаление AppX не выполняется в `specialize` | Ловушка `0x80073cf2` срабатывает до применения файла ответов; удаление закреплено на Stage 4 (AR-507) |
| `S5-DEV-4` | PowerShell-однострочники заменены атомарными `reg add` | 24H2 игнорирует хвосты команд с `&&`/`&`; каждая инъекция — отдельный `RunSynchronousCommand` (AR-303, AR-502) |
| `S5-DEV-5` | Исправлены пространства имён `wcm`/`xsi` | При неверных значениях setup игнорирует `wcm:action` и команды не применяются |

## 5. Предпролётная защита (ключевой риск этапа)

**Ловушка `0x80073cf2`.** Проверка `SYSPRP AppxSysprep` сравнивает установленные для пользователей пакеты с provisioned-копиями. Пакет, установленный для Администратора, но не provisioned для всех, валит generalize сообщением «Sysprep was unable to validate your Windows installation».

Порядок реакции:

1. `P3.1` показывает количество нарушений по объявленным шаблонам Stage 4.
2. Если нарушения есть — прогон с `-FixSysprepValidation` удаляет только эти пакеты (`Remove-AppxPackage -AllUsers`), защищённые шаблоны не затрагиваются.
3. Пакеты вне манифеста (`P3.2`, `SKIP`) фиксируются в отчёте: решение по ним принимает инженер, автоматическое удаление не выполняется.

**Дефект CopyProfile 23H2/24H2.** Кэши `WebCache`/`INetCache` из профиля Администратора попадают в `Default User` и ломают оболочку нового пользователя (мигающая панель задач, не открывается «Пуск»). `-PurgeProfileCaches` очищает кэши до generalize; запертые файлы фиксируются как `WARN`, и тогда устранение переносится в Stage 6.

## 6. Верификация

| ID | Проверка | Ожидание | Источник |
|---|---|---|---|
| `P0.1` | Audit Mode | `SystemSetupInProgress = 1` | скрипт |
| `P0.2` | Сетевая изоляция | 0 активных адаптеров | скрипт |
| `P0.3` | Шаблон существует | `templates/unattend.xml.template` | скрипт |
| `P2.1` | BOM отсутствует | `False` | скрипт |
| `P2.2` | XML валиден | `valid` | скрипт |
| `P3.1` | Ловушка AppX | 0 нарушений | скрипт |
| `P4.1` | Гигиена кэшей | выполнено / `WARN` | скрипт |
| `S1`–`S6` | Результат запечатывания | см. ADR-0014 | вручную, после OOBE |

## 7. Риски

| ID | Риск | Митигация |
|---|---|---|
| `R1` | Ошибка валидации generalize (`0x80073cf2`) | Предпролётная проверка `P3.1` + `-FixSysprepValidation`; журналы `setupact.log`/`setuperr.log` в бэкапе |
| `R2` | Дефект CopyProfile в 24H2 | Очистка кэшей `-PurgeProfileCaches`; перенос устранения в Stage 6 |
| `R3` | Неверный разбор файла ответов | Исправленные пространства имён; проверки `P2.1`/`P2.2`; отказ от неподтверждённых элементов |
| `R4` | Потеря настроек, привязанных к пользователю | Принято ADR-0014 п.2; компенсация политиками Stage 6 |
| `R5` | Необратимость generalize и `ResetBase` | Повторное развёртывание по `Recovery_Procedure.md` (SC_FACTORY_RESET_CAPABLE) |
| `R6` | Фоновая активность Store во время generalize | Сеть отключена (AR-709), активные адаптеры — блокирующее предусловие |

## 8. Результат

Ожидаемый: ноутбук выключен, `sysprep_succeeded.tag` присутствует, при следующем запуске OOBE останавливается на создании пользователя. После создания `devops` — контрольные точки: твики в профиле (`H-003`), IFEO ASUS, `DiagTrack`, отсутствие `hiberfil.sys`.

## 9. Переход

Stage 6 — первичная инициализация профиля `devops` и цементирование контура (`algorithm/manual/Stage6_Ohook_Activation.md`, `algorithm/auto/Stage6_AutoSetup.md`). До возврата сети — проверка `H-004`.

---

<!-- Источник: docs/research/step4.md; ADR-0005, ADR-0014; README §5.6, §9.5. Файл UTF-8 без BOM, LF. -->
