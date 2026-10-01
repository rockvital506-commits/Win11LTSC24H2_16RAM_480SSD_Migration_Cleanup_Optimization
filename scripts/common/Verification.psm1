<#
.SYNOPSIS
    Контур верификации (AR-307) и коды возврата (AR-306).

.DESCRIPTION
    Предоставляет:
      - New-VerificationContext : контекст проверок;
      - Add-VerificationCheck   : регистрация результата (PASS/FAIL/WARN/SKIP);
      - Write-VerificationReport: вывод в консоль + markdown (UTF-8 без BOM, LF, AR-101/102);
      - Get-VerificationExitCode: код возврата по итогам проверок.

    Правило: ни один изменяющий скрипт не считается успешным без PASS-блока (AR-307).

.NOTES
    Module-ID  : MOD-COMMON-003
    Stage      : All
    ADR        : ADR-0009
    Rules      : AUTOMATION_RULES.md (AR-101, AR-102, AR-306, AR-307)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-VerificationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title
    )

    return [pscustomobject]@{
        Title   = $Title
        Checks  = New-Object System.Collections.Generic.List[object]
        Started = (Get-Date).ToUniversalTime()
    }
}

function Add-VerificationCheck {
    <# Регистрирует результат одной проверки. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Check,
        [string]$Expected = '',
        [string]$Actual = '',
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')][string]$Status,
        [string]$Note = ''
    )

    $Context.Checks.Add([pscustomobject]@{
        Id       = $Id
        Check    = $Check
        Expected = $Expected
        Actual   = $Actual
        Status   = $Status
        Note     = $Note
    })
}

function Get-VerificationFailures {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    return @($Context.Checks | Where-Object { $_.Status -eq 'FAIL' })
}

function Write-VerificationReport {
    <# Выводит проверки в консоль; при -ExportPath пишет markdown (UTF-8 без BOM, LF). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$ExportPath,
        [string]$HostName = $env:COMPUTERNAME
    )

    Write-Host ''
    Write-Host ('========== ВЕРИФИКАЦИЯ: {0} ==========' -f $Context.Title)

    foreach ($c in $Context.Checks) {
        $color = 'Gray'
        if ($c.Status -eq 'PASS') { $color = 'Green' }
        if ($c.Status -eq 'FAIL') { $color = 'Red' }
        if ($c.Status -eq 'WARN') { $color = 'Yellow' }
        Write-Host ('{0,-6} {1,-40} ожидание: {2,-28} факт: {3}' -f $c.Status, $c.Check, $c.Expected, $c.Actual) -ForegroundColor $color
        if ($c.Note) { Write-Host ('       - {0}' -f $c.Note) -ForegroundColor DarkGray }
    }

    $pass = @($Context.Checks | Where-Object { $_.Status -eq 'PASS' }).Count
    $fail = @($Context.Checks | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = @($Context.Checks | Where-Object { $_.Status -eq 'WARN' }).Count

    Write-Host '-----------------------------------------------------------'
    Write-Host ('PASS: {0}; FAIL: {1}; WARN: {2}' -f $pass, $fail, $warn)

    if ($ExportPath) {
        $dir = Split-Path -Parent $ExportPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('# Верификация: {0}' -f $Context.Title)
        $lines.Add('')
        $lines.Add('| Поле | Значение |')
        $lines.Add('|---|---|')
        $lines.Add('| Дата (UTC) | {0} |' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
        $lines.Add('| Хост | {0} |' -f $HostName)
        $lines.Add('| Начало | {0} |' -f $Context.Started.ToString('yyyy-MM-ddTHH:mm:ssZ'))
        $lines.Add('')
        $lines.Add('| ID | Проверка | Ожидание | Факт | Статус | Примечание |')
        $lines.Add('|---|---|---|---|---|---|')
        foreach ($c in $Context.Checks) {
            $lines.Add('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $c.Id, $c.Check, $c.Expected, $c.Actual, $c.Status, $c.Note)
        }
        $lines.Add('')
        $lines.Add('> Сгенерировано scripts/common/Verification.psm1. Файл UTF-8 без BOM, LF (AR-101, AR-102).')

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($ExportPath, (($lines -join "`n") + "`n"), $utf8NoBom)
        Write-Host ('Отчёт выгружен: {0}' -f $ExportPath)
    }
}

function Get-VerificationExitCode {
    <# 0 — все PASS/SKIP; 10 — есть FAIL (AR-306). #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    if ((Get-VerificationFailures -Context $Context).Count -gt 0) { return 10 }
    return 0
}

Export-ModuleMember -Function New-VerificationContext, Add-VerificationCheck, Get-VerificationFailures, Write-VerificationReport, Get-VerificationExitCode
