<#
.SYNOPSIS
    Верификация контура самозащиты Stage 6 (единая точка проверки).

.DESCRIPTION
    Проверяет без изменений:
      G*  — NTFS Deny SYSTEM на объектах AclManifest (PAT-11, ADR-0003);
      T*  — задача System_Immunity_Core зарегистрирована и активна (PAT-NEW-4);
      TR* — задачи-реаниматоры выведены из строя (PAT-04);
      F*  — правила брандмауэра против процессов-обходчиков (PAT-09);
      D*  — запрет DoH (PAT-08);
      P*  — доверенная зона Defender (ADR-0015);
      B*  — артефакты автоматизации размещены в D:\GD_Tool (PAT-NEW-3);
      L*  — эталонный слепок политик CleanLTSCPolicy существует (PAT-06);
      A*  — состояние активации (SC_PERMANENT_ACTIVATION, H-004);
      R*  — дефект оболочки 24H2 (S5-OPEN-3): кэши Default-профиля.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER PageFileMb
    Ожидаемый размер подкачки (для сквозного контроля Stage 4, по умолчанию 4096).

.PARAMETER ExportReport
    Путь к markdown-отчёту верификации (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./tweaks/apply/Assert-ImmunityState.ps1 -ExportReport ./docs/artifacts/Stage6_immunity.md

.NOTES
    Script-ID  : SCRIPT-IMM-001
    Stage      : 6
    Patterns   : PAT-04, PAT-06, PAT-08, PAT-09, PAT-11, PAT-NEW-2, PAT-NEW-3, PAT-NEW-4, PAT-17
    ADR        : ADR-0003, ADR-0004, ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-306, AR-307, AR-501, AR-503)
    Depends    : scripts/common/{Logging,Verification}.psm1, tweaks/{acl,tasks}/*.json
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [int]$PageFileMb = 4096,

    [string]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-IMM-001'
$tasksRoot = Join-Path $env:SystemRoot 'System32/Tasks'

function Test-DenyWriteForSystem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $acl = Get-Acl -LiteralPath $Path
    foreach ($rule in $acl.Access) {
        if ([string]$rule.IdentityReference -notmatch 'SYSTEM|S-1-5-18') { continue }
        if ($rule.AccessControlType -ne 'Deny') { continue }
        if ([string]$rule.FileSystemRights -match 'Write|Modify|FullControl|WriteData') { return $true }
    }
    return $false
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 6 — контур самозащиты (верификация)'

    # --- G: NTFS-замки ---
    $aclManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/acl/AclManifest.json') -Raw | ConvertFrom-Json
    foreach ($entry in $aclManifest.entries) {
        $locked = Test-DenyWriteForSystem -Path ([string]$entry.path)
        Add-VerificationCheck -Context $context -Id ('G{0}' -f $entry.id) -Check ('NTFS-замок: {0}' -f (Split-Path -Leaf ([string]$entry.path))) `
            -Expected 'DENY SYSTEM:(W)' -Actual $(if ($locked) { 'присутствует' } else { 'отсутствует' }) `
            -Status $(if ($locked) { 'PASS' } else { 'FAIL' }) -Note ([string]$entry.pattern)
    }

    # --- T: задача контура ---
    $taskManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/tasks/TaskManifest.json') -Raw | ConvertFrom-Json
    foreach ($task in $taskManifest.register) {
        $registered = Get-ScheduledTask -TaskName ([string]$task.name) -ErrorAction SilentlyContinue
        Add-VerificationCheck -Context $context -Id ('T{0}' -f $task.id) -Check ('Задача {0}' -f $task.name) `
            -Expected 'State = Ready' -Actual $(if ($registered) { [string]$registered.State } else { 'отсутствует' }) `
            -Status $(if ($registered -and $registered.State -eq 'Ready') { 'PASS' } else { 'FAIL' }) -Note ([string]$task.pattern)
    }

    foreach ($item in $taskManifest.retire) {
        $full = [string]$item.taskPath
        $name = Split-Path -Leaf $full
        $parent = Split-Path -Parent $full
        if (-not $parent.EndsWith('\')) { $parent = $parent + '\' }
        $obj = Get-ScheduledTask -TaskPath $parent -TaskName $name -ErrorAction SilentlyContinue
        $state = if ($obj) { [string]$obj.State } else { 'отсутствует' }
        Add-VerificationCheck -Context $context -Id ('TR{0}' -f $item.id) -Check ('Реаниматор {0}' -f $name) `
            -Expected 'Disabled или отсутствует' -Actual $state `
            -Status $(if ((-not $obj) -or $obj.State -eq 'Disabled') { 'PASS' } else { 'FAIL' }) -Note ([string]$item.pattern)
    }

    # --- F: брандмауэр ---
    $expectedRules = @('Block Telemetry Core', 'Block WaaSMedic Outbound Agent')
    $ruleIndex = 0
    foreach ($ruleName in $expectedRules) {
        $ruleIndex++
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        $ok = $false
        $detail = 'отсутствует'
        if ($rule) {
            $ok = ($rule.Enabled -eq 'True') -and ($rule.Direction -eq 'Outbound') -and ($rule.Action -eq 'Block')
            $detail = ('Enabled={0}; Direction={1}; Action={2}' -f $rule.Enabled, $rule.Direction, $rule.Action)
        }
        Add-VerificationCheck -Context $context -Id ('F{0}' -f $ruleIndex) -Check ('Правило: {0}' -f $ruleName) `
            -Expected 'Enabled; Outbound; Block' -Actual $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Note 'PAT-09'
    }

    # --- D: DoH ---
    $doh = $null
    try {
        $doh = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'DoHPolicy' -ErrorAction Stop).DoHPolicy
    }
    catch { $doh = $null }
    Add-VerificationCheck -Context $context -Id 'D1' -Check 'DoH запрещён (DoHPolicy=1)' -Expected '1' `
        -Actual $(if ($null -eq $doh) { '<нет>' } else { [string]$doh }) `
        -Status $(if ($doh -eq 1) { 'PASS' } else { 'FAIL' }) -Note 'PAT-08'

    # --- P: доверенная зона Defender ---
    if (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue) {
        $pref = Get-MpPreference
        $exPaths = @($pref.ExclusionPath)
        $exProc  = @($pref.ExclusionProcess)
        Add-VerificationCheck -Context $context -Id 'P1' -Check 'Исключения Defender (пути)' -Expected '>= 4' `
            -Actual ([string]$exPaths.Count) -Status $(if ($exPaths.Count -ge 4) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0015'
        Add-VerificationCheck -Context $context -Id 'P2' -Check 'Исключение wscript.exe' -Expected 'присутствует' `
            -Actual $(if ($exProc -contains 'wscript.exe') { 'присутствует' } else { 'отсутствует' }) `
            -Status $(if ($exProc -contains 'wscript.exe') { 'PASS' } else { 'FAIL' }) -Note 'ADR-0015'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'P1' -Check 'Исключения Defender' -Expected 'Get-MpPreference' `
            -Actual 'модуль недоступен' -Status 'SKIP' -Note 'LTSC IoT без Defender'
    }

    # --- B: артефакты автоматизации ---
    foreach ($file in @('D:\GD_Tool\ImmunityCore.ps1', 'D:\GD_Tool\AutoSetup.bat', 'D:\GD_Tool\Launcher.vbs', 'D:\GD_Tool\FirewallRules.json')) {
        Add-VerificationCheck -Context $context -Id ('B{0}' -f (Split-Path -Leaf $file)) -Check ('Файл {0}' -f $file) `
            -Expected 'существует' -Actual $(if (Test-Path -LiteralPath $file) { 'существует' } else { 'отсутствует' }) `
            -Status $(if (Test-Path -LiteralPath $file) { 'PASS' } else { 'FAIL' }) -Note 'PAT-NEW-3'
    }

    # --- L: эталонный слепок политик ---
    $gpoDir = 'D:\GD_Tool\CleanLTSCPolicy'
    $hasIni = Test-Path -LiteralPath (Join-Path $gpoDir 'gpt.ini')
    Add-VerificationCheck -Context $context -Id 'L1' -Check 'Слепок CleanLTSCPolicy' -Expected 'gpt.ini присутствует' `
        -Actual $(if ($hasIni) { 'присутствует' } else { 'отсутствует' }) -Status $(if ($hasIni) { 'PASS' } else { 'FAIL' }) -Note 'PAT-06'

    # --- A: активация (SC_PERMANENT_ACTIVATION, H-004) ---
    $license = $null
    try {
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction Stop |
            Select-Object -First 1
    }
    catch { $license = $null }
    if ($license) {
        $statusText = switch ([int]$license.LicenseStatus) {
            0 { 'Unlicensed' } 1 { 'Licensed' } 2 { 'OOBGrace' } 3 { 'OOTGrace' } 4 { 'NonGenuineGrace' } 5 { 'Notification' } 6 { 'ExtendedGrace' }
            default { 'Unknown' }
        }
        Add-VerificationCheck -Context $context -Id 'A1' -Check 'Активация Windows' -Expected 'Licensed' `
            -Actual $statusText -Status $(if ([int]$license.LicenseStatus -eq 1) { 'PASS' } else { 'WARN' }) -Note 'SC_PERMANENT_ACTIVATION'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'A1' -Check 'Активация Windows' -Expected 'Licensed' `
            -Actual 'класс лицензирования недоступен' -Status 'WARN' -Note 'SC_PERMANENT_ACTIVATION'
    }

    # --- R: дефект оболочки 24H2 (S5-OPEN-3) ---
    $defaultCache = Join-Path $env:SystemDrive 'Users\Default\AppData\Local\Microsoft\Windows\WebCache'
    $cachePresent = Test-Path -LiteralPath $defaultCache
    Add-VerificationCheck -Context $context -Id 'R1' -Check 'Кэши Default-профиля (24H2)' -Expected 'отсутствуют' `
        -Actual $(if ($cachePresent) { 'присутствуют' } else { 'отсутствуют' }) `
        -Status $(if ($cachePresent) { 'WARN' } else { 'PASS' }) -Note 'S5-OPEN-3'

    # --- Сквозной контроль Stage 4 ---
    $pf = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'C:*' } | Select-Object -First 1
    $pfOk = $pf -and ([int]$pf.InitialSize -eq $PageFileMb) -and ([int]$pf.MaximumSize -eq $PageFileMb)
    Add-VerificationCheck -Context $context -Id 'M1' -Check 'Подкачка после запечатывания' -Expected ('{0}/{0} МБ' -f $PageFileMb) `
        -Actual $(if ($pf) { '{0}/{1} МБ' -f $pf.InitialSize, $pf.MaximumSize } else { '<нет>' }) `
        -Status $(if ($pfOk) { 'PASS' } else { 'FAIL' }) -Note 'PAT-13, H-003'
    $hiberfil = Test-Path -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys')
    Add-VerificationCheck -Context $context -Id 'M2' -Check 'hiberfil.sys отсутствует' -Expected 'отсутствует' `
        -Actual $(if ($hiberfil) { 'присутствует' } else { 'отсутствует' }) `
        -Status $(if ($hiberfil) { 'FAIL' } else { 'PASS' }) -Note 'PAT-14, H-003'

    Write-VerificationReport -Context $context -ExportPath $ExportReport
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
