<#
.SYNOPSIS
    Stage 6: подготовка контура самозащиты (иммунизация перед активацией).

.DESCRIPTION
    Оркестратор подготовительной фазы Stage 6. Выполняется в профиле devops,
    при отключённой сети (AR-709), до микро-карантина активации:
      P0  предусловия: права, изоляция сети, каталог D:\GD_Tool, наличие LGPO.exe;
      P1  доверенная зона Defender (Invoke-DefenderAllowList.ps1) — до первой
          ACL-операции, иначе поведенческий анализатор поместит .bat в карантин;
      P2  развёртывание рантайма в D:\GD_Tool: ImmunityCore.ps1 (из шаблона),
          AutoSetup.bat, Launcher.vbs + верификация SHA256 (PAT-20);
      P3  задача System_Immunity_Core и вывод из строя задач-реаниматоров
          (Apply-TaskManifest.ps1, PAT-NEW-4, PAT-04);
      P3b правила брандмауэра по декларации tweaks/firewall/ (PAT-09);
      P4  NTFS-замки по AclManifest.json (Apply-AclManifest.ps1) — только с -ApplyAcl;
      P5  сводка и печать ручного чек-листа микро-карантина активации;
      P6  с -VerifyOnly: сквозная верификация (Assert-ImmunityState.ps1).

    Скрипт НЕ управляет сетью: включение сети для активации — ручное действие
    владельца (AR-709, README §4.5).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: план без изменений.

.PARAMETER VerifyOnly
    Ничего не менять: выполнить только P0 и сквозную верификацию P6.

.PARAMETER SkipDefender
    Не трогать доверенную зону Defender.

.PARAMETER SkipTasks
    Не регистрировать задачу и не трогать реаниматоров.

.PARAMETER ApplyAcl
    Применить NTFS-замки (deny) сразу, не дожидаясь запуска AutoSetup.bat.

.PARAMETER SkipFirewall
    Не применять правила брандмауэра и не разворачивать FirewallRules.json.

.PARAMETER ApplyTaskAcl
    Дополнительно поставить DENY на XML-файлы выведенных из строя задач.

.PARAMETER UnregisterTasks
    Удалять задачи-реаниматоры вместо отключения (AR-204, XML в бэкапе).

.PARAMETER AllowNetwork
    Не считать активные сетевые адаптеры блокирующим условием (не рекомендуется).

.PARAMETER VerificationReport
    Путь к markdown-отчёту верификации (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -Audit
    pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -ApplyAcl -ApplyTaskAcl -VerificationReport ./docs/artifacts/Stage6_preflight.md
    pwsh -File ./scripts/Stage6_Immunity_Prepare.ps1 -VerifyOnly -VerificationReport ./docs/artifacts/Stage6_immunity.md

.NOTES
    Script-ID  : SCRIPT-STAGE6-001
    Stage      : 6
    Patterns   : PAT-04, PAT-06, PAT-08, PAT-09, PAT-11, PAT-NEW-2, PAT-NEW-3, PAT-NEW-4
    ADR        : ADR-0003, ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-105, AR-201, AR-204, AR-206, AR-301, AR-303, AR-304, AR-306, AR-307, AR-501, AR-709)
    Depends    : scripts/common/*, tweaks/apply/*, tweaks/{acl,tasks}/*.json, templates/ImmunityCore.ps1.template
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$Audit,

    [switch]$VerifyOnly,

    [switch]$SkipDefender,

    [switch]$SkipTasks,

    [switch]$SkipFirewall,

    [switch]$ApplyAcl,

    [switch]$ApplyTaskAcl,

    [switch]$UnregisterTasks,

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
$scriptId = 'SCRIPT-STAGE6-001'
$toolDir  = 'D:\GD_Tool'
$runtimeFiles = @(
    @{ Source = (Join-Path $RepoRoot 'templates/ImmunityCore.ps1.template'); Target = (Join-Path $toolDir 'ImmunityCore.ps1') },
    @{ Source = (Join-Path $RepoRoot 'scripts/Stage6_AutoSetup.bat');        Target = (Join-Path $toolDir 'AutoSetup.bat') },
    @{ Source = (Join-Path $RepoRoot 'scripts/Stage6_Launcher.vbs');         Target = (Join-Path $toolDir 'Launcher.vbs') },
    @{ Source = (Join-Path $RepoRoot 'tweaks/firewall/FirewallManifest.json'); Target = (Join-Path $toolDir 'FirewallRules.json') }
)

function Test-NetworkIsolation {
    [CmdletBinding()]
    param()
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $bad.Add($adapter.Name)
    }
    return $bad
}

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

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context = New-VerificationContext -Title 'Stage 6 — подготовка контура самозащиты'

    # --- P0: предусловия ---
    $adapters = @(Test-NetworkIsolation)
    $netStatus = if ($adapters.Count -eq 0 -or $AllowNetwork) { 'PASS' } else { 'FAIL' }
    Add-VerificationCheck -Context $context -Id 'P0.1' -Check 'Сеть изолирована (AR-709)' `
        -Expected '0 активных адаптеров' -Actual ([string]$adapters.Count) -Status $netStatus `
        -Note ($(if ($adapters.Count) { 'Активны: ' + ($adapters -join ', ') } else { 'Изоляция подтверждена.' }))

    $toolOk = Test-Path -LiteralPath $toolDir
    Add-VerificationCheck -Context $context -Id 'P0.2' -Check 'Каталог автоматизации D:\GD_Tool' `
        -Expected 'существует' -Actual $(if ($toolOk) { 'существует' } else { 'отсутствует' }) `
        -Status $(if ($toolOk) { 'PASS' } else { 'FAIL' }) -Note 'PAT-NEW-3'

    $lgpoOk = Test-Path -LiteralPath (Join-Path $toolDir 'LGPO.exe')
    Add-VerificationCheck -Context $context -Id 'P0.3' -Check 'LGPO.exe на месте' `
        -Expected 'существует' -Actual $(if ($lgpoOk) { 'существует' } else { 'отсутствует' }) `
        -Status $(if ($lgpoOk) { 'PASS' } else { 'WARN' }) -Note 'PAT-06: без LGPO импорт политик будет пропущен'

    $snapshotOk = Test-Path -LiteralPath (Join-Path $toolDir 'CleanLTSCPolicy\gpt.ini')
    Add-VerificationCheck -Context $context -Id 'P0.4' -Check 'Слепок CleanLTSCPolicy' `
        -Expected 'gpt.ini присутствует' -Actual $(if ($snapshotOk) { 'присутствует' } else { 'отсутствует' }) `
        -Status $(if ($snapshotOk) { 'PASS' } else { 'WARN' }) -Note 'PAT-06: порядок создания — LGPO.exe /b D:\GD_Tool\, затем переименование GUID-каталога'

    $templateOk = Test-Path -LiteralPath (Join-Path $RepoRoot 'templates/ImmunityCore.ps1.template')
    Add-VerificationCheck -Context $context -Id 'P0.5' -Check 'Шаблон рантайма в репозитории' `
        -Expected 'существует' -Actual $(if ($templateOk) { 'существует' } else { 'отсутствует' }) `
        -Status $(if ($templateOk) { 'PASS' } else { 'FAIL' })

    $preconditionFailures = (Get-VerificationFailures -Context $context).Count
    if ($preconditionFailures -gt 0 -and -not $Audit) {
        Write-VerificationReport -Context $context -ExportPath $VerificationReport
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('Не выполнены предусловия: {0}.' -f $preconditionFailures)
        exit $exit.Precondition
    }

    if (-not $VerifyOnly) {
        # --- P1: доверенная зона Defender (до первой ACL-операции) ---
        if (-not $SkipDefender) {
            Write-Log -Component $scriptId -Message 'P1: доверенная зона Defender...'
            $defCode = Invoke-SubScript -Path (Join-Path $RepoRoot 'tweaks/apply/Invoke-DefenderAllowList.ps1') -Arguments @{}
            if ($defCode -ne 0) {
                Write-Log -Level 'FAIL' -Component $scriptId -Message ('Исключения Defender не применены (код {0}).' -f $defCode)
            }
        }

        # --- P2: развёртывание рантайма ---
        Write-Log -Component $scriptId -Message 'P2: развёртывание рантайма в D:\GD_Tool...'
        foreach ($item in $runtimeFiles) {
            if (-not (Test-Path -LiteralPath $item.Source)) {
                Add-VerificationCheck -Context $context -Id ('P2.{0}' -f (Split-Path -Leaf $item.Target)) -Check ('Источник {0}' -f $item.Source) `
                    -Expected 'существует' -Actual 'отсутствует' -Status 'FAIL'
                continue
            }

            $srcHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
            $dstExists = Test-Path -LiteralPath $item.Target
            $dstHash = if ($dstExists) { (Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash } else { '' }
            $same = ($srcHash -eq $dstHash)

            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Копирование {0} -> {1}' -f $item.Source, $item.Target)
            }
            elseif ($same) {
                Write-Log -Level 'INFO' -Component $scriptId -Message ('Актуален: {0}' -f $item.Target)
            }
            elseif ($PSCmdlet.ShouldProcess($item.Target, 'Deploy runtime file')) {
                Assert-PathAllowed -Path $item.Target -RepoRoot $RepoRoot
                Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Развёрнут: {0}' -f $item.Target)
            }
        }

        if (-not $Audit) {
            foreach ($item in $runtimeFiles) {
                if (-not (Test-Path -LiteralPath $item.Target)) { continue }
                $srcHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
                $dstHash = (Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash
                Add-VerificationCheck -Context $context -Id ('P2.{0}' -f (Split-Path -Leaf $item.Target)) -Check ('SHA256 {0}' -f (Split-Path -Leaf $item.Target)) `
                    -Expected $srcHash.Substring(0, 12) -Actual $dstHash.Substring(0, 12) `
                    -Status $(if ($srcHash -eq $dstHash) { 'PASS' } else { 'FAIL' }) -Note 'PAT-20'
            }
        }

        # --- P3: задача контура и реаниматоры ---
        if (-not $SkipTasks) {
            Write-Log -Component $scriptId -Message 'P3: задача System_Immunity_Core и вывод реаниматоров...'
            $taskArgs = @{}
            if ($ApplyTaskAcl) { $taskArgs['ApplyTaskAcl'] = $true }
            if ($UnregisterTasks) { $taskArgs['Unregister'] = $true }
            $taskCode = Invoke-SubScript -Path (Join-Path $RepoRoot 'tweaks/apply/Apply-TaskManifest.ps1') -Arguments $taskArgs
            if ($taskCode -ne 0) {
                Write-Log -Level 'FAIL' -Component $scriptId -Message ('Задачи: код {0}.' -f $taskCode)
            }
        }

        # --- P3b: правила брандмауэра (PAT-09) ---
        if (-not $SkipFirewall) {
            Write-Log -Component $scriptId -Message 'P3b: правила брандмауэра...'
            $fwCode = Invoke-SubScript -Path (Join-Path $RepoRoot 'tweaks/apply/Apply-FirewallManifest.ps1') -Arguments @{}
            if ($fwCode -ne 0) {
                Write-Log -Level 'FAIL' -Component $scriptId -Message ('Брандмауэр: код {0}.' -f $fwCode)
            }
        }
        else {
            Add-VerificationCheck -Context $context -Id 'P3.9' -Check 'Правила брандмауэра' -Expected 'применены' `
                -Actual 'пропущены флагом -SkipFirewall' -Status 'WARN' -Note 'PAT-09'
        }

        # --- P4: NTFS-замки (деноминация контура) ---
        if ($ApplyAcl) {
            Write-Log -Component $scriptId -Message 'P4: NTFS Deny SYSTEM...'
            $aclCode = Invoke-SubScript -Path (Join-Path $RepoRoot 'tweaks/apply/Apply-AclManifest.ps1') -Arguments @{ Phase = 'Deny' }
            if ($aclCode -ne 0) {
                Write-Log -Level 'FAIL' -Component $scriptId -Message ('ACL: код {0}.' -f $aclCode)
            }
        }
        else {
            Add-VerificationCheck -Context $context -Id 'P4.1' -Check 'NTFS-замки' -Expected 'применяются' `
                -Actual 'отложены до запуска AutoSetup.bat' -Status 'WARN' -Note 'PAT-11: применить флагом -ApplyAcl или вручную запустить задачу'
        }
    }

    # --- P5: ручной чек-лист микро-карантина активации ---
    Write-Log -Component $scriptId -Message 'P5: ручные шаги активационного окна (README §4.5, algorithm/manual/Stage6_Ohook_Activation.md):'
    Write-Log -Component $scriptId -Message '  1) включить сеть вручную (скрипт сеть не поднимает, AR-709);'
    Write-Log -Component $scriptId -Message '  2) выполнить перманентную активацию (ADR-0004, SC_PERMANENT_ACTIVATION);'
    Write-Log -Component $scriptId -Message '  3) в планировщике запустить System_Immunity_Core («Выполнить») — контур зацементируется;'
    Write-Log -Component $scriptId -Message '  4) отключить сеть и выполнить -VerifyOnly.'

    # --- P6: сквозная верификация ---
    if (-not $Audit) {
        Write-Log -Component $scriptId -Message 'P6: сквозная верификация контура...'
        $verifyArgs = @{}
        if ($VerificationReport) { $verifyArgs['ExportReport'] = $VerificationReport }
        $verifyCode = Invoke-SubScript -Path (Join-Path $RepoRoot 'tweaks/apply/Assert-ImmunityState.ps1') -Arguments $verifyArgs
    }

    Write-VerificationReport -Context $context -ExportPath $VerificationReport

    if ($Audit) {
        Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: изменения не вносились.'
        exit $exit.Ok
    }

    Write-Log -Level 'PASS' -Component $scriptId -Message 'Подготовка Stage 6 завершена.'
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
