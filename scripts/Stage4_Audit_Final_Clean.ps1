<#
.SYNOPSIS
    Stage 4 — финальная санитария Audit Mode (оркестратор).

.DESCRIPTION
    Выполняется в 100% сетевой изоляции, до Sysprep (Stage 5). Последовательность:

      P0  предусловия: права, изоляция сети, наличие каталога C:\Drivers
      P1  сессия бэкапа (реестр, службы, конфигурация подкачки)
      P2  временный щит PnP (PAT-15) -> импорт INF через pnputil -> СНЯТИЕ щита в finally
      P3  применение твиков через tweaks/apply/Apply-Tweaks.ps1 (реестр, службы, AppX)
      P4  виртуальная память: hibernation off (PAT-14), фиксированный pagefile (PAT-13)
      P5  обслуживание хранилища: DISM StartComponentCleanup /ResetBase (PAT-18),
          очистка SoftwareDistribution\Download
      P6  NTFS: disablelastaccess
      P7  верификация через tweaks/apply/Assert-TweakState.ps1
      P8  BCD (PAT-12) НЕ выполняется автоматически: отдельный изолированный шаг
          tweaks/bcd/Set-BcdVbsFlags.ps1 (AR-505). Флаг -IncludeBcd разрешает вызов
          из оркестратора осознанно.

    КРИТИЧНО: барьер PnP снимается в блоке finally. Если барьер оставить активным,
    ядро блокирует линкеры драйверов и часть устройств (тачпад, аудио) отваливается
    с ошибками 28/48.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER DriversPath
    Каталог с «голыми» INF-драйверами. По умолчанию C:\Drivers.

.PARAMETER PageFileMb
    Фиксированный размер файла подкачки, МБ. По умолчанию 4096 (PAT-13, 16 ГБ ОЗУ).

.PARAMETER Audit
    Режим только чтения: ничего не меняет, показывает план и текущее состояние.

.PARAMETER SkipDrivers
    Пропустить шаг импорта драйверов (каталог отсутствует или не нужен).

.PARAMETER SkipServicing
    Пропустить DISM /ResetBase (например, для ускоренного повторного прогона).

.PARAMETER IncludeBcd
    Вызвать tweaks/bcd/Set-BcdVbsFlags.ps1 в рамках оркестратора (по умолчанию — нет).

.PARAMETER AllowNetwork
    Не блокировать выполнение при обнаруженном активном сетевом адаптере.

.PARAMETER VerificationReport
    Путь для markdown-отчёта верификации.

.EXAMPLE
    pwsh -File ./scripts/Stage4_Audit_Final_Clean.ps1 -Audit
    pwsh -File ./scripts/Stage4_Audit_Final_Clean.ps1 -VerificationReport ./docs/artifacts/Stage4_tweakstate.md

.NOTES
    Script-ID  : SCRIPT-STAGE4-001
    Stage      : 4
    Patterns   : PAT-12, PAT-13, PAT-14, PAT-15, PAT-18, PAT-20
    ADR        : ADR-0012, ADR-0013
    Rules      : AUTOMATION_RULES.md (AR-204, AR-301, AR-302, AR-303, AR-304, AR-306, AR-307, AR-501, AR-505, AR-709)
    Depends    : scripts/common/*, tweaks/apply/*, tweaks/bcd/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$DriversPath = 'C:\Drivers',

    [int]$PageFileMb = 4096,

    [switch]$Audit,

    [switch]$SkipDrivers,

    [switch]$SkipServicing,

    [switch]$IncludeBcd,

    [switch]$AllowNetwork,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-STAGE4-001'
$script:PnpShieldScript = Join-Path $RepoRoot 'tweaks/apply/Invoke-PnpShield.ps1'

function Test-NetworkIsolation {
    <# Возвращает список активных адаптеров (Status=Up) с адресом шлюза. #>
    [CmdletBinding()]
    param()

    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $bad.Add($adapter.Name)
    }
    return $bad
}

function Invoke-DriverImport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DriversPath)

    $infFiles = @(Get-ChildItem -LiteralPath $DriversPath -Recurse -Filter '*.inf' -File -ErrorAction Stop)
    if ($infFiles.Count -eq 0) {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('В {0} не найдено ни одного .inf' -f $DriversPath)
        return
    }

    Write-Log -Component $scriptId -Message ('Найдено INF-файлов: {0}. Импорт в DriverStore...' -f $infFiles.Count)

    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($inf in $infFiles) {
        & pnputil.exe /add-driver $inf.FullName /install | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed.Add($inf.Name) }
        else { Write-Log -Level 'PASS' -Component $scriptId -Message ('Импортирован: {0}' -f $inf.Name) }
    }

    if ($failed.Count -gt 0) {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('Не импортированы ({0}): {1}' -f $failed.Count, ($failed -join ', '))
    }
}

function Invoke-MemoryConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$PageFileMb,
        [switch]$Audit
    )

    # PAT-14: уничтожение гибернации (удаляет hiberfil.sys)
    $hiberfil = Test-Path -LiteralPath 'C:\hiberfil.sys' -ErrorAction SilentlyContinue
    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('hiberfil.sys: {0} -> powercfg /hibernate off' -f $(if ($hiberfil) { 'присутствует' } else { 'отсутствует' }))
    }
    else {
        & powercfg.exe /hibernate off | Out-Null
        Write-Log -Level 'PASS' -Component $scriptId -Message 'Гибернация отключена (hiberfil.sys удалён системой).'
    }

    # PAT-13: фиксация файла подкачки
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $pf = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'C:*' } | Select-Object -First 1

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('pagefile: AutomaticManaged={0}; текущая настройка: {1}; целевая: {2}/{2} МБ' -f $cs.AutomaticManagedPagefile, $(if ($null -eq $pf) { '<нет>' } else { ('{0}/{1}' -f $pf.InitialSize, $pf.MaximumSize) }), $PageFileMb)
        return
    }

    if ($cs.AutomaticManagedPagefile) {
        $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
        Write-Log -Level 'PASS' -Component $scriptId -Message 'Автоматическое управление подкачкой отключено.'
    }

    if ($null -ne $pf) {
        $pf | Set-CimInstance -Property @{ InitialSize = $PageFileMb; MaximumSize = $PageFileMb } -ErrorAction Stop
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Файл подкачки зафиксирован: {0}/{0} МБ.' -f $PageFileMb)
    }
    else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = 'C:\pagefile.sys'; InitialSize = $PageFileMb; MaximumSize = $PageFileMb } -ErrorAction Stop | Out-Null
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Файл подкачки создан с фиксированным размером: {0}/{0} МБ.' -f $PageFileMb)
    }
}

function Invoke-ServicingCleanup {
    [CmdletBinding()]
    param([switch]$Audit)

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'DISM /online /cleanup-image /StartComponentCleanup /ResetBase + очистка SoftwareDistribution\Download'
        return
    }

    Write-Log -Component $scriptId -Message 'Сжатие хранилища компонентов (ResetBase)... это длительная операция.'
    & dism.exe /online /cleanup-image /StartComponentCleanup /ResetBase | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('DISM завершился с кодом {0}' -f $LASTEXITCODE)
    }
    else {
        Write-Log -Level 'PASS' -Component $scriptId -Message 'WinSxS сжат (ResetBase: старые компоненты удалены безвозвратно).'
    }

    $download = 'C:\Windows\SoftwareDistribution\Download'
    if (Test-Path -LiteralPath $download) {
        Get-ChildItem -LiteralPath $download -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Level 'PASS' -Component $scriptId -Message 'Кэш SoftwareDistribution\Download очищен.'
    }
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    Write-Log -Component $scriptId -Message ('Режим: {0}' -f $(if ($Audit) { 'AUDIT (изменения не вносятся)' } else { 'ПРИМЕНЕНИЕ' }))

    # --- P0: предусловия ---
    $activeAdapters = @(Test-NetworkIsolation)
    if ($activeAdapters.Count -gt 0) {
        $msg = 'Обнаружены активные сетевые адаптеры: {0}. Stage 4 выполняется в 100% изоляции (AR-709, NC_INTERNET_DURING_TWEAKS).' -f ($activeAdapters -join ', ')
        if ($AllowNetwork) {
            Write-Log -Level 'WARN' -Component $scriptId -Message ($msg + ' Продолжение разрешено флагом -AllowNetwork.')
        }
        else {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ($msg + ' Отключите сеть либо используйте -AllowNetwork осознанно.')
            exit $exit.Precondition
        }
    }

    if (-not $SkipDrivers -and -not (Test-Path -LiteralPath $DriversPath)) {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('Каталог драйверов не найден: {0}. Шаг импорта будет пропущен.' -f $DriversPath)
        $SkipDrivers = $true
    }

    # --- P1: сессия бэкапа ---
    $backupDir = ''
    if (-not $Audit) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage4'
        Write-Log -Level 'INFO' -Component $scriptId -Message ('Сессия бэкапа: {0}' -f $backupDir)
        $bcdSnapshot = Export-BcdSnapshot -BackupDir $backupDir
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Снимок BCD (AR-505): {0}' -f $bcdSnapshot)
        Get-ChildItem -LiteralPath $DriversPath -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName |
            Set-Content -LiteralPath (Join-Path $backupDir 'drivers_inf_list.txt') -Encoding UTF8
    }

    # --- P2: щит PnP и импорт драйверов (барьер гарантированно снимается) ---
    if (-not $SkipDrivers) {
        Write-Log -Component $scriptId -Message 'Активация временного щита PnP (PAT-15)...'
        & $script:PnpShieldScript -RepoRoot $RepoRoot -Enable -Audit:$Audit | Out-Null

        try {
            if (-not $Audit) { Invoke-DriverImport -DriversPath $DriversPath }
            else { Write-Log -Level 'AUDIT' -Component $scriptId -Message ('План импорта INF из {0}' -f $DriversPath) }
        }
        finally {
            Write-Log -Component $scriptId -Message 'Снятие щита PnP (обязательный шаг, PAT-15)...'
            & $script:PnpShieldScript -RepoRoot $RepoRoot -Disable -Audit:$Audit | Out-Null
            if (-not $Audit) {
                $state = & $script:PnpShieldScript -RepoRoot $RepoRoot -Audit 2>&1 | Out-String
                Write-Log -Component $scriptId -Message ('Состояние щита после снятия: {0}' -f ($state.Trim() -split "`r?`n" | Select-Object -Last 1))
            }
        }
    }
    else {
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Импорт драйверов пропущен (-SkipDrivers).'
    }

    # --- P3: твики (реестр, службы, AppX) ---
    $applyScript = Join-Path $RepoRoot 'tweaks/apply/Apply-Tweaks.ps1'
    & $applyScript -RepoRoot $RepoRoot -Audit:$Audit
    $applyCode = $LASTEXITCODE
    if ($applyCode -ne 0 -and $applyCode -ne $null) {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('Apply-Tweaks вернул код {0}' -f $applyCode)
    }

    # --- P4: виртуальная память ---
    Invoke-MemoryConfiguration -PageFileMb $PageFileMb -Audit:$Audit

    # --- P5: обслуживание хранилища ---
    if (-not $SkipServicing) { Invoke-ServicingCleanup -Audit:$Audit }

    # --- P6: NTFS ---
    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'fsutil behavior set disablelastaccess 1'
    }
    else {
        & fsutil.exe behavior set disablelastaccess 1 | Out-Null
        Write-Log -Level 'PASS' -Component $scriptId -Message 'NTFS: disablelastaccess=1.'
    }

    # --- P8: BCD (отдельный шаг, AR-505) ---
    if ($IncludeBcd) {
        Write-Log -Component $scriptId -Message 'Вызов BCD-скрипта (-IncludeBcd, AR-505)...'
        & (Join-Path $RepoRoot 'tweaks/bcd/Set-BcdVbsFlags.ps1') -RepoRoot $RepoRoot -Audit:$Audit
    }
    else {
        Write-Log -Level 'WARN' -Component $scriptId -Message ('BCD не изменялся. Выполните отдельно: pwsh -File {0} -RepoRoot <repo> (AR-505).' -f (Join-Path $RepoRoot 'tweaks/bcd/Set-BcdVbsFlags.ps1'))
    }

    # --- P7: верификация ---
    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Верификация в режиме -Audit не выполняется (состояние ещё не изменено).'
        exit $exit.Ok
    }

    Write-Log -Component $scriptId -Message 'Верификация состояния...'
    & (Join-Path $RepoRoot 'tweaks/apply/Assert-TweakState.ps1') -RepoRoot $RepoRoot -PageFileMb $PageFileMb -ExportReport $VerificationReport
    $verifyCode = $LASTEXITCODE

    if ($backupDir) {
        Get-BackupManifest -BackupDir $backupDir | Out-Null
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Манифест бэкапа сформирован: {0}' -f $backupDir)
    }

    if ($verifyCode -ne 0) {
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('Верификация вернула код {0}. Проверьте отчёт и повторите.' -f $verifyCode)
        exit $exit.VerifyFailed
    }

    Write-Log -Level 'PASS' -Component $scriptId -Message 'Stage 4 завершён. Система готова к Stage 5 (Sysprep).'
    exit $exit.Ok
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    # Гарантия безопасности: барьер PnP не должен оставаться активным после любых сценариев.
    if (-not $Audit) {
        try {
            & $script:PnpShieldScript -RepoRoot $RepoRoot -Disable 2>&1 | Out-Null
        }
        catch {
            Write-Log -Level 'ERROR' -Component $scriptId -Message ('Не удалось подтвердить снятие щита PnP в finally: {0}' -f $_.Exception.Message)
        }
    }
    Stop-LogSession -ScriptId $scriptId
}
