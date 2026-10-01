<#
.SYNOPSIS
    Сосуществование WSL2 и VMware Workstation Pro через WHP API: директивы .vmx.

.DESCRIPTION
    Stage 7 — слой гипервизорного сосуществования (ADR-0002, AR-702, AR-708).

    Скрипт проверяет режим, при котором WSL2 и VMware работают одновременно:
      - компонент HypervisorPlatform включён (WHP API);
      - hypervisorlaunchtype = auto (гипервизор загружен);
      - полноценный Hyper-V не включён;
      - VBS/HVCI отключены (иначе вложенная виртуализация и Thread Director деградируют).

    Затем приводит конфигурацию всех виртуальных машин под D:\VM к объявленному
    набору директив из devops/hypervisor/vmware/VM.vmx.template:
      priority.grabbed / priority.ungrabbed — приоритет процессов ВМ;
      sched.mem.pshare.enable = FALSE       — без page-sharing (износ SSD, PAT-22);
      mainMem.useNamedFile   = FALSE        — память ВМ не выгружается в .vmem;
      mainMem.backing        = swap         — хост-страницы, а не файл;
      vhv.enable             = TRUE         — вложенная виртуализация (VT-x/EPT).

    Каждый изменяемый .vmx получает резервную копию в сессии бэкапа (AR-304).
    Отсутствующие каталоги/ВМ — не ошибка: скрипт сообщает SKIP и завершается 0.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER VmRoot
    Корень виртуальных машин (по умолчанию D:\VM, README §7.5).

.PARAMETER Audit
    Только чтение: показать diff по каждому .vmx, ничего не менять.

.EXAMPLE
    pwsh -File ./devops/hypervisor/Configure-WhpCoexistence.ps1 -Audit
    pwsh -File ./devops/hypervisor/Configure-WhpCoexistence.ps1

.NOTES
    Script-ID  : SCRIPT-HV-002
    Stage      : 7
    Patterns   : PAT-07, PAT-22
    ADR        : ADR-0002, ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-206, AR-301, AR-302, AR-303, AR-304, AR-306, AR-307, AR-501, AR-702, AR-708, AR-709)
    Depends    : devops/hypervisor/vmware/VM.vmx.template, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string]$VmRoot = 'D:\VM',

    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-HV-002'
$templatePath = Join-Path $RepoRoot 'devops/hypervisor/vmware/VM.vmx.template'

# Директивы, снимаемые из шаблона: строки вида ключ = "значение" (без комментариев).
function Get-VmxDirective {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TemplatePath)

    $directives = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Get-Content -LiteralPath $TemplatePath)) {
        if ($line -match '^\s*#' -or $line -notmatch '\S') { continue }
        if ($line -match '^\s*([\w\.]+)\s*=\s*(.+?)\s*$') {
            $directives.Add([pscustomobject]@{ Key = $Matches[1]; Value = $Matches[2] })
        }
    }
    return $directives
}

function Set-VmxDirective {
    <# Идемпотентно приводит файл к набору директив; возвращает $true, если были изменения. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Directives
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]](Get-Content -LiteralPath $Path))
    $changed = $false

    foreach ($d in $Directives) {
        $pattern = '^\s*' + [regex]::Escape($d.Key) + '\s*='
        $index = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pattern) { $index = $i; break }
        }
        $target = '{0} = {1}' -f $d.Key, $d.Value
        if ($index -ge 0) {
            if ($lines[$index].Trim() -ne $target) { $lines[$index] = $target; $changed = $true }
        }
        else {
            $lines.Add($target); $changed = $true
        }
    }

    if ($changed) { Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII }
    return $changed
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 7 — сосуществование WSL2 и VMware (WHP)'

    $whp = Get-WindowsOptionalFeature -Online -FeatureName 'HypervisorPlatform' -ErrorAction SilentlyContinue
    Add-VerificationCheck -Context $context -Id 'C0.1' -Check 'HypervisorPlatform (WHP API)' `
        -Expected 'Enabled' -Actual $(if ($whp) { [string]$whp.State } else { 'NotFound' }) `
        -Status $(if ($whp -and $whp.State -eq 'Enabled') { 'PASS' } else { 'FAIL' }) -Note 'AR-701, ADR-0002'

    $launch = (& bcdedit.exe /enum '{current}' 2>$null) | Where-Object { $_ -match '^\s*hypervisorlaunchtype\s+' } | Select-Object -First 1
    $launchType = if ($launch) { (($launch -split '\s+') | Where-Object { $_ } | Select-Object -Last 1) } else { 'NotSet' }
    Add-VerificationCheck -Context $context -Id 'C0.2' -Check 'hypervisorlaunchtype' -Expected 'auto' -Actual $launchType `
        -Status $(if ($launchType -eq 'auto') { 'PASS' } else { 'FAIL' }) -Note 'AR-702'

    $hyperv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue
    Add-VerificationCheck -Context $context -Id 'C0.3' -Check 'Полноценный Hyper-V не включён' `
        -Expected 'Disabled/NotFound' -Actual $(if ($hyperv) { [string]$hyperv.State } else { 'NotFound' }) `
        -Status $(if ($hyperv -and $hyperv.State -eq 'Enabled') { 'FAIL' } else { 'PASS' }) -Note 'AR-701'

    if (-not (Test-Path -LiteralPath $templatePath)) {
        Add-VerificationCheck -Context $context -Id 'C1.0' -Check 'Шаблон .vmx' -Expected 'существует' -Actual 'отсутствует' -Status 'FAIL'
        Write-VerificationReport -Context $context
        exit $exit.Precondition
    }
    $directives = @(Get-VmxDirective -TemplatePath $templatePath)

    $vmxFiles = @()
    if (Test-Path -LiteralPath $VmRoot) {
        $vmxFiles = @(Get-ChildItem -LiteralPath $VmRoot -Recurse -Filter '*.vmx' -File -ErrorAction SilentlyContinue)
    }

    if ($vmxFiles.Count -eq 0) {
        Add-VerificationCheck -Context $context -Id 'C1.1' -Check ('Виртуальные машины под {0}' -f $VmRoot) `
            -Expected '≥ 1' -Actual '0' -Status 'SKIP' -Note 'ВМ создаются владельцем после этого шага; директивы применятся повторным прогоном.'
        Write-Log -Level 'WARN' -Component $scriptId -Message ('Каталог {0} пуст или отсутствует: применяемость отложена.' -f $VmRoot)
    }
    else {
        $backupDir = if ($Audit) { '' } else { New-BackupSession -RepoRoot $RepoRoot -StageId 'stage7-vmx' }
        $index = 0
        foreach ($vmx in $vmxFiles) {
            $index++
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0}: проверка директив ({1} шт.)' -f $vmx.FullName, $directives.Count)
                continue
            }
            Assert-PathAllowed -Path $vmx.FullName -RepoRoot $RepoRoot
            Copy-Item -LiteralPath $vmx.FullName -Destination (Join-Path $backupDir $vmx.Name) -Force
            $changed = Set-VmxDirective -Path $vmx.FullName -Directives $directives
            Write-Log -Level $(if ($changed) { 'PASS' } else { 'INFO' }) -Component $scriptId `
                -Message ('{0}: {1}' -f $vmx.FullName, $(if ($changed) { 'директивы приведены' } else { 'уже соответствуют (AR-303)' }))
        }

        if (-not $Audit) {
            foreach ($vmx in $vmxFiles) {
                $text = Get-Content -LiteralPath $vmx.FullName -Raw
                $missing = @($directives | Where-Object { $text -notmatch ('(?m)^\s*' + [regex]::Escape($_.Key) + '\s*=') })
                Add-VerificationCheck -Context $context -Id ('C1.{0}' -f (Split-Path -Leaf $vmx.FullName)) -Check $vmx.Name `
                    -Expected ('{0}/{0} директив' -f $directives.Count) -Actual ('{0}/{1}' -f ($directives.Count - $missing.Count), $directives.Count) `
                    -Status $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'PAT-22, AR-708'
            }
        }
    }

    if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: .vmx не изменялись.' }

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
