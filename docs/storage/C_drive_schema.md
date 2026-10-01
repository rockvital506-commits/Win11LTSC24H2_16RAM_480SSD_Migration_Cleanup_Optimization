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
| `RELATED` | `ADR-0007` (rev.2), `ADR-0011`, `PAT-NEW-6`, `PAT-NEW-7`, `partitioning_research.md`, `D_drive_schema.md` |

---

## 1. Физический уровень

| Параметр | Значение |
|---|---|
| Устройство | NVMe SSD 480 ГБ |
| Таблица разделов | GPT |
| Режим загрузки | UEFI (Legacy MBR исключён) |
| Выравнивание | 1 MiB для всех разделов |

## 2. Таблица разделов

| # | Тип | ФС | Размер | Байты (эталон) | Кластер | Монтирование | Метка | Назначение |
|---|---|---|---|---|---|---|---|---|
| 1 | EFI System Partition | FAT32 | 260 MiB | 272 629 760 | 4 КБ | **скрытая, без буквы** | `EFI` | Загрузчик Windows, BCD, WinRE-ссылки |
| 2 | MSR | — | 16 MiB | 16 777 216 | — | hidden | `MSR` | Microsoft System Reserved |
| 3 | Windows | NTFS | 200 GiB | 214 748 364 800 | 4 КБ | `C:\` | `Windows` | ОС, программы, профили |
| 4 | Data | NTFS | весь остаток ≈246.7 GiB | по факту | 64 КБ | `D:\` | `Data` | ВМ, контейнеры, проекты, бэкапы конфигов |

> `OPEN-1` — **RESOLVED** (ADR-0011): ESP не получает буквы диска. Буква `F:` закреплена за USB-носителем (README §8); вариант `C:\EFI` отклонён как лишняя точка монтирования системного раздела.
> Единицы — MiB/GiB (двоичные); байтовые эталоны — ADR-0011, `partitioning_research.md` §4.5.

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
├── Vitality\                            (рабочая среда, Stage 8: ADR-0017, docs/runtime/RUNTIME_SCHEMA.md)
│   ├── bin\ config\ logs\ state\ workspace\ backup\   (состав — runtime/manifests/RuntimeManifest.json)
│   └── .vitality.json                   (маркер: SHA256 манифеста, AR-301)
└── Recovery\                            (WinRE)
```

## 5. Предполагаемый расход места (после Stage 4)

| Компонент | Объём | Комментарий |
|---|---|---|
| Windows LTSC IoT 24H2 | ~24 GiB | после накопительных обновлений Stage 3 |
| Program Files | ~5 GiB | VS Code, Visual C++, winget-пакеты |
| Users | ~9 GiB | профиль `devops` + `Default` |
| WinSxS | ~5 GiB | после `StartComponentCleanup /ResetBase` |
| pagefile.sys | 4 GiB | фиксированный (Stage 4: PAT-13) |
| Temp / Cache | ~3 GiB | периодическая очистка |
| **Резерв** | **~150 GiB** | будущие обновления и приложения |
| **Итого C:\** | **200 GiB** | эталон: 214 748 364 800 Б |

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

Критерии: GPT; 4 раздела типов EFI/MSR/Basic; ESP 260 MiB FAT32 **без буквы диска**; MSR 16 MiB; `C:` NTFS 200 GiB кластер 4 КБ; `D:` — весь остаток; выравнивание 1 MiB — 100 %.

---

<!-- Источник: README §6, §7, §9.1; ADR-0007; PAT-NEW-6/7. Файл UTF-8 без BOM, LF. -->
