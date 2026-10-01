# Stage1_Report.md — Отчёт этапа 1 (разметка NVMe SSD)

| Поле | Значение |
|---|---|
| `REPORT_ID` | SR-1 |
| `STAGE` | Stage 1 — Partitioning |
| `STATUS` | **IN_PROGRESS** — пакет автоматизации DONE (rev.2: GiB + скрытая ESP); аппаратная верификация ожидает нативного прогона на хосте |
| `DATE_START` | 2026-10-01 |
| `DATE_END` | — (закрывается после прогона V1–V7 на хосте) |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `PREVIOUS` | `Stage0_Report.md` |
| `NEXT` | `Stage2_Report.md` |
| `COMMIT_BASE` | `cbe60eb` (Stage 0) |

> **Важно о статусе.** Физическая разметка NVMe на стенде выполнена владельцем ранее (см. `docs/research/step1.md` … `step5.md`: этапы 1–5 пройдены, хост запечатан). Данный отчёт закрывает **воспроизводимость** Stage 1: пакет документов, решение (ADR-0007), паттерны и скрипт повторяемой верификации для циклов Factory Reset (SC_FACTORY_RESET_CAPABLE). Инструментальная проверка фактической геометрии стенда агентом **не выполнялась** и должна быть проведена на хосте.

---

## 1. Контекст и цель этапа

Stage 1 — необратимая операция: разметка NVMe уничтожает предыдущую систему, изменение геометрии после этапа невозможно без потери данных (README §4.5, `GATE_PARTITIONING`). Цель этапа:

1. зафиксировать схему разметки нормативно (ADR-0007) и описательно (`docs/storage/*`);
2. обеспечить выравнивание 1 MiB на всех разделах (`PAT-NEW-6`);
3. сделать схему воспроизводимой и проверяемой машинно (`PAT-NEW-7`);
4. исключить автоматизацию деструктивных операций (AR-204).

## 2. Исходное состояние стенда (заполняется инженером на хосте)

| Параметр | Значение | Примечание |
|---|---|---|
| `DEVICE_MODEL` | _заполнить_ | точная модель ASUS Vivobook (`OPEN-4`) |
| BIOS (версия, дата) | _заполнить_ | |
| Intel VMD/RST | _заполнить_ | `OPEN-2`: влияет на видимость NVMe установщиком |
| Secure Boot | _заполнить_ | `OPEN-3`: читается, не изменяется без ADR |
| NVMe (модель, прошивка, серийный) | _заполнить_ | |
| Ёмкость (декларированная / фактическая) | 480 ГБ / _заполнить_ | согласовать единицы (SI vs GiB, DEV-2) |
| Бэкап старой системы | _путь, объём, SHA256_ | обязателен до разметки (README §4.5) |

## 3. Выполненные операции (агент, 2026-10-01)

| # | Операция | Артефакт | Результат |
|---|---|---|---|
| 1 | Зафиксировано решение по схеме разметки | `ADR-0007-partition-scheme.md` | ACCEPTED |
| 2 | Оформлено исследование разметки | `docs/storage/partitioning_research.md` | DONE |
| 3 | Оформлены схемы разделов | `C_drive_schema.md`, `D_drive_schema.md` | DONE |
| 4 | Оформлены паттерны Stage 1 | `PAT-NEW-6`, `PAT-NEW-7`, `PAT-INDEX.md` | DONE |
| 5 | Оформлен ручной алгоритм подготовки железа | `algorithm/manual/Stage1_Hardware_Preparation.md` | DONE |
| 6 | Оформлен алгоритм разметки и верификации | `algorithm/auto/Stage1_DiskGenius_Partition.md` | DONE |
| 7 | Разработан скрипт верификации (read-only) | `scripts/Stage1_DiskGenius_Partition.ps1` | DONE |
| 8 | Прогон валидатора конвенций | `scripts/rules/Test-RepositoryConventions.ps1` | PASS |
| 9 | Закрытие `DEV-1`/`DEV-2` решением владельца | `ADR-0011-size-units-and-esp-mount.md` | ACCEPTED |
| 10 | Приведение схем и скрипта к единицам GiB, ESP без буквы | README §6/§7/§9.1, `docs/storage/*`, `scripts/Stage1_DiskGenius_Partition.ps1` | DONE |

## 4. Изменения и мутации

| Объект | Было | Стало | Паттерн | Бэкап |
|---|---|---|---|---|
| Разделы NVMe | — | — | — | — |

**Мутаций стенда на этом шаге не производилось.** Разметка относится к ручным деструктивным операциям (ADR-0007) и выполняется инженером; скрипт только читает состояние. Файловые операции ограничены репозиторием.

## 5. Верификация

### 5.1 Проверки схемы (V1–V7) — критерии, ожидающие нативного прогона

| ID | Проверка | Ожидание | Статус |
|---|---|---|---|
| `V1` | GPT + загрузочный диск UEFI | GPT, IsBoot = True | PENDING |
| `V2` | Типы разделов | EFI / MSR / Basic / Basic | PENDING |
| `W1` | ESP без буквы диска (ADR-0011) | `DriveLetter = $null` | PENDING |
| `V3` | Выравнивание 1 MiB | 4/4 раздела `Offset % 1 MiB == 0` | PENDING |
| `V4` | Размеры (MiB/GiB) | ESP 260 MiB (272 629 760 Б); MSR 16 MiB (16 777 216 Б); C: 200 GiB (214 748 364 800 Б); D: весь остаток ≈246.7 GiB | PENDING |
| `V5` | ФС и кластеры | FAT32 4 КБ; NTFS 4 КБ; NTFS 64 КБ | PENDING |
| `V6` | NTFS-параметры | `disable8dot3 D:` = 1; `disablelastaccess` = 1 | PENDING |
| `V7` | Бэкапы таблиц разделов | файлы на `F:\BACKUPS\` + SHA256 | PENDING |

Команда прогона:

```powershell
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1 -ExportReport ./docs/artifacts/Stage1_partition_verify.md
```

Результат (`Stage1_partition_verify.md`) прикладывается к коммиту, а статус этапа переводится в `DONE`.

### 5.2 Проверки, выполненные агентом

| Проверка | Результат |
|---|---|
| Валидатор конвенций репозитория (59+ файлов) | **PASS**, 0 нарушений |
| Баланс конструкций `scripts/Stage1_DiskGenius_Partition.ps1` | OK (`{}`, `()`, `[]` сбалансированы) |
| Соответствие скрипта конвенциям AR-401/AR-402 (шапка, Schema) | PASS (валидатор) |
| Отсутствие запрещённых токенов (AR-403/AR-404/AR-406) | PASS (валидатор) |

## 6. Метрики (§3.5 README)

| Метрика | Цель | Факт |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | 2/28 документировано (Stage 1: PAT-NEW-6, PAT-NEW-7) |
| `M_ADR_COUNT` | ≥1 на решение | ADR-0007 закрыт |
| `M_PARTITION_ALIGNMENT` | 1 MiB | PENDING (нативный прогон); единицы схемы — MiB/GiB (ADR-0011) |
| `M_DOC_FRESHNESS` | актуальность | 2026-10-01 |

## 7. Отклонения, открытые пункты, waivers

| ID | Тип | Описание | Требуемое действие |
|---|---|---|---|
| `DEV-1` | Документация | Точка монтирования ESP | **RESOLVED** (ADR-0011): ESP скрытая, без буквы диска; `F:` закреплена за USB-носителем, вариант `C:\EFI` отклонён |
| `DEV-2` | Единицы измерения | «ГБ» без указания системы (SI против GiB) | **RESOLVED** (ADR-0011): канонические единицы — MiB/GiB; байтовые эталоны зафиксированы; `D:` — весь остаток |
| `DEV-3` | Документация (закрыто) | `docs/research/anchor1.md` — ESP 100–250 МБ; README §6.3.2/§7.2 — 260 МБ | Закрыто в пользу 260 МБ (ADR-0007, §4.1 `partitioning_research.md`) |
| `OPEN-2` | Аппаратное | Состояние Intel VMD/RST не зафиксировано | Проверить в BIOS, записать в §2 |
| `OPEN-3` | Аппаратное | Состояние Secure Boot не зафиксировано; влияние на `DISABLE-LSA-ISOLATION/DISABLE-VBS` проверяется на Stage 4 (`H-001`) | Записать в §2; проверить на Stage 4 |
| `OPEN-4` | Аппаратное | Точная модель ноутбука | Записать в §2 |
| `LIM-1` | Инструментальное | Нативный PowerShell-прогон невозможен в песочнице агента | Выполнить на хосте Windows (команда в §5.1) |
| `DEV-3` | Документация | ESP 100–250 МБ в `anchor1` против 260 MiB в README | **RESOLVED**: утверждено 260 MiB (ADR-0007, §4.1 `partitioning_research.md`) |

Waivers: нет.

## 8. Артефакты этапа

| Артефакт | Путь | Статус |
|---|---|---|
| ADR | `docs/decisions/ADR-0007-partition-scheme.md` (rev.2); `docs/decisions/ADR-0011-size-units-and-esp-mount.md` | DONE |
| Исследование | `docs/storage/partitioning_research.md` | DONE |
| Схемы | `docs/storage/C_drive_schema.md`, `docs/storage/D_drive_schema.md` | DONE |
| Паттерны | `docs/patterns/PAT-NEW-6-partition-alignment.md`, `PAT-NEW-7-partition-scheme.md`, `PAT-INDEX.md` | DONE |
| Алгоритмы | `algorithm/manual/Stage1_Hardware_Preparation.md`, `algorithm/auto/Stage1_DiskGenius_Partition.md` | DONE |
| Скрипт верификации | `scripts/Stage1_DiskGenius_Partition.ps1` | DONE |
| Отчёт верификации | `docs/artifacts/Stage1_partition_verify.md` | PENDING (генерируется на хосте) |
| Бэкапы таблиц разделов | `F:\BACKUPS\` | PENDING (вне Git) |

## 9. Следующий шаг

1. На хосте Windows: выполнить §5.1, приложить `Stage1_partition_verify.md`, перевести отчёт в `DONE`.
2. `DEV-1`/`DEV-2` закрыты (ADR-0011); пересчётов больше не требуется.
3. Stage 2 — Ventoy-контур: `templates/ventoy.json.template`, `templates/u_w11_ltsc_iot.xml.template` (UTF-8 **без BOM**), `algorithm/manual/Stage2_Ventoy_Install.md`, `algorithm/auto/Stage2_Audit_Mode_Workflow.md`, `docs/storage/F_drive_schema.md`, `ADR-0005`.

---

<!-- AR-904: отчёт содержит метрики §3.5; файл UTF-8 без BOM, LF. -->
