# D_drive_schema.md — Схема раздела данных

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | STORAGE-0003 |
| `DRIVE` | `D:\` (раздел Data, NVMe SSD 480 ГБ) |
| `STAGE` | 1 (схема) |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | **APPROVED** (ADR-0007); runtime-структура наполняется на этапах 6–7 |
| `RELATED` | `ADR-0007`, `PAT-NEW-6`, `PAT-NEW-7`, `C_drive_schema.md`, `partitioning_research.md` |

---

## 1. Параметры раздела

| Параметр | Значение |
|---|---|
| Номер раздела | 4 (GPT) |
| ФС | **NTFS** (exFAT запрещён: `NC_EXFAT_DATA`) |
| Размер | ~279 ГБ (расчётно 279.7 ГБ) |
| Кластер | **64 КБ** |
| Метка | `Data` |
| Точка монтирования | `D:\` |
| Выравнивание | 1 MiB |

## 2. Обоснование выбора

| Решение | Причина |
|---|---|
| NTFS, не exFAT | exFAT не поддерживает POSIX-атрибуты, симлинки и сокеты — ломает `git clone` и сборку C++ |
| Кластер 64 КБ | крупные последовательные записи (`.vmdk`, тома контейнеров, артефакты сборок): меньше операций над метаданными и фрагментации |
| Отдельный раздел, не папка на `C:` | изоляция фонового износа и упрощение бэкапа конфигураций; сохранение ёмкости `C:` |
| Выравнивание 1 MiB | PAT-NEW-6, `H-005` (VALIDATED) |

**Компромиссы 64 КБ:** увеличенный расход на мелких файлах; NTFS-сжатие и дедупликация применяются ограниченно. Для целевого профиля (ВМ/контейнеры/артефакты) выгода перевешивает. Изменение размера кластера — только через `GATE_PARTITIONING`.

## 3. Твики NTFS (пост-настройка Stage 1)

```powershell
fsutil behavior set disable8dot3 D: 1      # отключить генерацию коротких имён 8.3
fsutil behavior set disablelastaccess 1    # не обновлять время последнего доступа
```

Обе настройки снижают количество операций записи метаданных. Проверяются скриптом `Stage1_DiskGenius_Partition.ps1` (раздел «fsutil»).

## 4. Целевая структура `D:\` (после этапов 6–7)

```
D:\
├── GD_Tool\                      # Контур самозащиты (Stage 6, PAT-NEW-3)
│   ├── LGPO.exe
│   ├── CleanLTSCPolicy\          # эталонный слепок политик
│   ├── AutoSetup.bat             # ASCII-only (AR-105)
│   └── Launcher.vbs
├── VM\                           # VMware Workstation (Stage 7, PAT-22)
│   ├── <VM_NAME>\
│   │   ├── <VM_NAME>.vmx         # mainMem.useNamedFile = "FALSE"
│   │   └── *.vmdk                # pre-allocated
│   └── Templates\
├── Docker\                       # тома контейнеров вне C: (AR-707)
│   ├── volumes\
│   └── compose\
├── Projects\                     # git clone, сборки
├── Drivers\                      # «голые» INF-драйверы (Stage 4, опционально)
└── Backups\                      # снимки конфигураций, манифесты SHA256
```

## 5. Правила размещения

| Правило | Основание |
|---|---|
| Тома Docker и диски ВМ — только на `D:\` | AR-707, AR-708, SC_SSD_LONGEVITY |
| Файлы ВМ: `mainMem.useNamedFile=FALSE`, `sched.mem.pshare.enable=FALSE` | PAT-22 |
| `D:\GD_Tool` — в списке исключений Defender | Stage 6 (§4.2 README) |
| Бэкапы конфигураций — в `D:\Backups` с манифестом SHA256; в Git не коммитятся | AR-304, AR-803 |
| Данные разработки на exFAT-носителях не размещаются | `NC_EXFAT_DATA` |
| Изменение структуры разделов/ФС/кластера | `GATE_PARTITIONING` |

## 6. Верификация

```powershell
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1
```

Ожидание: раздел 4 — NTFS, размер ~279 ГБ ±допуск, кластер 64 КБ, выравнивание 1 MiB, `fsutil disable8dot3 D:` = 1, `disablelastaccess` = 1.

---

<!-- Источник: README §6.3.5, §7.5; ADR-0007; PAT-NEW-6/7; AR-707/AR-708. Файл UTF-8 без BOM, LF. -->
