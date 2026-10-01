# Stage 1 (auto) — Разметка NVMe и верификация схемы

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | ALG-S1-AUTO |
| `STAGE` | 1 |
| `TYPE` | auto (с ручным выполнением деструктивных операций) |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | DONE |
| `RELATED` | `ADR-0007`, `PAT-NEW-6`, `PAT-NEW-7`, `scripts/Stage1_DiskGenius_Partition.ps1`, `docs/storage/*` |

---

## Состав этапа

| Часть | Выполняет | Автоматизация |
|---|---|---|
| A. Разметка | инженер вручную в DiskGenius (WinPE) | **не автоматизируется** (AR-204: необратимая операция) |
| B. Пост-настройка NTFS | инженер/скрипт на установленной ОС | `fsutil` — 3 команды |
| C. Верификация схемы | скрипт | `Stage1_DiskGenius_Partition.ps1` (read-only) |

## A. Разметка (DiskGenius, WinPE)

Предусловие: выполнен `algorithm/manual/Stage1_Hardware_Preparation.md`.

| # | Операция | Параметры |
|---|---|---|
| 1 | Резервная копия **старой** таблицы разделов | DiskGenius → Backup Partition Table → `F:\BACKUPS\` |
| 2 | Инициализация диска | GPT (Legacy MBR не использовать) |
| 3 | ESP | 260 МБ, FAT32, кластер 4 КБ, выравнивание **1 MiB**, метка `EFI` |
| 4 | MSR | 16 МБ, без ФС |
| 5 | Windows | 200 ГБ, NTFS, кластер 4 КБ, выравнивание 1 MiB, метка `Windows` |
| 6 | Data | ~279 ГБ (остаток), NTFS, кластер **64 КБ**, выравнивание 1 MiB, метка `Data` |
| 7 | Резервная копия **новой** таблицы разделов | DiskGenius → Backup Partition Table → `F:\BACKUPS\` |
| 8 | Проверка выравнивания | DiskGenius → Verify: все разделы на границе 1 MiB |

> **Единицы измерения (контрольный пункт):** суммы 200 + 279.7 ГБ сходятся с ёмкостью 480 ГБ только в десятичной системе (SI, 1 ГБ = 10⁹ байт). Если инженер вводит значения в двоичных единицах интерфейса (GiB), фактический размер `D:\` окажется ≈ 232 GiB. Фактические значения фиксируются верификацией (часть C) и, при отклонении, выносятся на `GATE_PARTITIONING`.

> **Точка монтирования ESP (`OPEN-1`):** README §6.2 указывает `F:\EFI`, §7.2 — `C:\EFI`. Буква `F:` закреплена за USB-носителем, поэтому до решения владельца ESP **не назначать букву** (оставить скрытой) — это безопасный вариант по умолчанию.

## B. Пост-настройка NTFS (после установки ОС)

Выполняется в Audit Mode (Stage 2/3) или на установленной системе:

```powershell
fsutil behavior set disable8dot3 D: 1        # отключить короткие имена 8.3 на томе данных
fsutil behavior set disablelastaccess 1      # не обновлять время последнего доступа
fsutil behavior set encryptpagingfile 0      # шифрование pagefile выключено (согласовано с PAT-13)
```

Размер и фиксация `pagefile.sys`, удаление `hiberfil.sys` — **Stage 4** (`PAT-13`, `PAT-14`), здесь не выполняются.

## C. Верификация схемы (скрипт)

```powershell
# Отчёт в консоль
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1

# С выгрузкой markdown-отчёта
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1 -ExportReport ./docs/artifacts/Stage1_partition_verify.md

# Другой номер диска / нестандартный допуск
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1 -DiskNumber 0 -SizeToleranceMB 512
```

Проверки: `V1` GPT+UEFI, `V2` типы разделов, `V3` выравнивание 1 MiB, `V4` размеры, `V5` ФС и кластеры, `V6` NTFS-параметры (`fsutil`).

Запуск возможен:
- из WinPE с PowerShell (если сборка WinPE содержит модуль `Storage`);
- на установленной ОС в Audit Mode — **рекомендуемый** вариант (полные данные о томах и `fsutil`).

Ненулевой код возврата (`10`) означает расхождение схемы: фиксируется в `Stage1_Report.md`, изменения разметки — только через `GATE_PARTITIONING`.

## Критерии приёмки (README §9.1)

- [ ] Бэкап таблицы разделов до разметки сохранён на `F:\BACKUPS\` + SHA256
- [ ] GPT создана корректно
- [ ] ESP: 260 МБ, FAT32, 1 MiB alignment
- [ ] MSR: 16 МБ
- [ ] `C:`: 200 ГБ, NTFS, 4 КБ кластер, 1 MiB alignment
- [ ] `D:`: ~279 ГБ, NTFS, 64 КБ кластер, 1 MiB alignment
- [ ] `fsutil disable8dot3 D:` = 1, `disablelastaccess` = 1
- [ ] `Stage1_Report.md` создан и заполнен
- [ ] `C_drive_schema.md`, `D_drive_schema.md`, `ADR-0007` созданы
- [ ] Верификация (`Stage1_DiskGenius_Partition.ps1`) — `PASS`

## Артефакты этапа

| Артефакт | Путь |
|---|---|
| Скрипт верификации | `scripts/Stage1_DiskGenius_Partition.ps1` |
| Исследование разметки | `docs/storage/partitioning_research.md` |
| Схемы | `docs/storage/C_drive_schema.md`, `docs/storage/D_drive_schema.md` |
| Решение | `docs/decisions/ADR-0007-partition-scheme.md` |
| Паттерны | `docs/patterns/PAT-NEW-6-partition-alignment.md`, `PAT-NEW-7-partition-scheme.md` |
| Отчёт | `docs/artifacts/Stage1_Report.md` |
| Бэкапы таблиц разделов | `F:\BACKUPS\` (вне Git) |

## Переход

Stage 2 — Ventoy-шаблон `u_w11_ltsc_iot.xml` и установка ОС в Audit Mode (`algorithm/manual/Stage2_Ventoy_Install.md`, `algorithm/auto/Stage2_Audit_Mode_Workflow.md`).

---

<!-- Файл UTF-8 без BOM, LF. -->
