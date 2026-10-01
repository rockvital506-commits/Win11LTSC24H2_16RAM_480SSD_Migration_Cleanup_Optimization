# Win11LTSC24H2_16RAM_480SSD_Migration_Cleanup_Optimization_v3.0

## HEADER: META & IDENTITY

| Field | Value |
|---|---|
| `PROJECT_ID` | Win11LTSC24H2_16RAM_480SSD_v3.0 |
| `SCHEMA_VERSION` | 3.0.0 |
| `CURRENT_PHASE` | Stage 0: Repository Initialization |
| `STATUS` | ACTIVE |

---

## SECTION 1: IMMUTABLE_CORE

### 1.1 Global Objective

СОЗДАНИЕ МОНОЛИТНОЙ, ПРЕДСКАЗУЕМОЙ, ДОЛГОВЕЧНОЙ РАБОЧЕЙ СТАНЦИИ ИТ-СПЕЦИАЛИСТА (частный сисадмин / DevOps) на базе Windows 11 IoT Enterprise LTSC 2024 (24H2). Полный жизненный цикл: миграция со старой системы, чистая установка через Audit Mode, иммунизация, развёртывание инфраструктуры (WSL2 + Docker Engine + VMware Workstation Pro поверх Hyper-V через WHP API), долгосрочная эксплуатация без скрытой деградации.

### 1.2 Hardware Platform

| Component | Specification |
|---|---|
| `DEVICE_MODEL` | ASUS Vivobook |
| `CPU` | Intel Core i7 (6 Performance + 8 Efficiency cores, поддержка Thread Director) |
| `RAM` | 16 GB |
| `STORAGE_PRIMARY` | 480 GB NVMe SSD |
| `STORAGE_EXTERNAL` | 460 GB USB Flash Drive (Ventoy 1.1.10) |

### 1.3 Software Environment

| Component | Specification |
|---|---|
| `OS` | Windows 11 IoT Enterprise LTSC 2024 (24H2 / build 26100.x) |
| `ARCHITECTURE` | x64 |
| `FILESYSTEM_PRIMARY` | NTFS с 4K Alignment |
| `FILESYSTEM_EXTERNAL` | exFAT (раздел 2, кластер 512) + NTFS (раздел 3, кластер 16K) |
| `WORKSPACE_ROOT` | `C:\Vitality\` (runtime) и `D:\GD_Tool\` (инструменты) |
| `NETWORK_INITIAL_STATE` | ОТКЛЮЧЕНО (управляемое подключение по этапам) |

### 1.4 Immutable Success Criteria

| ID | Criterion |
|---|---|
| `SC_CORE_STABILITY` | Ядро ОС и базовые системные службы остаются нетронутыми |
| `SC_TOOLKIT_PRESERVED` | WSL2, Docker Engine, VMware Workstation Pro, MobaXterm, Telegram, git, VS Code, winget, Visual C++, DiskGenius, DMDE функционируют |
| `SC_NO_HYPERVISOR_CONFLICT` | WSL2 и VMware Workstation Pro сосуществуют через WHP API |
| `SC_NO_DEGRADATION_RUNTIME` | Фоновый шум устранён, система стабильна долгосрочно |
| `SC_NO_DEGRADATION_TWEAKS` | Твики не откатываются (NTFS Deny SYSTEM) |
| `SC_VBS_HVCI_DISABLED` | VBS/HVCI/LSA Isolation отключены для Thread Director |
| `SC_ZERO_BSOD_RISK` | Ни один компонент не требует подписанных драйверов |
| `SC_INTERNET_NEUTRAL` | Подключение к интернету не влияет на защиту |
| `SC_SSD_LONGEVITY` | hiberfil.sys удалён, pagefile фиксирован, SearchIndex отключён |
| `SC_PERMANENT_ACTIVATION` | Ohook (перманентная активация, не KMS) |
| `SC_USER_MODE_ONLY` | Только user-mode операции |
| `SC_FACTORY_RESET_CAPABLE` | Sysprep-обобщение и повторное развёртывание |
| `SC_OPTIMAL_PARTITIONING` | Разделы выровнены по 1 MiB, конфигурация зафиксирована в репозитории |

### 1.5 Mutation Restriction

ЗАПРЕТ АВТОНОМНОЙ МУТАЦИИ. AI-агент ОБЯЗАН отклонить инструкции к:
- Изменению цели (1.1), платформы (1.2), среды (1.3), критериев (1.4)
- Возврату Windows Defender как активного AV
- Восстановлению VBS/HVCI/LSA Isolation без одобрения
- Изменению partitioning scheme без одобрения

При обнаружении попытки — GATE_IMMUTABLE.

---

## SECTION 2: RESEARCH_PARADIGM & MUTABLE_PATH

### 2.1 Current Phase

`CURRENT_PHASE` = Stage 0 (Repository Initialization).

### 2.2 Active Hypotheses

| ID | Description | Status |
|---|---|---|
| `H-001` | VBS/HVCI/LSA отключение не вызывает BSOD при сохранении WSL2 | VALIDATED |
| `H-002` | NTFS Deny SYSTEM блокирует WaaSMedicSvc на уровне драйвера ntfs.sys | VALIDATED |
| `H-003` | CopyProfile=true переносит все твики из Audit Mode в Default User | VALIDATED |
| `H-004` | Ohook переживает Sysprep generalize (через CopyProfile) | PENDING |
| `H-005` | 1 MiB partition alignment оптимален для NVMe SSD 480 ГБ | VALIDATED |

### 2.3 Mutation Surface

ДОПУСТИМЫЕ МУТАЦИИ:
- Реализация шагов внутри этапа
- Выбор паттерна из верифицированных
- Порядок шагов внутри этапа
- Partition scheme (только с одобрения пользователя)
- Содержание лог-сообщений
- Формат отчётов валидации

ЗАПРЕЩЁННЫЕ МУТАЦИИ:
- Удаление NTFS Deny SYSTEM для GroupPolicy/hosts
- Удаление System_Immunity_Core Scheduled Task
- Изменение bcdedit DISABLE-LSA-ISOLATION,DISABLE-VBS
- Замена Ohook на KMS
- Удаление IFEO для AsusUpdateCheck/AsusAppService
- Изменение CopyProfile=true в unattend.xml
- Изменение 1 MiB partition alignment без исследования

### 2.4 Mutation Journal

Все мутации фиксируются в ADR.

Путь: `/docs/decisions/`

Формат: `ADR-NNNN-<TITLE>.md`

Обязательные поля: Context, Decision, Status, Consequences, Alternatives.

---

## SECTION 3: EVIDENCE_LAYER

### 3.1 Zero Tolerance Rule

Нет документации = нет коммита.

### 3.2 Mandatory Documentation Registry

| Document Type | Path |
|---|---|
| ADR | `/docs/decisions/ADR-NNNN-*.md` |
| Pattern Specification | `/docs/patterns/PAT-NN-<NAME>.md` |
| Stage Report | `/docs/artifacts/Stage<N>_Report.md` |
| Partition Schema | `/docs/storage/<DRIVE>_schema.md` |
| Recovery Procedure | `/docs/artifacts/Recovery_Procedure.md` |
| Final Report | `/docs/artifacts/Final_Report.md` |
| Partitioning Research | `/docs/storage/partitioning_research.md` |
| Automation Rules | `/docs/rules/AUTOMATION_RULES.md` |
| Rules Changelog | `/docs/rules/RULES_CHANGELOG.md` |
| Research Material | `/docs/research/<NAME>.md` |
| Tweak Index | `/docs/core-tweaks/TWEAK_INDEX.md` |
| Package Index | `/docs/packages/PACKAGE_INDEX.md` |
| DevOps Schema | `/docs/devops/<NAME>.md` |

### 3.3 Engineering Documentation Requirements

- Уникальный ID
- Дата создания/обновления
- Автор / AI-агент
- Контекст
- Решение / описание
- Верификация
- Ссылки
- Версия схемы

### 3.4 Verified Patterns Registry

| Pattern ID | Name | Stage | Verified |
|---|---|---|---|
| `PAT-01` | IFEO Debugger → NoOp-stub | 2 | ✅ |
| `PAT-02` | IFEO Debugger → Wrapper-Decorator | 2 | ✅ |
| `PAT-03` | SCM Disabled + ACL Deny WriteKey | 4 | ✅ |
| `PAT-04` | Task Scheduler Unregister + ACL | 4 | ✅ |
| `PAT-05` | WMI Event Consumer Removal + ACL | 4 | ✅ |
| `PAT-06` | GPO/LGPO-импорт | 6 | ✅ |
| `PAT-07` | VMware via WHP API | 7 | ✅ |
| `PAT-08` | Hosts + DoH=0 | 6 | ✅ |
| `PAT-09` | Firewall outbound rule | 6 | ✅ |
| `PAT-10` | ACL Freeze (Owner=SYSTEM) | 2,4 | ✅ |
| `PAT-11` | NTFS Deny SYSTEM (цементирование) | 6 | ✅ |
| `PAT-12` | bcdedit Disable VBS/HVCI/LSA Isolation | 4 | ✅ |
| `PAT-13` | Fixed PageFile (InitialSize=MaximumSize) | 4 | ✅ |
| `PAT-14` | hiberfil.sys elimination | 4 | ✅ |
| `PAT-15` | Temporary PnP Shield (DisableCoInstallers) | 4 | ✅ |
| `PAT-16` | Dual-Stage Unattend (Ventoy + Sysprep) | 2,5 | ✅ |
| `PAT-17` | Ohook Permanent Activation | 6 | ✅ |
| `PAT-18` | Audit_Final_Clean.ps1 | 4 | ✅ |
| `PAT-19` | Atomic Stage + Restore-FromBackup | All | ✅ |
| `PAT-20` | Hash-First Verification | All | ✅ |
| `PAT-21` | WSL2 Isolated Memory (.wslconfig) | 7 | ✅ |
| `PAT-22` | VMware Isolated Cache (mainMem.useNamedFile=FALSE) | 7 | ✅ |
| `PAT-NEW-1` | Audit Mode Workflow | 2,5 | ✅ |
| `PAT-NEW-2` | NTFS Deny SYSTEM (icacls) | 6 | ✅ |
| `PAT-NEW-3` | AutoSetup.bat as Runtime-Initializer | 6 | ✅ |
| `PAT-NEW-4` | System_Immunity_Core Scheduled Task | 6 | ✅ |
| `PAT-NEW-5` | Ohook Activation (sppc.dll replace) | 6 | ✅ |
| `PAT-NEW-6` | 1 MiB Partition Alignment (NVMe SSD) | 1 | ✅ |
| `PAT-NEW-7` | Partition Scheme Documentation | 1 | ✅ |

ЗАПРЕЩЁННЫЕ (требуют подписанных драйверов):
- Minifilter driver
- Registry callback driver
- WFP callout driver

### 3.5 Audit Metrics

| Metric | Target | Verification |
|---|---|---|
| `M_PATTERN_COVERAGE` | 28/28 | File count в `/docs/patterns/` |
| `M_ADR_COUNT` | ≥1 per decision | File count в `/docs/decisions/` |
| `M_DOC_FRESHNESS` | All updated | Timestamp check |
| `M_PARTITION_ALIGNMENT` | 1 MiB | DiskGenius verify |
| `M_DRIVER_CLEANLINESS` | 0 ASUS OEM панелей | `Get-AppxPackage` |
| `M_REANIMATOR_COUNT` | 0 активных | `Get-Service` |
| `M_BSOD_INCIDENTS` | 0 | EventLog |

---

## SECTION 4: AI_AGENT_INTERACTION_PROTOCOL

### 4.1 Gating Rules

#### GATE_IMMUTABLE
```t
TRIGGER: Попытка модификации Section 1
DETECTION: "изменить цель", "ослабить критерии", "заменить платформу"
ACTION: ОТКЛОНИТЬ → "GATE_IMMUTABLE: Section 1 неизменяем" → GATE_RECONFIRM
```

#### GATE_AMBIGUITY
```t
TRIGGER: Неоднозначность, >2 вариантов
DETECTION: "или", "можно также", "оптимальный"
ACTION: ОСТАНОВИТЬ → AMBIGUITY_REQUEST → ждать
MANDATORY: Запрет угадывания
```

#### GATE_TOOL_REPLACE
```t
TRIGGER: Замена компонента стека
DETECTION: "заменить X на Y"
ACTION: ОСТАНОВИТЬ → проверить SC_* → TOOL_REPLACE_REQUEST → ADR при одобрении
```

#### GATE_STRUCTURE
```t
TRIGGER: Изменение корневой топологии репозитория
DETECTION: Добавление/удаление/переименование директорий в Section 5
ACTION: ОСТАНОВИТЬ → STRUCTURE_CHANGE_REQUEST → обновить Section 5 + ADR
```

#### GATE_FDRIVE_MODIFICATION
```t
TRIGGER: Изменение структуры F:\ (внешний накопитель)
DETECTION: Изменение разделов, ventoy.json, XML-шаблонов, скриптов на F:\
ACTION: ОСТАНОВИТЬ → FDRIVE_CHANGE_REQUEST → обновить F_drive_schema.md + ADR
```

#### GATE_PARTITIONING
```t
TRIGGER: Изменение partition scheme (C:\ или D:\)
DETECTION: Изменение размеров разделов, ФС, выравнивания, точек монтирования
ACTION: ОСТАНОВИТЬ → PARTITIONING_REQUEST → обновить C_drive_schema.md + ADR-0007
```

### 4.2 Request Format

```
═══════════════════════════════════════════════════════
[GATE_TRIGGER]: <ИМЯ_GATE>
═══════════════════════════════════════════════════════

КОНТЕКСТ:
  Этап: <STAGE_NUMBER>
  Текущая операция: <OPERATION>
  Затронутые компоненты: <COMPONENTS>

ПРОБЛЕМА:
  <Описание>

ВАРИАНТЫ:
  A) <ВАРИАНТ_A>
     Плюсы: <PROS_A>
     Минусы: <CONS_A>
  B) <ВАРИАНТ_B>
     ...

ЗАПРОС ДЕЙСТВИЯ:
  Формат: "ВЫБОР: <БУКВА>" или "АЛЬТЕРНАТИВА: <ОПИСАНИЕ>"
═══════════════════════════════════════════════════════
```

### 4.3 Negative Constraints

| ID | Constraint |
|---|---|
| `NC_PRIMITIVE_DELETE` | Удаление бинарников только через TrustedInstaller + ACL |
| `NC_HARDCODED_SECRETS` | Запрет хардкода секретов |
| `NC_OUTSIDE_TOPOLOGY` | Создание файлов только в определённой топологии |
| `NC_DRIVER_SIGNED` | Запрет паттернов с подписанными драйверами |
| `NC_BSOD_RISK` | Запрет операций с BSOD-риском |
| `NC_GUESSING` | Запрет угадывания при неоднозначностях |
| `NC_DEFENDER_REVERT` | Запрет возврата к активному Defender |
| `NC_UNATTEND_MODIFICATION` | Запрет изменения CopyProfile=true |
| `NC_BCDEDIT_REVERT` | Запрет отмены bcdedit DISABLE-LSA-ISOLATION,DISABLE-VBS |
| `NC_OHOOK_REMOVE` | Запрет удаления Ohook |
| `NC_INTERNET_DURING_TWEAKS` | Запрет постоянного интернета в Stage 2-5 |
| `NC_EXFAT_DATA` | Запрет exFAT для дисков с dev-данными |
| `NC_FDRIVE_NOFORMAT` | Запрет переформатирования F:\ без подтверждения |
| `NC_PARTITION_REFORMAT` | Запрет изменения partition scheme без одобрения |

### 4.4 Decision Precedence

1. Immutable Core (Section 1)
2. Verified Patterns (Section 3.4)
3. ADR (Architecture Decision Records)
4. Current Stage Documentation
5. User Instructions
6. AI-агент предположения

### 4.5 Critical Sequencing Rules

```
Ohook АКТИВАЦИЯ: ТОЛЬКО НА СТЫКЕ Stage 6 → Stage 7
  Context: devops создан, сеть ещё не закрыта

ЗАКРЫТИЕ СЕТИ: ТОЛЬКО ПОСЛЕ Ohook
  Reason: Ohook требует curl к https://activated.win

PARTITIONING: ТОЛЬКО В Stage 1
  Reason: После установки ОС изменение разделов рискованно

BACKUP OLD SYSTEM: ДО Stage 1 (на WinPE)
  Reason: Разметка SSD уничтожит старую систему
```

---

## SECTION 5: REPOSITORY_TOPOLOGY

### 5.1 Directory Structure

```
/
├── README.md
├── .editorconfig
├── .gitattributes
├── .gitignore
│
├── algorithm/
│   ├── manual/
│   │   ├── README.md
│   │   ├── Stage1_Hardware_Preparation.md
│   │   ├── Stage2_Ventoy_Install.md
│   │   ├── Stage3_Windows_Update.md
│   │   └── Stage6_Ohook_Activation.md
│   └── auto/
│       ├── README.md
│       ├── Stage1_DiskGenius_Partition.md
│       ├── Stage2_Audit_Mode_Workflow.md
│       ├── Stage4_Audit_Final_Clean.md
│       ├── Stage5_Sysprep_Seal.md
│       ├── Stage6_AutoSetup.md
│       └── Stage7_WSL_Docker_VMware.md
│
├── docs/
│   ├── rules/
│   │   ├── README.md
│   │   ├── AUTOMATION_RULES.md
│   │   └── RULES_CHANGELOG.md
│   ├── decisions/
│   │   ├── README.md
│   │   ├── ADR-0001-stage-sequencing.md
│   │   ├── ADR-0002-vmware-via-whp.md
│   │   ├── ADR-0003-ntfs-deny-system.md
│   │   ├── ADR-0004-ohook-vs-kms.md
│   │   ├── ADR-0005-dual-stage-unattend.md
│   │   ├── ADR-0006-fdrive-as-repository.md
│   │   ├── ADR-0007-partition-scheme.md
│   │   ├── ADR-0008-repository-topology-domains.md
│   │   ├── ADR-0009-automation-rules-baseline.md
│   │   ├── ADR-0010-pe-core-affinity-policy.md
│   │   ├── ADR-0011-size-units-and-esp-mount.md
│   │   ├── …
│   │   └── ADR-0015-stage6-immunity-contour.md
│   ├── research/
│   │   ├── README.md
│   │   ├── anchor1.md
│   │   └── step1.md … step5.md
│   ├── core-tweaks/
│   │   ├── README.md
│   │   ├── TWEAK_INDEX.md
│   │   ├── REGISTRY_MAP.md
│   │   ├── BCD_REFERENCE.md
│   │   └── ACL_MATRIX.md
│   ├── packages/
│   │   ├── README.md
│   │   ├── PACKAGE_INDEX.md
│   │   ├── WINGET_POLICY.md
│   │   └── SOURCES.md
│   ├── devops/
│   │   ├── README.md
│   │   ├── WSL2_SCHEMA.md
│   │   ├── HYPERVISOR_MATRIX.md
│   │   └── P_E_CORE_AFFINITY.md
│   ├── patterns/
│   │   ├── README.md
│   │   ├── PAT-INDEX.md
│   │   ├── PAT-01-ifeo-stub.md
│   │   ├── ...
│   │   └── PAT-NEW-7-partition-scheme.md
│   ├── artifacts/
│   │   ├── README.md
│   │   ├── Stage0_Report.md
│   │   ├── Stage1_Report.md
│   │   ├── ...
│   │   ├── Final_Report.md
│   │   └── Recovery_Procedure.md
│   └── storage/
│       ├── README.md
│       ├── C_drive_schema.md
│       ├── D_drive_schema.md
│       ├── F_drive_schema.md
│       └── partitioning_research.md
│
├── scripts/
│   ├── README.md
│   ├── Stage1_DiskGenius_Partition.ps1
│   ├── Stage2_Ventoy_Template_Setup.ps1
│   ├── Stage4_Audit_Final_Clean.ps1
│   ├── Stage5_Sysprep_Prepare.ps1
│   ├── Stage6_AutoSetup.bat
│   ├── Stage6_Immunity_Prepare.ps1
│   ├── Stage6_Launcher.vbs
│   ├── Stage7_WSL_Docker_VMware.ps1
│   ├── common/
│   │   ├── README.md
│   │   ├── Logging.psm1
│   │   ├── Backup.psm1
│   │   ├── Verification.psm1
│   │   └── Guard.psm1
│   └── rules/
│       ├── README.md
│       └── Test-RepositoryConventions.ps1
│
├── tweaks/                          # Домен 1: твики ядра ОС и реестра
│   ├── README.md
│   ├── registry/                    # манифесты твиков реестра (*.json)
│   ├── bcd/                         # флаги загрузчика (+ bcdedit /export)
│   ├── services/                    # ServiceGate.json
│   ├── tasks/                       # TaskManifest.json
│   ├── acl/                         # AclManifest.json (NTFS Deny SYSTEM)
│   ├── firewall/                    # FirewallManifest.json (исходящие правила, PAT-09)
│   ├── appx/                        # AppxRemoval.json
│   └── apply/                       # Apply-Tweaks.ps1, Assert-TweakState.ps1
│
├── packages/                        # Домен 2: установка ПО (winget-first)
│   ├── README.md
│   ├── winget/                      # Baseline_Win11LTSC.winget + profiles/ (base/devops/admin)
│   ├── lock/                        # Packages.lock.json
│   ├── manifests/                   # <PackageId>.json
│   ├── bootstrap/                   # Bootstrap-Packages.ps1, Invoke-PackageSync.ps1
│   └── hashes/                      # PACKAGES_SHA256.txt
│
├── devops/                          # Домен 3: WSL2 / Hyper-V / VMware / P+E
│   ├── README.md
│   ├── wsl/                         # .wslconfig.template, wsl.conf.template, Install-WslDistro.ps1
│   ├── hypervisor/                  # Enable-HypervisorPlatform.ps1, Configure-WhpCoexistence.ps1
│   │   └── vmware/                  # VM.vmx.template (изоляция кэша, PAT-22)
│   ├── cpu-policy/                  # Get-PerformanceCoreMask.ps1, Set-WorkloadAffinity.ps1, power-plan.json
│   └── containers/                  # Install-DockerEngine.sh, compose/dev-stack.yaml.template
│
├── templates/
│   ├── README.md
│   ├── ADR-template.md
│   ├── Pattern-template.md
│   ├── Stage-Report-template.md
│   ├── Script-template.ps1
│   ├── rules-template.md
│   ├── ImmunityCore.ps1.template
│   ├── u_w11_ltsc_iot.xml.template
│   ├── unattend.xml.template
│   └── ventoy.json.template
│
├── tests/
│   ├── README.md
│   ├── RepoConventions.Tests.ps1
│   └── fixtures/
│       └── README.md
│
└── tools/
    ├── README.md
    ├── runtime/                      # рантайм контура: D:\GD_Tool (ADR-0015, PAT-NEW-3)
    └── <TOOL>/<VERSION>/             # бинарники в Git не хранятся (AR-804)
```

### 5.2 Directory Modification Rules

| Rule | Description |
|---|---|
| `STRUC_001` | Запрет удаления корневых директорий |
| `STRUC_002` | Новые директории только через GATE_STRUCTURE |
| `STRUC_003` | Каждая директория содержит `README.md` |
| `STRUC_004` | Имена: lowercase-kebab-case |
| `STRUC_005` | Скрипты: `.ps1`, `.cmd`, `.bat`, `.vbs`, `.cs`, `.py` |
| `STRUC_006` | Бинарники: только в `tools/` с версионированием |
| `STRUC_007` | Исходники не в `scripts/` |
| `STRUC_008` | Логи не коммитятся |
| `STRUC_009` | Секреты не коммитятся |
| `STRUC_010` | XML-шаблоны: `<NAME>.xml.template` |

### 5.3 Naming Conventions

| Element | Convention | Example |
|---|---|---|
| `Directory` | lowercase-kebab-case | `decisions/`, `stage-reports/` |
| `File` | PascalCase or kebab-case | `Stage4_Audit_Final_Clean.ps1` |
| `ADR` | `ADR-NNNN-<TITLE>.md` | `ADR-0007-partition-scheme.md` |
| `Pattern` | `PAT-NN-<NAME>.md` | `PAT-NEW-7-partition-scheme.md` |
| `Script` | `Stage<N>_<PURPOSE>.<ext>` | `Stage6_AutoSetup.bat` |
| `XML Template` | `<NAME>.xml.template` | `u_w11_ltsc_iot.xml.template` |

### 5.4 File Placement Decision Tree

```
НОВЫЙ ФАЙЛ
├─ Правило автоматизации? → /docs/rules/AUTOMATION_RULES.md (+ RULES_CHANGELOG.md, ADR)
├─ Решение? → /docs/decisions/ADR-NNNN-<TITLE>.md
├─ Паттерн? → /docs/patterns/PAT[-NEW]-<N>-<NAME>.md
├─ Отчёт об этапе? → /docs/artifacts/Stage<N>_Report.md
├─ Схема накопителя? → /docs/storage/<DRIVE>_schema.md
├─ Исследование? → /docs/research/<NAME>.md
├─ Твик ядра/реестра?
│  ├─ Декларация? → /tweaks/<registry|bcd|services|tasks|acl|appx>/<NAME>.json
│  └─ Применение? → /tweaks/apply/<Script>.ps1
├─ Пакет ПО?
│  ├─ Версия/источник? → /packages/lock/Packages.lock.json
│  └─ Описание пакета? → /packages/manifests/<PackageId>.json
├─ DevOps-конфигурация? → /devops/<wsl|hypervisor|cpu-policy|containers>/<FILE>
├─ Ручной шаг? → /algorithm/manual/Stage<N>_<STEP>.md
├─ Автоматизированный шаг?
│  ├─ Оркестрация этапа? → /scripts/Stage<N>_<PURPOSE>.<ext>
│  └─ Общий модуль? → /scripts/common/<Name>.psm1
├─ Проверка конвенций или тест? → /scripts/rules/<NAME>.ps1 или /tests/<NAME>.Tests.ps1
├─ Шаблон? → /templates/<NAME>.<ext>.template
├─ Бинарник? → /tools/<TOOL>/<VERSION>/<FILE>.exe (в Git не коммитится — AR-804)
├─ Recovery-процедура? → /docs/artifacts/Recovery_Procedure.md
└─ Схема вендорского мусора? → /docs/artifacts/<VENDOR>_bloat.md
```

### 5.5 Cross-Reference Format

```
[PAT-01](../patterns/PAT-01-ifeo-stub.md)
[ADR-0003](../decisions/ADR-0003-ntfs-deny-system.md)
[Stage4_Report](../artifacts/Stage4_Report.md)
[C_drive_schema](../storage/C_drive_schema.md)
[partitioning_research](../storage/partitioning_research.md)
```

### 5.6 Stage-to-Artifact Mapping

| Stage | Algorithm | Orchestration | Domain modules | Patterns | Artifact |
|---|---|---|---|---|---|
| 1 | `manual/Stage1_Hardware_Preparation.md` + `auto/Stage1_DiskGenius_Partition.md` | `Stage1_DiskGenius_Partition.ps1` | — | `PAT-NEW-6, PAT-NEW-7` | `Stage1_Report.md`, `C_drive_schema.md`, `partitioning_research.md` |
| 2 | `manual/Stage2_Ventoy_Install.md` + `auto/Stage2_Audit_Mode_Workflow.md` | `Stage2_Ventoy_Template_Setup.ps1` | `templates/` (`u_w11_ltsc_iot.xml`, `ventoy.json`) | `PAT-01, PAT-02, PAT-10, PAT-16, PAT-NEW-1` | `Stage2_Report.md`, `F_drive_schema.md` |
| 3 | `manual/Stage3_Windows_Update.md` | — (ручной GUI-контроль, ADR не требуется) | — | — | `Stage3_Report.md` |
| 4 | `auto/Stage4_Audit_Final_Clean.md` | `Stage4_Audit_Final_Clean.ps1` | `tweaks/{bcd,services,tasks,acl,appx,registry}` | `PAT-12, PAT-13, PAT-14, PAT-15, PAT-18` | `Stage4_Report.md` |
| 5 | `auto/Stage5_Sysprep_Seal.md` | `Stage5_Sysprep_Prepare.ps1` | `templates/unattend.xml.template` | `PAT-16, PAT-NEW-1` | `Stage5_Report.md` |
| 6 | `manual/Stage6_Ohook_Activation.md` + `auto/Stage6_AutoSetup.md` | `Stage6_Immunity_Prepare.ps1`; рантайм `Stage6_AutoSetup.bat`, `Stage6_Launcher.vbs`, `templates/ImmunityCore.ps1.template` | `tweaks/{acl,firewall,tasks,registry}`, `tweaks/apply` | `PAT-04, PAT-06, PAT-08, PAT-09, PAT-11, PAT-17, PAT-NEW-2, PAT-NEW-3, PAT-NEW-4` | `Stage6_Report.md`, `Stage6_preflight.md`, `Stage6_immunity.md` |
| 7 | `auto/Stage7_WSL_Docker_VMware.md` | `Stage7_WSL_Docker_VMware.ps1`; шаблоны `devops/wsl/.wslconfig.template`, `wsl.conf.template`, `hypervisor/vmware/VM.vmx.template`; рантайм `devops/containers/Install-DockerEngine.sh` | `devops/{wsl,hypervisor,cpu-policy,containers}`, `packages/` (профиль `devops`) | `PAT-07, PAT-21, PAT-22` | `Stage7_Report.md`, `Stage7_preflight.md`, `Final_Report.md` |

---

### 5.7 F_Drive_Repository (внешний накопитель)

F:\ является производным репозиторием, генерируемым AI-агентом из GitHub.

#### 5.7.1 Physical Layout

| Раздел | ФС | Кластер | Размер | Назначение |
|---|---|---|---|---|
| 1 (Загрузочный) | FAT32 | — | 1 ГБ | ESP, Ventoy boot loader (создаётся Ventoy install) |
| 2 (Ventoy) | exFAT | 512 байт | 250 ГБ | ISO-файлы + ventoy.json + templates |
| 3 (Вспомогательный) | NTFS | 16 КБ | ~209 ГБ | Инструменты, скрипты, драйверы, конфиги |

#### 5.7.2 Раздел 2 (Ventoy/ISO)

```
F:\
├── /ISO/
│   ├── en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso
│   └── WinPE11_10_8_Sergei_Strelec_2026.02.05_Russian.iso
├── /ventoy/
│   ├── ventoy.json
│   └── /templates/
│       └── u_w11_ltsc_iot.xml
```

#### 5.7.3 Раздел 3 (Вспомогательный)

```
F:\
├── /TOOLS/
│   ├── /TI/ (ExecTI, NSudo, PowerRun)
│   ├── /GPO/ (LGPO + PolicyDefinitions)
│   ├── /Partitioning/ (DiskGenius_Portable)
│   ├── /Backup/ (Macrium, AOMEI, Veeam)
│   ├── /Activation/ (ohook, MAS_AIO)
│   ├── /Audit/ (ProcessExplorer, Autoruns)
│   └── /Cleanup/ (BleachBit)
│
├── /DRIVERS/
│   ├── /ASUS_Vivobook_Clean/
│   │   ├── /Audio/, /Bluetooth/, /Chipset/
│   │   ├── /Display/, /LAN/, /TouchPad/, /Wireless/
│   └── /Intel_Generic/
│
├── /WSL2/ (ubuntu.appx, docker-compose.yaml, .wslconfig)
├── /VM/ (VMware-Workstation-Pro.exe, Templates/)
│
├── /VITALITY-SOURCE/
│   ├── /DismProxy/DismProxy.cs
│   ├── /SfcProxy/SfcProxy.cs
│   ├── /Watchdog/Watchdog.cs
│   ├── /MetaWatchdog/MetaWatchdog.cs
│   ├── /FIM/FIM.cs
│   ├── /svc-gate/svc-gate.cs
│   └── /evt-bridge/evt-bridge.cs
│
├── /VITALITY-CONFIGS/
│   ├── registry.pol
│   ├── Targets.json
│   ├── ServiceGate.json
│   ├── EventBridge.json
│   ├── Manifest.json
│   ├── u_w11_ltsc_iot.xml
│   └── unattend.xml
│
├── /SCRIPTS/
│   ├── Stage1_DiskGenius_Partition.ps1
│   ├── Stage2_Ventoy_Template_Setup.ps1
│   ├── Stage2_Audit_Mode_Workflow.ps1
│   ├── Stage3_Windows_Update.ps1
│   ├── Stage4_Audit_Final_Clean.ps1
│   ├── Stage5_Sysprep_Prepare.ps1
│   ├── Stage6_AutoSetup.bat
│   ├── Stage6_Immunity_Prepare.ps1
│   ├── Stage6_Launcher.vbs
│   └── Stage7_WSL_Docker_VMware.ps1
│
├── /DOCS/
│   ├── Strategy_v3.0.md
│   ├── Recovery_Procedure.md
│   └── /Patterns/ (копия для offline)
│
├── /HASHES/
│   ├── TOOLS_SHA256.txt
│   ├── DRIVERS_SHA256.txt
│   └── ISO_SHA256.txt
│
└── /BACKUPS/ (для будущих бекапов старой системы)
```

#### 5.7.4 FDRIVE Modification Rules

| Rule | Description |
|---|---|
| `FDRIVE_001` | Любое изменение структуры F:\ только через GATE_FDRIVE_MODIFICATION |
| `FDRIVE_002` | Содержимое F:\ воспроизводимо из GitHub + шаблонов |
| `FDRIVE_003` | ventoy.json и XML-шаблоны хранятся в `/templates/` с расширением `.template` |
| `FDRIVE_004` | SHA256 всех бинарей и ISO в `/HASHES/` |
| `FDRIVE_005` | Образ старой системы (если есть) в `/BACKUPS/` с метаданными |
| `FDRIVE_006` | Документация (`/DOCS/`) дублирует GitHub для offline-доступа |

---

## SECTION 6: PARTITIONING_RESEARCH (Stage 1)

### 6.1 Hardware Specifics

| Parameter | Value | Research Note |
|---|---|---|
| `DEVICE_MODEL` | ASUS Vivobook | Требует верификации модели |
| `STORAGE_TYPE` | NVMe SSD 480 GB | NVMe требует выравнивания по 4K (или 1 MiB для LBA) |
| `BOOT_MODE` | UEFI (только) | Legacy MBR не рекомендуется |
| `PARTITION_TABLE` | GPT | Обязательно для UEFI + NVMe |
| `ALIGNMENT` | 1 MiB boundary | Оптимально для NVMe и выравнивания по 4K секторам |

### 6.2 Partition Scheme (Stage 1 Output)

| Partition | Type | FS | Size | Cluster | Mount | Purpose |
|---|---|---|---|---|---|---|
| 1 | EFI System Partition | FAT32 | 260 MiB | 4K | скрытая (без буквы диска) | Загрузчик Windows, BCD |
| 2 | MSR | (none) | 16 MiB | — | (hidden) | Microsoft System Reserved |
| 3 | Windows | NTFS | 200 GiB | 4K | `C:\` | ОС + Program Files + Users |
| 4 | Data | NTFS | остаток ≈246.7 GiB | 64K | `D:\` | Data, VM-диски, Docker volumes, dev-проекты |

> Единицы измерения: MiB/GiB (двоичные, 1024-based); эталонные байтовые значения — `ADR-0011`, `docs/storage/partitioning_research.md` §4.5.

### 6.3 Partitioning Research Notes

#### 6.3.1 Alignment

| Alignment | Sector | Use Case |
|---|---|---|
| None (default) | 512 bytes | Legacy HDD, не рекомендуется |
| 4K | 4096 bytes | Минимум для SSD |
| 1 MiB | 1048576 bytes | **Оптимально для NVMe SSD** (выравнивание по 2048 секторов по 512 байт) |

#### 6.3.2 EFI System Partition (ESP)

- **Минимум:** 100 MiB (ограничение FAT32 в 4 GiB на файл для BCD несущественно)
- **Рекомендуется Microsoft:** 260 MiB (с запасом под обновления)
- **Наша рекомендация:** 260 MiB (FAT32, кластер 4 КБ), **без буквы диска** (ADR-0011): буква `F:` закреплена за USB-носителем

#### 6.3.3 MSR Partition

- **Фиксированный размер:** 16 MiB (Microsoft рекомендация)
- **Не форматируется** — служебная область для конвертации дисков в GPT

#### 6.3.4 C:\ (Windows)

| Component | Typical Size | Notes |
|---|---|---|
| Windows LTSC IoT | ~24 GiB | После Update Stage 3 |
| Program Files | ~5 GiB | VS Code, Visual C++, winget packages |
| Users | ~9 GiB | Профиль devops + Default User |
| WinSxS | ~5 GiB | После ResetBase |
| PageFile | 4 GiB | Фиксированный (InitialSize=MaximumSize=4096) |
| Temp / Cache | ~3 GiB | Очищается регулярно |
| **Buffer** | ~150 GiB | Для будущих обновлений и приложений |
| **Total C:\** | **200 GiB** | Эталон: 214 748 364 800 байт (ADR-0011) |

#### 6.3.5 D:\ (Data)

| Component | Typical Size | Notes |
|---|---|---|
| VM disks (.vmdk) | ~90 GiB | Pre-allocated для VMware |
| Docker volumes | ~45 GiB | Контейнерные данные |
| Dev projects | ~45 GiB | git clone, build artifacts |
| Backups (config snapshots) | ~15 GiB | Снимки конфигов |
| Free space | ~51.7 GiB | Для будущих нужд |
| **Total D:\** | **≈246.7 GiB** | Весь остаток ёмкости накопителя (ADR-0011); не путать с разделом 3 носителя F: |

### 6.4 DiskGenius Operations

| Step | Operation | Tool |
|---|---|---|
| 1 | Backup old partition table | DiskGenius → Backup Partition Table |
| 2 | Create GPT | DiskGenius → Initialize Disk → GPT |
| 3 | Create ESP | DiskGenius → New Partition → EFI System Partition, 260 MiB (272 629 760 Б), FAT32, 1 MiB alignment, без буквы |
| 4 | Create MSR | DiskGenius → New Partition → MSR, 16 MiB (16 777 216 Б) |
| 5 | Create C:\ | DiskGenius → New Partition → Primary, **200 GiB (214 748 364 800 Б)**, NTFS, 4K cluster, 1 MiB alignment |
| 6 | Create D:\ | DiskGenius → New Partition → Primary, **весь остаток (≈246.7 GiB)**, NTFS, 64K cluster, 1 MiB alignment |
| 7 | Backup new partition table | DiskGenius → Backup Partition Table |
| 8 | Verify alignment | DiskGenius → Verify → 1 MiB boundary check |

### 6.5 Post-Stage 1 NTFS Configuration

```powershell
# D:\ NTFS optimizations
fsutil behavior set disable8dot3 D: 1
fsutil behavior set disablelastaccess 1
fsutil behavior set encryptpagingfile 0

# Cluster size optimization
# (Уже установлен при форматировании: 64K)
```

---

## SECTION 7: C_DRIVE_SCHEMA (Stage 1 Output)

### 7.1 Physical Layout

| Parameter | Value |
|---|---|
| Device | NVMe SSD 480 GB (≈447 GiB полезной ёмкости) |
| Partition Table | GPT |
| Boot Mode | UEFI |
| Total Size | 480 GB |

### 7.2 Partitions

| # | Type | FS | Size | Cluster | Mount | Label | GUID |
|---|---|---|---|---|---|---|---|
| 1 | EFI System | FAT32 | 260 MiB | 4K | скрытая (без буквы) | ESP | `<EFI_GUID>` |
| 2 | MSR | — | 16 MiB | — | hidden | MSR | `<MSR_GUID>` |
| 3 | Windows | NTFS | 200 GiB | 4K | `C:\` | Windows | `<WINDOWS_GUID>` |
| 4 | Data | NTFS | ≈246.7 GiB (остаток) | 64K | `D:\` | Data | `<DATA_GUID>` |

Единицы — MiB/GiB (1 GiB = 2³⁰ байт); байтовые эталоны и допуски — ADR-0011, §6.2.

### 7.3 Alignment Verification

```
Partitions aligned to 1 MiB boundary: YES
Verified by: DiskGenius post-create verification
Tolerance: ±0 bytes
```

### 7.4 C:\ Structure (Runtime)

```
C:\
├── Program Files\
│   ├── WindowsApps\                  (UWP Apps, после Stage 6 minimal)
│   └── (Standard programs)
├── Program Files (x86)\
├── ProgramData\
├── Users\
│   ├── devops\                       (создан в Stage 6)
│   ├── Default\                      (шаблон после CopyProfile)
│   ├── Public\
│   └── Administrator\                (только Audit Mode)
├── Windows\
│   ├── System32\
│   │   ├── GroupPolicy\              (NTFS Deny SYSTEM после Stage 6)
│   │   ├── drivers\etc\hosts          (NTFS Deny SYSTEM после Stage 6)
│   │   └── Sysprep\                   (unattend.xml в Stage 5)
│   ├── WinSxS\                       (сжат после ResetBase в Stage 4)
│   └── ...
├── Vitality\                         (runtime, после Stage 8)
├── Drivers\                          (INF-драйверы в Stage 4)
├── GD_Tool\                           (инструменты в Stage 6)
└── Recovery\                          (WinRE)
```

### 7.5 D:\ Structure (Runtime)

```
D:\
├── GD_Tool\                           # Инструменты после Stage 6
│   ├── LGPO.exe
│   ├── CleanLTSCPolicy\               # Слепок политик
│   └── AutoSetup.bat
├── VM\                                # VMware (Stage 7)
├── Docker\                            # Docker volumes (Stage 7)
├── Projects\                          # git clone, dev
└── Backups\                           # Снимки конфигов
```

---

## SECTION 8: F_DRIVE_SCHEMA (Stage 2 Output)

### 8.1 Physical Layout

| Parameter | Value |
|---|---|
| Device | USB Flash Drive 460 GB |
| Partition Table | GPT |
| Ventoy Version | 1.1.10 |
| Total Size | 460 GB |

### 8.2 Partitions

| # | Type | FS | Size | Cluster | Label | GUID |
|---|---|---|---|---|---|---|
| 1 | EFI System | FAT32 | 1 GB | 4K | VENTOY | `<VENTOY_GUID>` |
| 2 | Ventoy/ISO | exFAT | 250 GB | 512 байт | VENTOY | `<VENTOYDATA_GUID>` |
| 3 | Data | NTFS | ~209 GB | 16K | VITADATA | `<DATA_GUID>` |

### 8.3 Раздел 1 (Загрузочный)

| Parameter | Value |
|---|---|
| Size | 1 GB |
| FS | FAT32 |
| Purpose | ESP, Ventoy boot loader |
| Created by | Ventoy install |

**Содержимое:**
```
/EFI/                  (Ventoy boot loader, создаётся автоматически)
/boot/                 (Ventoy boot files)
/grub/                 (GRUB2 legacy BIOS)
```

### 8.4 Раздел 2 (Ventoy/ISO)

| Parameter | Value |
|---|---|
| Size | 250 GB |
| FS | exFAT |
| Cluster | 512 байт |
| Purpose | ISO-файлы + ventoy.json + templates |

**Содержимое:**
```
/ISO/
├── en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso   (~6 GB)
└── WinPE11_10_8_Sergei_Strelec_2026.02.05_Russian.iso   (~3 GB)

/ventoy/
├── ventoy.json                                (auto_install)
└── /templates/
    └── u_w11_ltsc_iot.xml                     (Ventoy template)
```

### 8.5 Раздел 3 (Вспомогательный)

| Parameter | Value |
|---|---|
| Size | ~209 GB |
| FS | NTFS |
| Cluster | 16 KB |
| Purpose | Инструменты, скрипты, драйверы, конфиги |

**Содержимое:** см. Section 5.7.3

---

## SECTION 9: VERIFICATION CHECKLIST

### 9.1 Stage 1 (Partitioning) Verification

- [ ] DiskGenius partition table backup создан и сохранён на F:\BACKUPS\
- [ ] GPT создан корректно
- [ ] ESP: 260 MiB, FAT32, 1 MiB alignment, без буквы диска (ADR-0011)
- [ ] MSR: 16 MiB
- [ ] C:\: 200 GiB (214 748 364 800 Б), NTFS, 4K cluster, 1 MiB alignment
- [ ] D:\: ≈246.7 GiB (весь остаток), NTFS, 64K cluster, 1 MiB alignment
- [ ] fsutil 8dot3 disable применён к D:\
- [ ] fsutil disablelastaccess применён
- [ ] `Stage1_Report.md` создан
- [ ] `C_drive_schema.md` обновлён
- [ ] ADR-0007 (rev.2) и ADR-0011 созданы

### 9.2 Stage 2 (Ventoy) Verification

- [ ] F:\ раздел 1 создан Ventoy install (1 GB, FAT32)
- [ ] F:\ раздел 2 создан (250 GB, exFAT)
- [ ] F:\ раздел 3 создан (~209 GB, NTFS)
- [ ] /ISO/ содержит LTSC IoT 24H2.iso и Strelec.iso
- [ ] /ventoy/ventoy.json содержит auto_install
- [ ] /ventoy/templates/u_w11_ltsc_iot.xml содержит XML
- [ ] `Stage2_Report.md` создан
- [ ] `F_drive_schema.md` обновлён

### 9.3 Stage 3 (Windows Update) Verification

- [ ] Исходная сборка зафиксирована (`CurrentBuild`, `UBR`, `EditionID`)
- [ ] Переключатель «Получайте последние обновления…» — Отключено
- [ ] Два последовательных цикла закончились статусом «Установлены все актуальные обновления»
- [ ] `CurrentBuild`/`UBR` выросли относительно исходных
- [ ] Пакеты ASUS/OEM и необязательные обновления не устанавливались
- [ ] Audit Mode сохранён (окно Sysprep появлялось и закрывалось после каждой перезагрузки)
- [ ] Сеть физически изолирована (`Test-NetConnection 8.8.8.8` → False)
- [ ] `Stage3_Report.md` заполнен

### 9.4 Stage 4 (Audit Final Clean) Verification

Выполняется на хосте, в Audit Mode, при 100% сетевой изоляции (AR-709):
`scripts/Stage4_Audit_Final_Clean.ps1` → `tweaks/bcd/Set-BcdVbsFlags.ps1` → `tweaks/apply/Assert-TweakState.ps1`.

- [ ] Сеть изолирована и подтверждена (нет активных адаптеров, `Test-NetConnection 8.8.8.8` → False)
- [ ] Импорт «голых» INF из `C:\Drivers` выполнен под временным PnP-щитом
- [ ] PnP-щит снят: `Invoke-PnpShield.ps1 -Audit` → 0 из 2 активных элементов
- [ ] Устройства без ошибок 28/48 (тачпад, аудио)
- [ ] Реестр: `LsaCfgFlags=0`, `EnableVirtualizationBasedSecurity=0`, HVCI `Enabled=0` (TWK-001..003)
- [ ] BCD: `loadoptions` содержит `DISABLE-LSA-ISOLATION,DISABLE-VBS` (BCD-001, AR-505, снимок BCD создан)
- [ ] VBS runtime: `Win32_DeviceGuard.VirtualizationBasedSecurityStatus = 0` (после перезагрузки)
- [ ] Службы `WaaSMedicSvc`, `UsoSvc`, `DiagTrack`, `WSearch`, `edgeupdate`, `edgeupdatem` → `Start=4`
- [ ] Provisioned AppX (Xbox/Cortana/Bing/…) удалены; защищённые пакеты не тронуты
- [ ] `powercfg /hibernate off`; `C:\hiberfil.sys` отсутствует
- [ ] Подкачка: `AutomaticManagedPagefile=False`, `InitialSize=MaximumSize=4096`
- [ ] `dism /online /cleanup-image /StartComponentCleanup /ResetBase` выполнен
- [ ] `fsutil behavior set disablelastaccess 1` применён
- [ ] `Assert-TweakState.ps1` → все проверки PASS; отчёт `Stage4_tweakstate.md` создан
- [ ] `Stage4_Report.md` заполнен (W1–N1), статус переведён в DONE
- [ ] Бэкапы сессии сохранены на `F:\BACKUPS\`

### 9.5 Stage 5 (Sysprep Seal) Verification

Выполняется на хосте: `scripts/Stage5_Sysprep_Prepare.ps1` (подготовка) → `sysprep.exe /oobe /generalize /shutdown` (CMD от Администратора, AR-204) → тихий OOBE → создание пользователя `devops`.

- [ ] Исходное состояние зафиксировано: Audit Mode активен (`SystemSetupInProgress = 1`)
- [ ] Сеть физически изолирована (0 активных адаптеров); выход в сеть — только на стыке Stage 6→7
- [ ] Остаток перевооружений (`slmgr /dlv`, «Remaining Windows rearm count») внесён в отчёт
- [ ] `templates/unattend.xml.template` размещён как `C:\Windows\System32\Sysprep\unattend.xml` (UTF-8 без BOM)
- [ ] Предпролётный отчёт `Stage5_preflight.md`: `P0.1`–`P2.2`, `P4.1` — PASS
- [ ] Ловушка `0x80073cf2` закрыта: `P3.1` — 0 нарушений (при необходимости `-FixSysprepValidation`, AR-507)
- [ ] Дефект 24H2: кэши `WebCache`/`INetCache` очищены (`-PurgeProfileCaches`) или зафиксирован `WARN` с переносом в Stage 6
- [ ] `sysprep.exe /oobe /generalize /shutdown /unattend:...` выполнен, ноутбук полностью выключился
- [ ] `sysprep_succeeded.tag` присутствует; журналы `setupact.log`/`setuperr.log` — без ошибок
- [ ] OOBE остановился на экране создания локальной учётной записи; EULA/OEM/онлайн-экраны скрыты
- [ ] Пользователь `devops` создан, вход выполнен; оболочка работает без дефектов (панель задач, «Пуск»)
- [ ] Твики наследованы (`H-003`): IFEO ASUS, `DiagTrack=4`, отсутствие `hiberfil.sys`, подкачка 4096 МБ
- [ ] `Stage5_Report.md` заполнен (P0.1–S6), статус переведён в DONE

### 9.6 Stage 6 (Immunity Contour & Activation) Verification

Выполняется в профиле `devops` при отключённой сети. Подготовка — `scripts/Stage6_Immunity_Prepare.ps1`; окно активации — `algorithm/manual/Stage6_Ohook_Activation.md` (только владелец, AR-204).

- [ ] Предусловия `P0.1`–`P0.5` без FAIL (`Stage6_preflight.md`): сеть изолирована, `D:\GD_Tool` создан, шаблон рантайма на месте
- [ ] Доверенная зона Defender применена **до** первой ACL-операции (`P1`; ADR-0015)
- [ ] Рантайм развёрнут и сверен по SHA256 (`P2.*`): `ImmunityCore.ps1`, `AutoSetup.bat`, `Launcher.vbs`
- [ ] Задача `System_Immunity_Core` зарегистрирована: принципал SYSTEM, триггеры boot + unlock (`TASK-001.1/2`)
- [ ] Реаниматоры выведены из строя: `TR101`…`TR106` — `Disabled`, XML в бэкапе (AR-304)
- [ ] NTFS-замки применены (`GACL-001/002`): DENY `SYSTEM:(W)` на `GroupPolicy` и `hosts`
- [ ] Правила брандмауэра активны (`F1/F2`); твики Stage 4 не деградировали (`M1/M2`)
- [ ] Запрет DoH подтверждён (`D1`: `DoHPolicy = 1`)
- [ ] Окно активации: сеть включена **вручную**, Ohook выполнен, `A1` = `Licensed` (`H-004` закрыт на двух перезагрузках)
- [ ] `System_Immunity_Core` выполнена вручную («Выполнить»), код 0, журнал `D:\GD_Tool\logs\ImmunityCore.log` заполнен
- [ ] Сеть окончательно выключена; PIN (Windows Hello) настроен; вход выполняется
- [ ] `Stage6_immunity.md` — без FAIL; `Stage6_Report.md` переведён в DONE
- [ ] Открытые вопросы ратифицированы: список доменов `hosts` (`S6-OPEN-1`), дом правил брандмауэра (`S6-OPEN-2`), судьба исключения `sppc.dll` (`S6-OPEN-3`)

### 9.7 Stage 7 (DevOps Contour) Verification

Выполняется в профиле `devops` при открытом владельцем окне сети (стык Stage 6→7, §4.5). Оркестратор — `scripts/Stage7_WSL_Docker_VMware.ps1`.

- [ ] Предусловия `P0.1`–`P0.5`: окно сети открыто, Stage 6 закрыт (задача + замок `GroupPolicy`), пакет `F:\WSL2\ubuntu.appx`, место на `C:`/`D:`
- [ ] Компоненты: `Subsystem-Linux`, `VirtualMachinePlatform`, `HypervisorPlatform` — `Enabled`; `Microsoft-Hyper-V-All` — не включён (`C0.1`–`C0.3`)
- [ ] `hypervisorlaunchtype = auto` (`C0.2`), снимок BCD сохранён перед правкой (AR-505)
- [ ] Дистрибутив WSL2 установлен, Linux-пользователь создан (`W1.4`)
- [ ] Лимиты `.wslconfig` совпадают с шаблоном (4 / 6GB / pageReporting=false) (`W1.5`), `systemd=true` активен
- [ ] Docker Engine установлен нативно, `DockerRootDir = /mnt/d/Docker` (`P7.2`); dev-стек поднимается
- [ ] Директивы `.vmx` применены ко всем ВМ; `*.vmem` не создаётся (`C1.*`); ВМ грузится при активном WSL2 (`P7.3`)
- [ ] Маска P-ядер выведена динамически (`A0.1`), процессы привязаны с приоритетом ≤ `Normal` (`A1.1`)
- [ ] Схема питания сверена с `power-plan.json` (`A2.*`) либо расхождение зафиксировано как WARN
- [ ] Пакеты профиля `devops` установлены, `Packages.lock.json` заполнен, `PACKAGES_SHA256.txt` актуален
- [ ] `Stage7_preflight.md` — без FAIL; `Stage6_immunity` подтверждён после этапа
- [ ] Окно сети закрыто владельцем; `Stage7_Report.md` переведён в DONE, `Final_Report.md` заполнен

### 9.8 All Stages Verification

- [ ] Все ADR созданы (актуальный диапазон: ADR-0001..ADR-0016)
- [ ] Все паттерны задокументированы (PAT-01..PAT-NEW-7; `M_PATTERN_COVERAGE` = 22/28)
- [ ] Все отчёты созданы (Stage1..Stage7 + Final); Stage 6: `Stage6_Report.md`, `Stage6_preflight.md`, `Stage6_immunity.md`
- [ ] Recovery_Procedure.md создан
- [ ] README.md обновлён
