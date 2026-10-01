<#
.SYNOPSIS
    Бэкап-перед-изменением (AR-304, PAT-19): реестр, службы, BCD, конфигурация.

.DESCRIPTION
    Предоставляет:
      - New-BackupSession      : каталог backups/<UTC>_<stage>/ (gitignored);
      - Export-RegistryKey     : reg.exe export указанной ветки;
      - Export-ServiceConfig   : выгрузка Start/ImagePath по списку служб;
      - Export-BcdSnapshot     : bcdedit /export (обязательно до правки BCD, AR-505);
      - Get-BackupManifest     : манифест SHA256 всех файлов сессии (PAT-20).

    Каталог backups/ не коммитится (AR-803).

.NOTES
    Module-ID  : MOD-COMMON-002
    Stage      : All
    ADR        : ADR-0009
    Rules      : AUTOMATION_RULES.md (AR-206, AR-304, AR-308, AR-803)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-BackupSession {
    <# Создаёт каталог сессии бэкапа под <RepoRoot>/backups/ и возвращает его путь. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$StageId
    )

    $root = Join-Path $RepoRoot 'backups'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $session = Join-Path $root ('{0}_{1}' -f $stamp, $StageId)
    New-Item -ItemType Directory -Path $session -Force | Out-Null

    return $session
}

function Export-RegistryKey {
    <# Экспортирует ветку реестра в .reg внутри каталога сессии бэкапа. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $safeName = $RegistryPath -replace '[\\: ]', '_'
    $file     = Join-Path $BackupDir ('{0}.reg' -f $safeName)

    & reg.exe export $RegistryPath $file /y | Out-Null
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Warning ('Не удалось экспортировать ветку {0} (код {1}). Возможно, ветка отсутствует.' -f $RegistryPath, $code)
    }

    return $file
}

function Export-ServiceConfig {
    <# Выгружает конфигурацию служб (Start, ImagePath) в JSON-файл сессии бэкапа. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$ServiceName,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($name in $ServiceName) {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $name
        if (Test-Path -LiteralPath $key) {
            $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            $items.Add([pscustomobject]@{
                Name      = $name
                Start     = $props.Start
                ImagePath = $props.ImagePath
                Exists    = $true
            })
        }
        else {
            $items.Add([pscustomobject]@{ Name = $name; Start = $null; ImagePath = $null; Exists = $false })
        }
    }

    $file = Join-Path $BackupDir 'services_before.json'
    $items | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
    return $file
}

function Export-BcdSnapshot {
    <# Обязательный снимок BCD перед изменением флагов загрузчика (AR-505). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $file = Join-Path $BackupDir 'bcd_backup.bcd'
    & bcdedit.exe /export $file | Out-Null
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw ('bcdedit /export завершился с кодом {0}. Изменение BCD запрещено без успешного снимка (AR-505).' -f $code)
    }

    return $file
}

function Get-BackupManifest {
    <# Формирует манифест SHA256 всех файлов сессии бэкапа (PAT-20). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $manifest = Join-Path $BackupDir 'MANIFEST_SHA256.txt'
    $files = Get-ChildItem -LiteralPath $BackupDir -File | Where-Object { $_.Name -ne 'MANIFEST_SHA256.txt' }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $lines.Add(('{0}  {1}' -f $hash, $f.Name))
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifest, (($lines -join "`n") + "`n"), $utf8NoBom)

    return $manifest
}

Export-ModuleMember -Function New-BackupSession, Export-RegistryKey, Export-ServiceConfig, Export-BcdSnapshot, Get-BackupManifest
