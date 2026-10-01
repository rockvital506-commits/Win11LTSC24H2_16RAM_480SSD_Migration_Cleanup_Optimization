<#
.SYNOPSIS
    Ограничители безопасности: allow-list путей (AR-206) и защита от самоблокировки (AR-506).

.DESCRIPTION
    Предоставляет:
      - Assert-Administrator   : проверка прав (AR-401);
      - Get-AllowedRoot        : перечень разрешённых корней записи;
      - Test-PathAllowed       : проверка пути по allow-list;
      - Assert-PathAllowed     : жёсткий отказ при записи вне allow-list;
      - Assert-NotSelfLocking  : проверка перед ACL-операцией: не отбираем ли права
                                 у текущего пользователя/администраторов (AR-506).

    Смысл: доменные скрипты не должны создавать необратимые состояния и не должны
    писать вне объявленной топологии.

.NOTES
    Module-ID  : MOD-COMMON-004
    Stage      : All
    ADR        : ADR-0009, ADR-0003 (будущий, NTFS Deny SYSTEM)
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-506)
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    [CmdletBinding()]
    param()

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        throw 'Требуются права администратора (AR-401).'
    }

    return $true
}

function Get-AllowedRoot {
    <#
        Разрешённые корни записи (AR-206):
          - каталог репозитория (передаётся вызывающим скриптом);
          - C:\Vitality, D:\GD_Tool, D:\Drivers (рабочие каталоги проекта);
          - %SystemRoot%\System32\Sysprep — размещение второго файла ответов
            unattend.xml (Stage 5, ADR-0014 п.1);
          - %TEMP% (транзитные файлы инструментов).
        Расширение списка — только через ADR.
    #>
    [CmdletBinding()]
    param(
        [string]$RepoRoot = ''
    )

    $roots = New-Object System.Collections.Generic.List[string]
    if ($RepoRoot) { $roots.Add((Resolve-Path -LiteralPath $RepoRoot).Path) }
    $roots.Add('C:\Vitality')
    $roots.Add('D:\GD_Tool')
    $roots.Add('D:\Drivers')

    # ADR-0014 п.1: каталог размещения второго файла ответов (Stage 5, Sysprep Seal).
    if ($env:SystemRoot) { $roots.Add((Join-Path $env:SystemRoot 'System32\Sysprep')) }

    if ($env:TEMP) { $roots.Add($env:TEMP) }

    return $roots
}

function Test-PathAllowed {
    <# Возвращает $true, если путь находится внутри одного из разрешённых корней. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RepoRoot = ''
    )

    $full = $Path
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $false
    }

    foreach ($root in (Get-AllowedRoot -RepoRoot $RepoRoot)) {
        $r = $root.TrimEnd('\', '/')
        if ($full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    return $false
}

function Assert-PathAllowed {
    <# Жёсткий отказ при попытке записи вне allow-list (AR-206). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RepoRoot = ''
    )

    if (-not (Test-PathAllowed -Path $Path -RepoRoot $RepoRoot)) {
        throw ('Запись вне allow-list запрещена (AR-206): {0}' -f $Path)
    }

    return $true
}

function Assert-NotSelfLocking {
    <#
        Проверка перед операцией с ACL (AR-506).
        Запрещает правило Deny, которое применяется к текущему пользователю,
        группе Administrators или SYSTEM в объёме, лишающем возможности отката.
        Правило Deny для SYSTEM на запись (W) допускается: оно не блокирует
        доступ администратора (чтение и смена ACL остаются возможными).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Principal,
        [Parameter(Mandatory = $true)][string]$Rights,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    if ($Principal -like '*Administrators*' -or $Principal -eq $current) {
        throw ('Отказ самоблокировки (AR-506): запрещено правило Deny {0}:({1}) для {2}' -f $TargetPath, $Rights, $Principal)
    }

    if ($Rights -match 'F' -or $Rights -match 'D' -or $Rights -match 'DC') {
        throw ('Отказ самоблокировки (AR-506): запрещены полные/owner-права Deny ({0}) на {1}' -f $Rights, $TargetPath)
    }

    return $true
}

Export-ModuleMember -Function Assert-Administrator, Get-AllowedRoot, Test-PathAllowed, Assert-PathAllowed, Assert-NotSelfLocking
