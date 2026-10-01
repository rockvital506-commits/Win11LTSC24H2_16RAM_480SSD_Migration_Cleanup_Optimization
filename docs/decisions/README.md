# docs/decisions/ — Architecture Decision Records

Формат: `ADR-NNNN-<TITLE>.md`. Обязательные поля: Context, Decision, Status, Consequences, Alternatives (§2.4 README). Шаблон: `templates/ADR-template.md`.

| ADR | Тема | Статус |
|---|---|---|
| `ADR-0001-stage-sequencing.md` | Последовательность этапов и гейты переходов | **ACCEPTED** (оформлен при аудите) |
| `ADR-0002-vmware-via-whp.md` | VMware через WHP API | **ACCEPTED** (Stage 7) |
| `ADR-0003-ntfs-deny-system.md` | NTFS Deny SYSTEM | **ACCEPTED** (Stage 6) |
| `ADR-0004-ohook-vs-kms.md` | Ohook вместо KMS | **ACCEPTED** (Stage 6) |
| `ADR-0005-dual-stage-unattend.md` | Двухэтапный unattend (Ventoy + Sysprep) | **ACCEPTED** |
| `ADR-0006-fdrive-as-repository.md` | F:\ как производный репозиторий (артефакты вне Git) | **ACCEPTED** (оформлен при аудите) |
| `ADR-0007-partition-scheme.md` | Схема разделов | **ACCEPTED (rev.2 — ADR-0011)** |
| `ADR-0008-repository-topology-domains.md` | Топология: домены + перенос research1 (rev.2: +`runtime/`, ADR-0017) | **ACCEPTED** |
| `ADR-0009-automation-rules-baseline.md` | Базовый свод правил автоматизации | **ACCEPTED** |
| `ADR-0010-pe-core-affinity-policy.md` | Политика привязки нагрузок к P+E-ядрам | **ACCEPTED** |
| `ADR-0011-size-units-and-esp-mount.md` | Единицы GiB и скрытая ESP | **ACCEPTED** |
| `ADR-0012-vbs-hvci-lsa-disable.md` | Демонтаж VBS/HVCI/LSA (реестр + BCD) | **ACCEPTED** |
| `ADR-0013-ssd-longevity-memory.md` | Долговечность SSD: hiberfil + фиксированная подкачка | **ACCEPTED** |
| `ADR-0014-sysprep-seal.md` | Запечатывание Sysprep: размещение файла ответов, CopyProfile, предпролётные защиты | **ACCEPTED** |
| `ADR-0015-stage6-immunity-contour.md` | Контур самозащиты Stage 6: порядок фаз, доверенная зона, транзакция | **ACCEPTED** |
| `ADR-0016-stage7-devops-contour.md` | Контур Stage 7: поставка дистрибутива, лимиты WSL2, нативный Docker, P+E | **ACCEPTED** |
| `ADR-0017-runtime-workspace.md` | Рабочая среда `C:\Vitality\`: домен `runtime/`, манифест состава, права без Deny | **ACCEPTED** (Stage 8) |

**Правило:** ADR-0001…ADR-0007 создаются на соответствующих этапах; ранние номера не занимаются задним числом без записи в отчёте.
