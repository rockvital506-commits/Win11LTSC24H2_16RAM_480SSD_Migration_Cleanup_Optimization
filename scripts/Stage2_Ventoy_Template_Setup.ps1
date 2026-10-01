<#
.SYNOPSIS
    Валидация и рендер файлов Ventoy-контура (Stage 2, PAT-16).

.DESCRIPTION
    Stage 2 — установка без интерактивных экранов. Скрипт проверяет шаблоны
    контура и (по запросу) рендерит рабочие файлы:

      (по умолчанию)   только чтение: шаблоны, их кодировки, состав и значения;
      -Render          рендер ventoy.json и u_w11_ltsc_iot.xml в -OutDir;
      -DeployToMedia   размещение файлов на носителе Ventoy (-MediaRoot);
                       требует -AcknowledgeFDriveModification (AR-202, AR-204,
                       GATE_FDRIVE_MODIFICATION).

    Проверки: JSON-составляющие (control/menu_alias/auto_install), совпадение
    имени ISO с подтверждённым (S2-OPEN-1), отсутствие BOM в XML, три прохода
    (windowsPE/specialize/oobeSystem), заглушки PAT-01 ASUS, телеметрия,
    отсутствие автоматической разметки и активного <Mode>Audit</Mode> (S2-ACT-1).

    Пишет отчёт docs/artifacts/Stage2_preflight.md (UTF-8 без BOM, LF).
    Сеть скрипт не использует и не поднимает (AR-709).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER IsoName
    Подтверждённое имя ISO-образа (шаблон сравнивается с этим значением).

.PARAMETER RenderedXmlName
    Имя рендеримого файла ответов (по умолчанию u_w11_ltsc_iot.xml).

.PARAMETER MediaRoot
    Корень носителя Ventoy (например, F:\): с ним выполняются проверки V2.1.

.PARAMETER OutDir
    Каталог рендера (allow-list, AR-206). Обязателен при -Render.

.PARAMETER Render
    Рендерить рабочие файлы: ventoy.json (LF, без BOM) и файл ответов (CRLF, без BOM).

.PARAMETER DeployToMedia
    Копировать отрендеренные файлы на носитель (требует -MediaRoot).

.PARAMETER AcknowledgeFDriveModification
    Явное подтверждение записи на F: (GATE_FDRIVE_MODIFICATION, AR-202).

.PARAMETER VerificationReport
    Путь к отчёту (по умолчанию docs/artifacts/Stage2_preflight.md).

.EXAMPLE
    pwsh -File ./scripts/Stage2_Ventoy_Template_Setup.ps1
    pwsh -File ./scripts/Stage2_Ventoy_Template_Setup.ps1 -MediaRoot F:\
    pwsh -File ./scripts/Stage2_Ventoy_Template_Setup.ps1 -Render -OutDir ./out/stage2

.NOTES
    Script-ID  : SCRIPT-STAGE2-001
    Stage      : 2
    Patterns   : PAT-01, PAT-16
    ADR        : ADR-0005, ADR-0007
    Rules      : AUTOMATION_RULES.md (AR-101, AR-102, AR-105, AR-201, AR-202, AR-204, AR-206, AR-301, AR-306, AR-307, AR-709)
    Depends    : templates/ventoy.json.template, templates/u_w11_ltsc_iot.xml.template
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$IsoName = 'en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso',

    [string]$RenderedXmlName = 'u_w11_ltsc_iot.xml',

    [string]$MediaRoot,

    [string]$OutDir,

    [switch]$Render,

    [switch]$DeployToMedia,

    [switch]$AcknowledgeFDriveModification,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-STAGE2-001'
$jsonTemplate = Join-Path $RepoRoot 'templates/ventoy.json.template'
$xmlTemplate  = Join-Path $RepoRoot 'templates/u_w11_ltsc_iot.xml.template'
$report       = if ($VerificationReport) { $VerificationReport } else { Join-Path $RepoRoot 'docs/artifacts/Stage2_preflight.md' }

function Get-FileTextNoBom {
    <# Читает текст как UTF-8; возвращает объект с текстом и признаком BOM. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    return [pscustomobject]@{
        Text    = [System.Text.Encoding]::UTF8.GetString($bytes)
        HasBom  = $hasBom
        MixedEol = (($bytes -contains 0x0D) -and -not ([System.Text.Encoding]::UTF8.GetString($bytes) -match "`r`n"))
    }
}

function Write-Rendered {
    <# Пишет рабочий файл: UTF-8 без BOM, заданные окончания строк. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][ValidateSet('LF', 'CRLF')][string]$Eol
    )

    $normalized = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    if ($Eol -eq 'CRLF') { $normalized = $normalized -replace "`n", "`r`n" }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 2 — Ventoy-контур и файл ответов'

    # --- V0: шаблоны контура ---
    $templatesDir = Join-Path $RepoRoot 'templates'
    Add-VerificationCheck -Context $context -Id 'V0.1' -Check 'Каталог шаблонов' -Expected 'templates/' -Actual $(if (Test-Path -LiteralPath $templatesDir) { 'существует' } else { 'отсутствует' }) -Status $(if (Test-Path -LiteralPath $templatesDir) { 'PASS' } else { 'FAIL' })

    $jsonOk = $false
    $json = $null
    if (Test-Path -LiteralPath $jsonTemplate) {
        $jsonRaw = Get-FileTextNoBom -Path $jsonTemplate
        try {
            $json = $jsonRaw.Text | ConvertFrom-Json
            $jsonOk = $true
        }
        catch {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('ventoy.json.template: некорректный JSON — {0}' -f $_.Exception.Message)
        }
        Add-VerificationCheck -Context $context -Id 'V0.2' -Check 'ventoy.json.template: JSON' -Expected 'валидный JSON' -Actual $(if ($jsonOk) { 'валидный' } else { 'ошибка разбора' }) -Status $(if ($jsonOk) { 'PASS' } else { 'FAIL' })
        Add-VerificationCheck -Context $context -Id 'V0.2.1' -Check 'ventoy.json.template: без BOM' -Expected 'UTF-8 без BOM' -Actual $(if ($jsonRaw.HasBom) { 'BOM присутствует' } else { 'BOM отсутствует' }) -Status $(if ($jsonRaw.HasBom) { 'FAIL' } else { 'PASS' }) -Note 'AR-101'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'V0.2' -Check 'ventoy.json.template' -Expected 'файл' -Actual 'отсутствует' -Status 'FAIL'
    }

    if ($jsonOk) {
        $sections = @('control', 'menu_alias', 'auto_install')
        $missing = @($sections | Where-Object { -not ($json.PSObject.Properties.Name -contains $_) })
        Add-VerificationCheck -Context $context -Id 'V0.3' -Check 'Состав ventoy.json' -Expected ($sections -join ', ') -Actual $(if ($missing.Count -eq 0) { 'все разделы' } else { 'нет: ' + ($missing -join ', ') }) -Status $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' })

        $iso = [string]$json.auto_install[0].image
        Add-VerificationCheck -Context $context -Id 'V0.4' -Check 'Имя ISO (S2-OPEN-1)' -Expected ('/' + $IsoName) -Actual $iso -Status $(if ($iso -eq ('/ISO/' + $IsoName)) { 'PASS' } else { 'FAIL' }) -Note 'Подтверждено владельцем 2026-10-01.'

        $tpl = [string]$json.auto_install[0].template
        $expectedTpl = '/ventoy/templates/' + $RenderedXmlName
        Add-VerificationCheck -Context $context -Id 'V0.5' -Check 'Путь шаблона в auto_install' -Expected $expectedTpl -Actual $tpl -Status $(if ($tpl -eq $expectedTpl) { 'PASS' } else { 'FAIL' })
    }

    # --- V1: первый файл ответов ---
    if (Test-Path -LiteralPath $xmlTemplate) {
        $xmlRaw = Get-FileTextNoBom -Path $xmlTemplate
        Add-VerificationCheck -Context $context -Id 'V1.1' -Check 'u_w11_ltsc_iot: без BOM' -Expected 'UTF-8 без BOM' -Actual $(if ($xmlRaw.HasBom) { 'BOM присутствует' } else { 'BOM отсутствует' }) -Status $(if ($xmlRaw.HasBom) { 'FAIL' } else { 'PASS' }) -Note 'BOM → отказ setup.exe на первой секунде.'

        $xmlOk = $false
        $xmlDoc = $null
        try { $xmlDoc = [xml]$xmlRaw.Text; $xmlOk = $true } catch { Write-Log -Level 'FAIL' -Component $scriptId -Message ('u_w11_ltsc_iot.xml.template: {0}' -f $_.Exception.Message) }
        Add-VerificationCheck -Context $context -Id 'V1.2' -Check 'Файл ответов: XML' -Expected 'well-formed' -Actual $(if ($xmlOk) { 'валиден' } else { 'ошибка разбора' }) -Status $(if ($xmlOk) { 'PASS' } else { 'FAIL' })

        if ($xmlOk) {
            $passes = @($xmlDoc.unattend.settings | ForEach-Object { $_.pass })
            $need = @('windowsPE', 'specialize', 'oobeSystem')
            $missingPasses = @($need | Where-Object { $passes -notcontains $_ })
            Add-VerificationCheck -Context $context -Id 'V1.3' -Check 'Проходы файла ответов' -Expected ($need -join ', ') -Actual $(if ($missingPasses.Count -eq 0) { 'все проходы' } else { 'нет: ' + ($missingPasses -join ', ') }) -Status $(if ($missingPasses.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'Разметка (windowsPE) и specialize — зона Ventoy-файла (ADR-0005).'

            $text = $xmlRaw.Text
            $pat01 = @('AsusUpdateCheck.exe', 'AsusAppService.exe')
            $missingPat = @($pat01 | Where-Object { $text -notmatch [regex]::Escape($_) })
            Add-VerificationCheck -Context $context -Id 'V1.4' -Check 'Заглушки PAT-01 (ASUS)' -Expected ($pat01 -join ', ') -Actual $(if ($missingPat.Count -eq 0) { 'обе записи IFEO' } else { 'нет: ' + ($missingPat -join ', ') }) -Status $(if ($missingPat.Count -eq 0) { 'PASS' } else { 'FAIL' })

            $diag = ($text -match 'DiagTrack') -and ($text -match 'Start[^"]*"\s*/d\s+4')
            $drv = $text -match 'SearchOrderConfig[^"]*"\s*/d\s+0'
            Add-VerificationCheck -Context $context -Id 'V1.5' -Check 'Телеметрия и драйверы' -Expected 'DiagTrack=4, SearchOrderConfig=0' -Actual ('DiagTrack={0}, DriverSearching={1}' -f $(if ($diag) { '4' } else { 'нет' }), $(if ($drv) { '0' } else { 'нет' })) -Status $(if ($diag -and $drv) { 'PASS' } else { 'FAIL' })

            $noComments = [regex]::Replace($text, '(?s)<!--.*?-->', '')
            $auditActive = $noComments -match '<Mode>\s*Audit\s*</Mode>'
            $partAuto = $noComments -match '<DiskConfiguration'
            Add-VerificationCheck -Context $context -Id 'V1.6' -Check 'Разметка вручную, Audit не форсируется' -Expected 'нет DiskConfiguration и активного Mode=Audit' -Actual ('DiskConfiguration={0}, Mode=Audit={1}' -f $(if ($partAuto) { 'есть' } else { 'нет' }), $(if ($auditActive) { 'активен' } else { 'отключён' })) -Status $(if ((-not $partAuto) -and (-not $auditActive)) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0007, AR-204; S2-OPEN-2/S2-ACT-1.'
        }
    }
    else {
        Add-VerificationCheck -Context $context -Id 'V1.1' -Check 'u_w11_ltsc_iot.xml.template' -Expected 'файл' -Actual 'отсутствует' -Status 'FAIL'
    }

    # --- V2: носитель (только при -MediaRoot) ---
    if ($MediaRoot) {
        $isoPath     = Join-Path (Join-Path $MediaRoot 'ISO') $IsoName
        $jsonPath    = Join-Path (Join-Path $MediaRoot 'ventoy') 'ventoy.json'
        $xmlPath     = Join-Path (Join-Path $MediaRoot 'ventoy\templates') $RenderedXmlName
        foreach ($item in @(
            @{ Id = 'V2.1'; Name = 'ISO на носителе'; Path = $isoPath },
            @{ Id = 'V2.2'; Name = 'ventoy.json на носителе'; Path = $jsonPath },
            @{ Id = 'V2.3'; Name = 'Файл ответов на носителе'; Path = $xmlPath }
        )) {
            $exists = Test-Path -LiteralPath $item.Path
            Add-VerificationCheck -Context $context -Id $item.Id -Check $item.Name -Expected $item.Path -Actual $(if ($exists) { 'найден' } else { 'отсутствует' }) -Status $(if ($exists) { 'PASS' } else { 'WARN' }) -Note 'Проверка носителя; отсутствие файла не блокирует рендер.'
        }
    }
    else {
        Add-VerificationCheck -Context $context -Id 'V2.0' -Check 'Проверка носителя' -Expected '-MediaRoot F:\' -Actual 'не задан' -Status 'SKIP' -Note 'Раздел 2 носителя проверяется при прогоне на стенде.'
    }

    # --- R: рендер ---
    if ($Render) {
        if (-not $OutDir) {
            Add-VerificationCheck -Context $context -Id 'R0.1' -Check 'Каталог рендера' -Expected '-OutDir' -Actual 'не задан' -Status 'FAIL'
        }
        elseif ((Get-VerificationFailures -Context $context).Count -gt 0) {
            Add-VerificationCheck -Context $context -Id 'R0.1' -Check 'Рендер' -Expected 'нет FAIL до рендера' -Actual 'есть FAIL шаблонов' -Status 'FAIL' -Note 'Рендер запрещён при ошибках шаблонов (AR-302).'
        }
        else {
            Assert-PathAllowed -Path $OutDir -Purpose 'рендер Stage 2' | Out-Null
            $targetXml  = Join-Path $OutDir $RenderedXmlName
            $targetJson = Join-Path $OutDir 'ventoy.json'
            Write-Rendered -Path $targetXml  -Text (Get-FileTextNoBom -Path $xmlTemplate).Text  -Eol 'CRLF'
            Write-Rendered -Path $targetJson -Text (Get-FileTextNoBom -Path $jsonTemplate).Text -Eol 'LF'
            Add-VerificationCheck -Context $context -Id 'R1.1' -Check 'Файл ответов отрендерен' -Expected 'CRLF, без BOM' -Actual $targetXml -Status 'PASS'
            Add-VerificationCheck -Context $context -Id 'R1.2' -Check 'ventoy.json отрендерен' -Expected 'LF, без BOM' -Actual $targetJson -Status 'PASS'
        }
    }

    # --- D: размещение на носителе ---
    if ($DeployToMedia) {
        if (-not $MediaRoot) {
            Add-VerificationCheck -Context $context -Id 'D0.1' -Check 'Носитель' -Expected '-MediaRoot' -Actual 'не задан' -Status 'FAIL'
        }
        elseif (-not $AcknowledgeFDriveModification) {
            Add-VerificationCheck -Context $context -Id 'D0.2' -Check 'Запись на F: разрешена' -Expected '-AcknowledgeFDriveModification' -Actual 'подтверждение не дано' -Status 'FAIL' -Note 'GATE_FDRIVE_MODIFICATION: без явного подтверждения владельца запись запрещена (AR-202, AR-204).'
        }
        elseif ((Get-VerificationFailures -Context $context).Count -gt 0) {
            Add-VerificationCheck -Context $context -Id 'D0.3' -Check 'Размещение' -Expected 'нет FAIL' -Actual 'есть FAIL' -Status 'FAIL'
        }
        else {
            $staging = Join-Path $env:TEMP 'ventoy_stage2'
            Write-Rendered -Path (Join-Path $staging $RenderedXmlName) -Text (Get-FileTextNoBom -Path $xmlTemplate).Text -Eol 'CRLF'
            Write-Rendered -Path (Join-Path $staging 'ventoy.json') -Text (Get-FileTextNoBom -Path $jsonTemplate).Text -Eol 'LF'
            $destDir = Join-Path $MediaRoot 'ventoy\templates'
            if ($PSCmdlet.ShouldProcess($MediaRoot, 'Размещение ventoy.json и файла ответов (GATE_FDRIVE_MODIFICATION)')) {
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item -LiteralPath (Join-Path $staging $RenderedXmlName) -Destination (Join-Path $destDir $RenderedXmlName) -Force
                Copy-Item -LiteralPath (Join-Path $staging 'ventoy.json') -Destination (Join-Path $MediaRoot 'ventoy\ventoy.json') -Force
                Add-VerificationCheck -Context $context -Id 'D1.1' -Check 'Файлы размещены на носителе' -Expected $MediaRoot -Actual 'выполнено' -Status 'PASS' -Note 'F: изменён с явного подтверждения (AR-202).'
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Размещено: {0}' -f $MediaRoot)
            }
        }
    }

    $failCount = (Get-VerificationFailures -Context $context).Count
    Write-VerificationReport -Context $context -ExportPath $report
    if ($Render -and $failCount -eq 0) { Write-Log -Level 'PASS' -Component $scriptId -Message ('Рендер выполнен в {0}.' -f $OutDir) }
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
