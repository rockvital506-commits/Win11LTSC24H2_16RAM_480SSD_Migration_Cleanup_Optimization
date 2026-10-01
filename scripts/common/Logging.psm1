<#
.SYNOPSIS
    Единый контур логирования (AR-305) и коды возврата (AR-306).

.DESCRIPTION
    Предоставляет:
      - Write-Log            : структурированная строка ISO-8601 UTC + уровень;
      - Start-LogSession     : транскрипт сессии в logs/ (каталог gitignored);
      - Stop-LogSession      : закрытие транскрипта;
      - Get-ExitCode         : канонические коды возврата проекта.

    Требования: PowerShell 5.1 (AR-403); модуль не пишет вне allow-list (AR-206).

.NOTES
    Module-ID  : MOD-COMMON-001
    Stage      : All
    ADR        : ADR-0009
    Rules      : AUTOMATION_RULES.md (AR-206, AR-305, AR-306, AR-403)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LogFile = $null

function Get-ExitCode {
    <# Канонические коды возврата (AR-306). #>
    [CmdletBinding()]
    param()

    return @{
        Ok           = 0
        VerifyFailed = 10
        Precondition = 20
        Partial      = 30
        Fatal        = 99
    }
}

function Write-Log {
    <# Структурированная запись: [ISO-8601 UTC] [LEVEL] message #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'PASS', 'FAIL', 'AUDIT')][string]$Level = 'INFO',
        [string]$Component = 'stage'
    )

    if ($Message -match "`r|`n") {
        $Message = $Message -replace "`r?`n", ' | '
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line  = '[{0}] [{1}] [{2}] {3}' -f $stamp, $Level, $Component, $Message

    $color = 'Gray'
    if ($Level -eq 'PASS')  { $color = 'Green' }
    if ($Level -eq 'FAIL')  { $color = 'Red' }
    if ($Level -eq 'ERROR') { $color = 'Red' }
    if ($Level -eq 'WARN')  { $color = 'Yellow' }
    if ($Level -eq 'AUDIT') { $color = 'Cyan' }

    Write-Host $line -ForegroundColor $color

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function Start-LogSession {
    <# Открывает файл лога в <RepoRoot>/logs/ (gitignored) и запускает транскрипт. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ScriptId
    )

    $logDir = Join-Path $RepoRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $script:LogFile = Join-Path $logDir ('{0}_{1}.log' -f $ScriptId, $stamp)

    Start-Transcript -Path $script:LogFile -Append | Out-Null
    Write-Log -Level 'INFO' -Component $ScriptId -Message ('Сессия открыта: {0}' -f $script:LogFile)
    return $script:LogFile
}

function Stop-LogSession {
    <# Закрывает транскрипт. #>
    [CmdletBinding()]
    param(
        [string]$ScriptId = 'stage'
    )

    Write-Log -Level 'INFO' -Component $ScriptId -Message 'Сессия закрыта.'
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Транскрипт мог не запускаться (например, при -Audit); это не ошибка.
    }
    $script:LogFile = $null
}

Export-ModuleMember -Function Get-ExitCode, Write-Log, Start-LogSession, Stop-LogSession
