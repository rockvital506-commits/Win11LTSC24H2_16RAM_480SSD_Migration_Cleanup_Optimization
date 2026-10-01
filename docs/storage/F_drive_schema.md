# F_drive_schema.md — Схема внешнего носителя (Ventoy, 460 ГБ)

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | STORAGE-0004 |
| `DRIVE` | `F:\` (USB Flash 460 ГБ, Ventoy 1.1.10) |
| `STAGE` | 2 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | **IN_PROGRESS** — схема зафиксирована; фактические размеры требуют протоколирования (F-OPEN-1) |
| `RELATED` | `ADR-0005`, `PAT-16`, `templates/ventoy.json.template`, README §5.7, §8, `docs/artifacts/Stage2_Report.md` |

---

## 1. Назначение

Внешний носитель — **производный** репозиторий (README §5.7): он воспроизводится из GitHub + шаблонов + сторонних бинарников и служит средством развёртывания (Ventoy) и offline-хранилищем инструментов. Источник истины — репозиторий; носитель может быть пересоздан.

## 2. Физическая раскладка

| # | Раздел | ФС | Кластер | Размер | Назначение |
|---|---|---|---|---|---|
| 1 | VTOYEFI | FAT32 | — | ~1 ГБ (создаёт установщик Ventoy) | Загрузчик Ventoy |
| 2 | VENTOY (данные) | exFAT | 512 Б | 250 ГБ | ISO-образы, `ventoy.json`, шаблоны |
| 3 | VITADATA | NTFS | 16 КБ | весь остаток | Инструменты, драйверы, конфиги, бэкапы таблиц разделов |

> **Единицы измерения (F-OPEN-1).** README §5.7.1/§8.2 задаёт размеры без указания системы. При трактовке по ADR-0011 (двоичные единицы): раздел 2 — 250 GiB, раздел 3 — остаток ≈177.4 GiB (носитель 460 ГБ ≈ 428.4 GiB). Фактическая раскладка протоколируется командой:
>
> ```powershell
> Get-Partition -DiskNumber <N> | Select-Object PartitionNumber, Offset, Size, DriveLetter
> Get-Volume -DriveLetter F | Format-List
> ```
>
> Если носитель уже размечен в SI-трактовке — **переразметка не выполняется** (риск потери данных); расхождение фиксируется и утверждается через `GATE_FDRIVE_MODIFICATION`.

## 3. Раздел 2 — Ventoy / ISO

```
F:\
├── /ISO/
│   ├── en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso
│   └── WinPE11_10_8_Sergei_Strelec_2026.02.05_Russian.iso
└── /ventoy/
    ├── ventoy.json                       (рендер templates/ventoy.json.template)
    └── /templates/
        └── u_w11_ltsc_iot.xml            (рендер templates/u_w11_ltsc_iot.xml.template, UTF-8 БЕЗ BOM)
```

**Критические правила:**

| Правило | Обоснование |
|---|---|
| Имя ISO-файла должно **байт-в-байт** совпадать с полем `image` в `ventoy.json` | При расхождении `auto_install` молча не срабатывает; установка идёт как обычная, без файла ответов. Пункт `S2-OPEN-1` |
| Файл ответов — **UTF-8 без BOM** | Иначе `setup.exe` отклоняет файл (AR-101, `docs/research/step1.md`) |
| `ventoy.json` — строгий JSON (без комментариев) | Парсер Ventoy чувствителен к синтаксису; проверка — перед записью на носитель |
| exFAT для раздела 2 допустим только потому, что здесь нет dev-данных | `NC_EXFAT_DATA` (нет POSIX-атрибутов и симлинков) |

## 4. Раздел 3 — инструменты и бэкапы

Структура соответствует README §5.7.3:

```
F:\
├── /TOOLS/          (TI, GPO/LGPO, Partitioning/DiskGenius, Backup, Activation, Audit, Cleanup)
├── /DRIVERS/        (ASUS_Vivobook_Clean, Intel_Generic)
├── /WSL2/           (ubuntu.appx, docker-compose.yaml, .wslconfig)
├── /VM/             (VMware-Workstation-Pro.exe, Templates)
├── /VITALITY-SOURCE/ (исходники вспомогательных утилит, если применимо)
├── /VITALITY-CONFIGS/(registry.pol, Targets.json, u_w11_ltsc_iot.xml, unattend.xml)
├── /SCRIPTS/        (копии скриптов из scripts/ для offline-доступа)
├── /DOCS/           (копии docs/ для offline-доступа)
├── /HASHES/         (TOOLS_SHA256.txt, DRIVERS_SHA256.txt, ISO_SHA256.txt)
└── /BACKUPS/        (бэкапы таблиц разделов Stage 1, образы старой системы)
```

## 5. Правила модификации (FDRIVE_001…006)

| Правило | Содержание |
|---|---|
| `FDRIVE_001` | Любое изменение структуры `F:\` — только через `GATE_FDRIVE_MODIFICATION` |
| `FDRIVE_002` | Содержимое воспроизводимо из GitHub + шаблонов |
| `FDRIVE_003` | `ventoy.json` и XML-шаблоны хранятся в репозитории с расширением `.template` |
| `FDRIVE_004` | SHA256 всех бинарников и образов — в `/HASHES/` (PAT-20) |
| `FDRIVE_005` | Образ старой системы — в `/BACKUPS/` с метаданными |
| `FDRIVE_006` | Копии `docs/` дублируют GitHub для offline-доступа |

## 6. Верификация

| ID | Проверка | Команда/метод | Критерий |
|---|---|---|---|
| `F1` | Раскладка разделов | `Get-Partition`, DiskGenius | 3 раздела; ФС FAT32/exFAT/NTFS; кластеры совпадают |
| `F2` | Содержимое `/ISO/` | `Get-ChildItem F:\ISO` | оба ISO присутствуют, имена совпадают с `ventoy.json` |
| `F3` | Валидность `ventoy.json` | `Get-Content F:\ventoy\ventoy.json -Raw \| ConvertFrom-Json` | парсится без ошибок |
| `F4` | Кодировка файла ответов | `Get-Content F:\ventoy\templates\u_w11_ltsc_iot.xml -Encoding Byte -TotalCount 3` | не `239 187 191` (нет BOM) |
| `F5` | Хеши | `/HASHES/*.txt` | соответствуют файлам (`Get-FileHash`) |
| `F6` | Раздел 3 | `Get-Volume -DriveLetter F` | NTFS, кластер 16 КБ |

## 7. Открытые пункты

| ID | Пункт | Действие |
|---|---|---|
| `F-OPEN-1` | Единицы измерения разделов 2–3 (SI против GiB) и фактический размер VTOYEFI (Ventoy версии 1.1.10 создаёт раздел меньшего размера, чем 1 ГБ, в зависимости от режима) | Протоколировать фактические значения; при отклонении — ADR + `GATE_FDRIVE_MODIFICATION`. Переразметку не выполнять |
| `S2-OPEN-1` | Расхождение имени ISO | **RESOLVED** (2026-10-01, подтверждено владельцем): фактическое имя — `en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso`. Обновлены `templates/ventoy.json.template`, README §5.7.2/§8.4, этот документ |
| `F-OPEN-2` | Точное имя WinPE-ISO (`WinPE11_10_8_Sergei_Strelec_2026.02.05_Russian.iso` по README §5.7.2/§8.4) не подтверждено | Подтвердить фактическое имя; при расхождении — исправить `menu_alias` и README. На `auto_install` не влияет (используется только для пункта меню) |
| `F-OPEN-3` | SHA256 ISO и бинарников не зафиксированы | Внести в `/HASHES/ISO_SHA256.txt` на носителе и в отчёт (PAT-20) |

---

<!-- Источник: README §5.7, §8; ADR-0005; PAT-16. Файл UTF-8 без BOM, LF. -->
