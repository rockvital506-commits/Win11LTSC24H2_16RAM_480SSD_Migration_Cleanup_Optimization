<#
.SYNOPSIS
    Доверенная зона Microsoft Defender для контура самозащиты (Stage 6).

.DESCRIPTION
    Ультра-ранняя инъекция исключений до первой ACL-операции: без неё
    поведенческий анализатор расценивает массовое изменение прав на системные
    каталоги как ransomware-активность и помещает AutoSetup.bat в карантин.

    Декларация (ADR-0015), состав зафиксирован и не расширяется без ADR:

      DEF-001  path    D:\GD_Tool                                   каталог автоматизации
      DEF-002  path    C:\Windows\System32\GroupPolicy              цель NTFS-замка
      DEF-003  path    C:\Windows\System32\drivers\etc\hosts        доверенная зона hosts
      DEF-004  path    C:\Windows\System32\sppc.dll                файл активации (SC_PERMANENT_ACTIVATION)
      DEF-005  process wscript.exe                                  лаунчер контура

    Режимы: по умолчанию — добавить отсутствующие исключения (идемпотентно);
    -Remove — снять объявленные исключения (обратимость, AR-301).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: показать, что было бы добавлено или снято.

.PARAMETER Remove
    Снять объявленные исключения вместо добавления.

.EXAMPLE
    pwsh -File ./tweaks/apply/Invoke-DefenderAllowList.ps1 -Audit
    pwsh -File ./tweaks/apply/Invoke-DefenderAllowList.ps1

.NOTES
    Script-ID  : SCRIPT-DEF-001
    Stage      : 6
    Patterns   : PAT-09, PAT-NEW-3
    ADR        : ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-206, AR-301, AR-303, AR-306, AR-307, AR-701)
    Depends    : scripts/common/{Logging,Verification}.psm1, модуль Defender
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-DEF-001'

$defenderPaths = @(
    @{ Id = 'DEF-001'; Path = 'D:\GD_Tool' },
    @{ Id = 'DEF-002'; Path = (Join-Path $env:SystemRoot 'System32\GroupPolicy') },
    @{ Id = 'DEF-003'; Path = (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts') },
    @{ Id = 'DEF-004'; Path = (Join-Path $env:SystemRoot 'System32\sppc.dll') }
)
$defenderProcesses = @(
    @{ Id = 'DEF-005'; Name = 'wscript.exe' }
)

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 6 — доверенная зона Defender'

    if (-not (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue)) {
        Add-VerificationCheck -Context $context -Id 'DEF-000' -Check 'Модуль Defender доступен' `
            -Expected 'Get-MpPreference' -Actual 'командлет отсутствует' -Status 'FAIL' `
            -Note 'LTSC IoT без Defender или урезанный компонент; исключения не управляются (AR-701).'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }

    $pref = Get-MpPreference
    $currentPaths = @($pref.ExclusionPath)
    $currentProcesses = @($pref.ExclusionProcess)

    foreach ($item in $defenderPaths) {
        $present = $currentPaths -contains $item.Path
        if ($Remove) {
            if (-not $present) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: исключение отсутствует (AR-303).' -f $item.Id)
            }
            elseif ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Снятие исключения: {0}' -f $item.Path)
            }
            elseif ($PSCmdlet.ShouldProcess($item.Path, 'Remove-MpPreference -ExclusionPath')) {
                Remove-MpPreference -ExclusionPath $item.Path -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Исключение снято: {0}' -f $item.Path)
            }
        }
        else {
            if ($present) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: исключение уже есть (AR-303).' -f $item.Id)
            }
            elseif ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Добавление исключения: {0}' -f $item.Path)
            }
            elseif ($PSCmdlet.ShouldProcess($item.Path, 'Add-MpPreference -ExclusionPath')) {
                Add-MpPreference -ExclusionPath $item.Path -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Исключение добавлено: {0}' -f $item.Path)
            }
        }
    }

    foreach ($item in $defenderProcesses) {
        $present = $currentProcesses -contains $item.Name
        if ($Remove) {
            if ($present -and -not $Audit -and $PSCmdlet.ShouldProcess($item.Name, 'Remove-MpPreference -ExclusionProcess')) {
                Remove-MpPreference -ExclusionProcess $item.Name -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Исключение процесса снято: {0}' -f $item.Name)
            }
        }
        else {
            if ($present) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: исключение уже есть (AR-303).' -f $item.Id)
            }
            elseif ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Добавление исключения процесса: {0}' -f $item.Name)
            }
            elseif ($PSCmdlet.ShouldProcess($item.Name, 'Add-MpPreference -ExclusionProcess')) {
                Add-MpPreference -ExclusionProcess $item.Name -ErrorAction Stop
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Исключение процесса добавлено: {0}' -f $item.Name)
            }
        }
    }

    if (-not $Audit) {
        $after = Get-MpPreference
        $pathsAfter = @($after.ExclusionPath)
        $procAfter  = @($after.ExclusionProcess)

        if ($Remove) {
            $left = @($defenderPaths | Where-Object { $pathsAfter -contains $_.Path })
            $status = if ($left.Count -eq 0) { 'PASS' } else { 'FAIL' }
            Add-VerificationCheck -Context $context -Id 'DEF-R' -Check 'Исключения сняты' -Expected '0' -Actual ([string]$left.Count) -Status $status -Note 'AR-301'
        }
        else {
            $missing = @($defenderPaths | Where-Object { $pathsAfter -notcontains $_.Path })
            Add-VerificationCheck -Context $context -Id 'DEF-A1' -Check 'Исключения путей' -Expected ([string]$defenderPaths.Count) `
                -Actual ([string]($defenderPaths.Count - $missing.Count)) -Status $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0015'
            $missProc = @($defenderProcesses | Where-Object { $procAfter -notcontains $_.Name })
            Add-VerificationCheck -Context $context -Id 'DEF-A2' -Check 'Исключения процессов' -Expected ([string]$defenderProcesses.Count) `
                -Actual ([string]($defenderProcesses.Count - $missProc.Count)) -Status $(if ($missProc.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0015'
        }
    }
    else {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: исключения не изменялись.'
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
