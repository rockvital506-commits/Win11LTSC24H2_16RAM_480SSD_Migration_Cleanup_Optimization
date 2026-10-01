# PAT-15 — Временный щит PnP (DisableCoInstallers)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-15 |
| `NAME` | Временный щит PnP (DisableCoInstallers) |
| `STAGE` | 4 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0012`, `tweaks/apply/Invoke-PnpShield.ps1`, `scripts/Stage4_Audit_Final_Clean.ps1`, `docs/research/step3.md` |

---

## Контекст

Вендорские компоненты ASUS внедряются через Co-инсталляторы и Device Software Components. Их нужно нейтрализовать на время инъекции драйверов, но нельзя блокировать постоянно: ядро использует те же механизмы для внутренних линкеров драйверов (Software Components).

## Решение

Барьер включается только на время импорта INF и снимается гарантированно:
- `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions` → `DenyDeviceIDs = 1`;
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer` → `DisableCoInstallers = 1`;
- снятие — удаление обоих значений в блоке `finally` оркестратора, а также отдельным идемпотентным прогоном `-Disable`.

## Реализация

| Артефакт | Путь |
|---|---|
| Управление барьером | `tweaks/apply/Invoke-PnpShield.ps1` (`-Enable` / `-Disable` / `-Audit`) |
| Вызов из этапа | `scripts/Stage4_Audit_Final_Clean.ps1` (фаза P2 + `finally`) |

```powershell
pwsh -File ./tweaks/apply/Invoke-PnpShield.ps1 -Enable
try { <импорт INF через pnputil> } finally { pwsh -File ./tweaks/apply/Invoke-PnpShield.ps1 -Disable }
```

## Верификация

Критерий: после этапа оба значения отсутствуют (или равны 0). Проверка: `pwsh -File ./tweaks/apply/Invoke-PnpShield.ps1 -Audit` → «Активных элементов барьера: 0 из 2».

Дополнительно: `pnputil /enum-drivers` не должен содержать вендорских панелей ASUS; устройства (тачпад, аудио) — без ошибок 28/48.

## Ограничения и риски

- **Критический риск:** оставленный барьер ломает PnP (ошибки 28/48 на тачпаде/аудио). Митигация: снятие в `finally`, идемпотентный `-Disable`, контроль состояния.
- Барьер не является защитой от WPBT-внедрения файлов: он блокирует Co-инсталляторы, а не развёртывание. Остаточное развёртывание нейтрализуется `PAT-01`.

## Альтернативы

| Вариант | Причина отклонения |
|---|---|
| Постоянный запрет Co-инсталляторов | Ломает внутренние линкеры драйверов, устройства отваливаются |
| Удаление вендорских файлов | WPBT повторяет развёртывание; требуется trustedinstaller-права (`NC_PRIMITIVE_DELETE`) |
| Без щита | Co-инсталляторы подтягивают панели ASUS в момент импорта |

---

<!-- Файл UTF-8 без BOM, LF. -->
