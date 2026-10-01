<#
.SYNOPSIS
    Установка дистрибутива WSL2 из офлайн-носителя и развёртывание лимитов.

.DESCRIPTION
    Stage 7 — первая фаза DevOps-контура. Дистрибутив поставляется офлайн
    (F:\WSL2\ubuntu.appx, README §5.7.3) и не является приложением Windows,
    поэтому AR-601 (winget-first) на него не распространяется — исключение
    зафиксировано ADR-0016.

    Порядок:
      1. предусловия: права, наличие appx, отсутствие уже установленного
         дистрибутива, свободное место;
      2. развёртывание дистрибутива одним из двух путей:
         - AppxExe (по умолчанию, anchor1): распаковка .appx как архива в
           C:\DevOps\WSL\Ubuntu и запуск <DistroExe> для создания Linux-пользователя;
         - Import: wsl --import из install.tar.gz (чистая установка без Appx-обвязки);
      3. деплой лимитов: devops/wsl/.wslconfig.template -> %USERPROFILE%\.wslconfig
         (единственный источник лимитов, AR-703);
      4. (опция) деплой /etc/wsl.conf с systemd=true внутрь дистрибутива;
      5. wsl --shutdown и верификация состояния (`wsl -l -v`).

    Скрипт НЕ поднимает сеть (AR-709): окно сети открыто владельцем по §4.5 README.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER AppxPath
    Путь к офлайн-пакету дистрибутива (по умолчанию F:\WSL2\ubuntu.appx).

.PARAMETER DistroName
    Имя дистрибутива для верификации (по умолчанию Ubuntu).

.PARAMETER InstallRoot
    Каталог распаковки AppxExe-пути (по умолчанию C:\DevOps\WSL\Ubuntu).

.PARAMETER DistroExe
    Имя исполняемого файла дистрибутива в InstallRoot (по умолчанию ubuntu2204.exe).

.PARAMETER UseImport
    Использовать путь Import (wsl --import) вместо запуска Appx-исполняемого файла.

.PARAMETER ConfigureDistro
    Дополнительно записать /etc/wsl.conf (systemd=true) внутрь дистрибутива.

.PARAMETER SkipWslConfig
    Не разворачивать %USERPROFILE%\.wslconfig (только проверка).

.PARAMETER Audit
    Только чтение: план и предусловия без изменений.

.EXAMPLE
    pwsh -File ./devops/wsl/Install-WslDistro.ps1 -Audit
    pwsh -File ./devops/wsl/Install-WslDistro.ps1 -ConfigureDistro

.NOTES
    Script-ID  : SCRIPT-WSL-001
    Stage      : 7
    Patterns   : PAT-21
    ADR        : ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-302, AR-303, AR-304, AR-306, AR-307, AR-501, AR-701, AR-703, AR-709)
    Depends    : devops/wsl/.wslconfig.template, devops/wsl/wsl.conf.template, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string]$AppxPath = 'F:\WSL2\ubuntu.appx',

    [string]$DistroName = 'Ubuntu',

    [string]$InstallRoot = 'C:\DevOps\WSL\Ubuntu',

    [string]$DistroExe = 'ubuntu2204.exe',

    [switch]$UseImport,

    [switch]$ConfigureDistro,

    [switch]$SkipWslConfig,

    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-WSL-001'
$wslConfigTemplate = Join-Path $RepoRoot 'devops/wsl/.wslconfig.template'
$wslConfTemplate   = Join-Path $RepoRoot 'devops/wsl/wsl.conf.template'

function Get-WslDistroList {
    <# Список установленных дистрибутивов (без учёта кодировки консоли: --quiet). #>
    [CmdletBinding()]
    param()

    $out = & wsl.exe --list --quiet 2>$null
    return @($out | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 7 — установка дистрибутива WSL2'

    if (-not (Get-Command -Name wsl.exe -ErrorAction SilentlyContinue)) {
        Add-VerificationCheck -Context $context -Id 'W0.1' -Check 'WSL доступен' -Expected 'wsl.exe' `
            -Actual 'не найден' -Status 'FAIL' -Note 'Сначала Enable-HypervisorPlatform.ps1 (AR-701).'
    }

    $appxOk = Test-Path -LiteralPath $AppxPath
    Add-VerificationCheck -Context $context -Id 'W0.2' -Check 'Офлайн-пакет дистрибутива' `
        -Expected $AppxPath -Actual $(if ($appxOk) { 'существует' } else { 'отсутствует' }) `
        -Status $(if ($appxOk) { 'PASS' } else { 'FAIL' }) -Note 'README §5.7.3; AR-804 (в Git не коммитится)'

    $existing = @(Get-WslDistroList)
    $already = ($existing | Where-Object { $_ -eq $DistroName }).Count -gt 0
    Add-VerificationCheck -Context $context -Id 'W0.3' -Check ('Дистрибутив {0} ещё не установлен' -f $DistroName) `
        -Expected 'отсутствует' -Actual $(if ($already) { 'уже установлен' } else { 'отсутствует' }) `
        -Status $(if ($already) { 'SKIP' } else { 'PASS' }) -Note ($existing -join ', ')

    $wslConfigTarget = Join-Path $env:USERPROFILE '.wslconfig'
    Add-VerificationCheck -Context $context -Id 'W0.4' -Check '.wslconfig в профиле' `
        -Expected 'развёрнут из шаблона' -Actual $(if (Test-Path -LiteralPath $wslConfigTarget) { 'существует' } else { 'отсутствует' }) `
        -Status 'PASS' -Note 'AR-703'

    if ((Get-VerificationFailures -Context $context).Count -gt 0) {
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }

    if ($already) {
        Write-Log -Level 'INFO' -Component $scriptId -Message ('Дистрибутив {0} уже установлен: шаг установки пропущен (AR-303).' -f $DistroName)
    }
    elseif ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Развёртывание {0} из {1} ({2})' -f $DistroName, $AppxPath, $(if ($UseImport) { 'wsl --import' } else { 'AppxExe' }))
    }
    else {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage7-wsl'
        Write-Log -Component $scriptId -Message ('Сессия бэкапа: {0}' -f $backupDir)

        if ($UseImport) {
            # Путь Import: install.tar.gz из состава пакета.
            $stage = Join-Path $backupDir 'appx'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $zip = Join-Path $stage 'distro.zip'
            Copy-Item -LiteralPath $AppxPath -Destination $zip -Force
            Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
            $tar = Get-ChildItem -LiteralPath $stage -Recurse -Filter 'install.tar.gz' | Select-Object -First 1
            if (-not $tar) {
                Add-VerificationCheck -Context $context -Id 'W1.1' -Check 'install.tar.gz в пакете' -Expected 'найден' -Actual 'отсутствует' -Status 'FAIL'
                Write-VerificationReport -Context $context
                exit $exit.Precondition
            }
            Assert-PathAllowed -Path $InstallRoot -RepoRoot $RepoRoot
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
            & wsl.exe --import $DistroName $InstallRoot $tar.FullName
            if ($LASTEXITCODE -ne 0) {
                Add-VerificationCheck -Context $context -Id 'W1.1' -Check 'wsl --import' -Expected 'код 0' -Actual ('код {0}' -f $LASTEXITCODE) -Status 'FAIL'
                Write-VerificationReport -Context $context
                exit $exit.Fatal
            }
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Импортирован дистрибутив {0} в {1}.' -f $DistroName, $InstallRoot)
        }
        else {
            # Путь AppxExe (anchor1): распаковка и запуск исполняемого файла дистрибутива.
            Assert-PathAllowed -Path $InstallRoot -RepoRoot $RepoRoot
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
            # Копия пакета остаётся в каталоге сессии бэкапа: удаление файлов запрещено (AR-201).
            $zip = Join-Path $backupDir 'distro.zip'
            Copy-Item -LiteralPath $AppxPath -Destination $zip -Force
            Expand-Archive -LiteralPath $zip -DestinationPath $InstallRoot -Force

            $exe = Join-Path $InstallRoot $DistroExe
            if (-not (Test-Path -LiteralPath $exe)) {
                Add-VerificationCheck -Context $context -Id 'W1.2' -Check ('Исполняемый файл {0}' -f $DistroExe) `
                    -Expected 'найден' -Actual 'отсутствует' -Status 'FAIL' -Note 'Проверить имя exe в пакете.'
                Write-VerificationReport -Context $context
                exit $exit.Precondition
            }

            Write-Log -Component $scriptId -Message ('Запуск {0}: создайте Linux-пользователя в открывшемся окне.' -f $exe)
            $proc = Start-Process -FilePath $exe -Wait -PassThru
            Add-VerificationCheck -Context $context -Id 'W1.2' -Check 'Создание Linux-пользователя' -Expected 'код 0' `
                -Actual ('код {0}' -f $proc.ExitCode) -Status $(if ($proc.ExitCode -eq 0) { 'PASS' } else { 'WARN' }) `
                -Note 'Интерактивный шаг: результат подтверждается проверкой W1.4.'
        }

        & wsl.exe --shutdown | Out-Null
    }

    # Лимиты WSL2: единственный источник — шаблон (AR-703, PAT-21).
    if (-not $SkipWslConfig) {
        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('.wslconfig: {0} -> {1}' -f $wslConfigTemplate, $wslConfigTarget)
        }
        elseif ($PSCmdlet.ShouldProcess($wslConfigTarget, 'Deploy .wslconfig from template')) {
            Copy-Item -LiteralPath $wslConfigTemplate -Destination $wslConfigTarget -Force
            Write-Log -Level 'PASS' -Component $scriptId -Message ('Лимиты развёрнуты: {0}' -f $wslConfigTarget)
        }
    }

    # systemd=true внутри дистрибутива (AR-707).
    if ($ConfigureDistro) {
        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('/etc/wsl.conf в {0}' -f $DistroName)
        }
        else {
            $conf = Get-Content -LiteralPath $wslConfTemplate -Raw
            $conf | & wsl.exe -d $DistroName -u root -- bash -c 'cat > /etc/wsl.conf'
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Level 'PASS' -Component $scriptId -Message '/etc/wsl.conf записан (systemd=true).'
            }
            else {
                Write-Log -Level 'WARN' -Component $scriptId -Message ('Запись /etc/wsl.conf: код {0}.' -f $LASTEXITCODE)
            }
            & wsl.exe --shutdown | Out-Null
        }
    }

    if (-not $Audit) {
        $installed = @(Get-WslDistroList)
        Add-VerificationCheck -Context $context -Id 'W1.4' -Check ('Дистрибутив {0} установлен' -f $DistroName) `
            -Expected 'в списке wsl -l -v' -Actual $(if ($installed -contains $DistroName) { 'установлен' } else { 'отсутствует' }) `
            -Status $(if ($installed -contains $DistroName) { 'PASS' } else { 'FAIL' })

        $cfg = Join-Path $env:USERPROFILE '.wslconfig'
        $cfgText = if (Test-Path -LiteralPath $cfg) { Get-Content -LiteralPath $cfg -Raw } else { '' }
        $limitsOk = ($cfgText -match 'processors\s*=\s*4') -and ($cfgText -match 'memory\s*=\s*6GB') -and ($cfgText -match 'pageReporting\s*=\s*false')
        Add-VerificationCheck -Context $context -Id 'W1.5' -Check 'Лимиты .wslconfig (AR-703)' `
            -Expected 'processors=4, memory=6GB, pageReporting=false' -Actual $(if ($limitsOk) { 'совпадают' } else { 'расхождение' }) `
            -Status $(if ($limitsOk) { 'PASS' } else { 'FAIL' }) -Note 'PAT-21'
    }
    else {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: изменения не вносились.'
    }

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
