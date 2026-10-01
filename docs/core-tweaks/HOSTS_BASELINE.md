# HOSTS_BASELINE.md — Базовый перечень доменов для `hosts`

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | HOSTS-001 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | **PROPOSED** — на ратификацию владельцем (`S6-OPEN-1`) |
| `RELATED` | `PAT-08`, `ADR-0003`, `ADR-0015`, `tweaks/acl/AclManifest.json` (`ACL-002`), `TWK-006` |

Перечень закрывает **канал имён**: записи вида `0.0.0.0 <домен>` в `%SystemRoot%\System32\drivers\etc\hosts`
([TWK-006](TWEAK_INDEX.md) делает этот канал единственным). Записи применяются в окне `grant` ACL-транзакции,
после чего файл цементируется ([ACL-002](ACL_MATRIX.md), [PAT-11](../patterns/PAT-11-ntfs-deny-cementing.md)).

> **Статус.** Список составлен агентом как типовой базовый набор (телеметрия, CEIP, обработка дефектов,
> совместимость) и **не является обязательным**: владелец вычёркивает ненужные строки, после чего перечень
> переносится в декларацию и применяется скриптом (см. §4).

## 1. Телеметрия и диагностика (рекомендуется)

| Домен | Назначение |
|---|---|
| `vortex.data.microsoft.com` | Основной канал телеметрии |
| `vortex-win.data.microsoft.com` | Канал телеметрии Windows |
| `telemetry.microsoft.com` | Классическая точка сбора |
| `settings-win.data.microsoft.com` | Настройки телеметрии |
| `watson.telemetry.microsoft.com` | Телеметрия Watson |
| `v10.events.data.microsoft.com` | События (новый конвейер) |
| `v10c.events.data.microsoft.com` | События (клиентский конвейер) |
| `v20.events.data.microsoft.com` | События (конвейер v20) |
| `self.events.data.microsoft.com` | События диагностики |
| `browser.events.data.microsoft.com` | События браузера |
| `mobile.events.data.microsoft.com` | События мобильных компонентов |
| `umwatsonc.events.data.microsoft.com` | Отчёты о сбоях |

## 2. CEIP, SQM и обратная связь

| Домен | Назначение |
|---|---|
| `ceip.microsoft.com` | Программа улучшения качества |
| `sqm.microsoft.com` | SQM-телеметрия |
| `feedback.microsoft-hohm.com` | Обратная связь (старый контур) |
| `feedback.search.microsoft.com` | Обратная связь поиска |
| `feedback.windows.com` | Обратная связь Windows |

## 3. Обработка дефектов и совместимость

| Домен | Назначение |
|---|---|
| `watson.microsoft.com` | Приём дампов Watson |
| `oca.microsoft.com` | Online Crash Analysis |
| `compat.microsoft.com` | Данные совместимости приложений |
| `ceuswatcab01.blob.core.windows.net` | Канал Watson (сервер 1) |
| `ceuswatcab02.blob.core.windows.net` | Канал Watson (сервер 2) |
| `eauswatcab01.blob.core.windows.net` | Канал Watson (резерв) |

## 4. Опционально: обновления

| Домен | Назначение | Комментарий |
|---|---|---|
| `windowsupdate.microsoft.com` | Точка обновления | Включать только если политика прямо требует; Stage 3 выполнен, обновления не планируются |
| `download.windowsupdate.com` | Загрузка пакетов | То же |
| `wustat.windows.com` | Статистика WU | То же |

> Записи этой группы **не включаются** в предлагаемый базовый набор по умолчанию: они уже перекрыты политиками
> и службами Stage 3–4. Добавляются владельцем при необходимости.

## 5. Что дальше (после ратификации)

| # | Действие | Артефакт |
|---|---|---|
| 1 | Владелец отмечает нужные строки и вычёркивает лишние | правка этого документа или ответ в чате |
| 2 | Перечень переносится в декларацию | `tweaks/hosts/HostsManifest.json` (потребует `GATE_STRUCTURE`) либо расширение `AclManifest.json` |
| 3 | Апплейер записывает `hosts` в окне `grant` | `Set-HostsBaseline.ps1` (PAT-08, идемпотентно, бэкап файла по AR-502) |
| 4 | Верификация | `Assert-ImmunityState.ps1` (проверки `GACL-002`, `H1`) |

До ратификации файл `hosts` **не изменяется**: действуют правила брандмауэра ([PAT-09](../patterns/PAT-09-firewall-outbound.md))
и запрет DoH (`TWK-006`).
