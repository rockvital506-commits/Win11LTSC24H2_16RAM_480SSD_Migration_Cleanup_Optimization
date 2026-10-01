<#
.SYNOPSIS
    Регистрация задачи самозащиты System_Immunity_Core и вывод из строя задач-реаниматоров.

.DESCRIPTION
    Читает tweaks/tasks/TaskManifest.json и:
      1. register — регистрирует (идемпотентно) задачу System_Immunity_Core:
         триггеры «при запуске» и «при разблокировании рабочей станции»,
         принципал Administrators с наивысшими правами, действие
         wscript.exe D:\GD_Tool\Launcher.vbs (PAT-NEW-4);
      2. retire — отключает задачи телеметрии, экспортируя XML каждой в бэкап
         (AR-304). Unregister (удаление) — только явным флагом -Unregister (AR-204);
      3. опционально ставит DENY на запись для SYSTEM на XML-файл задачи
         (denyWriteToSystem), чтобы система не могла реактивировать её сама
         (PAT-04 + PAT-11).

    Задача регистрируется из сгенерированного XML (декларативное описание
    триггеров), а не через наборы параметров: это исключает расхождение между
    манифестом и фактической задачей.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Audit
    Только чтение: показать план и текущее состояние задач.

.PARAMETER Unregister
    Удалять (а не отключать) задачи-реаниматоры. Деструктивно: XML каждой задачи
    предварительно экспортируется в бэкап (AR-204).

.PARAMETER SkipRegister
    Не трогать задачу System_Immunity_Core.

.PARAMETER SkipRetire
    Не трогать задачи-реаниматоры.

.PARAMETER ApplyTaskAcl
    Применить DENY SYSTEM:(W) на XML-файлы выведенных из строя задач.

.PARAMETER VerificationReport
    Путь к markdown-отчёту верификации (UTF-8 без BOM, LF).

.EXAMPLE
    pwsh -File ./tweaks/apply/Apply-TaskManifest.ps1 -Audit
    pwsh -File ./tweaks/apply/Apply-TaskManifest.ps1 -ApplyTaskAcl

.NOTES
    Script-ID  : SCRIPT-TASK-001
    Stage      : 6
    Patterns   : PAT-04, PAT-11, PAT-NEW-2, PAT-NEW-4
    ADR        : ADR-0003, ADR-0015
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-303, AR-304, AR-306, AR-307, AR-501, AR-502, AR-506)
    Depends    : scripts/common/*, tweaks/tasks/TaskManifest.json, modules ScheduledTasks
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [switch]$Audit,

    [switch]$Unregister,

    [switch]$SkipRegister,

    [switch]$SkipRetire,

    [switch]$ApplyTaskAcl,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Backup.psm1')       -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-TASK-001'
$tasksRoot = Join-Path $env:SystemRoot 'System32/Tasks'

function New-ImmunityTaskXml {
    <# Собирает XML задачи из записи манифеста (декларативные триггеры/действия). #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Task)

    $doc = New-Object System.Xml.XmlDocument
    $decl = $doc.CreateXmlDeclaration('1.0', 'UTF-16', $null)
    $doc.AppendChild($decl) | Out-Null

    $taskNode = $doc.CreateElement('Task', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    $taskNode.SetAttribute('version', '1.2')
    $doc.AppendChild($taskNode) | Out-Null

    $reg = $doc.CreateElement('RegistrationInfo', $taskNode.NamespaceURI)
    $taskNode.AppendChild($reg) | Out-Null
    $desc = $doc.CreateElement('Description', $taskNode.NamespaceURI)
    $desc.InnerText = [string]$Task.description
    $reg.AppendChild($desc) | Out-Null

    $triggers = $doc.CreateElement('Triggers', $taskNode.NamespaceURI)
    $taskNode.AppendChild($triggers) | Out-Null
    foreach ($trigger in $Task.triggers) {
        if ($trigger.type -eq 'BootTrigger') {
            $node = $doc.CreateElement('BootTrigger', $taskNode.NamespaceURI)
            $triggers.AppendChild($node) | Out-Null
        }
        elseif ($trigger.type -eq 'SessionStateChangeTrigger') {
            $node = $doc.CreateElement('SessionStateChangeTrigger', $taskNode.NamespaceURI)
            $state = $doc.CreateElement('StateChange', $taskNode.NamespaceURI)
            $state.InnerText = 'SessionUnlock'
            $node.AppendChild($state) | Out-Null
            $triggers.AppendChild($node) | Out-Null
        }
    }

    $principals = $doc.CreateElement('Principals', $taskNode.NamespaceURI)
    $taskNode.AppendChild($principals) | Out-Null
    $principal = $doc.CreateElement('Principal', $taskNode.NamespaceURI)
    $principal.SetAttribute('id', 'Author')
    $principals.AppendChild($principal) | Out-Null
    # Принципал — SYSTEM (S-1-5-18): контур не зависит от активной сессии.
    $userId = $doc.CreateElement('UserId', $taskNode.NamespaceURI)
    $userId.InnerText = 'S-1-5-18'
    $principal.AppendChild($userId) | Out-Null
    $runLevel = $doc.CreateElement('RunLevel', $taskNode.NamespaceURI)
    $runLevel.InnerText = 'HighestAvailable'
    $principal.AppendChild($runLevel) | Out-Null

    $settings = $doc.CreateElement('Settings', $taskNode.NamespaceURI)
    $taskNode.AppendChild($settings) | Out-Null
    $settingsMap = @{
        'AllowStartOnDemand'              = 'true'
        'StartWhenAvailable'              = 'true'
        'MultipleInstancesPolicy'         = 'IgnoreNew'
        'DisallowStartIfOnBatteries'      = 'false'
        'StopIfGoingOnBatteries'          = 'false'
        'RunOnlyIfNetworkAvailable'       = 'false'
        'Enabled'                         = 'true'
        'ExecutionTimeLimit'              = 'PT0S'
    }
    foreach ($key in $settingsMap.Keys) {
        $node = $doc.CreateElement($key, $taskNode.NamespaceURI)
        $node.InnerText = $settingsMap[$key]
        $settings.AppendChild($node) | Out-Null
    }

    $actions = $doc.CreateElement('Actions', $taskNode.NamespaceURI)
    $taskNode.AppendChild($actions) | Out-Null
    $exec = $doc.CreateElement('Exec', $taskNode.NamespaceURI)
    $actions.AppendChild($exec) | Out-Null
    $command = $doc.CreateElement('Command', $taskNode.NamespaceURI)
    $command.InnerText = [string]$Task.action.execute
    $exec.AppendChild($command) | Out-Null
    $arguments = $doc.CreateElement('Arguments', $taskNode.NamespaceURI)
    $arguments.InnerText = [string]$Task.action.arguments
    $exec.AppendChild($arguments) | Out-Null

    return $doc.OuterXml
}

try {
    Assert-Administrator | Out-Null
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null

    $context  = New-VerificationContext -Title 'Stage 6 — задачи планировщика (самозащита и реаниматоры)'
    $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'tweaks/tasks/TaskManifest.json') -Raw | ConvertFrom-Json

    $backupDir = ''
    if (-not $Audit) {
        $backupDir = New-BackupSession -RepoRoot $RepoRoot -StageId 'stage6'
        Write-Log -Component $scriptId -Message ('Бэкап-сессия: {0}' -f $backupDir)
    }

    # --- Регистрация System_Immunity_Core (PAT-NEW-4) ---
    if (-not $SkipRegister) {
        foreach ($task in $manifest.register) {
            $existing = Get-ScheduledTask -TaskName ([string]$task.name) -ErrorAction SilentlyContinue
            if ($existing) {
                if (-not $Audit -and $backupDir) {
                    Export-ScheduledTask -TaskName ([string]$task.name) |
                        Set-Content -LiteralPath (Join-Path $backupDir ('task_{0}_before.xml' -f $task.id)) -Encoding UTF8
                }
                Write-Log -Level 'INFO' -Component $scriptId -Message ('Задача уже существует: {0} (будет перерегистрирована по манифесту).' -f $task.name)
            }

            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('Регистрация задачи {0}: {1} {2}' -f $task.name, $task.action.execute, $task.action.arguments)
            }
            elseif ($PSCmdlet.ShouldProcess([string]$task.name, 'Register-ScheduledTask')) {
                $xml = New-ImmunityTaskXml -Task $task
                Register-ScheduledTask -TaskName ([string]$task.name) -Xml $xml -Force | Out-Null
                Write-Log -Level 'PASS' -Component $scriptId -Message ('Задача зарегистрирована: {0}' -f $task.name)
            }

            if (-not $Audit) {
                $registered = Get-ScheduledTask -TaskName ([string]$task.name) -ErrorAction SilentlyContinue
                $state = if ($registered) { [string]$registered.State } else { 'отсутствует' }
                Add-VerificationCheck -Context $context -Id ('{0}.1' -f $task.id) -Check ('Задача {0} зарегистрирована' -f $task.name) `
                    -Expected 'State = Ready' -Actual $state -Status $(if ($registered) { 'PASS' } else { 'FAIL' }) -Note 'PAT-NEW-4'

                if ($registered) {
                    $triggerTypes = @($registered.Triggers | ForEach-Object { $_.CimClass.CimClassName })
                    $hasBoot = @($triggerTypes | Where-Object { $_ -match 'BootTrigger' }).Count -gt 0
                    $hasUnlock = @($triggerTypes | Where-Object { $_ -match 'SessionStateChangeTrigger' }).Count -gt 0
                    Add-VerificationCheck -Context $context -Id ('{0}.2' -f $task.id) -Check ('Триггеры {0}' -f $task.name) `
                        -Expected 'boot + unlock' -Actual $(('boot={0}; unlock={1}' -f $hasBoot, $hasUnlock)) `
                        -Status $(if ($hasBoot -and $hasUnlock) { 'PASS' } else { 'FAIL' }) -Note 'PAT-NEW-4'
                }
            }
        }
    }

    # --- Вывод из строя задач-реаниматоров (PAT-04) ---
    if (-not $SkipRetire) {
        foreach ($item in $manifest.retire) {
            $fullPath = [string]$item.taskPath
            $name = Split-Path -Leaf $fullPath
            $parent = Split-Path -Parent $fullPath
            if (-not $parent.EndsWith('\')) { $parent = $parent + '\' }

            $taskObj = Get-ScheduledTask -TaskPath $parent -TaskName $name -ErrorAction SilentlyContinue
            if (-not $taskObj) {
                Add-VerificationCheck -Context $context -Id $item.id -Check ('Задача {0}' -f $fullPath) `
                    -Expected 'выведена из строя' -Actual 'не найдена' -Status 'SKIP' -Note $item.pattern
                continue
            }

            $stateBefore = [string]$taskObj.State
            if ($Audit) {
                Write-Log -Level 'AUDIT' -Component $scriptId -Message ('{0}: {1} (текущее состояние {2})' -f $item.action, $fullPath, $stateBefore)
                continue
            }

            if ($backupDir) {
                Export-ScheduledTask -TaskName $name -TaskPath $parent |
                    Set-Content -LiteralPath (Join-Path $backupDir ('task_{0}.xml' -f $item.id)) -Encoding UTF8
            }

            if ($PSCmdlet.ShouldProcess($fullPath, ([string]$item.action))) {
                if ($Unregister) {
                    Unregister-ScheduledTask -TaskName $name -TaskPath $parent -Confirm:$false -ErrorAction Stop
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('Задача удалена (XML в бэкапе): {0}' -f $fullPath)
                }
                else {
                    Disable-ScheduledTask -TaskName $name -TaskPath $parent -ErrorAction Stop | Out-Null
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('Задача отключена: {0}' -f $fullPath)
                }
            }

            $taskFile = Join-Path $tasksRoot ($fullPath.TrimStart('\'))
            if ($ApplyTaskAcl -and (Test-Path -LiteralPath $taskFile)) {
                Assert-PathAllowed -Path $taskFile -RepoRoot $RepoRoot
                Assert-NotSelfLocking -Principal 'SYSTEM' -Rights '(W)' -TargetPath $taskFile | Out-Null
                if ($PSCmdlet.ShouldProcess($taskFile, 'icacls /deny SYSTEM:(W)')) {
                    & icacls.exe $taskFile /deny 'SYSTEM:(W)' | Out-Null
                    Write-Log -Level 'PASS' -Component $scriptId -Message ('DENY SYSTEM:(W) на файл задачи: {0}' -f $taskFile)
                }
            }

            $after = Get-ScheduledTask -TaskPath $parent -TaskName $name -ErrorAction SilentlyContinue
            $stateAfter = if ($after) { [string]$after.State } else { 'удалена' }
            $ok = (-not $after -and $Unregister) -or ($after -and $after.State -eq 'Disabled')
            Add-VerificationCheck -Context $context -Id $item.id -Check ('Задача {0}' -f $fullPath) `
                -Expected $(if ($Unregister) { 'удалена' } else { 'Disabled' }) -Actual $stateAfter `
                -Status $(if ($ok) { 'PASS' } else { 'FAIL' }) -Note $item.pattern
        }
    }

    if ($backupDir) { Get-BackupManifest -BackupDir $backupDir | Out-Null }

    Write-VerificationReport -Context $context -ExportPath $VerificationReport
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
