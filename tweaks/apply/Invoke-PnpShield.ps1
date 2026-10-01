<#
.SYNOPSIS
    Временный щит PnP (PAT-15): барьер Co-инсталляторов на время инъекции драйверов.

.DESCRIPTION
    Цикл жизни барьера строго контролируется:
      -Enable  : включаются DenyDeviceIDs и DisableCoInstallers (барьер Co-инсталляторов);
      -Disable : значения удаляются, Plug-and-Play возвращается в штатный режим.

    КРИТИЧНО: барьер нельзя оставлять активным. Если он остаётся, ядро блокирует
    внутренние линкеры драйверов (Software Components) и часть устройств (тачпад,
    аудиокодек Realtek) отваливается с ошибками 28/48. Поэтому:
      * вызывающий скрипт обязан снимать барьер в блоке finally;
      * каждый режим сообщает целевое состояние и проверяет его (AR-307).

.PARAMETER RepoRoot
    Корень репозитория (для логирования).

.PARAMETER Enable
    Поднять барьер.

.PARAMETER Disable
    Снять барьер (основной безопасный режим, идемпотентен).

.PARAMETER Audit
    Не изменять реестр, только показать текущее состояние и план.

.EXAMPLE
    pwsh -File ./tweaks/apply/Invoke-PnpShield.ps1 -RepoRoot C:\repo -Enable
    pwsh -File ./tweaks/apply/Invoke-PnpShield.ps1 -RepoRoot C:\repo -Disable

.NOTES
    Script-ID  : SCRIPT-TWEAKS-PNP
    Stage      : 4
    Patterns   : PAT-15
    ADR        : ADR-0012
    Rules      : AUTOMATION_RULES.md (AR-301, AR-302, AR-306, AR-307)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Enable,

    [switch]$Disable,

    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1') -Force
$exit = Get-ExitCode
$scriptId = 'SCRIPT-TWEAKS-PNP'

$script:ShieldKeys = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'; Name = 'DenyDeviceIDs' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer';     Name = 'DisableCoInstallers' }
)

function Get-ShieldState {
    [CmdletBinding()]
    param()

    $active = 0
    foreach ($k in $script:ShieldKeys) {
        try {
            $v = (Get-ItemProperty -LiteralPath $k.Path -Name $k.Name -ErrorAction Stop).$($k.Name)
            if ([int]$v -eq 1) { $active++ }
        }
        catch {
            # Значения нет — элемент барьера не активен.
        }
    }
    return $active
}

try {
    if ($Enable -and $Disable) {
        Write-Log -Level 'FAIL' -Component $scriptId -Message 'Укажите либо -Enable, либо -Disable, но не оба.'
        exit $exit.Precondition
    }

    if ($Audit) {
        $state = Get-ShieldState
        Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Активных элементов барьера: {0} из {1} (изменения не вносятся)' -f $state, $script:ShieldKeys.Count)
        exit $exit.Ok
    }

    if ($Disable) {
        if ((Get-ShieldState) -eq 0) {
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Барьер уже снят (идемпотентный пропуск).'
            exit $exit.Ok
        }
        foreach ($k in $script:ShieldKeys) {
            if ($PSCmdlet.ShouldProcess($k.Path, ('удалить значение {0}' -f $k.Name))) {
                try {
                    Remove-ItemProperty -LiteralPath $k.Path -Name $k.Name -Force -ErrorAction Stop
                }
                catch {
                    Write-Log -Level 'WARN' -Component $scriptId -Message ('Не удалось удалить {0} (возможно, отсутствует).' -f $k.Name)
                }
            }
        }
        $state = Get-ShieldState
        if ($state -eq 0) {
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Барьер снят: Plug-and-Play в штатном режиме.'
            exit $exit.Ok
        }
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('Барьер не снят полностью: активных элементов {0}' -f $state)
        exit $exit.VerifyFailed
    }

    if ($Enable) {
        if ((Get-ShieldState) -eq $script:ShieldKeys.Count) {
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Барьер уже активен (идемпотентный пропуск).'
            exit $exit.Ok
        }
        foreach ($k in $script:ShieldKeys) {
            if (-not (Test-Path -LiteralPath $k.Path)) {
                New-Item -Path $k.Path -Force | Out-Null
            }
            if ($PSCmdlet.ShouldProcess($k.Path, ('установить {0}=1' -f $k.Name))) {
                New-ItemProperty -LiteralPath $k.Path -Name $k.Name -Value 1 -PropertyType DWord -Force | Out-Null
            }
        }
        $state = Get-ShieldState
        if ($state -eq $script:ShieldKeys.Count) {
            Write-Log -Level 'PASS' -Component $scriptId -Message 'Барьер активирован (временный, снимается вызывающим скриптом в finally).'
            exit $exit.Ok
        }
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('Барьер активирован не полностью: {0} из {1}' -f $state, $script:ShieldKeys.Count)
        exit $exit.VerifyFailed
    }

    Write-Log -Level 'FAIL' -Component $scriptId -Message 'Не указан режим: используйте -Enable, -Disable или -Audit.'
    exit $exit.Precondition
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
