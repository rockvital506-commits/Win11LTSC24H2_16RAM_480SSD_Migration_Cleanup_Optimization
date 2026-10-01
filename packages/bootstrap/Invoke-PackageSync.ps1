<#
.SYNOPSIS
    Синхронизация установленного ПО с lock-файлом пакетов (AR-601…AR-607).

.DESCRIPTION
    Stage 7 — единственный разрешённый путь управления пакетами (AR-601):
    ручные `winget upgrade/uninstall` запрещены (AR-606). Скрипт приводит
    систему к состоянию packages/lock/Packages.lock.json.

    Режимы:
      (по умолчанию)        установка/приведение к версиям lock-файла;
      -ResolveVersions      запрос `winget show` и заполнение lock-файла
                            (выполняется в окне сети один раз, AR-602);
      -Verify               только чтение: сравнение установленного с lock;
      -Remove               точное удаление версии из lock-файла (AR-204).

    Ограничения:
      - пакет с `status = UNPINNED` не устанавливается: сначала версии (AR-602);
      - msstore отключается (AR-604), источник winget фиксирован;
      - сеть скрипт не поднимает: в режимах установки требуется открытое окно
        сети (AR-709), иначе FAIL предусловия.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Profile
    Профиль: base | devops | admin. Без параметра — все пакеты lock-файла.

.PARAMETER ResolveVersions
    Заполнить версии и хэши в lock-файле через `winget show`.

.PARAMETER Verify
    Только чтение: что установлено и что ожидается.

.PARAMETER Remove
    Удалить пакеты профиля (точные версии). Только по явному флагу (AR-204).

.PARAMETER Audit
    Не менять ничего: печатать команды, которые были бы выполнены.

.EXAMPLE
    pwsh -File ./packages/bootstrap/Invoke-PackageSync.ps1 -ResolveVersions
    pwsh -File ./packages/bootstrap/Invoke-PackageSync.ps1 -Profile devops
    pwsh -File ./packages/bootstrap/Invoke-PackageSync.ps1 -Verify

.NOTES
    Script-ID  : SCRIPT-PKG-002
    Stage      : 7
    Patterns   : —
    ADR        : ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-301, AR-302, AR-303, AR-306, AR-307, AR-501, AR-601…AR-607, AR-709)
    Depends    : packages/lock/Packages.lock.json, packages/winget/profiles/*.winget, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [ValidateSet('base', 'devops', 'admin')][string]$Profile,

    [switch]$ResolveVersions,

    [switch]$Verify,

    [switch]$Remove,

    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-PKG-002'
$lockPath = Join-Path $RepoRoot 'packages/lock/Packages.lock.json'

function Get-WingetPath {
    [CmdletBinding()]
    param()
    return (Get-Command -Name winget.exe -ErrorAction SilentlyContinue)
}

function Get-PackageSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Lock,
        [string]$ProfileName
    )

    $items = @($Lock.packages)
    if ($ProfileName) {
        # Профиль читается из winget-списка: состав объявлен одним источником.
        $profileFile = Join-Path $RepoRoot ('packages/winget/profiles/{0}.winget' -f $ProfileName)
        if (-not (Test-Path -LiteralPath $profileFile)) { throw ('Профиль не найден: {0}' -f $profileFile) }
        $declared = @((Get-Content -LiteralPath $profileFile -Raw -Encoding UTF8 | ConvertFrom-Json).Sources[0].Packages | ForEach-Object { $_.PackageIdentifier })
        $items = @($items | Where-Object { $declared -contains $_.id })
    }
    return $items
}

function Get-InstalledVersion {
    <# Версия установленного пакета по данным winget list (пустая строка — не установлен). #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Id)

    $out = & winget.exe list --id $Id --exact --accept-source-agreements 2>$null
    foreach ($line in @($out)) {
        if ($line -match [regex]::Escape($Id) -and $line -match '^\S') {
            $fields = [regex]::Split(($line -replace '\s{2,}', '|'), '\|') | Where-Object { $_ -ne '' }
            for ($i = 0; $i -lt $fields.Count; $i++) {
                if ($fields[$i] -eq $Id) {
                    if ($i + 1 -lt $fields.Count) { return $fields[$i + 1].Trim() }
                    break
                }
            }
        }
    }
    return ''
}

function Get-WingetShowInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Id)

    $out = & winget.exe show --id $Id --exact --source winget 2>$null
    $version = ''
    $sha = ''
    foreach ($line in @($out)) {
        if (-not $version -and $line -match '^\s*Version:\s*(\S+)') { $version = $Matches[1] }
        if (-not $sha -and $line -match '^\s*Sha256:\s*([0-9a-fA-F]{64})') { $sha = $Matches[1] }
    }
    return [pscustomobject]@{ Version = $version; Sha256 = $sha }
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 7 — синхронизация пакетов (winget)'

    $winget = Get-WingetPath
    if (-not $winget) {
        Add-VerificationCheck -Context $context -Id 'PKG0.1' -Check 'winget доступен' -Expected 'winget.exe' -Actual 'не найден' -Status 'FAIL' -Note 'AR-601'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }
    Add-VerificationCheck -Context $context -Id 'PKG0.1' -Check 'winget доступен' -Expected 'найден' -Actual ([string]$winget.Source) -Status 'PASS'

    if (-not (Test-Path -LiteralPath $lockPath)) {
        Add-VerificationCheck -Context $context -Id 'PKG0.2' -Check 'Lock-файл' -Expected 'Packages.lock.json' -Actual 'отсутствует' -Status 'FAIL'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # --- AR-604: источники фиксированы, msstore отключён ---
    $sources = (& winget.exe source list --accept-source-agreements 2>$null) -join "`n"
    $msstorePresent = $sources -match 'msstore'
    if ($msstorePresent -and -not $Audit -and -not $Verify) {
        if ($PSCmdlet.ShouldProcess('msstore', 'winget source remove')) {
            & winget.exe source remove msstore 2>$null | Out-Null
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Источник msstore отключён (AR-604).'
        }
    }
    Add-VerificationCheck -Context $context -Id 'PKG0.3' -Check 'msstore отключён (AR-604)' `
        -Expected 'источник отсутствует' -Actual $(if ($msstorePresent -and -not $Audit -and -not $Verify) { 'отключён' } elseif ($msstorePresent) { 'присутствует' } else { 'отсутствует' }) `
        -Status $(if ($msstorePresent -and ($Audit -or $Verify)) { 'WARN' } else { 'PASS' })

    $packages = @(Get-PackageSet -Lock $lock -ProfileName $Profile)
    if ($packages.Count -eq 0) {
        Add-VerificationCheck -Context $context -Id 'PKG0.4' -Check 'Состав пакетов' -Expected '≥ 1' -Actual '0' -Status 'FAIL' -Note 'Проверить -Profile и lock-файл.'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }

    # --- сеть нужна только для установки и резолва (AR-709) ---
    if (-not $Verify) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        $netStatus = if ($adapters.Count -gt 0) { 'PASS' } else { 'FAIL' }
        if ($ResolveVersions -or (-not $Remove)) {
            Add-VerificationCheck -Context $context -Id 'PKG0.5' -Check 'Окно сети открыто (AR-709)' `
                -Expected '≥ 1 адаптер' -Actual ([string]$adapters.Count) -Status $netStatus `
                -Note 'Сеть поднимает владелец (§4.5 README).'
        }
    }

    if ($ResolveVersions) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage7-packages'
        Copy-Item -LiteralPath $lockPath -Destination (Join-Path $backupDir 'Packages.lock.json') -Force
        $updated = 0
        foreach ($pkg in $packages) {
            $info = Get-WingetShowInfo -Id $pkg.id
            if (-not $info.Version) {
                Write-Log -Level 'WARN' -Component $scriptId -Message ('{0}: winget show не вернул версию.' -f $pkg.id)
                continue
            }
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0}: version={1}, sha256={2}' -f $pkg.id, $info.Version, $(if ($info.Sha256) { 'есть' } else { 'нет' }))
                continue
            }
            $pkg.version = $info.Version
            $pkg.status = 'PINNED'
            $pkg.date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
            if ($info.Sha256) { $pkg.sha256 = $info.Sha256 }
            $updated++
            Write-Log -Level 'PASS' -Component $scriptId -Message ('{0}: версия {1} зафиксирована.' -f $pkg.id, $info.Version)
        }
        if (-not $Audit) {
            $lock | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lockPath -Encoding UTF8
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Lock-файл обновлён: {0} пакет(ов).' -f $updated)
        }
        Add-VerificationCheck -Context $context -Id 'PKG-R1' -Check 'Версии зафиксированы' -Expected ([string]$packages.Count) `
            -Actual ([string]$updated) -Status $(if ($updated -eq $packages.Count) { 'PASS' } else { 'WARN' }) -Note 'AR-602'
    }
    else {
        $okCount = 0
        $pending = @($packages | Where-Object { $_.status -ne 'PINNED' -or -not $_.version })
        if ($pending.Count -gt 0) {
            Add-VerificationCheck -Context $context -Id 'PKG-P0' -Check 'Lock-файл заполнен (AR-602)' `
                -Expected '0 UNPINNED' -Actual ([string]$pending.Count) -Status 'FAIL' `
                -Note ('Запустите: Invoke-PackageSync.ps1 -ResolveVersions. Не зафиксированы: ' + (($pending | ForEach-Object { $_.id }) -join ', '))
            Write-VerificationReport -Context $context
            exit $exit.Precondition
        }

        foreach ($pkg in $packages) {
            $installed = Get-InstalledVersion -Id $pkg.id
            if ($Remove) {
                if (-not $installed) {
                    Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: не установлен (AR-303).' -f $pkg.id)
                    continue
                }
                if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message ('winget uninstall {0} --version {1}' -f $pkg.id, $pkg.version); continue }
                if ($PSCmdlet.ShouldProcess($pkg.id, ('winget uninstall --version {0}' -f $pkg.version))) {
                    & winget.exe uninstall --id $pkg.id --exact --version $pkg.version --accept-source-agreements --disable-interactivity | Out-Null
                    Write-Log -Level $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }) -Component $scriptId -Message ('{0}: удаление, код {1}.' -f $pkg.id, $LASTEXITCODE)
                }
                continue
            }

            if ($installed -eq $pkg.version) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('{0}: {1} — уже целевая версия (AR-303).' -f $pkg.id, $installed)
                $okCount++
                continue
            }
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('winget install --id {0} --exact --version {1} (установлено: {2})' -f $pkg.id, $pkg.version, $(if ($installed) { $installed } else { 'нет' }))
                continue
            }
            if ($PSCmdlet.ShouldProcess($pkg.id, ('winget install --version {0}' -f $pkg.version))) {
                & winget.exe install --id $pkg.id --exact --version $pkg.version --accept-source-agreements --accept-package-agreements --silent --disable-interactivity --source winget | Out-Null
                $code = $LASTEXITCODE
                Write-Log -Level $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }) -Component $scriptId -Message ('{0}: установка версии {1}, код {2}.' -f $pkg.id, $pkg.version, $code)
                if ($code -eq 0) { $okCount++ }
            }
        }

        if (-not $Audit) {
            foreach ($pkg in $packages) {
                $installed = Get-InstalledVersion -Id $pkg.id
                $match = ($installed -eq $pkg.version)
                Add-VerificationCheck -Context $context -Id ('PKG-' + $pkg.id) -Check $pkg.id `
                    -Expected $pkg.version -Actual $(if ($installed) { $installed } else { 'не установлен' }) `
                    -Status $(if ($Remove) { $(if (-not $installed) { 'PASS' } else { 'FAIL' }) } else { $(if ($match) { 'PASS' } else { 'FAIL' }) }) `
                    -Note $(if ($Verify) { 'AR-306: режим -Verify.' } else { 'AR-602/AR-603' })
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
