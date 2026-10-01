<#
.SYNOPSIS
    <Краткое назначение скрипта в одну строку.>

.DESCRIPTION
    Эталонный шаблон автоматизации проекта (AR-401, AR-402, AR-403).
    Копируйте в целевой каталог и заполните поля блока .NOTES.

    Обязательные свойства:
      - идемпотентность: повторный запуск не меняет результат (AR-301);
      - режим -Audit / -WhatIf по умолчанию (AR-302);
      - проверка состояния до изменения (AR-303);
      - бэкап-перед-изменением (AR-304);
      - verification-блок PASS/FAIL (AR-307);
      - коды возврата 0 / 10 / 20 / 30 / 99 (AR-306).

.NOTES
    Script-ID   : <SCRIPT-ID>
    Stage       : <N>
    Patterns    : PAT-NN
    ADR         : ADR-NNNN
    Rules       : AUTOMATION_RULES.md (AR-3xx, AR-4xx)
    Depends     : scripts/common/Logging.psm1, Backup.psm1, Verification.psm1, Guard.psm1
    Author      : <Автор / AI-агент>
    Created     : YYYY-MM-DD
    Schema      : 3.0.0

.PARAMETER RepoRoot
    Корень репозитория. По умолчанию — каталог двумя уровнями выше скрипта.

.PARAMETER Audit
    Режим только чтения: скрипт сообщает, что было бы изменено, и не выполняет запись.

.EXAMPLE
    pwsh -File ./scripts/StageN_Example.ps1 -Audit
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Коды возврата (AR-306) -------------------------------------------------
$script:ExitOk           = 0
$script:ExitVerifyFailed = 10
$script:ExitPrecondition = 20
$script:ExitPartial      = 30
$script:ExitFatal        = 99

# --- Логирование (заменяется на Logging.psm1 в боевых скриптах) -------------
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'PASS', 'FAIL')][string]$Level = 'INFO'
    )
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Host ('[{0}] [{1}] {2}' -f $stamp, $Level, $Message)
}

# --- 1. Предусловия (AR-303) ------------------------------------------------
function Test-Precondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        Write-Log -Level 'FAIL' -Message ('RepoRoot не найден: {0}' -f $RepoRoot)
        return $false
    }

    # TODO: проверить версию ОС, наличие утилит из tools/, состояние сети (AR-709).
    return $true
}

# --- 2. Основное действие ---------------------------------------------------
function Invoke-Work {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,

        [switch]$Audit
    )

    $targets = @(
        # TODO: перечислить целевые объекты (ключи реестра, службы, пакеты).
    )

    foreach ($target in $targets) {
        if ($Audit) {
            Write-Log -Message ('AUDIT: {0} — изменение не выполняется' -f $target)
            continue
        }

        # Бэкап-перед-изменением (AR-304)
        # Export-Backup -Component $target -RepoRoot $RepoRoot

        if ($PSCmdlet.ShouldProcess($target, 'Применить изменение')) {
            Write-Log -Message ('Применяю: {0}' -f $target)
        }
    }
}

# --- 3. Верификация (AR-307) ------------------------------------------------
function Test-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $checks = @(
        # TODO: описать проверки: @{ Name = '...'; Expected = '...'; Actual = '...' }
    )

    $failed = 0
    foreach ($check in $checks) {
        if ($check.Expected -eq $check.Actual) {
            Write-Log -Level 'PASS' -Message ('{0}: PASS' -f $check.Name)
        }
        else {
            Write-Log -Level 'FAIL' -Message ('{0}: FAIL (ожидалось {1}, получено {2})' -f $check.Name, $check.Expected, $check.Actual)
            $failed++
        }
    }

    return $failed
}

# --- Точка входа ------------------------------------------------------------
try {
    Write-Log -Message ('Старт. Audit={0}' -f [bool]$Audit)

    if (-not (Test-Precondition -RepoRoot $RepoRoot)) {
        exit $script:ExitPrecondition
    }

    Invoke-Work -RepoRoot $RepoRoot -Audit:$Audit

    if ($Audit) {
        Write-Log -Message 'Режим -Audit завершён, изменения не вносились.'
        exit $script:ExitOk
    }

    $failed = Test-Result -RepoRoot $RepoRoot
    if ($failed -gt 0) {
        Write-Log -Level 'FAIL' -Message ('Верификация провалена: {0} проверок' -f $failed)
        exit $script:ExitVerifyFailed
    }

    Write-Log -Level 'PASS' -Message 'Все проверки пройдены.'
    exit $script:ExitOk
}
catch {
    Write-Log -Level 'ERROR' -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $script:ExitFatal
}
