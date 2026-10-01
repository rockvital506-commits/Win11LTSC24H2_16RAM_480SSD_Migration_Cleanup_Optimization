# ADR-0005 — Двухэтапный файл ответов (Ventoy + Sysprep)

| Поле | Значение |
|---|---|
| `ADR_ID` | ADR-0005 |
| `TITLE` | Dual-stage unattend: separate answer files for install and generalize |
| `STATUS` | **ACCEPTED** |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `APPROVED_BY` | rockvital506-commits (архитектура зафиксирована в `docs/research/anchor1.md`; детализация настоящим ADR) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `PAT-16`, `PAT-NEW-1`, `PAT-01`, `templates/u_w11_ltsc_iot.xml.template`, `templates/unattend.xml.template`, `algorithm/manual/Stage2_Ventoy_Install.md`, `algorithm/auto/Stage5_Sysprep_Seal.md`, README §1.4 `SC_FACTORY_RESET_CAPABLE`, §4.5 |

---

## Context

Проект требует, чтобы все твики и настройки, созданные в Audit Mode, были перенесены в шаблон профиля `Default User` и сохранялись при каждом последующем развёртывании (`SC_FACTORY_RESET_CAPABLE`, `H-003` VALIDATED). Механика переноса — `CopyProfile=true` в проходе `specialize`, который применяется **только** при `sysprep /generalize`.

Одновременно нужны ранние настройки, которые обязаны сработать **до** первого входа пользователя и до появления сети: принятие EULA, нейтрализация вендорских компонентов ASUS (внедряются BIOS через таблицу WPBT при инициализации оборудования), запрет автоматической подтяжки драйверов, отключение телеметрии.

Объединить это в один файл нельзя:

| Ограничение | Следствие |
|---|---|
| `CopyProfile` применяется на проходе `specialize` и «съедает» профиль текущего пользователя | Файл с `CopyProfile` нельзя подкладывать на этапе установки: обобщение выполняется позже, на Stage 5, иначе твики не будут перенесены |
| Файл ответов на установку (windowsPE) содержит `Mode=Audit`/преднастроенное поведение OOBE | При повторном применении на Sysprep эти элементы конфликтуют с `generalize` |
| `C:\Windows\System32\Sysprep\unattend.xml` читается только при `sysprep.exe` | Не участвует в первичной установке |
| Ventoy подменяет файл ответов на этапе windowsPE через `auto_install` | Требуется отдельный файл с путём, прописанным в `ventoy.json` |

## Decision

Применяются **два независимых файла ответов**, каждый со своей областью действия:

| # | Файл | Расположение | Проходы | Область |
|---|---|---|---|---|
| 1 | `u_w11_ltsc_iot.xml` | `F:\ventoy\templates\` (носитель Ventoy) | `windowsPE`, `specialize`, `oobeSystem` | Первичная установка: EULA, IFEO-заглушки ASUS (PAT-01), DiagTrack, SearchOrderConfig, вход в Audit Mode |
| 2 | `unattend.xml` | `C:\Windows\System32\Sysprep\` | `specialize` (+ `oobeSystem`) | Запечатывание: `CopyProfile=true`, фиксация политик, часовой пояс, скрытие экранов OOBE |

Правила:

1. **Разделение по расположению, а не по содержимому.** Файл с `CopyProfile=true` никогда не размещается на носителе Ventoy; файл установки никогда не копируется в каталог `Sysprep`.
2. **Файл № 1 не содержит `CopyProfile`.** Файл № 2 не содержит элементов, управляющих выбором раздела и принятием EULA.
3. **Шаблоны хранятся в репозитории** как `templates/*.xml.template` (STRUC_010) в кодировке **UTF-8 без BOM** (AR-101). Рендер в имя без `.template` выполняется инженером на носителе/хосте.
4. **Продукционный XML-проходы проверяются в виртуальной машине** до применения на железе (единственный надёжный способ валидации схемы unattend).
5. **Элементы с неподтверждённой поддержкой схемой** (например, `<Mode>Audit</Mode>` для oobeSystem — пункт `S2-OPEN-2`) в шаблоне присутствуют, но **отключены**, с документированной альтернативой (`Ctrl+Shift+F3` на экране OOBE). Включение допускается только после успешной проверки в ВМ.
6. **Изменения содержимого файлов ответов** — только через это ADR (обновление) либо новый ADR; содержимое фиксируется хешем в отчёте соответствующего этапа (PAT-20).

## Consequences

**Положительные:**

- Твики Audit Mode переносятся в `Default User` штатным механизмом (`CopyProfile`), что делает конфигурацию воспроизводимой при каждом Factory Reset.
- Ранняя нейтрализация ASUS работает до первого запуска пользовательского ПО; `SearchOrderConfig=0` исключает подтяжку вендорских панелей из интернета.
- Файлы изолированы: ошибка в одном не влияет на другой.

**Отрицательные / компромиссы:**

- Два файла нужно поддерживать синхронно с документацией (PAT-16) и контролировать их расположение; ошибка размещения (файл с `CopyProfile` на носителе) приведёт к неожиданному поведению при установке.
- `CopyProfile` официально помечен Microsoft как «не рекомендуется для версий после Windows 7»; механизм сохранён осознанно (требование SC_FACTORY_RESET_CAPABLE), риск фиксируется и проверяется на Stage 5 (`H-004` — статус PENDING для Ohook).

## Alternatives

| Вариант | Причина отклонения |
|---|---|
| Единый `unattend.xml` на оба этапа | `CopyProfile` на этапе установки не имеет профиля-источника (обобщение ещё не выполнялось); конфликт проходов audit/generalize |
| Только второй файл (Sysprep), без файла установки | Ранние настройки (EULA, IFEO, DiagTrack) срабатывают слишком поздно: WPBT-компоненты успевают развернуться до specialize |
| Полностью ручная настройка без файлов ответов | Нарушает SC_FACTORY_RESET_CAPABLE и воспроизводимость; исключает Audit Mode workflow |
| Конфигурация через `DISM /Apply-Image` с offline-правкой реестра | Усложняет процесс; не покрывает элементы OOBE и IFEO на первом запуске |

## Verification

| ID | Проверка | Как | Критерий |
|---|---|---|---|
| `A1` | Валидность XML | открыть оба шаблона в ВМ/просмотрщике | парсится без ошибок, кодировка UTF-8 без BOM |
| `A2` | Файл № 1 отработал | в Audit Mode: `reg query "HKLM\...\Image File Execution Options\AsusUpdateCheck.exe" /v Debugger` | значение `ntsd -d` |
| `A3` | DiagTrack отключён | `reg query HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack /v Start` | `0x4` |
| `A4` | SearchOrderConfig=0 | `reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v SearchOrderConfig` | `0x0` |
| `A5` | Файл № 2 отработал | после Stage 5: сравнить профиль `Default` с эталоном | твики присутствуют |
| `A6` | Размещение файлов | `Test-Path F:\ventoy\templates\u_w11_ltsc_iot.xml`, `Test-Path C:\Windows\System32\Sysprep\unattend.xml` | без взаимного дублирования |

Результаты фиксируются в `docs/artifacts/Stage2_Report.md` (A1–A4), `Stage5_Report.md` (A5).
