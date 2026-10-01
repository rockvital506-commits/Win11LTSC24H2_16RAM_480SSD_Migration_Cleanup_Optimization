# Recovery_Procedure.md — Процедура восстановления (PAT-19)

| Поле | Значение |
|---|---|
| `DOCUMENT_ID` | REC-001 |
| `SCHEMA_VERSION` | 3.0.0 |
| `DATE` | 2026-10-01 |
| `AUTHOR` | AI-агент (Arena.ai) |
| `STATUS` | ACTIVE |
| `RELATED` | `PAT-19`, `PAT-20`, AR-201, AR-202, AR-204, AR-301, AR-304, AR-307, AR-308, AR-505, `scripts/common/Backup.psm1`, README §9.9 |

Документ описывает откат и восстановление после любого этапа. **Все операции восстановления выполняет
владелец**: они изменяют систему (AR-204), а некоторые необратимы (AR-202). Агент восстановление не запускает.

---

## 1. Где лежат бэкапы

Каждый этап, меняющий систему, создаёт сессию бэкапа: `backups/<UTC-время>_<этап>/` (модуль `Backup.psm1`,
AR-308). Каталог `backups/` исключён из Git — это рабочая область стенда.

| Этап | Состав сессии |
|---|---|
| 4 | `.reg`-экспорты изменённых веток реестра, `services_before.json`, `bcd_backup.bcd`, список удалённых AppX |
| 5 | копия `unattend.xml`, журналы `sysprep` (`setupact.log`, `setuperr.log`) |
| 6 | копия `CleanLTSCPolicy` (слепок политик), исходные `hosts` и файлы GPO, XML задач, SDDL-слепки ACL до/после, экспорт правил брандмауэра, список исключений Defender |
| 7 | копии `*.vmx` каждой ВМ, `Packages.lock.json`, экспорт схемы питания (`powercfg /list`) |

В каждом каталоге — `MANIFEST_SHA256.txt` (PAT-20). **Перед восстановлением проверьте хэши**:

```powershell
Get-Content ./backups/<сессия>/MANIFEST_SHA256.txt | ForEach-Object {
    $h, $name = $_ -split '\s+', 2
    if ((Get-FileHash (Join-Path './backups/<сессия>' $name) -Algorithm SHA256).Hash -ne $h) { Write-Warning "Изменён: $name" }
}
```

## 2. Общие правила

1. Восстанавливать **в обратном порядке**: сначала артефакты позднего этапа (7 → 6 → 5 → 4).
2. Удаление файлов автономно запрещено (AR-201): восстанавливается копия поверх, ничего не стирается.
3. После каждого шага — верификация (AR-307), результат фиксируется в `Stage*_Report.md`.
4. Разрушительные операции (`bcdedit /import`, форматирование, `wsl --unregister`, `powercfg /restoredefaultschemes`)
   выполняются только с явного подтверждения владельца (AR-202, AR-204).

## 3. Матрица отката

| Объект | Источник | Команда восстановления | Проверка |
|---|---|---|---|
| Флаги BCD (VBS/HVCI/LSA) | `bcd_backup.bcd` или целевые команды | `bcdedit /deletevalue {current} vsmlaunchtype` и т.п. (точечно); `bcdedit /import` — только по одобрению | `Assert-TweakState.ps1` (B1, V1) |
| Гипервизор | — | `bcdedit /set hypervisorlaunchtype off` | `Stage7_WSL_Docker_VMware.ps1 -Audit` (`C0.2`) |
| Ветки реестра | `.reg`-экспорты | `reg import "<файл>.reg"` | `Assert-TweakState.ps1` (R1–R3) |
| Типы запуска служб | `services_before.json` | `Set-Service -Name <N> -StartupType ...` либо `reg add ...\Services\<N> /v Start` | `Assert-TweakState.ps1` (S-*) |
| Задачи планировщика | XML-экспорты, `TaskManifest.json` | `schtasks /create /xml "<файл>" /tn "<имя>" /f`; снятие — `Apply-TaskManifest.ps1` | `Assert-ImmunityState.ps1` (T*) |
| NTFS Deny SYSTEM (GPO/hosts) | копии файлов | см. §5 (нужен доступ SYSTEM/TrustedInstaller) | `Assert-ImmunityState.ps1` (GACL-001/002) |
| Правила брандмауэра | экспорт правил | `netsh advfirewall firewall delete rule name="<имя>"` (по манифесту) или `netsh advfirewall import` | `Assert-ImmunityState.ps1` (FW*) |
| Слепок политик | каталог `CleanLTSCPolicy` | `LGPO.exe /g "<каталог-бэкапа>"` | `Assert-ImmunityState.ps1` (H1, DoH) |
| Дистрибутив WSL2 | — | `wsl --unregister Ubuntu` — **необратимо**, только по одобрению; данные томов на `D:\Docker` сохраняются | `Install-WslDistro.ps1 -Audit` |
| Docker Engine | — | `apt-get remove --purge docker-ce docker-ce-cli containerd.io` внутри дистрибутива | `docker info` |
| Директивы `.vmx` | `<ВМ>.vmx.<метка>.bak` рядом с файлом | копия `.bak` → `.vmx` (файл ВМ должен быть закрыт) | `Configure-WhpCoexistence.ps1` (`C1.*`) |
| Версии пакетов | `Packages.lock.json` | `Invoke-PackageSync.ps1 -Remove -Profile <профиль>` затем установка целевой версии | `Invoke-PackageSync.ps1 -Verify` |
| Схема питания | `powercfg /list` из сессии | `Set-WorkloadAffinity.ps1 -ApplyPowerPlan` | `Set-WorkloadAffinity.ps1` (`A2.*`) |

## 4. Полный откат к чистой системе

1. Убедиться, что данные, которые нужно сохранить, лежат на `D:` (тома `D:\Docker`, каталоги `D:\VM`) — они
   не затрагиваются переустановкой `C:`.
2. Загрузиться с носителя Ventoy (`F:`) и пройти установку заново (`algorithm/manual/Stage2_Ventoy_Install.md`).
3. Повторить этапы по чек-листам README §9.1–§9.7.
4. Форматирование `C:` — деструктивная операция: только владелец, с подтверждением (AR-202, AR-204).

## 5. Восстановление при активных замках (NTFS Deny SYSTEM)

Замки Stage 6 (PAT-11) блокируют запись в `C:\Windows\System32\GroupPolicy` и `...\drivers\etc\hosts`
даже для администратора. Порядок:

1. Временно отключить задачу контура (она вернёт замок при следующей загрузке):
   `schtasks /change /tn "System_Immunity_Core" /disable` — фиксируется как осознанное ослабление защиты.
2. Снять запрет: `icacls "<путь>" /remove:d SYSTEM`, при необходимости сначала получить владение
   (`takeown /f "<путь>" /a`) — операция владельца.
3. Восстановить файл из бэкапа, затем **вернуть замок**: `Apply-AclManifest.ps1`, включить задачу
   `schtasks /change /tn "System_Immunity_Core" /enable`.
4. Зафиксировать эпизод в `Stage6_Report.md` (что было снято, когда и почему).

Если система не загружается, шаги 2–3 выполняются офлайн (WinRE или второй ОС с правами на том `C:`).

## 6. Проверка после восстановления

```powershell
pwsh -File ./tweaks/apply/Assert-TweakState.ps1   -ExportReport ./docs/artifacts/Stage4_tweakstate.md
pwsh -File ./tweaks/apply/Assert-ImmunityState.ps1 -ExportReport ./docs/artifacts/Stage6_immunity.md
pwsh -File ./scripts/Final_Acceptance.ps1
```

Восстановление считается завершённым, когда `Final_Acceptance.md` не содержит FAIL, а записи о выполненных
операциях внесены в отчёты соответствующих этапов.

## 7. Ограничения

- Агент не выполняет восстановление: это мутирующие и частично необратимые операции (AR-201, AR-202, AR-204).
- `backups/` не коммитится в Git (AR-804); в репозитории описана процедура, а не сами данные.
- Деструктивные команды (`bcdedit /import`, `wsl --unregister`, `powercfg /restoredefaultschemes`, форматирование)
  применяются только по явному решению владельца.
