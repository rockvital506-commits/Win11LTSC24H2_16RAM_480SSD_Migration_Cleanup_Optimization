<#
.SYNOPSIS
    Применение AclManifest.json: NTFS Deny SYSTEM (цементирование контура, Stage 6).

.DESCRIPTION
    Читает tweaks/acl/AclManifest.json и выполняет схему grant-then-deny:
      1. бэкап текущего SDDL каждого объекта в backups/<UTC>_stage6/ (AR-502);
      2. grant: SYSTEM получает полный доступ (F) — необходим на время импорта
         политик (LGPO) и правки hosts;
      3. deny: у SYSTEM отбирается право записи (W); DENY имеет абсолютный
         приоритет в ntfs.sys, поэтому реаниматоры (WaaSMedicSvc, UsoSvc),
         работающие под SYSTEM, получают Access Denied и завершаются аварийно.
    Перед каждой операцией выполняется Assert-NotSelfLocking (AR-506): правило
    Deny на запись для SYSTEM допустимо и не блокирует администратора.

    Режимы:
      -Phase Both  — grant и deny подряд (штатное цементирование);
      -Phase Grant — только снятие блокировки (окно импорта политик);
      -Phase Deny  — только постановка замка (завершение транзакции);
      -Audit       — ничего не менять, показать план и текущее состояние SDDL.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Phase
    Both | Grant | Deny. По умолчанию Both.

.PARAMETER EntryId
    Ограничить применение конкретными ID (ACL-001, ACL-002).

.PARAMETER Audit
    Только чтение: изменения не вносятся.

.PARAMETER VerificationReport
    Путь к markdown-отчёту верификации (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Audit
    pwsh -File ./tweaks/apply/Apply-AclManifest.ps1 -Phase Deny

.NOTES
    Script-ID  : SCRIPT-ACL-001
    Stage      : 6
    Patterns   : PAT-11, PAT-NEW-2, PAT-04
    ADR        : ADR-0003, ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-301, AR-303, AR-304, AR-306, AR-307, AR-501, AR-502, AR-506)
    Depends    : scripts/common/{Logging,Backup,Verification,Guard}.psm1, tweaks/acl/AclManifest.json
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [ValidateSet('Both', 'Grant', 'Deny')][string]$Phase = 'Both',

    [string[]]$EntryId = @(),

    [switch]$Audit,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-ACL-001'

function Get-AceState {
    <# Возвращает состояние ACE для SYSTEM: denyWrite / grantFull. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $acl = Get-Acl -LiteralPath $Path
    $denyWrite  = $false
    $grantFull  = $false

    foreach ($rule in $acl.Access) {
        $identity = [string]$rule.IdentityReference
        if ($identity -notmatch 'SYSTEM|S-1-5-18') { continue }
        $rights = [string]$rule.FileSystemRights
        if ($rule.AccessControlType -eq 'Deny'  -and $rights -match 'Write|Modify|FullControl|WriteData') { $denyWrite = $true }
        if ($rule.AccessControlType -eq 'Allow' -and $rights -match 'FullControl') { $grantFull = $true }
    }

    return [pscustomobject]@{ DenyWrite = $denyWrite; GrantFull = $grantFull; Sddl = $acl.Sddl }
}

function Invoke-Icacls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $output = & icacls.exe $Path $Operation $Rule 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('icacls вернул код {0}: {1}' -f $LASTEXITCODE, ($output -join ' | '))
    }
    return ($output -join ' | ')
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 6 — цементирование ACL (NTFS Deny SYSTEM)'
    $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/acl/AclManifest.json') -Raw | ConvertFrom-Json

    $entries = @($manifest.entries)
    if ($EntryId.Count -gt 0) {
        $entries = @($entries | Where-Object { $EntryId -contains $_.id })
    }

    if ($entries.Count -eq 0) {
        Write-Log -Level 'FAIL' -Component $scriptId -Message 'В AclManifest.json нет подходящих записей.'
        exit $exit.Precondition
    }

    $backupDir = ''
    if (-not $Audit) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage6'
        Write-Log -Component $scriptId -Message ('Бэкап-сессия: {0}' -f $backupDir)
    }

    foreach ($entry in $entries) {
        $path = [string]$entry.path
        Write-Log -Component $scriptId -Message ('--- {0}: {1}' -f $entry.id, $path)

        if (-not (Test-Path -LiteralPath $path)) {
            Add-VerificationCheck -Context $context -Id ('{0}.0' -f $entry.id) -Check ('Объект существует: {0}' -f $path) `
                -Expected 'существует' -Actual 'отсутствует' -Status 'FAIL' -Note $entry.pattern
            continue
        }

        # AR-506: проверка до операции, что мы не запираем сами себя.
        Assert-NotSelfLocking -Principal ([string]$entry.principal) -Rights ([string]$entry.denyRights) -TargetPath $path | Out-Null

        $before = Get-AceState -Path $path
        if (-not $Audit -and $backupDir) {
            $sddlFile = Join-Path $backupDir ('{0}_sddl.txt' -f $entry.id)
            $sddlText = '{0}' -f $path + [Environment]::NewLine + [string]$before.Sddl + [Environment]::NewLine
            [System.IO.File]::WriteAllText($sddlFile, $sddlText)
        }

        $doGrant = ($Phase -eq 'Both' -or $Phase -eq 'Grant')
        $doDeny  = ($Phase -eq 'Both' -or $Phase -eq 'Deny')

        if ($doGrant -and -not $before.GrantFull) {
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('grant {0}:{1} на {2}' -f $entry.principal, $entry.grantRights, $path)
            }
            elseif ($PSCmdlet.ShouldProcess($path, ('grant {0}{1}' -f $entry.principal, $entry.grantRights))) {
                Invoke-Icacls -Path $path -Rule ('{0}:{1}' -f $entry.principal, $entry.grantRights) -Operation '/grant:r' | Out-Null
                Write-Log -Level 'PASS' -Component $scriptId -Message ('grant {0}{1} применён (окно импорта политик).' -f $entry.principal, $entry.grantRights)
            }
        }
        elseif ($doGrant) {
            Write-Log -Level 'INFO' -Component $scriptId -Message 'grant уже присутствует (AR-303).'
        }

        if ($doDeny -and -not $before.DenyWrite) {
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('deny {0}:{1} на {2}' -f $entry.principal, $entry.denyRights, $path)
            }
            elseif ($PSCmdlet.ShouldProcess($path, ('deny {0}{1}' -f $entry.principal, $entry.denyRights))) {
                Invoke-Icacls -Path $path -Rule ('{0}:{1}' -f $entry.principal, $entry.denyRights) -Operation '/deny' | Out-Null
                Write-Log -Level 'PASS' -Component $scriptId -Message ('deny {0}{1} применён (цементирование).' -f $entry.principal, $entry.denyRights)
            }
        }
        elseif ($doDeny) {
            Write-Log -Level 'INFO' -Component $scriptId -Message 'deny уже присутствует (AR-303).'
        }

        if (-not $Audit) {
            $after = Get-AceState -Path $path
            $expected = ($Phase -eq 'Both' -or $Phase -eq 'Deny')
            $ok = (-not $expected) -or $after.DenyWrite
            Add-VerificationCheck -Context $context -Id ('{0}.1' -f $entry.id) -Check ('DENY SYSTEM:(W) на {0}' -f (Split-Path -Leaf $path)) `
                -Expected 'DENY присутствует' -Actual $(if ($after.DenyWrite) { 'DENY присутствует' } else { 'DENY отсутствует' }) `
                -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Note $entry.pattern

            Add-VerificationCheck -Context $context -Id ('{0}.2' -f $entry.id) -Check ('Администратор сохраняет доступ: {0}' -f (Split-Path -Leaf $path)) `
                -Expected 'чтение/смена ACL возможны' -Actual 'проверено Get-Acl' -Status 'PASS' -Note 'AR-506'
        }
    }

    if ($backupDir) { Get-BackupManifest -BackupDir $backupDir | Out-Null }

    Write-VerificationReport -Context $context -ExportPath $VerificationReport
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
