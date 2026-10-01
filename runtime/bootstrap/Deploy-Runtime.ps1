<#
.SYNOPSIS
    Развёртывание рабочей среды C:\Vitality (Stage 8, ADR-0017).

.DESCRIPTION
    Идемпотентно приводит каталог рабочей среды к составу, объявленному в
    runtime/manifests/RuntimeManifest.json:

      1. проверяет манифест и статус состава;
      2. создаёт недостающие каталоги (существующие не изменяются, AR-201);
      3. пишет маркер .vitality.json с SHA256 манифеста (ключ идемпотентности,
         AR-301): при совпадении хэша операций не выполняется;
      4. по флагу -ApplyAcl применяет права (SYSTEM — FullControl,
         Administrators — чтение); Deny-записи в этом домене не применяются;
      5. фиксирует результат проверками D0–D3 и отчётом Stage8_preflight.md.

    Состав в манифесте имеет статус PROPOSED до ратификации (S8-OPEN-1):
    развёртывание такого состава возможно только по явному подтверждению
    -AcknowledgeProposedComposition, иначе — только -Audit.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Root
    Переопределение корня среды (по умолчанию — из манифеста).

.PARAMETER ManifestPath
    Путь к манифесту (по умолчанию runtime/manifests/RuntimeManifest.json).

.PARAMETER ApplyAcl
    Применить права из секции acls (AR-204, AR-506).

.PARAMETER AcknowledgeProposedComposition
    Подтверждение развёртывания состава со статусом PROPOSED (S8-OPEN-1).

.PARAMETER Audit
    Только проверки: ничего не создавать и не менять.

.PARAMETER VerificationReport
    Путь к отчёту (по умолчанию docs/artifacts/Stage8_preflight.md).

.EXAMPLE
    pwsh -File ./runtime/bootstrap/Deploy-Runtime.ps1 -Audit
    pwsh -File ./runtime/bootstrap/Deploy-Runtime.ps1 -ApplyAcl

.NOTES
    Script-ID  : SCRIPT-RUNTIME-001
    Stage      : 8
    Patterns   : PAT-19, PAT-20
    ADR        : ADR-0017
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-301, AR-302, AR-306, AR-307, AR-506, AR-509, AR-804)
    Depends    : runtime/manifests/RuntimeManifest.json, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string]$Root,

    [string]$ManifestPath,

    [switch]$ApplyAcl,

    [switch]$AcknowledgeProposedComposition,

    [switch]$Audit,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-RUNTIME-001'
if (-not $ManifestPath) { $ManifestPath = Join-Path $RepoRoot 'runtime/manifests/RuntimeManifest.json' }
$report = if ($VerificationReport) { $VerificationReport } else { Join-Path $RepoRoot 'docs/artifacts/Stage8_preflight.md' }

function Get-ManifestHash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 8 — развёртывание рабочей среды C:\Vitality'

    # --- D0: манифест ---
    $manifestOk = $false
    $manifest = $null
    if (Test-Path -LiteralPath $ManifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $manifestOk = $true
        }
        catch {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('Манифест не читается: {0}' -f $_.Exception.Message)
        }
    }
    Add-VerificationCheck -Context $context -Id 'D0.1' -Check 'Манифест состава' -Expected 'RuntimeManifest.json' `
        -Actual $(if ($manifestOk) { 'валиден' } else { 'отсутствует или повреждён' }) -Status $(if ($manifestOk) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0017'
    if (-not $manifestOk) {
        Write-VerificationReport -Context $context -ExportPath $report
        exit $exit.Precondition
    }

    $targetRoot = if ($Root) { $Root } else { [string]$manifest.root }
    try {
        Assert-PathAllowed -Path $targetRoot -Purpose 'развёртывание рабочей среды' | Out-Null
        Add-VerificationCheck -Context $context -Id 'D0.2' -Check 'Корень среды в allow-list (AR-206)' -Expected $targetRoot -Actual 'разрешён' -Status 'PASS'
    }
    catch {
        Add-VerificationCheck -Context $context -Id 'D0.2' -Check 'Корень среды в allow-list (AR-206)' -Expected $targetRoot -Actual $_.Exception.Message -Status 'FAIL'
        Write-VerificationReport -Context $context -ExportPath $report
        exit $exit.Precondition
    }

    $proposed = ([string]$manifest.status -ne 'RATIFIED')
    $compositionOk = (-not $proposed) -or $AcknowledgeProposedComposition -or $Audit
    Add-VerificationCheck -Context $context -Id 'D0.3' -Check 'Состав ратифицирован (S8-OPEN-1)' -Expected 'status=RATIFIED' `
        -Actual ([string]$manifest.status) -Status $(if (-not $proposed) { 'PASS' } elseif ($Audit) { 'WARN' } elseif ($AcknowledgeProposedComposition) { 'WARN' } else { 'FAIL' }) `
        -Note $(if ($proposed) { 'Состав — предложение; развёртывание требует -AcknowledgeProposedComposition.' } else { 'Состав подтверждён владельцем.' })

    if ((Get-VerificationFailures -Context $context).Count -gt 0) {
        Write-VerificationReport -Context $context -ExportPath $report
        exit $exit.Precondition
    }

    # --- D1: каталоги ---
    $created = 0
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @($manifest.directories)) {
        $path = Join-Path $targetRoot ([string]$dir.path)
        if (Test-Path -LiteralPath $path -PathType Container) { continue }
        if ($Audit) { $missing.Add([string]$dir.path); continue }
        if ($PSCmdlet.ShouldProcess($path, 'Создание каталога рабочей среды')) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            $created++
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Создан каталог: {0}' -f $path)
        }
    }
    $dirCount = @($manifest.directories).Count
    if ($Audit) {
        Add-VerificationCheck -Context $context -Id 'D1.1' -Check 'Каталоги состава' -Expected ([string]$dirCount) `
            -Actual $(if ($missing.Count -eq 0) { 'все существуют' } else { 'отсутствуют: ' + ($missing -join ', ') }) `
            -Status $(if ($missing.Count -eq 0) { 'PASS' } else { 'WARN' }) -Note 'Режим -Audit: план развёртывания.'
    }
    else {
        $stillMissing = @($manifest.directories | Where-Object { -not (Test-Path -LiteralPath (Join-Path $targetRoot $_.path) -PathType Container) })
        Add-VerificationCheck -Context $context -Id 'D1.1' -Check 'Каталоги состава' -Expected ([string]$dirCount) `
            -Actual ('{0} создано, отсутствует {1}' -f $created, $stillMissing.Count) `
            -Status $(if ($stillMissing.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'AR-201: существующие каталоги не изменяются.'
    }

    # --- D1.2: маркер ---
    $markerPath = Join-Path $targetRoot ([string]$manifest.markerFile)
    $hash = Get-ManifestHash -Path $ManifestPath
    if ($Audit) {
        $markerValid = $false
        if (Test-Path -LiteralPath $markerPath) {
            try {
                $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $markerValid = ([string]$marker.manifestSha256 -eq $hash)
            }
            catch { $markerValid = $false }
        }
        Add-VerificationCheck -Context $context -Id 'D1.2' -Check 'Маркер развёртывания' -Expected 'хэш совпадает' `
            -Actual $(if ($markerValid) { 'актуален' } else { 'требуется развёртывание' }) -Status $(if ($markerValid) { 'PASS' } else { 'WARN' })
    }
    else {
        $alreadyDeployed = $false
        if (Test-Path -LiteralPath $markerPath) {
            try {
                $existing = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $alreadyDeployed = ([string]$existing.manifestSha256 -eq $hash)
            }
            catch { $alreadyDeployed = $false }
        }
        if ($alreadyDeployed) {
            Add-VerificationCheck -Context $context -Id 'D1.2' -Check 'Маркер развёртывания' -Expected 'хэш совпадает' -Actual 'актуален, изменений не требуется' -Status 'PASS' -Note 'AR-301: повторный запуск идемпотентен.'
        }
        elseif ($PSCmdlet.ShouldProcess($markerPath, 'Запись маркера развёртывания')) {
            $markerObject = [pscustomobject]@{
                schemaVersion  = [string]$manifest.schemaVersion
                deployedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                manifestSha256 = $hash
                host           = $env:COMPUTERNAME
                composition    = [string]$manifest.status
            }
            $lines = @($markerObject | ConvertTo-Json -Depth 4)
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($markerPath, (($lines -join "`n") + "`n"), $utf8NoBom)
            Add-VerificationCheck -Context $context -Id 'D1.2' -Check 'Маркер развёртывания' -Expected 'хэш совпадает' -Actual 'записан' -Status 'PASS'
        }
    }

    # --- D1.3: права (только по флагу) ---
    if ($ApplyAcl) {
        if ($Audit) {
            Add-VerificationCheck -Context $context -Id 'D1.3' -Check 'Права каталога' -Expected '-ApplyAcl' -Actual 'пропущено в -Audit' -Status 'SKIP'
        }
        else {
            $applied = 0
            foreach ($acl in @($manifest.acls)) {
                $path = Join-Path $targetRoot ([string]$acl.path)
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $grant = '{0}:{1}' -f ([string]$acl.sid), ([string]$acl.rights)
                if ($PSCmdlet.ShouldProcess($path, ('icacls /grant ' + $grant))) {
                    & icacls.exe $path /grant $grant | Out-Null
                    if ($LASTEXITCODE -eq 0) { $applied++ } else { Write-Log -Level 'WARN' -Component $scriptId -Message ('icacls: код {0} для {1}' -f $LASTEXITCODE, $path) }
                }
            }
            $aclReport = (& icacls.exe $targetRoot) -join "`n"
            $systemOk = $aclReport -match 'S-1-5-18'
            Add-VerificationCheck -Context $context -Id 'D1.3' -Check 'Права каталога' -Expected 'SYSTEM FullControl' `
                -Actual ('применено записей: {0}; SYSTEM в ACL: {1}' -f $applied, $(if ($systemOk) { 'да' } else { 'нет' })) `
                -Status $(if ($applied -gt 0 -and $systemOk) { 'PASS' } else { 'WARN' }) -Note 'Deny-записи в домене не применяются (ADR-0017 п.4).'
        }
    }
    else {
        Add-VerificationCheck -Context $context -Id 'D1.3' -Check 'Права каталога' -Expected '-ApplyAcl' -Actual 'не запрошено' -Status 'SKIP' -Note 'Права применяются отдельным шагом (AR-204).'
    }

    # --- D2: дрейф и объём ---
    if (-not $Audit -and (Test-Path -LiteralPath $targetRoot)) {
        $allowed = @($manifest.directories | ForEach-Object { [string]$_.path }) + @($manifest.driftAllow)
        $extra = @(Get-ChildItem -LiteralPath $targetRoot -Force | Where-Object { $allowed -notcontains $_.Name } | ForEach-Object { $_.Name })
        Add-VerificationCheck -Context $context -Id 'D2.1' -Check 'Дрейф состава' -Expected 'только элементы манифеста' `
            -Actual $(if ($extra.Count -eq 0) { 'дрейфа нет' } else { 'лишние: ' + ($extra -join ', ') }) `
            -Status $(if ($extra.Count -eq 0) { 'PASS' } else { 'WARN' }) -Note 'Посторонние файлы не удаляются (AR-201); при необходимости — в манифест.'

        $size = (Get-ChildItem -LiteralPath $targetRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeGiB = if ($size) { [math]::Round($size / 1GB, 2) } else { 0 }
        $limit = [double]$manifest.sizeWarningGiB
        Add-VerificationCheck -Context $context -Id 'D2.2' -Check 'Объём среды' -Expected ('<= {0} GiB' -f $limit) -Actual ('{0} GiB' -f $sizeGiB) `
            -Status $(if ($sizeGiB -le $limit) { 'PASS' } else { 'WARN' }) -Note 'Крупные данные — на D: (SC_SSD_LONGEVITY, AR-509).'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'D2.1' -Check 'Дрейф и объём' -Expected 'после развёртывания' -Actual 'пропущено в -Audit' -Status 'SKIP'
    }

    if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: операции не выполнялись.' }
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
