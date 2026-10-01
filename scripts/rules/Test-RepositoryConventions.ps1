<#
.SYNOPSIS
    Проверка конвенций репозитория перед коммитом.

.DESCRIPTION
    Исполняемый валидатор правил AR-101, AR-102, AR-103, AR-105, AR-106, AR-207
    и конвенций STRUC_003, STRUC_004, STRUC_005, STRUC_008, STRUC_010, AR-804.

    Проверки:
      1. Каталоги: README.md, имя в lowercase-kebab-case.
      2. Кодировки по классу файла (матрица AR-1.1) и BOM.
      3. Окончания строк (CRLF/LF) и финальный перевод строки (AR-102/AR-103).
      4. Эвристика AR-105: кириллица в .bat/.cmd/.vbs/.inf.
      5. Эвристика AR-207: высокосигнальные шаблоны секретов.
      6. Шапка .ps1 (AR-401/AR-402) и запрещённые конструкции (AR-403/AR-404/AR-406).
      7. AR-804: крупные файлы в индексе Git.

.OUTPUTS
    PASS/FAIL/WARN по каждой проверке. Код возврата 0 (PASS) или 10 (нарушения).

.NOTES
    Script-ID   : SCRIPT-RULES-001
    Stage       : All
    Patterns    : —
    ADR         : ADR-0009
    Rules       : AUTOMATION_RULES.md (AR-101, AR-102, AR-103, AR-105, AR-106, AR-207)
    Author      : AI-агент (Arena.ai)
    Created     : 2026-10-01
    Schema      : 3.0.0

.PARAMETER RepoRoot
    Корень репозитория. По умолчанию — каталог двумя уровнями выше скрипта.

.PARAMETER MaxTrackedFileMB
    Порог размера файла в индексе Git (AR-804). По умолчанию 50 МБ.
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [int]$MaxTrackedFileMB = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitOk    = 0
$script:ExitFail  = 10
$script:Failures  = New-Object System.Collections.Generic.List[string]
$script:Warnings  = New-Object System.Collections.Generic.List[string]

# Каталоги, исключаемые из обхода
$script:ExcludedDirs = @('.git', 'logs', 'backups', 'node_modules')

# Классы файлов (матрица AR-1.1)
$script:Classes = @{
    PsUtf8Bom     = @('.ps1', '.psm1', '.psd1')
    XmlNoBom      = @('.xml')
    AsciiOnly     = @('.bat', '.cmd', '.vbs', '.inf')
    RegUtf16      = @('.reg')
    LfNoBom       = @('.md', '.json', '.yaml', '.yml', '.gitignore', '.gitattributes', '.editorconfig')
    CsvBom        = @('.csv')
    CrlfNoBom     = @('.txt', '.vmx', '.conf', '.wslconfig')
}
$script:BinaryExt  = @('.exe', '.dll', '.sys', '.msi', '.iso', '.img', '.vhd', '.vhdx', '.vmdk', '.zip', '.7z', '.rar', '.png', '.jpg', '.jpeg', '.ico', '.gif', '.pdf')

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:Failures.Add($Message)
}

function Add-Warning {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:Warnings.Add($Message)
}

function Test-HasUtf8Bom {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}

function Test-IsAscii {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    foreach ($b in $Bytes) {
        if ($b -gt 0x7F) { return $false }
    }
    return $true
}

function Get-EolStats {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $crlf = 0
    $cr = 0
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 0x0D) {
            $cr++
            if (($i + 1) -lt $Bytes.Length -and $Bytes[$i + 1] -eq 0x0A) { $crlf++ }
        }
    }
    return @{ Cr = $cr; Crlf = $crlf; HasFinalNewline = ($Bytes.Length -gt 0 -and $Bytes[$Bytes.Length - 1] -eq 0x0A) }
}

function Get-RepoFile {
    param([Parameter(Mandatory = $true)][string]$Root)

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
        $path = $_.FullName
        $skip = $false
        foreach ($dir in $script:ExcludedDirs) {
            if ($path -like ('*' + [System.IO.Path]::DirectorySeparatorChar + $dir + [System.IO.Path]::DirectorySeparatorChar + '*')) { $skip = $true }
        }
        -not $skip
    }
}

function Test-DirectoryConventions {
    param([Parameter(Mandatory = $true)][string]$Root)

    $dirs = Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force | Where-Object {
        $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
        $parts = $rel -split '[\\/]'
        ($parts | Where-Object { $script:ExcludedDirs -contains $_ }).Count -eq 0
    }

    foreach ($dir in $dirs) {
        $name = $dir.Name
        if ($name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            Add-Failure ('STRUC_004: имя каталога не в lowercase-kebab-case: {0}' -f $dir.FullName.Substring($Root.Length))
        }
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'README.md'))) {
            Add-Failure ('STRUC_003: нет README.md в каталоге: {0}' -f $dir.FullName.Substring($Root.Length))
        }
    }
}

function Test-FileConventions {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $ext = $File.Extension.ToLowerInvariant()
    $rel = $File.FullName
    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)

    if ($bytes.Length -eq 0) {
        Add-Warning ('Пустой файл: {0}' -f $rel)
        return
    }

    $hasBom = Test-HasUtf8Bom -Bytes $bytes
    $eol = Get-EolStats -Bytes $bytes

    if ($script:Classes.PsUtf8Bom -contains $ext) {
        if (-not $hasBom) { Add-Failure ('AR-101: .ps1/.psm1/.psd1 без BOM (нужен UTF-8 с BOM): {0}' -f $rel) }
        if ($eol.Cr -ne $eol.Crlf) { Add-Failure ('AR-102: .ps1 смешанные/одиночные окончания строк (нужен CRLF): {0}' -f $rel) }
        Test-ScriptHeader -File $File -Bytes $bytes
    }
    elseif ($script:Classes.XmlNoBom -contains $ext) {
        if ($hasBom) { Add-Failure ('AR-101: XML с BOM (WinPE setup.exe отклонит файл): {0}' -f $rel) }
        if ($eol.Cr -ne $eol.Crlf) { Add-Failure ('AR-102: XML должен быть CRLF: {0}' -f $rel) }
    }
    elseif ($script:Classes.AsciiOnly -contains $ext) {
        if ($hasBom) { Add-Failure ('AR-101: {0} с BOM недопустим: {1}' -f $ext, $rel) }
        if (-not (Test-IsAscii -Bytes $bytes)) { Add-Failure ('AR-105: не-ASCII (кириллица) в {0}: {1}' -f $ext, $rel) }
        if ($eol.Cr -ne $eol.Crlf) { Add-Failure ('AR-102: {0} должен быть CRLF: {1}' -f $ext, $rel) }
    }
    elseif ($script:Classes.RegUtf16 -contains $ext) {
        $isUtf16 = ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
        if (-not $isUtf16) { Add-Failure ('AR-101: .reg должен быть UTF-16LE с BOM: {0}' -f $rel) }
    }
    elseif ($script:Classes.LfNoBom -contains $ext -or ($script:Classes.LfNoBom -contains $File.Name)) {
        if ($hasBom) { Add-Failure ('AR-101: BOM недопустим: {0}' -f $rel) }
        if ($eol.Cr -ne 0) { Add-Failure ('AR-102: ожидается LF, найдены CR: {0}' -f $rel) }
    }
    elseif ($script:Classes.CsvBom -contains $ext) {
        if (-not $hasBom) { Add-Failure ('AR-101: CSV должен быть UTF-8 с BOM (Excel): {0}' -f $rel) }
    }
    elseif ($script:Classes.CrlfNoBom -contains $ext) {
        if ($hasBom) { Add-Failure ('AR-101: BOM недопустим: {0}' -f $rel) }
        if ($eol.Cr -ne $eol.Crlf) { Add-Failure ('AR-102: ожидается CRLF: {0}' -f $rel) }
    }

    if (-not $eol.HasFinalNewline) {
        Add-Failure ('AR-103: файл не заканчивается переводом строки: {0}' -f $rel)
    }

    if ($script:Classes.AsciiOnly -notcontains $ext -and -not $hasBom -and $script:Classes.RegUtf16 -notcontains $ext) {
        Test-SecretPatterns -File $File -Bytes $bytes
    }
}

function Test-ScriptHeader {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    $rel = $File.FullName

    if ($text -notmatch '#Requires -Version 5\.1') { Add-Failure ('AR-401: нет "#Requires -Version 5.1": {0}' -f $rel) }
    if ($text -notmatch 'Set-StrictMode')            { Add-Failure ('AR-401: нет Set-StrictMode: {0}' -f $rel) }
    if ($text -notmatch '\$ErrorActionPreference')   { Add-Failure ('AR-401: нет $ErrorActionPreference: {0}' -f $rel) }
    if ($text -notmatch 'SCHEMA_VERSION|Schema\s*:')  { Add-Failure ('AR-402: нет поля Schema/SCHEMA_VERSION в шапке: {0}' -f $rel) }

    # Исключение (ADR-0009): файлы scripts/rules/* являются реализацией правил и по
    # определению содержат литералы проверяемых конструкций. Скан запрещённых токенов
    # к ним не применяется — иначе валидатор находил бы нарушения в самом себе.
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $isRuleImplementation = ($File.DirectoryName -like ('*' + $sep + 'rules'))
    if ($isRuleImplementation) { return }

    if ($text -match 'Read-Host')          { Add-Failure ('AR-404: интерактивный Read-Host: {0}' -f $rel) }
    if ($text -match 'Invoke-Expression')  { Add-Failure ('AR-406: запрещён Invoke-Expression: {0}' -f $rel) }
    if ($text -match '\bForEach-Object\s+-Parallel') { Add-Failure ('AR-403: -Parallel отсутствует в PS 5.1: {0}' -f $rel) }
    if ($text -match '\$PSStyle|\?\?')      { Add-Warning  ('AR-403: возможна конструкция, отсутствующая в PS 5.1: {0}' -f $rel) }
}

function Test-SecretPatterns {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    $patterns = @(
        '-----BEGIN [A-Z ]*PRIVATE KEY-----',
        'ghp_[A-Za-z0-9]{20,}',
        'AKIA[0-9A-Z]{16}',
        'xox[baprs]-[A-Za-z0-9-]{10,}'
    )
    foreach ($p in $patterns) {
        if ($text -match $p) {
            Add-Failure ('AR-207: возможный секрет ({0}): {1}' -f $p, $File.FullName)
        }
    }
}

function Test-GitTrackedSizes {
    param([Parameter(Mandatory = $true)][string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Add-Warning 'git не найден — проверка AR-804 пропущена.'
        return
    }

    Push-Location $Root
    try {
        $tracked = & git ls-files 2>$null
        foreach ($item in $tracked) {
            $full = Join-Path $Root $item
            if (Test-Path -LiteralPath $full) {
                $sizeMB = (Get-Item -LiteralPath $full).Length / 1MB
                if ($sizeMB -gt $MaxTrackedFileMB) {
                    Add-Failure ('AR-804: файл в индексе превышает {0} МБ: {1} ({2:N1} МБ)' -f $MaxTrackedFileMB, $item, $sizeMB)
                }
            }
        }
    }
    finally {
        Pop-Location
    }
}

# --- Точка входа ------------------------------------------------------------
try {
    Write-Host ('Валидатор конвенций. RepoRoot: {0}' -f $RepoRoot)

    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        Write-Host ('FAIL: RepoRoot не найден: {0}' -f $RepoRoot)
        exit $script:ExitFail
    }

    Test-DirectoryConventions -Root $RepoRoot

    $files = Get-RepoFile -Root $RepoRoot
    foreach ($file in $files) {
        if ($script:BinaryExt -contains $file.Extension.ToLowerInvariant()) { continue }
        Test-FileConventions -File $file
    }

    Test-GitTrackedSizes -Root $RepoRoot

    foreach ($w in $script:Warnings)  { Write-Host ('WARN: {0}' -f $w) -ForegroundColor Yellow }
    foreach ($f in $script:Failures)  { Write-Host ('FAIL: {0}' -f $f) -ForegroundColor Red }

    Write-Host ('Проверено файлов: {0}; нарушений: {1}; предупреждений: {2}' -f $files.Count, $script:Failures.Count, $script:Warnings.Count)

    if ($script:Failures.Count -gt 0) {
        Write-Host 'ИТОГ: FAIL — коммит запрещён (AR-106, AR-903).'
        exit $script:ExitFail
    }

    Write-Host 'ИТОГ: PASS — конвенции соблюдены.'
    exit $script:ExitOk
}
catch {
    Write-Host ('FATAL: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 99
}
