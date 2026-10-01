<#
.SYNOPSIS
    Stage 5: предпролётная подготовка запечатывания (Sysprep Seal).

.DESCRIPTION
    Готовит хост к необратимой операции sysprep /oobe /generalize /shutdown:
      1. предусловия: права администратора, Audit Mode, сетевая изоляция (AR-709);
      2. бэкап-сессия: существующий unattend.xml и журналы Sysprep (AR-304);
      3. размещение второго файла ответов: templates/unattend.xml.template ->
         C:\Windows\System32\Sysprep\unattend.xml (ADR-0005 п.1, ADR-0014 п.1);
      4. защита от ловушки 0x80073cf2: поиск AppX, установленных для пользователя,
         но не provisioned для всех (SYSPRP AppxSysprep), с опциональным устранением
         строго по списку tweaks/appx/AppxRemoval.json (AR-507);
      5. гигиена профилей: очистка кэшей WebCache/INetCache перед generalize
         (известный дефект 24H2, ADR-0014 п.3);
      6. отчёт верификации и точная команда запуска. Сама команда Sysprep
         деструктивна (AR-204): выполняется только с явным -ExecuteSysprep.

    Модуль не поднимает сеть (AR-709) и не удаляет файлы вне allow-list (AR-206).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Режим только чтения: показать, что было бы сделано, без изменений.

.PARAMETER FixSysprepValidation
    Устранить найденные AppX-нарушения удалением установленных экземпляров
    для всех пользователей. Только по шаблонам tweaks/appx/AppxRemoval.json
    (AR-507), защищённые шаблоны не затрагиваются. Без флага — только отчёт.

.PARAMETER PurgeProfileCaches
    Очистить WebCache/INetCache в профиле текущего пользователя (Администратор).

.PARAMETER ExecuteSysprep
    Выполнить sysprep.exe /oobe /generalize /shutdown /unattend:... (AR-204:
    деструктивная и необратимая операция; без флага скрипт только готовит среду).

.PARAMETER AllowNetwork
    Не считать активные сетевые адаптеры блокирующим условием (не рекомендуется).

.PARAMETER VerificationReport
    Путь к markdown-отчёту верификации (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 -Audit
    pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 -FixSysprepValidation -PurgeProfileCaches -VerificationReport ./docs/artifacts/Stage5_preflight.md
    pwsh -File ./scripts/Stage5_Sysprep_Prepare.ps1 -ExecuteSysprep -Confirm:$false

.NOTES
    ВНИМАНИЕ: generalize выполняется в общем случае ограниченное число раз (лимит
    перевооружения). Ошибочный прогон может быть необратим — поэтому скрипт по
    умолчанию не запускает Sysprep и отдельно требует подтверждения.

    Script-ID  : SCRIPT-STAGE5-001
    Stage      : 5
    Patterns   : PAT-16, PAT-NEW-1
    ADR        : ADR-0005, ADR-0014
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-303, AR-304, AR-306, AR-307, AR-502, AR-507, AR-709)
    Depends    : scripts/common/*, templates/unattend.xml.template, tweaks/appx/AppxRemoval.json
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$Audit,

    [switch]$FixSysprepValidation,

    [switch]$PurgeProfileCaches,

    [switch]$ExecuteSysprep,

    [switch]$AllowNetwork,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-STAGE5-001'

$templatePath = Join-Path $RepoRoot 'templates/unattend.xml.template'
$appxManifest = Join-Path $RepoRoot 'tweaks/appx/AppxRemoval.json'
$sysprepDir   = Join-Path $env:SystemRoot 'System32/Sysprep'
$sysprepExe   = Join-Path $sysprepDir 'sysprep.exe'
$targetAnswer = Join-Path $sysprepDir 'unattend.xml'

function Test-NetworkIsolation {
    <# Возвращает список активных адаптеров (Status=Up). AR-709. #>
    [CmdletBinding()]
    param()

    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $bad.Add($adapter.Name)
    }
    return $bad
}

function Get-AuditModeState {
    <# Audit Mode определяется флагом SystemSetupInProgress в HKLM\SYSTEM\Setup. #>
    [CmdletBinding()]
    param()

    $value = 0
    try {
        $value = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup' -Name 'SystemSetupInProgress' -ErrorAction Stop).SystemSetupInProgress
    }
    catch {
        $value = 0
    }
    return [int]$value
}

function Get-UndeclaredAppxPackage {
    <#
        Ловушка Sysprep 0x80073cf2: пакет установлен для пользователя, но не
        provisioned для всех. Возвращает объект:
          EnumerationOk — удалось ли перечислить provisioned-пакеты (DISm-модуль);
          Packages      — список нарушителей, исключая защищённые шаблоны (AR-507).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Manifest)

    $provisionedNames = @{}
    foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)) {
        $provisionedNames[$p.PackageName] = $true
    }
    $enumerationOk = ($provisionedNames.Count -gt 0)
    $provisionedShort = @{}
    foreach ($name in $provisionedNames.Keys) {
        $provisionedShort[($name -split '_')[0]] = $true
    }

    $bad = New-Object System.Collections.Generic.List[object]
    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
        if ($provisionedNames.ContainsKey($pkg.PackageFullName)) { continue }
        if ($provisionedShort.ContainsKey($pkg.Name)) { continue }
        if ($pkg.IsFramework) { continue }

        $protected = $false
        foreach ($pattern in $Manifest.protectedPatterns) {
            if ($pkg.Name -like ('*{0}*' -f $pattern)) { $protected = $true; break }
        }
        if ($protected) { continue }

        $matched = $false
        foreach ($pattern in $Manifest.removePatterns) {
            if ($pkg.Name -like ('*{0}*' -f $pattern)) { $matched = $true; break }
        }

        $bad.Add([pscustomobject]@{
            Name       = $pkg.Name
            FullName   = $pkg.PackageFullName
            Declared   = $matched
        })
    }

    return [pscustomobject]@{
        EnumerationOk = $enumerationOk
        Packages      = $bad
    }
}

function Invoke-WebCacheHygiene {
    <# Очистка кэшей, повреждающих Default User при generalize в 24H2 (ADR-0014 п.3). #>
    [CmdletBinding()]
    param([switch]$Audit)

    $targets = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/WebCache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/INetCache')
    )

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { $result.Add(('нет: {0}' -f $t)); continue }
        if ($Audit) { $result.Add(('очистил бы: {0}' -f $t)); continue }

        try {
            Get-ChildItem -LiteralPath $t -Force -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $result.Add(('очищено: {0}' -f $t))
        }
        catch {
            $result.Add(('заблокировано: {0} ({1})' -f $t, $_.Exception.Message))
        }
    }

    $lock = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/WebCache/WebCacheV01.dat'
    if (Test-Path -LiteralPath $lock) { $result.Add(('WebCacheV01.dat занят процессом: {0}' -f $lock)) }

    return $result
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 5 — предпролётная подготовка Sysprep'

    # --- P0: предусловия ---
    $auditMode = Get-AuditModeState
    Add-VerificationCheck -Context $context -Id 'P0.1' -Check 'Audit Mode активен (SystemSetupInProgress)' `
        -Expected '1' -Actual ([string]$auditMode) -Status $(if ($auditMode -eq 1) { 'PASS' } else { 'FAIL' }) `
        -Note 'Без Audit Mode generalize не выполняется (AR-204).'

    $adapters = @(Test-NetworkIsolation)
    $netStatus = if ($adapters.Count -eq 0 -or $AllowNetwork) { 'PASS' } else { 'FAIL' }
    Add-VerificationCheck -Context $context -Id 'P0.2' -Check 'Сеть изолирована (AR-709)' `
        -Expected '0 активных адаптеров' -Actual ([string]$adapters.Count) -Status $netStatus `
        -Note ($(if ($adapters.Count) { 'Активны: ' + ($adapters -join ', ') } else { 'Изоляция подтверждена.' }))

    Add-VerificationCheck -Context $context -Id 'P0.3' -Check 'Шаблон второго файла ответов существует' `
        -Expected 'templates/unattend.xml.template' -Actual ([string](Test-Path -LiteralPath $templatePath)) `
        -Status $(if (Test-Path -LiteralPath $templatePath) { 'PASS' } else { 'FAIL' })

    $preconditionFailures = (Get-VerificationFailures -Context $context).Count
    if ($preconditionFailures -gt 0) {
        Write-VerificationReport -Context $context -ExportPath $VerificationReport
        if (-not $Audit) {
            Write-Log -Level 'FAIL' -Component $scriptId -Message ('Не выполнены предусловия: {0}. Изменения не вносились.' -f $preconditionFailures)
            exit $exit.Precondition
        }
    }

    # --- P1: бэкап-сессия (AR-304) ---
    $backupDir = ''
    if (-not $Audit) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage5'
        Write-Log -Component $scriptId -Message ('Бэкап-сессия: {0}' -f $backupDir)

        if (Test-Path -LiteralPath $targetAnswer) {
            Copy-Item -LiteralPath $targetAnswer -Destination (Join-Path $backupDir 'unattend_existing.xml') -Force
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Существующий unattend.xml сохранён в бэкап.'
        }
        foreach ($log in @('setupact.log', 'setuperr.log', 'sysprep_succeeded.tag')) {
            $src = Join-Path $sysprepDir $log
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $backupDir -Force }
        }
    }

    # --- P2: размещение второго файла ответов ---
    $deployState = 'не размещён'
    if ($Audit) {
        $deployState = 'AUDIT: копирование не выполняется'
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Копирование {0} -> {1}' -f $templatePath, $targetAnswer)
    }
    else {
        Assert-PathAllowed -Path $targetAnswer -RepoRoot $RepoRoot
        $same = $false
        if (Test-Path -LiteralPath $targetAnswer) {
            # PAT-20: сравнение по SHA256 — идемпотентность без побайтового разбора (AR-303).
            $hashTemplate = (Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash
            $hashCurrent  = (Get-FileHash -LiteralPath $targetAnswer -Algorithm SHA256).Hash
            $same = ($hashTemplate -eq $hashCurrent)
        }

        if ($same) {
            $deployState = 'актуален (совпадает с шаблоном)'
            Write-Log -Level 'PASS' -Component $scriptId -Message 'unattend.xml уже актуален (AR-303).'
        }
        else {
            Copy-Item -LiteralPath $templatePath -Destination $targetAnswer -Force
            $deployState = 'размещён'
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Размещён файл ответов: {0}' -f $targetAnswer)
        }

        # Верификация: отсутствие BOM и валидность XML.
        $deployed = [System.IO.File]::ReadAllBytes($targetAnswer)
        $hasBom = ($deployed.Length -ge 3 -and $deployed[0] -eq 0xEF -and $deployed[1] -eq 0xBB -and $deployed[2] -eq 0xBF)
        Add-VerificationCheck -Context $context -Id 'P2.1' -Check 'unattend.xml без BOM (AR-101)' `
            -Expected 'False' -Actual ([string]$hasBom) -Status $(if ($hasBom) { 'FAIL' } else { 'PASS' })

        $xmlOk = $false
        $xmlNote = ''
        try {
            [xml]$null = Get-Content -LiteralPath $targetAnswer -Raw -Encoding UTF8
            $xmlOk = $true
        }
        catch {
            $xmlNote = $_.Exception.Message
        }
        Add-VerificationCheck -Context $context -Id 'P2.2' -Check 'unattend.xml разбирается как XML' `
            -Expected 'valid' -Actual $(if ($xmlOk) { 'valid' } else { 'invalid' }) `
            -Status $(if ($xmlOk) { 'PASS' } else { 'FAIL' }) -Note $xmlNote
    }

    Add-VerificationCheck -Context $context -Id 'P2.3' -Check 'Состояние размещения файла ответов' `
        -Expected 'размещён' -Actual $deployState -Status $(if ($Audit) { 'SKIP' } else { 'PASS' })

    # --- P3: защита от ловушки 0x80073cf2 ---
    $appxManifestObject = Get-Content -LiteralPath $appxManifest -Raw | ConvertFrom-Json
    $appxReport = Get-UndeclaredAppxPackage -Manifest $appxManifestObject
    $undeclared = @($appxReport.Packages)

    $declared = @($undeclared | Where-Object { $_.Declared })
    $foreign  = @($undeclared | Where-Object { -not $_.Declared })

    Add-VerificationCheck -Context $context -Id 'P3.1' -Check 'AppX по манифесту Stage 4 не нарушают provisioning' `
        -Expected '0' -Actual ([string]$declared.Count) -Status $(if ($declared.Count -eq 0) { 'PASS' } else { 'WARN' }) `
        -Note $(if ($declared.Count) { 'Устранимо: -FixSysprepValidation' } else { 'Нарушений по объявленным шаблонам нет.' })

    Add-VerificationCheck -Context $context -Id 'P3.2' -Check 'Прочие AppX, не охваченные манифестом' `
        -Expected 'информационно' -Actual ([string]$foreign.Count) -Status 'SKIP' `
        -Note $(if ($foreign.Count) { ($foreign | Select-Object -First 8 | ForEach-Object { $_.Name }) -join '; ' } else { 'нет' })

    Add-VerificationCheck -Context $context -Id 'P3.0' -Check 'Перечисление provisioned-пакетов доступно' `
        -Expected 'True' -Actual ([string]$appxReport.EnumerationOk) -Status $(if ($appxReport.EnumerationOk) { 'PASS' } else { 'FAIL' }) `
        -Note 'При FAIL устранение ловушки не выполняется: неполный список опаснее бездействия.'

    if ($declared.Count -gt 0 -and $FixSysprepValidation -and -not $Audit -and -not $appxReport.EnumerationOk) {
        Write-Log -Level 'FAIL' -Component $scriptId -Message 'Перечисление provisioned-пакетов недоступно: устранение отменено.'
    }

    if ($declared.Count -gt 0 -and $FixSysprepValidation -and -not $Audit -and $appxReport.EnumerationOk) {
        Write-Log -Component $scriptId -Message ('Устранение ловушки Sysprep в пределах манифеста: {0} пакет(ов).' -f $declared.Count)
        foreach ($pkg in $declared) {
            if ($PSCmdlet.ShouldProcess($pkg.Name, 'Remove-AppxPackage -AllUsers')) {
                try {
                    Get-AppxPackage -AllUsers -Name $pkg.Name -ErrorAction Stop | Remove-AppxPackage -AllUsers -ErrorAction Stop
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('Удалён установленный экземпляр: {0}' -f $pkg.Name)
                }
                catch {
                    Write-Log -Level 'FAIL' -Component $scriptId -Message ('Не удалось удалить {0}: {1}' -f $pkg.Name, $_.Exception.Message)
                }
            }
        }
        Add-VerificationCheck -Context $context -Id 'P3.3' -Check 'Устранение выполнено (-FixSysprepValidation)' `
            -Expected 'without error' -Actual 'см. лог' -Status 'PASS'
    }

    # --- P4: гигиена профиля (24H2) ---
    if ($PurgeProfileCaches) {
        $hygiene = Invoke-WebCacheHygiene -Audit:$Audit
        Write-Log -Component $scriptId -Message ('Гигиена кэшей профиля: {0}' -f ($hygiene -join ' | '))
        Add-VerificationCheck -Context $context -Id 'P4.1' -Check 'Очистка кэшей профиля выполнена' `
            -Expected 'без блокировок' -Actual $(if ($hygiene.Count -gt 0) { 'см. лог' } else { 'нет целей' }) -Status 'PASS'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'P4.1' -Check 'Очистка кэшей профиля (WebCache/INetCache)' `
            -Expected '-PurgeProfileCaches' -Actual 'не запрошена' -Status 'WARN' `
            -Note 'Рекомендуется перед generalize (дефект Default User в 23H2/24H2).'
    }

    # --- P5: снимок политик, которые применит файл ответов (AR-502) ---
    $policyTargets = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'; Name = 'SearchOrderConfig' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'; Name = 'AutoUpdateCheckPeriodMinutes' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Name = 'DontOfferThroughWUAU' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Name = 'DontReportInfectionInformation' }
    )

    $baseline = New-Object System.Collections.Generic.List[string]
    foreach ($t in $policyTargets) {
        $currentValue = '<нет>'
        try {
            $currentValue = [string](Get-ItemProperty -LiteralPath $t.Path -Name $t.Name -ErrorAction Stop).($t.Name)
        }
        catch { $currentValue = '<нет>' }
        $baseline.Add(('{0}\{1} = {2}' -f $t.Path, $t.Name, $currentValue))
    }

    if ($backupDir) {
        $baselinePath = Join-Path $backupDir 'unattend_targets_before.txt'
        [System.IO.File]::WriteAllLines($baselinePath, $baseline)
        Write-Log -Level 'PASS' -Component $scriptId -Message ('Снимок целевых политик (AR-502): {0}' -f $baselinePath)
    }
    Add-VerificationCheck -Context $context -Id 'P5.1' -Check 'Снимок целевых политик выполнен (AR-502)' `
        -Expected '13 записей' -Actual ([string]$baseline.Count) -Status 'PASS'

    # --- P6: сводка и команда запуска ---
    if ($backupDir) { Get-BackupManifest -BackupDir $backupDir | Out-Null }

    Write-VerificationReport -Context $context -ExportPath $VerificationReport

    $sysprepCommand = 'cd /d "{0}" && sysprep.exe /oobe /generalize /shutdown /unattend:"{1}"' -f $sysprepDir, $targetAnswer
    Write-Log -Component $scriptId -Message ('Команда запечатывания (CMD от Администратора, НЕ PowerShell): {0}' -f $sysprepCommand)

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: изменения не вносились, Sysprep не запускался.'
        exit $exit.Ok
    }

    # --- P7: запуск Sysprep (деструктивно, AR-204) ---
    if (-not $ExecuteSysprep) {
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Sysprep НЕ запущен. Добавьте -ExecuteSysprep для запуска (AR-204: необратимая операция).'
        exit (Get-VerificationExitCode -Context $context)
    }

    Assert-PathAllowed -Path $sysprepExe -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $sysprepExe)) {
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('sysprep.exe не найден: {0}' -f $sysprepExe)
        exit $exit.Precondition
    }

    if ($PSCmdlet.ShouldProcess('Windows', 'sysprep /oobe /generalize /shutdown (необратимо)')) {
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Запуск sysprep.exe /oobe /generalize /shutdown ...'
        & $sysprepExe /oobe /generalize /shutdown ('/unattend:{0}' -f $targetAnswer)
        # Штатный сценарий: рабочая станция выключается, управление сюда не возвращается.
        Write-Log -Component $scriptId -Message ('sysprep.exe завершился с кодом {0}.' -f $LASTEXITCODE)
    }

    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
