<#
.SYNOPSIS
    Применение декларации правил брандмауэра (Stage 6, PAT-09).

.DESCRIPTION
    Читает tweaks/firewall/FirewallManifest.json и приводит Windows Firewall
    к объявленному состоянию: блокирующие исходящие правила по программам.
    Правила-обходчики (телеметрия совместимости, агент реаниматора обновлений)
    работают независимо от hosts и политик DNS, поэтому закрываются на уровне
    фильтра.

    Режимы: по умолчанию — добавить/включить отсутствующие правила (идемпотентно);
    -Remove — снять объявленные правила (обратимость, AR-204 — только явным флагом).

    Единый источник состава — манифест; рантайм-ядро читает тот же состав,
    развёрнутый как D:\GD_Tool\FirewallRules.json (tools/runtime/README.md).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: показать, что было бы применено или снято.

.PARAMETER Remove
    Снять объявленные правила вместо добавления.

.PARAMETER RuleId
    Обработать только указанное правило (FW-001/FW-002).

.EXAMPLE
    pwsh -File ./tweaks/apply/Apply-FirewallManifest.ps1 -Audit
    pwsh -File ./tweaks/apply/Apply-FirewallManifest.ps1

.NOTES
    Script-ID  : SCRIPT-FW-001
    Stage      : 6
    Patterns   : PAT-09
    ADR        : ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-303, AR-306, AR-307, AR-501)
    Depends    : tweaks/firewall/FirewallManifest.json, scripts/common/{Logging,Verification}.psm1
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$Remove,

    [string]$RuleId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-FW-001'
$manifestPath = Join-Path $RepoRoot 'tweaks/firewall/FirewallManifest.json'

function Resolve-RuleProgram {
    <# Манифест хранит путь с плейсхолдером %SystemRoot%; Firewall API ждёт абсолютный путь. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Program)

    return $Program.Replace('%SystemRoot%', $env:SystemRoot)
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 6 — правила брандмауэра'

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Add-VerificationCheck -Context $context -Id 'FW-000' -Check 'Манифест правил брандмауэра' `
            -Expected 'существует' -Actual 'отсутствует' -Status 'FAIL'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules = @($manifest.rules)
    if ($RuleId) { $rules = @($rules | Where-Object { $_.id -eq $RuleId }) }

    if ($rules.Count -eq 0) {
        Add-VerificationCheck -Context $context -Id 'FW-001' -Check 'Состав правил' -Expected '≥ 1' -Actual '0' -Status 'FAIL' -Note 'Проверить RuleId или манифест.'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }

    foreach ($rule in $rules) {
        $program = Resolve-RuleProgram -Program $rule.program
        $existing = Get-NetFirewallRule -DisplayName $rule.displayName -ErrorAction SilentlyContinue

        if ($Remove) {
            if (-not $existing) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: правило отсутствует (AR-303).' -f $rule.id)
                continue
            }
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Снятие правила: {0}' -f $rule.displayName)
            }
            elseif ($PSCmdlet.ShouldProcess($rule.displayName, 'Remove-NetFirewallRule')) {
                Remove-NetFirewallRule -DisplayName $rule.displayName -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Правило снято: {0}' -f $rule.displayName)
            }
            continue
        }

        if ($existing) {
            $enabled = [bool]$existing.Enabled
            if ($enabled) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: правило уже активно (AR-303).' -f $rule.id)
            }
            elseif ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Включение правила: {0}' -f $rule.displayName)
            }
            elseif ($PSCmdlet.ShouldProcess($rule.displayName, 'Set-NetFirewallRule -Enabled True')) {
                Set-NetFirewallRule -DisplayName $rule.displayName -Enabled True -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Правило включено: {0}' -f $rule.displayName)
            }
            continue
        }

        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Создание правила: {0} -> {1}' -f $rule.displayName, $program)
        }
        elseif ($PSCmdlet.ShouldProcess($rule.displayName, 'New-NetFirewallRule -Action Block')) {
            New-NetFirewallRule -DisplayName $rule.displayName -Direction $rule.direction -Program $program `
                -Action $rule.action -Profile $rule.profiles -Enabled $true -ErrorAction Stop | Out-Null
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Правило создано: {0} -> {1}' -f $rule.displayName, $program)
        }
    }

    if (-not $Audit) {
        $index = 0
        foreach ($rule in @($manifest.rules)) {
            $index++
            $actual = Get-NetFirewallRule -DisplayName $rule.displayName -ErrorAction SilentlyContinue
            $ok = $false
            if ($Remove) {
                $ok = ($null -eq $actual)
            }
            else {
                $ok = ($null -ne $actual) -and ([bool]$actual.Enabled) -and ([string]$actual.Action -eq 'Block')
            }
            Add-VerificationCheck -Context $context -Id ('FW-{0}' -f $rule.id) -Check $rule.displayName `
                -Expected $(if ($Remove) { 'отсутствует' } else { 'Enabled, Action=Block' }) `
                -Actual $(if ($null -eq $actual) { 'отсутствует' } else { ('Enabled={0}, Action={1}' -f $actual.Enabled, $actual.Action) }) `
                -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Note $rule.pattern
        }
    }
    else {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: правила не изменялись.'
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
