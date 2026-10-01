# docs/devops/ — Схемы DevOps-контура

Документация домена `devops/`: WSL2 + Docker Engine + VMware через WHP API + политика P+E-ядер.

| Планируемый документ | Содержание | Статус |
|---|---|---|
| `WSL2_SCHEMA.md` | Дистрибутив, `.wslconfig` (processors/memory/pageReporting), `systemd=true`, размещение томов на `D:\Docker` | PLAN |
| `HYPERVISOR_MATRIX.md` | Сосуществование WSL2/Hyper-V/VMware: какие компоненты включены, `hypervisorlaunchtype`, WHP-режим | PLAN |
| `P_E_CORE_AFFINITY.md` | Метод определения P-ядер, маски, приоритеты, привязка vmmemWSL и сборок | PLAN |

**Правила домена:** AR-701 … AR-710. Сетевая изоляция на этапах 2–5 сохраняется (AR-709, §4.5 README).
