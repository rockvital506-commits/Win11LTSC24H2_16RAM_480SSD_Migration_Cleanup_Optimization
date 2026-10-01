<#
.SYNOPSIS
    Изолированное изменение флагов загрузчика: демонтаж VBS/HVCI/LSA (PAT-12).

.DESCRIPTION
    Единственный скрипт проекта, которому разрешено менять BCD (AR-505).
    Обязательный порядок:
      1. проверка прав и предусловий;
      2. bcdedit /export в backups/<UTC>_bcd/ (отказ при неудаче снимка);
      3. применение loadoptions из tweaks/bcd/BcdManifest.json;
      4. верификация: bcdedit /enum {current} содержит ожидаемое значение;
      5. отчёт и предупреждение о необходимости перезагрузки.

    Режим -ProjectApplyBlocked: если элементы TWK-001..003 (реестр) ещё не применены
    и проект не применил их в текущей сессии, скрипт блокирует изменение BCD, чтобы
    не создать несогласованное состояние (BCD отключён, реестр — включён).

.PARAMETER RepoRoot
    Корень репозитория (для backups/).

.PARAMETER Audit
    Только показать план и текущее состояние, ничего не менять.

.PARAMETER Rollback
    Восстановить BCD из снимка backups/<...>/bcd_backup.bcd (bcdedit /import).

.PARAMETER SkipRegistryPrecheck
    Не проверять состояние элементов TWK-001..003 (осознанное исключение).

.EXAMPLE
    pwsh -File ./tweaks/bcd/Set-BcdVbsFlags.ps1 -RepoRoot C:\repo -Audit
    pwsh -File ./tweaks/bcd/Set-BcdVbsFlags.ps1 -RepoRoot C:\repo

.NOTES
    Script-ID  : SCRIPT-BCD-001
    Stage      : 4
    Patterns   : PAT-12
    ADR        : ADR-0012
    Rules      : AUTOMATION_RULES.md (AR-204, AR-301, AR-302, AR-304, AR-306, AR-307, AR-505)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$Rollback,

    [switch]$SkipRegistryPrecheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $RepoRoot 'scripts/common'
Import-Module (Join-Path $modulePath 'Logging.psm1')      -Force
Import-Module (Join-Path $modulePath 'Backup.psm1')       -Force
Import-Module (Join-Path $modulePath 'Verification.psm1') -Force
Import-Module (Join-Path $modulePath 'Guard.psm1')        -Force

$exit = Get-ExitCode
$scriptId = 'SCRIPT-BCD-001'

function Get-CurrentLoadOptions {
    [CmdletBinding()]
    param()

    $raw = (& bcdedit.exe /enum '{current}') 2>&1 | Out-String
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*loadoptions\s+(?<v>.+)$') { return $Matches['v'].Trim() }
    }
    return ''
}

function Get-RegistryPrecheckState {
    <# Проверяет TWK-001..003: возвращает список неприменённых. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $manifestPath = Join-Path $RepoRoot 'tweaks/registry/RegistryManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    $notApplied = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in $manifest.tweaks) {
        if ($tweak.id -notin @('TWK-001', 'TWK-002', 'TWK-003')) { continue }
        $actual = $null
        try {
            $actual = (Get-ItemProperty -LiteralPath $tweak.hive -Name $tweak.valueName -ErrorAction Stop).$($tweak.valueName)
        }
        catch {
            $actual = $null
        }
        if ($null -eq $actual -or [int]$actual -ne [int]$tweak.value) {
            $notApplied.Add($tweak.id)
        }
    }
    return $notApplied
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/bcd/BcdManifest.json') -Raw | ConvertFrom-Json
    $target = $manifest.settings[0]

    if ($Rollback) {
        $backupRoot = Join-Path $RepoRoot 'backups'
        $candidates = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter '*_bcd' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)
        if ($candidates.Count -eq 0) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message 'Снимок BCD не найден: откат невозможен.'
            exit $exit.Precondition
        }
        $snapshot = Join-Path $candidates[0].FullName 'bcd_backup.bcd'
        if (-not (Test-Path -LiteralPath $snapshot)) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('Файл снимка отсутствует: {0}' -f $snapshot)
            exit $exit.Precondition
        }

        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('План отката: bcdedit /import "{0}" (изменения не вносятся)' -f $snapshot)
            exit $exit.Ok
        }

        & bcdedit.exe /import $snapshot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('bcdedit /import завершился с кодом {0}' -f $LASTEXITCODE)
            exit $exit.Fatal
        }
        Write-Log -Level 'PASS' -Component $scriptId -Message ('BCD восстановлен из снимка: {0}' -f $snapshot)
        exit $exit.Ok
    }

    $current = Get-CurrentLoadOptions
    Write-Log -Component $scriptId -Message ('Текущие loadoptions: "{0}"' -f $current)
    Write-Log -Component $scriptId -Message ('Целевые loadoptions: "{0}"' -f $target.value)

    # Идемпотентность (AR-301/AR-303)
    if ($current -eq $target.value) {
        Write-Log -Level 'PASS' -Component $scriptId -Message 'Флаги уже установлены (идемпотентный пропуск).'
        exit $exit.Ok
    }

    if (-not $SkipRegistryPrecheck) {
        $notApplied = @(Get-RegistryPrecheckState -RepoRoot $RepoRoot)
        if ($notApplied.Count -gt 0) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('Блокировка (AR-505): элементы {0} не применены. Сначала Apply-Tweaks.ps1, затем BCD, либо -SkipRegistryPrecheck осознанно.' -f ($notApplied -join ', '))
            exit $exit.Precondition
        }
    }

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('План: bcdedit /export <backups>; bcdedit /set loadoptions "{0}" (изменения не вносятся)' -f $target.value)
        exit $exit.Ok
    }

    $session = New-BackupSession -RepoRoot $RepoRoot -StageId 'bcd'
    $snapshot = Export-BcdSnapshot -BackupDir $session
    Write-Log -Level 'PASS' -Component $scriptId -Message ('Снимок BCD создан: {0}' -f $snapshot)
    Get-BackupManifest -BackupDir $session | Out-Null

    if ($PSCmdlet.ShouldProcess('{current}', ('loadoptions = {0}' -f $target.value))) {
        & bcdedit.exe /set loadoptions $target.value | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('bcdedit /set завершился с кодом {0}. Выполните откат: -Rollback' -f $LASTEXITCODE)
            exit $exit.Fatal
        }
    }

    # Верификация (AR-307)
    $after = Get-CurrentLoadOptions
    if ($after -eq $target.value) {
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Верификация: loadoptions = "{0}"' -f $after)
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Для вступления флагов в силу требуется перезагрузка (Stage 4 завершается выключением через Sysprep).'
        exit $exit.Ok
    }

    Write-Log -Level 'FAIL' -Component $scriptId -Message ('Верификация провалена: получено "{0}"' -f $after)
    exit $exit.VerifyFailed
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
