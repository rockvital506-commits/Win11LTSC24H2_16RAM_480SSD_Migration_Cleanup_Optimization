# C_drive_schema.md — Схема системного накопителя (разделы EFI / MSR / Windows)

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | STORAGE-0002 |
| `DRIVE` | `C:\` (системный раздел NVMe SSD 480 ГБ) |
| `STAGE` | 1 (схема) |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | **APPROVED** (ADR-0007); runtime-структура наполняется на этапах 4–7 |
| `RELATED` | `ADR-0007`, `PAT-NEW-6`, `PAT-NEW-7`, `partitioning_research.md`, `D_drive_schema.md` |

---

## 1. Физический уровень

| Параметр | Значение |
|---|---|
| Устройство | NVMe SSD 480 ГБ |
| Таблица разделов | GPT |
| Режим загрузки | UEFI (Legacy MBR исключён) |
| Выравнивание | 1 MiB для всех разделов |

## 2. Таблица разделов

| # | Тип | ФС | Размер | Кластер | Монтирование | Метка | Назначение |
|---|---|---|---|---|---|---|---|
| 1 | EFI System Partition | FAT32 | 260 МБ | 4 КБ | `C:\EFI` (см. OPEN-1) | `EFI` | Загрузчик Windows, BCD, WinRE-ссылки |
| 2 | MSR | — | 16 МБ | — | hidden | `MSR` | Microsoft System Reserved |
| 3 | Windows | NTFS | 200 ГБ | 4 КБ | `C:\` | `Windows` | ОС, программы, профили |
| 4 | Data | NTFS | ~279 ГБ | 64 КБ | `D:\` | `Data` | ВМ, контейнеры, проекты, бэкапы конфигов |

> `OPEN-1`: в README §6.2 ESP указана как `F:\EFI`, в §7.2 — как `C:\EFI`. Расхождение вынесено на решение владельца (`GATE_PARTITIONING`); буква `F:` закреплена за USB-носителем (README §8), поэтому рабочая позиция — `C:\EFI`.

## 3. Проверка выравнивания

```
Все разделы выровнены по границе 1 MiB: ДА (критерий приёмки Stage 1)
Инструмент проверки: DiskGenius (post-create) + Stage1_DiskGenius_Partition.ps1
Допуск: 0 байт (Offset % 1 MiB == 0)
```

## 4. Структура `C:\` (целевое состояние после этапов 4–7)

```
C:\
├── Program Files\
│   ├── WindowsApps\                     (UWP — минимизированы на Stage 6)
│   └── <установленные приложения>       (winget, профиль base/devops)
├── Program Files (x86)\
├── ProgramData\
├── Users\
│   ├── devops\                          (создан на Stage 6)
│   ├── Default\                         (шаблон после CopyProfile, Stage 5)
│   ├── Public\
│   └── Administrator\                   (только Audit Mode, Stage 2–5)
├── Windows\
│   ├── System32\
│   │   ├── GroupPolicy\                 (NTFS Deny SYSTEM после Stage 6: PAT-11)
│   │   ├── drivers\etc\hosts            (NTFS Deny SYSTEM после Stage 6: PAT-11)
│   │   └── Sysprep\                     (unattend.xml на Stage 5: ADR-0005)
│   ├── WinSxS\                          (сжат через /ResetBase на Stage 4: PAT-18)
│   └── ...
├── Drivers\                             (INF-драйверы, Stage 4: PAT-15)
├── GD_Tool\                             (AutoSetup.bat, LGPO, CleanLTSCPolicy: Stage 6)
├── Vitality\                            (runtime-каталог, Stage 8)
└── Recovery\                            (WinRE)
```

## 5. Предполагаемый расход места (после Stage 4)

| Компонент | Объём | Комментарий |
|---|---|---|
| Windows LTSC IoT 24H2 | ~25 ГБ | после накопительных обновлений Stage 3 |
| Program Files | ~5 ГБ | VS Code, Visual C++, winget-пакеты |
| Users | ~10 ГБ | профиль `devops` + `Default` |
| WinSxS | ~5 ГБ | после `StartComponentCleanup /ResetBase` |
| pagefile.sys | 4 ГБ | фиксированный (Stage 4: PAT-13) |
| Temp / Cache | ~3 ГБ | периодическая очистка |
| **Резерв** | **~148 ГБ** | будущие обновления и приложения |
| **Итого C:\** | **200 ГБ** | |

## 6. Правила и ограничения

| Правило | Основание |
|---|---|
| Изменение размеров, ФС, кластеров или точек монтирования разделов 1–3 | `GATE_PARTITIONING`, обновление этого документа + ADR-0007 |
| hiberfil.sys | удаляется на Stage 4 (PAT-14), на `C:\` отсутствует |
| pagefile.sys | фиксированный 4096/4096 МБ на `C:\`, перенос на `D:\` не предусмотрен |
| Профили разработки, ВМ и контейнеры | размещаются на `D:\`, не на `C:\` (SC_SSD_LONGEVITY) |
| Тома Docker | только `D:\Docker` (AR-707) |

## 7. Верификация

```powershell
# Полная проверка схемы (read-only)
pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1 -ExportReport ./docs/artifacts/Stage1_partition_verify.md
```

Критерии: GPT; 4 раздела типов EFI/MSR/Basic; ESP 260 МБ FAT32; MSR 16 МБ; `C:` NTFS 200 ГБ кластер 4 КБ; выравнивание 1 MiB — 100 %.

---

<!-- Источник: README §6, §7, §9.1; ADR-0007; PAT-NEW-6/7. Файл UTF-8 без BOM, LF. -->
