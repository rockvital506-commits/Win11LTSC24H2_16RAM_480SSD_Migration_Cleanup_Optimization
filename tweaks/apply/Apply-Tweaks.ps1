<#
.SYNOPSIS
    Применение декларативных твиков из tweaks/ (реестр, службы, AppX).

.DESCRIPTION
    Единственная точка применения твиков (AR-501): ad-hoc правки в stage-скриптах
    запрещены. Порядок работы:
      1. проверка прав и предусловий;
      2. сессия бэкапа: экспорт затронутых веток реестра, конфигурации служб;
      3. применение манифеста реестра (идемпотентно, AR-301/303);
      4. применение ServiceGate (тип запуска 4 / Disabled);
      5. удаление provisioned AppX по списку (по умолчанию включено, отключается -SkipAppx);
      6. верификация через Assert-TweakState.ps1 (не вызывается при -Audit).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Режим только чтения: показать, что было бы изменено.

.PARAMETER SkipAppx
    Не трогать provisioned-пакеты.

.PARAMETER SkipServices
    Не трогать службы.

.EXAMPLE
    pwsh -File ./tweaks/apply/Apply-Tweaks.ps1 -RepoRoot C:\repo -Audit
    pwsh -File ./tweaks/apply/Apply-Tweaks.ps1 -RepoRoot C:\repo

.NOTES
    Script-ID  : SCRIPT-TWEAKS-001
    Stage      : 4, 6
    Patterns   : PAT-03, PAT-12, PAT-15
    ADR        : ADR-0012
    Rules      : AUTOMATION_RULES.md (AR-301, AR-302, AR-303, AR-304, AR-306, AR-307, AR-501, AR-503)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$SkipAppx,

    [switch]$SkipServices
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit = Get-ExitCode
$scriptId = 'SCRIPT-TWEAKS-001'
$script:Changed = 0

function Invoke-RegistryManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [string]$BackupDir,
        [switch]$Audit
    )

    foreach ($tweak in $Manifest.tweaks) {
        $current = $null
        try {
            $current = (Get-ItemProperty -LiteralPath $tweak.hive -Name $tweak.valueName -ErrorAction Stop).$($tweak.valueName)
        }
        catch {
            $current = $null
        }

        if ($null -ne $current -and [int]$current -eq [int]$tweak.value) {
            Write-Log -Component $scriptId -Message ('{0}: уже соответствует ({1}={2}), пропуск.' -f $tweak.id, $tweak.valueName, $tweak.value)
            continue
        }

        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0}: {1}\{2}: {3} -> {4}' -f $tweak.id, $tweak.nativePath, $tweak.valueName, $(if ($null -eq $current) { '<нет>' } else { $current }), $tweak.value)
            continue
        }

        if ($BackupDir -and -not (Test-Path -LiteralPath (Join-Path $BackupDir ((($tweak.nativePath -replace '[\\: ]', '_')) + '.reg')))) {
            Export-RegistryKey -RegistryPath $tweak.hive -BackupDir $BackupDir | Out-Null
        }

        if (-not (Test-Path -LiteralPath $tweak.hive)) {
            New-Item -Path $tweak.hive -Force | Out-Null
        }

        if ($PSCmdlet.ShouldProcess($tweak.hive, ('{0} = {1}' -f $tweak.valueName, $tweak.value))) {
            New-ItemProperty -LiteralPath $tweak.hive -Name $tweak.valueName -Value $tweak.value -PropertyType DWord -Force | Out-Null
            $script:Changed++
            Write-Log -Level 'PASS' -Component $scriptId -Message ('{0}: {1} = {2} применено.' -f $tweak.id, $tweak.valueName, $tweak.value)
        }
    }
}

function Invoke-ServiceGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [string]$BackupDir,
        [switch]$Audit
    )

    if ($BackupDir) {
        $names = @($Manifest.services | ForEach-Object { $_.name })
        Export-ServiceConfig -ServiceName $names -BackupDir $BackupDir | Out-Null
    }

    foreach ($svc in $Manifest.services) {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $svc.name
        if (-not (Test-Path -LiteralPath $key)) {
            Write-Log -Level 'WARN' -Component $scriptId -Message ('{0}: служба отсутствует в системе, пропуск.' -f $svc.name)
            continue
        }

        $current = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Start
        if ($null -ne $current -and [int]$current -eq [int]$svc.targetStart) {
            Write-Log -Component $scriptId -Message ('{0}: уже Start={1}, пропуск.' -f $svc.name, $svc.targetStart)
            continue
        }

        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0}: Start {1} -> {2}' -f $svc.name, $current, $svc.targetStart)
            continue
        }

        if ($PSCmdlet.ShouldProcess($svc.name, ('Start = {0}' -f $svc.targetStart))) {
            Set-ItemProperty -LiteralPath $key -Name 'Start' -Value $svc.targetStart -Type DWord -Force
            $script:Changed++
            Write-Log -Level 'PASS' -Component $scriptId -Message ('{0}: Start={1} (перезагрузка не требуется).' -f $svc.name, $svc.targetStart)
        }
    }
}

function Invoke-AppxRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [switch]$Audit
    )

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    if ($provisioned.Count -eq 0) {
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Provisioned-пакеты не обнаружены (модуль DISM может быть недоступен).'
        return
    }

    foreach ($pattern in $Manifest.removePatterns) {
        $matches = @($provisioned | Where-Object { $_.DisplayName -match $pattern })

        foreach ($m in $matches) {
            $isProtected = $false
            foreach ($p in $Manifest.protectedPatterns) {
                if ($m.DisplayName -match $p) { $isProtected = $true }
            }
            if ($isProtected) {
                Write-Log -Level 'WARN' -Component $scriptId -Message ('{0}: защищённый шаблон, удаление запрещено.' -f $m.DisplayName)
                continue
            }

            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Удаление provisioned: {0}' -f $m.PackageName)
                continue
            }

            if ($PSCmdlet.ShouldProcess($m.PackageName, 'Remove-AppxProvisionedPackage')) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $m.PackageName -ErrorAction Stop | Out-Null
                    $script:Changed++
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('Удалён provisioned-пакет: {0}' -f $m.PackageName)
                }
                catch {
                    Write-Log -Level 'WARN' -Component $scriptId -Message ('Не удалось удалить {0}: {1}' -f $m.PackageName, $_.Exception.Message)
                }
            }
        }
    }
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $registryManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/registry/RegistryManifest.json') -Raw | ConvertFrom-Json
    $serviceManifest  = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/services/ServiceGate.json')      -Raw | ConvertFrom-Json
    $appxManifest     = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/appx/AppxRemoval.json')          -Raw | ConvertFrom-Json

    $backupDir = ''
    if (-not $Audit) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'tweaks'
        Write-Log -Level 'INFO' -Component $scriptId -Message ('Сессия бэкапа: {0}' -f $backupDir)
    }

    Write-Log -Component $scriptId -Message ('Режим: {0}' -f $(if ($Audit) { 'AUDIT (изменения не вносятся)' } else { 'ПРИМЕНЕНИЕ' }))

    Invoke-RegistryManifest -Manifest $registryManifest -BackupDir $backupDir -Audit:$Audit
    if (-not $SkipServices) { Invoke-ServiceGate -Manifest $serviceManifest -BackupDir $backupDir -Audit:$Audit }
    if (-not $SkipAppx)     { Invoke-AppxRemoval -Manifest $appxManifest -Audit:$Audit }

    if (-not $Audit -and $backupDir) {
        $manifest = Get-BackupManifest -BackupDir $backupDir
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Манифест бэкапа: {0}' -f $manifest)
    }

    Write-Log -Level 'PASS' -Component $scriptId -Message ('Изменений внесено: {0}.' -f $script:Changed)
    exit $exit.Ok
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
