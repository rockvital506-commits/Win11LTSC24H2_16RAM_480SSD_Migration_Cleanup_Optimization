# Stage 2 (manual) — Подготовка Ventoy-контура и стерильная установка

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S2-MAN |
| `STAGE` | 2 |
| `TYPE` | manual |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE |
| `RELATED` | `ADR-0005`, `PAT-16`, `PAT-01`, `PAT-NEW-1`, `templates/ventoy.json.template`, `templates/u_w11_ltsc_iot.xml.template`, `docs/storage/F_drive_schema.md`, README §5.7, §9.2 |

---

## Цель

Развернуть на носителе F: контур автоматической установки (ISO + `ventoy.json` + файл ответов) и выполнить стерильную установку Windows 11 IoT Enterprise LTSC 24H2 на размеченный в Stage 1 раздел **с физически отключённой сетью**, получив рабочий стол встроенного Администратора в Audit Mode.

## Предусловия

| # | Требование |
|---|---|
| 1 | Stage 1 завершён: разметка выполнена, верификация пройдена (W1, V1–V6) |
| 2 | Носитель F: содержит `/ISO/` с образом LTSC IoT 24H2 и WinPE (см. `docs/storage/F_drive_schema.md`) |
| 3 | Сеть на целевом ноутбуке **физически отключена** (кабель извлечён, Wi-Fi выключен) — `NC_INTERNET_DURING_TWEAKS` |
| 4 | Шаблоны из репозитория доступны: `templates/ventoy.json.template`, `templates/u_w11_ltsc_iot.xml.template` |

## Шаги

### Шаг 1. Рендер конфигурации Ventoy

1. Открыть `templates/ventoy.json.template` и **сверить имя ISO** с фактическим файлом в `F:\ISO\` (пункт `S2-OPEN-1`: возможны два варианта имени).
2. Сохранить результат как `F:\ventoy\ventoy.json` — строгий JSON, **UTF-8 без BOM**, LF.
3. Проверить синтаксис:

```powershell
Get-Content F:\ventoy\ventoy.json -Raw | ConvertFrom-Json | Out-Null
```

### Шаг 2. Рендер файла ответов

1. Открыть `templates/u_w11_ltsc_iot.xml.template`.
2. Разобраться с элементом Audit Mode (пункт `S2-OPEN-2`): по умолчанию он **отключён** (закомментирован). Вариант A — раскомментировать `<Mode>Audit</Mode>` (только после проверки в ВМ); вариант B — оставить отключённым и войти в Audit Mode сочетанием `Ctrl+Shift+F3` на экране OOBE.
3. Сохранить как `F:\ventoy\templates\u_w11_ltsc_iot.xml` — **UTF-8 БЕЗ BOM**, CRLF.
4. Проверить отсутствие BOM:

```powershell
$b = Get-Content F:\ventoy\templates\u_w11_ltsc_iot.xml -Encoding Byte -TotalCount 3
if (($b -join ',') -eq '239,187,191') { Write-Host 'ОШИБКА: файл содержит BOM — setup.exe его отклонит' -ForegroundColor Red }
else { Write-Host 'OK: BOM отсутствует' -ForegroundColor Green }
```

### Шаг 3. Загрузка на целевой ноутбук

1. Вставить носитель F: в ASUS Vivobook.
2. Загрузиться через UEFI-меню (клавиша загрузочного меню ASUS) → выбрать USB → Ventoy.
3. В меню Ventoy выбрать `Windows 11 IoT Enterprise LTSC 24H2 (auto_install)`.
4. Убедиться, что `auto_install` сработал: экран выбора языка должен быть пропущен/минимизирован, лицензионное соглашение — принято автоматически.

### Шаг 4. Выбор раздела и установка

1. На экране выбора диска указать **созданный в Stage 1 раздел** (200 GiB, `Windows`). Не создавать разделы средствами установщика: разметка зафиксирована (ADR-0007 rev.2).
2. Дождаться распаковки `install.wim` и перезагрузки.
3. **После перезагрузки**:
   - Вариант B (по умолчанию): на первом экране OOBE нажать `Ctrl+Shift+F3` → вход в Audit Mode;
   - Вариант A: вход в Audit Mode происходит автоматически (если элемент включён и ВМ-проверка пройдена).

### Шаг 5. Проверка результата и изоляция

1. Убедиться, что открыт рабочий стол встроенного **Администратора** с окном Sysprep (окно закрыть **крестиком/Отмена**, не запускать обобщение — обобщение выполняется на Stage 5).
2. Проверить, что файл ответов отработал (см. `algorithm/auto/Stage2_Audit_Mode_Workflow.md`, проверки A2–A4).
3. **Сеть остаётся отключённой** до Stage 3 (обновления) — там подключение выполняется осознанно и на короткое время.

## Критерии выхода

| # | Критерий |
|---|---|
| 1 | `F:\ventoy\ventoy.json` валиден; имя ISO совпадает байт-в-байт |
| 2 | `F:\ventoy\templates\u_w11_ltsc_iot.xml` — UTF-8 без BOM |
| 3 | Установка выполнена на раздел Stage 1 (200 GiB) |
| 4 | Достигнут рабочий стол Администратора в Audit Mode |
| 5 | Проверки A2–A4 пройдены (требуется для отчёта этапа) |
| 6 | Сеть отключена |

## Артефакты шага

| Артефакт | Путь |
|---|---|
| Конфигурация Ventoy | `F:\ventoy\ventoy.json` (вне Git) |
| Файл ответов | `F:\ventoy\templates\u_w11_ltsc_iot.xml` (вне Git) |
| Схема носителя | `docs/storage/F_drive_schema.md` |
| Отчёт | `docs/artifacts/Stage2_Report.md` |

## Переход

Stage 3 — накат накопительных обновлений в Audit Mode с кратковременным подключением сети (`algorithm/manual/Stage3_Windows_Update.md`).

---

<!-- Файл UTF-8 без BOM, LF. -->
