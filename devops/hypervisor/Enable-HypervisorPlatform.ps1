<#
.SYNOPSIS
    Включение согласованных компонентов виртуализации (WSL2 + WHP) и фиксация гипервизорного режима.

.DESCRIPTION
    Stage 7 — гипервизорный слой. По AR-701 включаются ровно три компонента:
      - Microsoft-Windows-Subsystem-Linux  (WSL2);
      - VirtualMachinePlatform            (подсистема виртуальных машин);
      - HypervisorPlatform                (WHP API — для VMware Workstation Pro).

    Полноценный Hyper-V (Microsoft-Hyper-V-All) НЕ включается: управляющая
    обвязка не нужна, а её установка расширяет поверхность и конфликтует с
    требованием «минимальный контур» (ADR-0002, ADR-0016).

    Режим загрузчика: hypervisorlaunchtype = auto фиксируется ADR-0002 и
    проверяется верификацией (AR-702). Перед изменением BCD выгружается
    снимок (bcdedit /export, AR-505).

    Предусловие результативности (AR-706): VBS/HVCI/LSA отключены (ADR-0012)
    и не восстанавливаются — при нарушении скрипт завершается FAIL.

    Скрипт не поднимает сеть (AR-709).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: показать, что было бы включено, без DISM и BCD-операций.

.PARAMETER SkipVbsCheck
    Не считать включённые VBS/HVCI блокирующим условием (только отчёт WARN).

.EXAMPLE
    pwsh -File ./devops/hypervisor/Enable-HypervisorPlatform.ps1 -Audit
    pwsh -File ./devops/hypervisor/Enable-HypervisorPlatform.ps1

.NOTES
    Script-ID  : SCRIPT-HV-001
    Stage      : 7
    Patterns   : PAT-07
    ADR        : ADR-0002, ADR-0012, ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-206, AR-301, AR-302, AR-303, AR-304, AR-306, AR-307, AR-501, AR-505, AR-701, AR-702, AR-706, AR-709)
    Depends    : DISM (Enable-WindowsOptionalFeature), bcdedit, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$SkipVbsCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-HV-001'

# Согласованный состав компонентов (AR-701). Расширение — только через ADR.
$requiredFeatures = @(
    @{ Name = 'Microsoft-Windows-Subsystem-Linux'; Reason = 'WSL2 (PAT-21)' },
    @{ Name = 'VirtualMachinePlatform';           Reason = 'Подсистема виртуальных машин WSL2' },
    @{ Name = 'HypervisorPlatform';               Reason = 'WHP API для VMware (PAT-07)' }
)
$forbiddenFeatures = @(
    @{ Name = 'Microsoft-Hyper-V-All'; Reason = 'Полноценный Hyper-V не требуется (AR-701)' }
)

function Get-FeatureState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
    if ($feature) { return [string]$feature.State }
    return 'NotFound'
}

function Get-HypervisorLaunchType {
    [CmdletBinding()]
    param()

    $out = & bcdedit.exe /enum '{current}' 2>$null
    $line = $out | Where-Object { $_ -match '^\s*hypervisorlaunchtype\s+' } | Select-Object -First 1
    if ($line) { return (($line -split '\s+') | Where-Object { $_ } | Select-Object -Last 1) }
    return 'NotSet'
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 7 — компоненты виртуализации и WHP'

    # --- предусловие AR-706: VBS/HVCI/LSA отключены (ADR-0012) ---
    $vbsOff = ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity -eq 0)
    $hvciOff = ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 0)
    Add-VerificationCheck -Context $context -Id 'H0.1' -Check 'VBS/HVCI отключены (AR-706)' `
        -Expected '0/0' -Actual ('{0}/{1}' -f [int]$vbsOff, [int]$hvciOff) `
        -Status $(if ($vbsOff -and $hvciOff) { 'PASS' } elseif ($SkipVbsCheck) { 'WARN' } else { 'FAIL' }) `
        -Note 'ADR-0012, GATE_IMMUTABLE'

    # --- целевое состояние компонентов ---
    foreach ($item in $requiredFeatures) {
        $state = Get-FeatureState -Name $item.Name
        $ok = ($state -eq 'Enabled')
        if ($ok) {
            Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: уже включён (AR-303).' -f $item.Name)
        }
        elseif ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Включение компонента {0} ({1})' -f $item.Name, $item.Reason)
        }
        elseif ($PSCmdlet.ShouldProcess($item.Name, 'Enable-WindowsOptionalFeature')) {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $item.Name -All -NoRestart -ErrorAction Stop
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Включён компонент {0} (RestartNeeded={1}).' -f $item.Name, $result.RestartNeeded)
        }
    }

    foreach ($item in $forbiddenFeatures) {
        $state = Get-FeatureState -Name $item.Name
        $enabled = ($state -eq 'Enabled')
        Add-VerificationCheck -Context $context -Id ('H0.2.' + $item.Name) -Check ('{0} не включён' -f $item.Name) `
            -Expected 'Disabled/NotFound' -Actual $state -Status $(if ($enabled) { 'FAIL' } else { 'PASS' }) -Note $item.Reason
    }

    # --- режим гипервизора: auto (ADR-0002) ---
    $before = Get-HypervisorLaunchType
    if ($before -eq 'auto') {
        Write-Log -Level 'INFO' -Component $scriptId -Message 'hypervisorlaunchtype уже auto (AR-303).'
    }
    elseif ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('bcdedit /set hypervisorlaunchtype auto (сейчас: {0})' -f $before)
    }
    elseif ($PSCmdlet.ShouldProcess('{current}', 'bcdedit /set hypervisorlaunchtype auto')) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'backups'))) { New-Item -ItemType Directory -Path (Join-Path $RepoRoot 'backups') -Force | Out-Null }
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage7-hv'
        $bcd = Export-BcdSnapshot -BackupDir $backupDir
        Write-Log -Component $scriptId -Message ('Снимок BCD: {0}' -f $bcd)
        & bcdedit.exe /set hypervisorlaunchtype auto | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log -Level 'PASS' -Component $scriptId -Message 'hypervisorlaunchtype=auto установлен.' }
        else { Write-Log -Level 'FAIL' -Component $scriptId -Message ('bcdedit код {0}.' -f $LASTEXITCODE) }
    }

    if (-not $Audit) {
        foreach ($item in $requiredFeatures) {
            $state = Get-FeatureState -Name $item.Name
            Add-VerificationCheck -Context $context -Id ('H1.' + $item.Name) -Check ('Компонент {0}' -f $item.Name) `
                -Expected 'Enabled' -Actual $state -Status $(if ($state -eq 'Enabled') { 'PASS' } else { 'WARN' }) `
                -Note ($(if ($state -eq 'EnablePending') { 'Требуется перезагрузка.' } else { $item.Reason }))
        }
        $after = Get-HypervisorLaunchType
        Add-VerificationCheck -Context $context -Id 'H1.launchtype' -Check 'hypervisorlaunchtype' -Expected 'auto' -Actual $after `
            -Status $(if ($after -eq 'auto') { 'PASS' } else { 'FAIL' }) -Note 'ADR-0002, AR-702'
    }
    else {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: компоненты и BCD не изменялись.'
    }

    Write-VerificationReport -Context $context
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
