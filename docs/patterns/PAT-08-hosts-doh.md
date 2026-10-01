# PAT-08 — Hosts-блокировка + запрет DoH (двойной канал телеметрии)

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-08 |
| `NAME` | Hosts-блокировка + запрет DoH (двойной канал телеметрии) |
| `STAGE` | 6 |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0003`, `ADR-0015`, `tweaks/acl/AclManifest.json` (`ACL-002`), `tweaks/registry/RegistryManifest.json` (`TWK-006`) |

---

## Контекст

Правка файла `hosts` обнуляет телеметрию на уровне имён, но современные сборки Windows 11 24H2 резолвят имена через **DNS over HTTPS**, обходя локальный файл `hosts`. Блокировка только через `hosts` или только через `EnableAutoDoh` наблюдалась как неполная (в отдельных случаях `EnableAutoDoh=2` приводил к нарушению резолвинга в целом).

## Решение

Двойной канал, оба — политики/файл, оба — декларативны:

1. **Канал имён** — `C:\Windows\System32\drivers\etc\hosts`: объявленный список доменов → `0.0.0.0`; файл защищён DENY-ACE для SYSTEM (PAT-11).
2. **Канал транспорта** — политика `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` → `DoHPolicy = 1` (Prohibit DoH). Значения политики: `1` = запрет, `2` = разрешение, `3` = требование. Ветка политик, а не службы, — поэтому значение импортируемо LGPO и не сбрасывается службой `Dnscache` при обновлении.

Отвергнутые варианты: `EnableAutoDoh=2` в `…\Services\Dnscache\Parameters` (сервисная ветка, может нарушить резолвинг) и пер-интерфейсные `DohInterfaceSettings` (привязаны к GUID адаптеров, не переносимы).

## Реализация

| Артефакт | Путь |
|---|---|
| Замок на файл | `tweaks/acl/AclManifest.json` (`ACL-002`) |
| Реестровый твик | `tweaks/registry/RegistryManifest.json` (`TWK-006`, этап `4, 6`) |
| Проверка | `tweaks/apply/Assert-ImmunityState.ps1` (`D1`), `Assert-TweakState.ps1` |

## Проверка

| ID | Критерий |
|---|---|
| `D1` | `DoHPolicy = 1` (DWORD) |
| `GACL-002` | DENY Write для SYSTEM на `hosts` |
| `H1` | (вручную) `Resolve-DnsName <домен>` → запись из `hosts` |

## Замечания

- Список доменов — **S6-OPEN-1** (см. `docs/artifacts/Stage6_Report.md`): требуется ратификация перечня владельцем.
- Паттерн не заменяет брандмауэр: PAT-09 закрывает процессы-обходчики по именам процессов.
