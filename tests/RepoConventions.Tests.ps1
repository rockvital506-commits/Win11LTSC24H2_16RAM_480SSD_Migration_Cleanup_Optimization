<#
.SYNOPSIS
    Pester-обёртка над валидатором конвенций репозитория.

.DESCRIPTION
    Запускает scripts/rules/Test-RepositoryConventions.ps1 и проверяет код возврата.
    Требуется Pester 5.x: Invoke-Pester ./tests

.NOTES
    Script-ID   : SCRIPT-TEST-001
    Stage       : All
    ADR         : ADR-0009
    Rules       : AUTOMATION_RULES.md (AR-902)
    Author      : AI-агент (Arena.ai)
    Created     : 2026-10-01
    Schema      : 3.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Validator   = Join-Path $script:RepoRoot 'scripts/rules/Test-RepositoryConventions.ps1'
}

Describe 'Repository conventions' {

    It 'валидатор существует' {
        Test-Path -LiteralPath $script:Validator | Should -BeTrue
    }

    It 'валидатор возвращает код 0 (PASS)' {
        $output = & $script:Validator -RepoRoot $script:RepoRoot 2>&1 | Out-String
        $code = $LASTEXITCODE
        $code | Should -Be 0 -Because $output
    }

    It 'нет пустых каталогов без README.md' {
        $validatorFile = Get-Content -LiteralPath $script:Validator -Raw
        $validatorFile | Should -Match 'STRUC_003'
    }
}
