<#
.SYNOPSIS
    Верификация рабочей среды C:\Vitality (Stage 8, ADR-0017).

.DESCRIPTION
    Только чтение: сверяет фактическое состояние каталога с манифестом
    runtime/manifests/RuntimeManifest.json — состав, маркер развёртывания,
    дрейф, права и объём. Ничего не создаёт и не изменяет; сеть не использует.

    Проверки: A0.1 манифест, A1.1 каталоги, A1.2 маркер и SHA256, A1.3 права
    (информационно), A2.1 дрейф, A2.2 объём. Отчёт — docs/artifacts/Stage8_runtime.md.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Root
    Переопределение корня среды (по умолчанию — из манифеста).

.PARAMETER ManifestPath
    Путь к манифесту.

.PARAMETER ExportReport
    Путь к отчёту (по умолчанию docs/artifacts/Stage8_runtime.md).

.EXAMPLE
    pwsh -File ./runtime/bootstrap/Assert-RuntimeState.ps1

.NOTES
    Script-ID  : SCRIPT-RUNTIME-002
    Stage      : 8
    Patterns   : PAT-20
    ADR        : ADR-0017
    Rules      : AUTOMATION_RULES.md (AR-201, AR-206, AR-301, AR-306, AR-307, SC_SSD_LONGEVITY)
    Depends    : runtime/manifests/RuntimeManifest.json, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string]$Root,

    [string]$ManifestPath,

    [string]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-RUNTIME-002'
if (-not $ManifestPath) { $ManifestPath = Join-Path $RepoRoot 'runtime/manifests/RuntimeManifest.json' }
$report = if ($ExportReport) { $ExportReport } else { Join-Path $RepoRoot 'docs/artifacts/Stage8_runtime.md' }

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 8 — верификация рабочей среды C:\Vitality'

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        Add-VerificationCheck -Context $context -Id 'A0.1' -Check 'Манифест состава' -Expected 'RuntimeManifest.json' -Actual 'отсутствует' -Status 'FAIL'
        Write-VerificationReport -Context $context -ExportPath $report
        exit $exit.Precondition
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
    Add-VerificationCheck -Context $context -Id 'A0.1' -Check 'Манифест состава' -Expected 'валидный JSON' -Actual ('status={0}' -f [string]$manifest.status) -Status 'PASS' -Note 'ADR-0017'

    $targetRoot = if ($Root) { $Root } else { [string]$manifest.root }
    $rootExists = Test-Path -LiteralPath $targetRoot -PathType Container
    Add-VerificationCheck -Context $context -Id 'A1.0' -Check 'Корень среды' -Expected $targetRoot -Actual $(if ($rootExists) { 'существует' } else { 'отсутствует' }) -Status $(if ($rootExists) { 'PASS' } else { 'FAIL' })
    if (-not $rootExists) {
        Write-VerificationReport -Context $context -ExportPath $report
        exit $exit.VerifyFailed
    }

    $expected = @($manifest.directories)
    $missing = @($expected | Where-Object { -not (Test-Path -LiteralPath (Join-Path $targetRoot $_.path) -PathType Container) })
    Add-VerificationCheck -Context $context -Id 'A1.1' -Check 'Каталоги состава' -Expected ([string]$expected.Count) `
        -Actual $(if ($missing.Count -eq 0) { 'все существуют' } else { 'отсутствуют: ' + (($missing | ForEach-Object { $_.path }) -join ', ') }) `
        -Status $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' })

    $markerPath = Join-Path $targetRoot ([string]$manifest.markerFile)
    if (Test-Path -LiteralPath $markerPath) {
        $markerUpToDate = $false
        try {
            $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $markerUpToDate = ([string]$marker.manifestSha256 -eq $hash)
        }
        catch { $markerUpToDate = $false }
        Add-VerificationCheck -Context $context -Id 'A1.2' -Check 'Маркер развёртывания' -Expected 'хэш совпадает с манифестом' `
            -Actual $(if ($markerUpToDate) { 'актуален' } else { 'расходится — требуется повторное развёртывание' }) `
            -Status $(if ($markerUpToDate) { 'PASS' } else { 'FAIL' }) -Note 'AR-301'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'A1.2' -Check 'Маркер развёртывания' -Expected 'файл маркера' -Actual 'отсутствует' -Status 'FAIL' -Note 'Среда не развёрнута: Deploy-Runtime.ps1.'
    }

    $aclReport = (& icacls.exe $targetRoot) -join "`n"
    $aclApplied = ($aclReport -match 'S-1-5-18') -and ($aclReport -match 'S-1-5-32-544')
    Add-VerificationCheck -Context $context -Id 'A1.3' -Check 'Права каталога' -Expected 'SYSTEM и Administrators' -Actual $(if ($aclApplied) { 'в ACL' } else { 'не обнаружены' }) `
        -Status $(if ($aclApplied) { 'PASS' } else { 'WARN' }) -Note 'Применяется флагом -ApplyAcl; Deny-записи в домене не используются.'

    $allowed = @($expected | ForEach-Object { [string]$_.path }) + @($manifest.driftAllow)
    $extra = @(Get-ChildItem -LiteralPath $targetRoot -Force | Where-Object { $allowed -notcontains $_.Name } | ForEach-Object { $_.Name })
    Add-VerificationCheck -Context $context -Id 'A2.1' -Check 'Дрейф состава' -Expected 'только элементы манифеста' `
        -Actual $(if ($extra.Count -eq 0) { 'дрейфа нет' } else { 'лишние: ' + ($extra -join ', ') }) `
        -Status $(if ($extra.Count -eq 0) { 'PASS' } else { 'WARN' }) -Note 'Посторонние элементы не удаляются (AR-201).'

    $size = (Get-ChildItem -LiteralPath $targetRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $sizeGiB = if ($size) { [math]::Round($size / 1GB, 2) } else { 0 }
    $limit = [double]$manifest.sizeWarningGiB
    Add-VerificationCheck -Context $context -Id 'A2.2' -Check 'Объём среды' -Expected ('<= {0} GiB' -f $limit) -Actual ('{0} GiB' -f $sizeGiB) `
        -Status $(if ($sizeGiB -le $limit) { 'PASS' } else { 'WARN' }) -Note 'SC_SSD_LONGEVITY: крупные данные — на D:.'

    if ([string]$manifest.status -ne 'RATIFIED') {
        Add-VerificationCheck -Context $context -Id 'A2.3' -Check 'Состав ратифицирован' -Expected 'status=RATIFIED' -Actual ([string]$manifest.status) -Status 'WARN' -Note 'S8-OPEN-1: состав — предложение.'
    }

    Write-VerificationReport -Context $context -ExportPath $report
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
