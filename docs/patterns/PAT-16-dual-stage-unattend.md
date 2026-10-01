# PAT-16 — Dual-Stage Unattend (Ventoy + Sysprep)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-16 |
| `NAME` | Двухэтапный файл ответов: установка и обобщение |
| `STAGE` | 2 (файл № 1), 5 (файл № 2) |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0005`, `PAT-01`, `PAT-NEW-1`, `templates/u_w11_ltsc_iot.xml.template`, `templates/unattend.xml.template`, README §1.4 `SC_FACTORY_RESET_CAPABLE` |

---

## Контекст

Конфигурация должна: (а) рано нейтрализовать вендорские компоненты и телеметрию, (б) перенести все твики Audit Mode в шаблон `Default User`, (в) оставаться воспроизводимой при повторных развёртываниях (Factory Reset). Один файл ответов этого не обеспечивает: `CopyProfile` работает только при `sysprep /generalize`, а элементы первичной установки на обобщении конфликтуют с ним.

## Решение

Два файла ответов с непересекающимися областями действия:

| Файл | Расположение | Проходы | Содержание |
|---|---|---|---|
| `u_w11_ltsc_iot.xml` | `F:\ventoy\templates\` | `windowsPE`, `specialize`, `oobeSystem` | EULA; IFEO-заглушки ASUS (`PAT-01`); `DiagTrack Start=4`; `SearchOrderConfig=0`; вход в Audit Mode |
| `unattend.xml` | `C:\Windows\System32\Sysprep\` | `specialize`, `oobeSystem` | `CopyProfile=true`; фиксация политик (`RunSynchronousCommand`); часовой пояс; скрытие экранов OOBE |

Правило размещения: файл с `CopyProfile=true` **никогда** не попадает на носитель Ventoy, файл установки **никогда** не копируется в каталог `Sysprep`.

## Реализация

| Этап | Действие | Артефакт |
|---|---|---|
| 2 | Рендер шаблона в `u_w11_ltsc_iot.xml` (UTF-8 **без BOM**), размещение на носителе по пути из `ventoy.json` | `templates/u_w11_ltsc_iot.xml.template`, `templates/ventoy.json.template` |
| 2 | Ventoy подхватывает файл через `auto_install` (сопоставление по точному пути ISO) | `F:\ventoy\ventoy.json` |
| 5 | Рендер второго шаблона в `unattend.xml`, размещение в каталоге `Sysprep` | `templates/unattend.xml.template` |
| 5 | `sysprep.exe /oobe /generalize /shutdown /unattend:...` | `algorithm/auto/Stage5_Sysprep_Seal.md` |

Кодировка обоих файлов — UTF-8 **без BOM** (AR-101): BOM приводит к отказу парсера `setup.exe`. Шаблоны хранятся с расширением `.template` (STRUC_010) и валидируются валидатором как XML.

## Верификация

| ID | Проверка | Критерий |
|---|---|---|
| `A1` | XML-шаблоны валидны и без BOM | парсятся; первые 3 байта не `EF BB BF` |
| `A2`–`A4` | Файл № 1 отработал (IFEO, DiagTrack, SearchOrderConfig) | см. ADR-0005 (V1–V7 verification) |
| `A5` | Файл № 2 отработал | профиль `Default` содержит твики Audit Mode |
| `A6` | Размещение без дублирования | файл № 1 только на носителе, файл № 2 только в `Sysprep` |

## Ограничения и риски

- **Элементы схемы с неподтверждённой поддержкой.** `<Mode>Audit</Mode>` (вход в Audit Mode через unattend) оставлен в шаблоне отключённым: альтернатива — `Ctrl+Shift+F3` на экране OOBE (документированный способ). Пункт `S2-OPEN-2`.
- **`CopyProfile`** официально не рекомендован Microsoft для версий после Windows 7; применяется осознанно ради SC_FACTORY_RESET_CAPABLE. Побочный эффект: часть современных UWP-настроек может не переноситься.
- **Рассинхрон двух файлов**: изменение, внесённое только в один, приводит к неочевидному поведению. Контроль — ADR-0005 (п.6) и хеши в отчётах этапов.
- Валидация unattend на железе стоит установки; **проверка в ВМ обязательна** до боевого применения.

## Альтернативы

| Вариант | Причина отклонения |
|---|---|
| Единый файл ответов | `CopyProfile` требует профиля-источника; конфликт проходов audit/generalize |
| Только `unattend.xml` (Stage 5) | Ранние настройки срабатывают поздно: WPBT-компоненты успевают развернуться |
| Ручная настройка без файлов ответов | Не обеспечивает воспроизводимость и SC_FACTORY_RESET_CAPABLE |
