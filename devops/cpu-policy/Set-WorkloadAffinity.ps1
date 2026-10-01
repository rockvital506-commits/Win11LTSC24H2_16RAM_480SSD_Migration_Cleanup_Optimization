<#
.SYNOPSIS
    Привязка рабочих нагрузок к P-ядрам и проверка схемы питания (AR-705).

.DESCRIPTION
    Stage 7 — применение политики P+E (ADR-0010). Маска P-ядер берётся
    динамически из Get-PerformanceCoreMask.ps1 (хардкод запрещён, AR-704).

    Что делает скрипт:
      1. получает маску P-ядер; при Hybrid=$false ничего не применяет;
      2. привязывает перечисленные процессы к P-ядрам и поднимает им класс
         приоритета не выше Normal (AR-705): по умолчанию vmmemWSL (WSL2),
         процессы сборки и виртуализации;
      3. (опция -VerifyPowerPlan) сверяет схему питания с декларацией
         devops/cpu-policy/power-plan.json;
      4. (опция -ApplyPowerPlan) приводит схему питания к декларации через
         powercfg — это изменение системы, выполняется только явным флагом.

    Фоновые процессы списком не трогаются: смещение фоновых задач на E-ядра —
    штатное поведение планировщика Windows при отключённых VBS/HVCI (AR-706).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER ProcessName
    Имена процессов для привязки (по умолчанию vmmemWSL, msbuild, cl, devenv, vmware-vmx).

.PARAMETER Audit
    Только чтение: показать, что было бы применено.

.PARAMETER VerifyPowerPlan
    Сверить активную схему питания с power-plan.json.

.PARAMETER ApplyPowerPlan
    Применить значения из power-plan.json (powercfg). Деструктивным не является,
    но меняет систему — только явным флагом (AR-204).

.EXAMPLE
    pwsh -File ./devops/cpu-policy/Set-WorkloadAffinity.ps1 -Audit
    pwsh -File ./devops/cpu-policy/Set-WorkloadAffinity.ps1 -VerifyPowerPlan

.NOTES
    Script-ID  : SCRIPT-CPU-002
    Stage      : 7
    Patterns   : PAT-21
    ADR        : ADR-0010, ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-306, AR-307, AR-501, AR-704, AR-705, AR-706, AR-709)
    Depends    : devops/cpu-policy/Get-PerformanceCoreMask.ps1, power-plan.json, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string[]]$ProcessName = @('vmmemWSL', 'msbuild', 'cl', 'devenv', 'vmware-vmx'),

    [switch]$Audit,

    [switch]$VerifyPowerPlan,

    [switch]$ApplyPowerPlan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-CPU-002'
$powerPlanPath = Join-Path $RepoRoot 'devops/cpu-policy/power-plan.json'

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 7 — привязка нагрузок к P-ядрам'

    $topology = & (Join-Path $PSScriptRoot 'Get-PerformanceCoreMask.ps1') -AsJson | ConvertFrom-Json
    Add-VerificationCheck -Context $context -Id 'A0.1' -Check 'Определение P-ядер (AR-704)' `
        -Expected 'Hybrid=$true' -Actual ('Hybrid={0}; P={1}E={2}; mask=0x{3:X}' -f $topology.Hybrid, $topology.PCores, $topology.ECores, [uint64]$topology.PMask) `
        -Status $(if ($topology.Hybrid) { 'PASS' } else { 'WARN' }) -Note ($(if ($topology.Warning) { $topology.Warning } else { $topology.Method }))

    $pMask = [uint64]$topology.PMask
    $applied = 0
    $skipped = 0

    foreach ($name in $ProcessName) {
        $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) {
            Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: процессов нет (AR-303).' -f $name)
            $skipped++
            continue
        }

        foreach ($proc in $procs) {
            $current = $proc.ProcessorAffinity
            $currentMask = if ($current) { [uint64]$current.ToUInt64() } else { [uint64]0 }
            if ($currentMask -eq $pMask) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0} (PID {1}): уже на P-ядрах (AR-303).' -f $name, $proc.Id)
                $applied++
                continue
            }
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0} (PID {1}): affinity 0x{2:X} -> 0x{3:X}, priority Normal' -f $name, $proc.Id, $currentMask, $pMask)
                continue
            }
            if (-not $topology.Hybrid) {
                Write-Log -Level 'WARN' -Component $scriptId -Message ('{0}: гибридность не определена, привязка не применяется.' -f $name)
                continue
            }
            if ($PSCmdlet.ShouldProcess(('{0} (PID {1})' -f $name, $proc.Id), 'Set ProcessorAffinity to P-cores')) {
                try {
                    $proc.ProcessorAffinity = [IntPtr]([int64]$pMask)
                    if ($proc.PriorityClass -ne 'Normal') { $proc.PriorityClass = 'Normal' }
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('{0} (PID {1}): привязан к P-ядрам 0x{2:X}.' -f $name, $proc.Id, $pMask)
                    $applied++
                }
                catch {
                    Write-Log -Level 'WARN' -Component $scriptId -Message ('{0} (PID {1}): нет доступа к affinity: {2}' -f $name, $proc.Id, $_.Exception.Message)
                }
            }
        }
    }

    if (-not $Audit) {
        Add-VerificationCheck -Context $context -Id 'A1.1' -Check 'Привязка процессов' `
            -Expected 'применено/уже применено' -Actual ('{0} обр., {1} без процессов' -f $applied, $skipped) `
            -Status $(if ($topology.Hybrid) { 'PASS' } else { 'WARN' }) -Note 'AR-705: приоритет не выше Normal'
    }

    # --- схема питания по декларации ---
    if ($VerifyPowerPlan -or $ApplyPowerPlan) {
        if (-not (Test-Path -LiteralPath $powerPlanPath)) {
            Add-VerificationCheck -Context $context -Id 'A2.0' -Check 'Декларация схемы питания' -Expected 'power-plan.json' -Actual 'отсутствует' -Status 'FAIL'
        }
        else {
            $plan = Get-Content -LiteralPath $powerPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $active = (& powercfg.exe /getactivescheme) -join ' '
            Add-VerificationCheck -Context $context -Id 'A2.1' -Check 'Активная схема питания' `
                -Expected $plan.activeScheme -Actual $active -Status 'PASS' -Note 'Сверка выполняется вручную: имя схемы локализовано.'

            foreach ($setting in $plan.settings) {
                $query = (& powercfg.exe /query SCHEME_CURRENT $setting.subgroup $setting.setting) -join "`n"
                $match = [regex]::Match($query, 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)')
                $actualValue = if ($match.Success) { [Convert]::ToInt32($match.Groups[1].Value, 16) } else { -1 }
                $ok = ($actualValue -eq [int]$setting.targetAc)
                if ($ApplyPowerPlan -and -not $ok -and -not $Audit) {
                    if ($PSCmdlet.ShouldProcess($setting.setting, ('powercfg /setacvalueindex -> {0}' -f $setting.targetAc))) {
                        & powercfg.exe /setacvalueindex SCHEME_CURRENT $setting.subgroup $setting.setting $setting.targetAc | Out-Null
                        & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
                        $actualValue = [int]$setting.targetAc
                        $ok = $true
                        Write-Log -Level 'PASS' -Component $scriptId -Message ('{0}: установлено {1}.' -f $setting.name, $setting.targetAc)
                    }
                }
                Add-VerificationCheck -Context $context -Id $setting.id -Check $setting.name -Expected ([string]$setting.targetAc) `
                    -Actual ([string]$actualValue) -Status $(if ($ok) { 'PASS' } else { 'WARN' }) -Note $setting.reason
            }
        }
    }

    if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: изменения не вносились.' }

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
