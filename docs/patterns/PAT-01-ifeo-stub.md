# PAT-01 — IFEO Debugger → NoOp-stub

| Поле | Значение |
|---|---|
| `PATTERN_ID` | PAT-01 |
| `NAME` | IFEO NoOp-stub для вендорских исполняемых файлов |
| `STAGE` | 2 (внедрение), действует далее постоянно |
| `VERIFIED` | ✅ (README §3.4) |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `SCHEMA_VERSION` | 3.0.0 |
| `RELATED` | `ADR-0005`, `PAT-16`, `templates/u_w11_ltsc_iot.xml.template`, `docs/research/anchor1.md`, README §1.4 `SC_NO_DEGRADATION_RUNTIME` |

---

## Контекст

Прошивка ASUS Vivobook содержит ACPI-таблицу **WPBT** (Windows Platform Binary Table), которая заставляет ядро Windows развернуть в `System32` файлы `AsusUpdateCheck.exe` и `AsusAppService.exe` и зарегистрировать задачи для запуска утилит MyASUS. Механика не зависит от подключения к сети и работает даже на LTSC-редакции.

Простое удаление файлов не работает как решение: WPBT-развёртывание повторяется при обновлениях и обслуживании. Требуется блокировка **исполнения** по имени образа, а не удаление файла.

## Решение

Для целевого образа создаётся подраздел в `Image File Execution Options` (IFEO) со значением `Debugger = ntsd -d`:

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AsusUpdateCheck.exe
    Debugger = REG_SZ "ntsd -d"
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AsusAppService.exe
    Debugger = REG_SZ "ntsd -d"
```

Механика: диспетчер образов (`ntdll`/`CreateProcess`) при попытке запуска процесса сверяется с IFEO и запускает **отладчик** вместо приложения. Строка `ntsd -d` передаётся как «отладчик», которого в системе нет, — запуск завершается ничем (NoOp), приложение не стартует. Приём опирается на документированный механизм отладки образов, не требует драйверов и не создаёт риска BSOD (`SC_ZERO_BSOD_RISK`, `NC_DRIVER_SIGNED`).

## Реализация

| Компонент | Артефакт |
|---|---|
| Внедрение на Stage 2 | `templates/u_w11_ltsc_iot.xml.template`, проход `specialize`, `RunSynchronousCommand` (Order 1–2) |
| Внедрение как твик (повтор) | `tweaks/registry/` (манифест `TWK-*`, план) + `tweaks/apply/Apply-RegistryTweaks.ps1` |
| Перенос в Default User | обеспечивается `CopyProfile` (PAT-16, ADR-0005) |

Целевые имена образов фиксированы и не расширяются «на глаз»: добавление нового имени — изменение манифеста (`AR-501`) с обновлением этого паттерна и `docs/core-tweaks/TWEAK_INDEX.md`.

## Верификация

```powershell
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AsusUpdateCheck.exe" /v Debugger
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AsusAppService.exe" /v Debugger
```

Ожидание: `Debugger REG_SZ ntsd -d` для обоих ключей.

Дополнительная (косвенная) проверка: `Get-Process | Where-Object { $_.Path -like '*\Asus*' }` — процессов не должно быть; в `Event Viewer` фиксируется неуспешный запуск, что является штатным рапортом о срабатывании паттерна.

## Ограничения и риски

- Паттерн блокирует запуск **по имени образа**: если вендор переименует бинарник, блокировка не сработает (потребуется обновление манифеста).
- IFEO-ключи не мешают самому WPBT-развёртыванию файлов: файлы могут лежать в `System32`, но не исполняться. Это ожидаемый результат.
- Паттерн не является средством защиты от подмены: ключи находятся в реестре и технически могут быть изменены под SYSTEM (окончательное цементирование — PAT-11 на Stage 6).
- `ntsd` не входит в поставку Windows 11: выбор строки обусловлен именно тем, что отладчик отсутствует, и запуск становится NoOp.

## Альтернативы

| Вариант | Причина отклонения |
|---|---|
| Удаление файлов из `System32` | WPBT повторяет развёртывание; удаление бинарников требует trustedinstaller-прав (`NC_PRIMITIVE_DELETE`) |
| `PAT-02` (Wrapper-Decorator) | Избыточен: требуется лишь блокировка, а не подмена функциональности |
| Блокировка задачами планировщика (`PAT-04`) | Задача может быть пересоздана; IFEO действует на уровне запуска процесса |
| Драйверный minifilter | Запрещено (`NC_DRIVER_SIGNED`, `SC_ZERO_BSOD_RISK`) |
