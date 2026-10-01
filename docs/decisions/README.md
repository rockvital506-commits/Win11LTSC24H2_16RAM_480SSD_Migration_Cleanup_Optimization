# docs/decisions/ — Architecture Decision Records

Формат: `ADR-NNNN-<TITLE>.md`. Обязательные поля: Context, Decision, Status, Consequences, Alternatives (§2.4 README). Шаблон: `templates/ADR-template.md`.

| ADR | Тема | Статус |
|---|---|---|
| `ADR-0001-stage-sequencing.md` | Последовательность этапов | PLAN |
| `ADR-0002-vmware-via-whp.md` | VMware через WHP API | PLAN |
| `ADR-0003-ntfs-deny-system.md` | NTFS Deny SYSTEM | PLAN |
| `ADR-0004-ohook-vs-kms.md` | Ohook вместо KMS | PLAN |
| `ADR-0005-dual-stage-unattend.md` | Двухэтапный unattend | PLAN |
| `ADR-0006-fdrive-as-repository.md` | F:\ как производный репозиторий | PLAN |
| `ADR-0007-partition-scheme.md` | Схема разделов | PLAN |
| `ADR-0008-repository-topology-domains.md` | Топология: три домена + перенос research1 | **ACCEPTED** |
| `ADR-0009-automation-rules-baseline.md` | Базовый свод правил автоматизации | **ACCEPTED** |
| `ADR-0010-pe-core-affinity-policy.md` | Политика привязки нагрузок к P+E-ядрам | **ACCEPTED** |

**Правило:** ADR-0001…ADR-0007 создаются на соответствующих этапах; ранние номера не занимаются задним числом без записи в отчёте.
