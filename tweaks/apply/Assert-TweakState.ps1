<#
.SYNOPSIS
    Верификация состояния твиков (AR-307): реестр, службы, AppX, память, BCD.

.DESCRIPTION
    Скрипт только читает состояние. Проверяет:
      R1..Rn  — значения из tweaks/registry/RegistryManifest.json;
      S1..Sn  — типы запуска из tweaks/services/ServiceGate.json;
      X1      — отсутствие запрещённых provisioned-пакетов;
      M1      — фиксация файла подкачки (AutoManagedPagefile=False, Initial=Maximum=заданный);
      M2      — отсутствие hiberfil.sys (гибернация выключена);
      B1      — loadoptions содержит DISABLE-LSA-ISOLATION,DISABLE-VBS;
      V1      — VBS не запущен (Win32_DeviceGuard).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER PageFileMb
    Ожидаемый фиксированный размер подкачки, МБ. По умолчанию 4096.

.PARAMETER ExportReport
    Путь для markdown-отчёта (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./tweaks/apply/Assert-TweakState.ps1 -ExportReport ./docs/artifacts/Stage4_tweakstate.md

.NOTES
    Script-ID  : SCRIPT-TWEAKS-002
    Stage      : 4, 6
    Patterns   : PAT-03, PAT-11, PAT-12, PAT-13, PAT-14
    ADR        : ADR-0012, ADR-0013
    Rules      : AUTOMATION_RULES.md (AR-306, AR-307, AR-501)
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
$exit = Get-ExitCode
$scriptId = 'SCRIPT-TWEAKS-002'

try {
    $ctx = New-VerificationContext -Title 'Состояние твиков (Stage 4)'

    # --- R: реестр ---
    $registryManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/registry/RegistryManifest.json') -Raw | ConvertFrom-Json
    foreach ($tweak in $registryManifest.tweaks) {
        $actual = $null
        try {
            $actual = (Get-ItemProperty -LiteralPath $tweak.hive -Name $tweak.valueName -ErrorAction Stop).$($tweak.valueName)
        }
        catch {
            $actual = $null
        }
        $status = 'FAIL'
        if ($null -ne $actual -and [int]$actual -eq [int]$tweak.value) { $status = 'PASS' }
        Add-VerificationCheck -Context $ctx -Id $tweak.id -Check ('Реестр: {0}' -f $tweak.name) -Expected ([string]$tweak.value) -Actual $(if ($null -eq $actual) { '<нет>' } else { [string]$actual }) -Status $status -Note $tweak.pattern
    }

    # --- S: службы ---
    $serviceManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/services/ServiceGate.json') -Raw | ConvertFrom-Json
    foreach ($svc in $serviceManifest.services) {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $svc.name
        $actual = $null
        if (Test-Path -LiteralPath $key) {
            $actual = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Start
        }
        $status = 'FAIL'
        $note = $svc.pattern
        if ($null -eq $actual) { $status = 'SKIP'; $note = 'служба отсутствует в системе' }
        elseif ([int]$actual -eq [int]$svc.targetStart) { $status = 'PASS' }
        Add-VerificationCheck -Context $ctx -Id ('S-{0}' -f $svc.name) -Check ('Служба: {0}' -f $svc.name) -Expected ('Start={0}' -f $svc.targetStart) -Actual $(if ($null -eq $actual) { '<нет>' } else { 'Start=' + $actual }) -Status $status -Note $note
    }

    # --- X: provisioned AppX ---
    $appxManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/appx/AppxRemoval.json') -Raw | ConvertFrom-Json
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    if ($provisioned.Count -eq 0) {
        Add-VerificationCheck -Context $ctx -Id 'X0' -Check 'Provisioned-пакеты' -Expected 'список доступен' -Actual 'получить не удалось' -Status 'WARN' -Note 'модуль DISM недоступен или среда WinPE'
    }
    else {
        $leftover = New-Object System.Collections.Generic.List[string]
        foreach ($pattern in $appxManifest.removePatterns) {
            foreach ($p in @($provisioned | Where-Object { $_.DisplayName -match $pattern })) {
                $isProtected = $false
                foreach ($gp in $appxManifest.protectedPatterns) { if ($p.DisplayName -match $gp) { $isProtected = $true } }
                if (-not $isProtected) { $leftover.Add($p.DisplayName) }
            }
        }
        Add-VerificationCheck -Context $ctx -Id 'X1' -Check 'Provisioned-пакеты удалены' -Expected '0 совпадений' -Actual ('{0}' -f $leftover.Count) -Status $(if ($leftover.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note (($leftover -join '; '))
    }

    # --- M1: файл подкачки ---
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $auto = $cs.AutomaticManagedPagefile
    $pf = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'C:*' } | Select-Object -First 1
    if ($null -eq $pf) {
        Add-VerificationCheck -Context $ctx -Id 'M1' -Check 'Файл подкачки: настройка' -Expected ('фиксированный {0}/{0} МБ' -f $PageFileMb) -Actual 'настройка отсутствует' -Status 'FAIL' -Note 'PAT-13'
    }
    else {
        $sizeOk = ([int]$pf.InitialSize -eq $PageFileMb) -and ([int]$pf.MaximumSize -eq $PageFileMb)
        $autoOk = ($auto -eq $false)
        $status = 'FAIL'
        if ($sizeOk -and $autoOk) { $status = 'PASS' }
        Add-VerificationCheck -Context $ctx -Id 'M1' -Check 'Файл подкачки: фиксация' -Expected ('AutomaticManaged=False; {0}/{0} МБ' -f $PageFileMb) -Actual ('AutomaticManaged={0}; {1}/{2} МБ' -f $auto, $pf.InitialSize, $pf.MaximumSize) -Status $status -Note 'PAT-13'
    }

    # --- M2: гибернация ---
    $hiberfil = Test-Path -LiteralPath 'C:\hiberfil.sys' -ErrorAction SilentlyContinue
    Add-VerificationCheck -Context $ctx -Id 'M2' -Check 'hiberfil.sys отсутствует' -Expected 'отсутствует' -Actual $(if ($hiberfil) { 'присутствует' } else { 'отсутствует' }) -Status $(if ($hiberfil) { 'FAIL' } else { 'PASS' }) -Note 'PAT-14'

    # --- B1: loadoptions ---
    $raw = ''
    try { $raw = (& bcdedit.exe /enum '{current}') 2>&1 | Out-String } catch { $raw = '' }
    $loadoptions = ''
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*loadoptions\s+(?<v>.+)$') { $loadoptions = $Matches['v'].Trim() }
    }
    $bcdOk = ($loadoptions -match 'DISABLE-LSA-ISOLATION') -and ($loadoptions -match 'DISABLE-VBS')
    Add-VerificationCheck -Context $ctx -Id 'B1' -Check 'BCD: VBS/LSA демонтаж' -Expected 'DISABLE-LSA-ISOLATION,DISABLE-VBS' -Actual $(if ($loadoptions) { $loadoptions } else { '<нет>' }) -Status $(if ($bcdOk) { 'PASS' } else { 'FAIL' }) -Note 'PAT-12, AR-505'

    # --- V1: VBS runtime ---
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue
    if ($null -eq $dg) {
        Add-VerificationCheck -Context $ctx -Id 'V1' -Check 'VBS не запущен' -Expected 'VirtualizationBasedSecurityStatus=0' -Actual 'класс WMI недоступен' -Status 'WARN'
    }
    else {
        $vbs = [int]$dg.VirtualizationBasedSecurityStatus
        Add-VerificationCheck -Context $ctx -Id 'V1' -Check 'VBS не запущен' -Expected '0' -Actual ([string]$vbs) -Status $(if ($vbs -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'действует после перезагрузки'
    }

    Write-VerificationReport -Context $ctx -ExportPath $ExportReport

    exit (Get-VerificationExitCode -Context $ctx)
}
catch {
    Write-Host ('FATAL: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit $exit.Fatal
}
