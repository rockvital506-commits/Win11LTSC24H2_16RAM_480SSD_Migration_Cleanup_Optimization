<#
.SYNOPSIS
    Stage 7: развёртывание DevOps-контура (WSL2 + Docker + VMware + P+E).

.DESCRIPTION
    Оркестратор финального этапа. Выполняется в профиле devops при ОТКРЫТОМ
    окне сети (стык Stage 6 → 7, §4.5 README); сам скрипт сеть не поднимает
    (AR-709).

    Фазы:
      P0  предусловия: права, окно сети, закрытый Stage 6 (задачи + замки),
          свободное место, офлайн-пакет дистрибутива;
      P1  гипервизорные компоненты: Subsystem-Linux, VirtualMachinePlatform,
          HypervisorPlatform; hypervisorlaunchtype=auto (AR-701, AR-702);
      P2  дистрибутив WSL2 из офлайн-носителя + лимиты .wslconfig (PAT-21);
      P3  нативный Docker Engine в WSL2 + data-root на /mnt/d/Docker (AR-707);
      P4  VMware: директивы изоляции кэша во всех *.vmx под D:\VM (PAT-22);
      P5  политика P+E: маска P-ядер и привязка нагрузок (AR-704, AR-705);
      P6  пакеты профиля devops (делегирование в packages/bootstrap, AR-607);
      P7  сводный отчёт верификации.

    Отчёт: docs/artifacts/Stage7_preflight.md (или -VerificationReport).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: предусловия и план без изменений (P1–P6 выполняются в режиме -Audit).

.PARAMETER SkipHypervisor
    Не трогать компоненты виртуализации и BCD.

.PARAMETER SkipWsl
    Не разворачивать дистрибутив WSL2 и .wslconfig.

.PARAMETER SkipDocker
    Не запускать установку Docker Engine внутри дистрибутива.

.PARAMETER SkipVmware
    Не трогать директивы .vmx.

.PARAMETER SkipCpuPolicy
    Не выполнять привязку P-ядер и сверку схемы питания.

.PARAMETER SkipPackages
    Не запускать установку пакетов профиля devops.

.PARAMETER VerificationReport
    Путь к markdown-отчёту (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1 -Audit
    pwsh -File ./scripts/Stage7_WSL_Docker_VMware.ps1 -VerificationReport ./docs/artifacts/Stage7_preflight.md

.NOTES
    Script-ID  : SCRIPT-STAGE7-001
    Stage      : 7
    Patterns   : PAT-07, PAT-21, PAT-22
    ADR        : ADR-0002, ADR-0010, ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-302, AR-303, AR-306, AR-307, AR-501, AR-601, AR-607, AR-701, AR-703, AR-705, AR-707, AR-708, AR-709)
    Depends    : devops/**, packages/** (профиль devops), scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$Audit,

    [switch]$SkipHypervisor,

    [switch]$SkipWsl,

    [switch]$SkipDocker,

    [switch]$SkipVmware,

    [switch]$SkipCpuPolicy,

    [switch]$SkipPackages,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-STAGE7-001'
$distroName = 'Ubuntu'
$toolDir  = 'D:\GD_Tool'

function Invoke-SubScript {
    <# Запуск дочернего скрипта с прозрачным кодом возврата. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    $params = @{ RepoRoot = $RepoRoot }
    foreach ($key in $Arguments.Keys) { $params[$key] = $Arguments[$key] }

    & $Path @params
    return [int]$LASTEXITCODE
}

function Test-NetworkWindow {
    <# Окно сети должно быть открыто владельцем (AR-709): возвращает имена активных адаптеров. #>
    [CmdletBinding()]
    param()

    return @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { $_.Name })
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 7 — DevOps-контур (WSL2, Docker, VMware, P+E)'

    # --- P0: предусловия ---
    $adapters = @(Test-NetworkWindow)
    Add-VerificationCheck -Context $context -Id 'P0.1' -Check 'Окно сети открыто (стык Stage 6→7)' `
        -Expected '≥ 1 активный адаптер' -Actual ([string]$adapters.Count) `
        -Status $(if ($adapters.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
        -Note ($(if ($adapters.Count) { $adapters -join ', ' } else { 'Сеть поднимает владелец (§4.5 README); скрипт её не включает (AR-709).' }))

    $task = Get-ScheduledTask -TaskName 'System_Immunity_Core' -ErrorAction SilentlyContinue
    Add-VerificationCheck -Context $context -Id 'P0.2' -Check 'Stage 6 закрыт: задача контура' `
        -Expected 'зарегистрирована' -Actual $(if ($task) { [string]$task.State } else { 'отсутствует' }) `
        -Status $(if ($task) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0015: сначала цементирование, затем DevOps-контур.'

    $lockOk = $false
    try {
        $acl = Get-Acl -LiteralPath (Join-Path $env:SystemRoot 'System32\GroupPolicy')
        $lockOk = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and ([string]$_.IdentityReference -match 'SYSTEM|S-1-5-18') }).Count -gt 0
    }
    catch { $lockOk = $false }
    Add-VerificationCheck -Context $context -Id 'P0.3' -Check 'Stage 6 закрыт: NTFS-замок GroupPolicy' `
        -Expected 'DENY для SYSTEM' -Actual $(if ($lockOk) { 'присутствует' } else { 'отсутствует' }) `
        -Status $(if ($lockOk) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0003, PAT-11'

    $appx = 'F:\WSL2\ubuntu.appx'
    Add-VerificationCheck -Context $context -Id 'P0.4' -Check 'Офлайн-пакет дистрибутива' `
        -Expected $appx -Actual $(if (Test-Path -LiteralPath $appx) { 'существует' } else { 'отсутствует' }) `
        -Status $(if (Test-Path -LiteralPath $appx) { 'PASS' } else { 'WARN' }) -Note 'AR-804: бинарники в Git не хранятся.'

    foreach ($volume in @('C:', 'D:')) {
        $free = 0
        try { $free = [math]::Round((Get-PSDrive -Name $volume.TrimEnd(':')).Free / 1GB, 1) } catch { $free = -1 }
        Add-VerificationCheck -Context $context -Id ('P0.5.' + $volume) -Check ('Свободно на {0}' -f $volume) `
            -Expected '≥ 10 GiB' -Actual ('{0} GiB' -f $free) -Status $(if ($free -ge 10) { 'PASS' } else { 'WARN' }) `
            -Note 'Дистрибутив WSL2 и тома Docker размещаются на D: (AR-707).'
    }

    if ((Get-VerificationFailures -Context $context).Count -gt 0 -and -not $Audit) {
        Write-VerificationReport -Context $context -ExportPath $VerificationReport
        Write-Log -Level 'FAIL' -Component $scriptId -Message 'Предусловия не выполнены: DevOps-контур не разворачивается.'
        exit $exit.Precondition
    }

    $common = @{}
    if ($Audit) { $common['Audit'] = $true }

    # --- P1: компоненты виртуализации ---
    if (-not $SkipHypervisor) {
        Write-Log -Component $scriptId -Message 'P1: компоненты виртуализации (AR-701, AR-702)...'
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'devops/hypervisor/Enable-HypervisorPlatform.ps1') -Arguments $common
        if ($code -ne 0) { Write-Log -Level 'FAIL' -Component $scriptId -Message ('Компоненты виртуализации: код {0}.' -f $code) }
    }

    # --- P2: дистрибутив WSL2 и лимиты ---
    if (-not $SkipWsl) {
        Write-Log -Component $scriptId -Message 'P2: дистрибутив WSL2 и лимиты .wslconfig (PAT-21)...'
        $wslArgs = @{ ConfigureDistro = $true }
        if ($Audit) { $wslArgs['Audit'] = $true }
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'devops/wsl/Install-WslDistro.ps1') -Arguments $wslArgs
        if ($code -ne 0) { Write-Log -Level 'FAIL' -Component $scriptId -Message ('WSL2: код {0}.' -f $code) }
    }

    # --- P3: Docker Engine внутри дистрибутива ---
    if (-not $SkipDocker) {
        $dockerScript = Join-Path $RepoRoot 'devops/containers/Install-DockerEngine.sh'
        if ($Audit) {
            Write-Log -Level 'AUDIT' -Component $scriptId -Message ('bash -s < {0} (в дистрибутиве {1})' -f $dockerScript, $distroName)
        }
        elseif ($PSCmdlet.ShouldProcess($distroName, 'Install Docker Engine inside WSL2')) {
            Write-Log -Component $scriptId -Message 'P3: нативный Docker Engine в WSL2 (AR-707)...'
            Get-Content -LiteralPath $dockerScript -Raw | & wsl.exe -d $distroName -u root -- bash -s
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Level 'PASS' -Component $scriptId -Message 'Docker Engine установлен (проверка — в отчёте).'
            }
            else {
                Write-Log -Level 'FAIL' -Component $scriptId -Message ('Docker Engine: код {0}.' -f $LASTEXITCODE)
            }
        }
    }

    # --- P4: VMware (WHP + директивы .vmx) ---
    if (-not $SkipVmware) {
        Write-Log -Component $scriptId -Message 'P4: сосуществование WSL2/VMware и директивы .vmx (PAT-07, PAT-22)...'
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'devops/hypervisor/Configure-WhpCoexistence.ps1') -Arguments $common
        if ($code -ne 0) { Write-Log -Level 'FAIL' -Component $scriptId -Message ('VMware/WHP: код {0}.' -f $code) }
    }

    # --- P5: политика P+E ---
    if (-not $SkipCpuPolicy) {
        Write-Log -Component $scriptId -Message 'P5: политика P+E (AR-704, AR-705)...'
        $maskArgs = @{ VerifyPowerPlan = $true }
        if ($Audit) { $maskArgs['Audit'] = $true }
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'devops/cpu-policy/Set-WorkloadAffinity.ps1') -Arguments $maskArgs
        if ($code -ne 0) { Write-Log -Level 'WARN' -Component $scriptId -Message ('Привязка P-ядер: код {0}.' -f $code) }
    }

    # --- P6: пакеты профиля devops ---
    if (-not $SkipPackages) {
        $bootstrap = Join-Path $RepoRoot 'packages/bootstrap/Bootstrap-Packages.ps1'
        if (-not (Test-Path -LiteralPath $bootstrap)) {
            Add-VerificationCheck -Context $context -Id 'P6.0' -Check 'Пакеты профиля devops' -Expected 'Bootstrap-Packages.ps1' `
                -Actual 'домен packages/ ещё не развёрнут' -Status 'WARN' -Note 'AR-607: установка профиля — отдельный шаг с отчётом.'
        }
        else {
            Write-Log -Component $scriptId -Message 'P6: пакеты профиля devops (AR-601, AR-607)...'
            $pkgArgs = @{ Profile = 'devops' }
            if ($Audit) { $pkgArgs['Audit'] = $true }
            $code = Invoke-SubScript -Path $bootstrap -Arguments $pkgArgs
            if ($code -ne 0) { Write-Log -Level 'FAIL' -Component $scriptId -Message ('Пакеты: код {0}.' -f $code) }
        }
    }

    # --- P7: сводка ---
    if (-not $SkipWsl -and -not $Audit) {
        $installed = @((& wsl.exe --list --quiet 2>$null) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        Add-VerificationCheck -Context $context -Id 'P7.1' -Check ('Дистрибутив {0}' -f $distroName) `
            -Expected 'установлен' -Actual $(if ($installed -contains $distroName) { 'установлен' } else { 'отсутствует' }) `
            -Status $(if ($installed -contains $distroName) { 'PASS' } else { 'FAIL' })
    }

    if (-not $SkipDocker -and -not $Audit) {
        $dockerOk = $false
        try {
            $out = & wsl.exe -d $distroName -u root -- docker info --format '{{.DockerRootDir}}' 2>$null
            $dockerOk = ($LASTEXITCODE -eq 0) -and ($out -join '' -match '/mnt/d/Docker')
        }
        catch { $dockerOk = $false }
        Add-VerificationCheck -Context $context -Id 'P7.2' -Check 'Docker data-root на D:\Docker (AR-707)' `
            -Expected '/mnt/d/Docker' -Actual $(if ($dockerOk) { 'совпадает' } else { 'не подтверждён' }) `
            -Status $(if ($dockerOk) { 'PASS' } else { 'WARN' }) -Note 'Проверка docker info внутри дистрибутива.'
    }

    Write-VerificationReport -Context $context -ExportPath $VerificationReport

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: изменения не вносились.'
        exit $exit.Ok
    }

    Write-Log -Level 'PASS' -Component $scriptId -Message 'DevOps-контур развёрнут.'
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
