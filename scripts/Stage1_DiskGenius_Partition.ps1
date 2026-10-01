<#
.SYNOPSIS
    Stage 1 — верификация схемы разметки NVMe SSD (read-only).

.DESCRIPTION
    Проверяет соответствие фактической разметки утверждённой схеме ADR-0007 (rev.2) / ADR-0011:

      W1  ESP не имеет буквы диска (скрытая)
      V1  GPT + загрузочный диск UEFI
      V2  четыре раздела типов EFI / MSR / Basic / Basic
      V3  выравнивание всех разделов по границе 1 MiB (PAT-NEW-6)
      V4  размеры: ESP 260 MiB, MSR 16 MiB, Windows 200 GiB, Data ~246.7 GiB (остаток)
      V5  файловые системы и кластеры: FAT32 4 КБ, NTFS 4 КБ, NTFS 64 КБ
      V6  NTFS-параметры: disable8dot3 на D:, disablelastaccess (fsutil)

    ЕДИНИЦЫ (ADR-0011): схема задана в MiB/GiB (двоичные, 1024-based). Все параметры
    скрипта — в этих же единицах; сравнение выполняется в байтах с допуском.
    Раздел Data не имеет фиксированного размера: он забирает весь остаток ёмкости,
    поэтому его ожидаемое значение задаётся параметром -DataSizeGiB (справочно) и
    проверяется с расширенным допуском.

    ВАЖНО: скрипт НИЧЕГО не изменяет и не выполняет разметку. Разметка — деструктивная
    операция и выполняется вручную в DiskGenius (AR-204, ADR-0007). Поэтому параметры
    -Audit/-WhatIf не требуются: AR-302 применяется только к изменяющим скриптам.

.PARAMETER DiskNumber
    Номер физического диска. По умолчанию 0 (системный NVMe).

.PARAMETER EspSizeMiB
    Ожидаемый размер ESP в MiB. По умолчанию 260 (272 629 760 Б).

.PARAMETER MsrSizeMiB
    Ожидаемый размер MSR в MiB. По умолчанию 16 (16 777 216 Б).

.PARAMETER SystemSizeGiB
    Ожидаемый размер раздела Windows в GiB. По умолчанию 200 (214 748 364 800 Б).

.PARAMETER DataSizeGiB
    Справочный ожидаемый размер раздела Data в GiB. По умолчанию 246.7 (остаток ёмкости).

.PARAMETER SizeToleranceMiB
    Допуск для ESP/MSR/Windows, MiB. По умолчанию 512.

.PARAMETER DataToleranceMiB
    Допуск для раздела Data, MiB. По умолчанию 4096.

.PARAMETER AllowEspLetter
    Разрешить ESP с буквой диска (по умолчанию это нарушение ADR-0011).

.PARAMETER SkipNtfsOptions
    Пропустить проверку V6 (fsutil) — например, при запуске в WinPE.

.PARAMETER ExportReport
    Путь для выгрузки markdown-отчёта (например, ./docs/artifacts/Stage1_partition_verify.md).

.EXAMPLE
    pwsh -File ./scripts/Stage1_DiskGenius_Partition.ps1 -ExportReport ./docs/artifacts/Stage1_partition_verify.md

.NOTES
    Script-ID   : SCRIPT-STAGE1-001
    Stage       : 1
    Patterns    : PAT-NEW-6, PAT-NEW-7
    ADR         : ADR-0007 (rev.2), ADR-0011
    Rules       : AUTOMATION_RULES.md (AR-201, AR-204, AR-301, AR-306, AR-307)
    Depends     : Storage module (Get-Disk/Get-Partition/Get-Volume), fsutil
    Author      : AI-агент (Arena.ai)
    Created     : 2026-10-01
    Schema      : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$DiskNumber = 0,

    [int]$EspSizeMiB = 260,

    [int]$MsrSizeMiB = 16,

    [double]$SystemSizeGiB = 200,

    [double]$DataSizeGiB = 246.7,

    [int]$SizeToleranceMiB = 512,

    [int]$DataToleranceMiB = 4096,

    [switch]$AllowEspLetter,

    [switch]$SkipNtfsOptions,

    [string]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitOk           = 0
$script:ExitFail         = 10
$script:ExitPrecondition = 20

$script:GptEfi   = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$script:GptMsr   = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
$script:GptBasic = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

# ADR-0011: канонические единицы — двоичные (MiB/GiB)
$script:MiB = 1048576.0
$script:GiB = 1073741824.0

$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Check,
        [string]$Expected = '',
        [string]$Actual = '',
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')][string]$Status,
        [string]$Note = ''
    )

    $script:Results.Add([pscustomobject]@{
        ID       = $Id
        Check    = $Check
        Expected = $Expected
        Actual   = $Actual
        Status   = $Status
        Note     = $Note
    })
}

function Test-Elevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Size {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double]$Bytes)

    if ($Bytes -ge $script:GiB) { return ('{0:N2} GiB' -f ($Bytes / $script:GiB)) }
    return ('{0:N0} MiB' -f ($Bytes / $script:MiB))
}

function Compare-Size {
    <#
        Сравнение фактического размера с эталоном (байты) в пределах допуска.
        Возвращает Status (PASS/WARN/FAIL) и пояснение.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][double]$ActualBytes,
        [Parameter(Mandatory = $true)][double]$ExpectedBytes,
        [Parameter(Mandatory = $true)][double]$ToleranceBytes
    )

    $deviation = [Math]::Abs($ActualBytes - $ExpectedBytes)

    if ($deviation -le $ToleranceBytes) {
        return @{ Status = 'PASS'; Note = ('отклонение {0} (допуск {1})' -f (Format-Size -Bytes $deviation), (Format-Size -Bytes $ToleranceBytes)) }
    }

    $status = 'FAIL'
    $note   = ('отклонение {0} превышает допуск {1}' -f (Format-Size -Bytes $deviation), (Format-Size -Bytes $ToleranceBytes))

    # Отклонение менее 2 % при большом разделе — вероятная разница округления инструмента
    if ($ExpectedBytes -gt 0 -and ($deviation / $ExpectedBytes) -lt 0.02) {
        $status = 'WARN'
        $note   = ('отклонение {0} ({1:P2}) — в пределах 2 %: уточнить раскладку вручную' -f (Format-Size -Bytes $deviation), ($deviation / $ExpectedBytes))
    }

    return @{ Status = $status; Note = $note }
}

# --- W1/W2/V1/V3/V4 ----------------------------------------------------------
function Test-DiskScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$DiskNumber
    )

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop

    Add-Result -Id 'V1a' -Check 'Таблица разделов' -Expected 'GPT' -Actual $disk.PartitionStyle -Status $(if ($disk.PartitionStyle -eq 'GPT') { 'PASS' } else { 'FAIL' })

    $bootStatus = 'PASS'
    $bootState  = 'загрузочный (UEFI)'
    if (-not $disk.IsBoot) { $bootStatus = 'WARN'; $bootState = 'не загрузочный' }
    Add-Result -Id 'V1b' -Check 'Роль диска' -Expected 'загрузочный' -Actual $bootState -Status $bootStatus -Note ('Модель: {0}; прошивка: {1}' -f $disk.FriendlyName, $disk.FirmwareVersion)

    Add-Result -Id 'V1c' -Check 'Ёмкость накопителя' -Expected '≈447 GiB (маркировка 480 ГБ)' -Actual (Format-Size -Bytes $disk.Size) -Status $(if ($disk.Size -gt 400GB) { 'PASS' } else { 'WARN' })

    $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop)

    $types = @($parts | ForEach-Object { $_.GptType.ToString().ToLowerInvariant() })
    $expectedTypes = @($script:GptEfi, $script:GptMsr, $script:GptBasic, $script:GptBasic)
    $typesOk = $true
    foreach ($t in $expectedTypes) {
        if ($types -notcontains $t) { $typesOk = $false }
    }
    Add-Result -Id 'V2' -Check 'Типы разделов (EFI/MSR/Basic/Basic)' -Expected ($expectedTypes -join ', ') -Actual ('разделов: {0}; {1}' -f $parts.Count, ($types -join ', ')) -Status $(if ($typesOk) { 'PASS' } else { 'FAIL' })

    $aligned   = 0
    $unaligned = New-Object System.Collections.Generic.List[string]
    foreach ($p in $parts) {
        if (($p.Offset % 1MB) -eq 0) { $aligned++ }
        else { $unaligned.Add(('{0} @ {1}' -f $p.PartitionNumber, $p.Offset)) }
    }
    $alignStatus = 'PASS'
    $alignNote   = 'все разделы на границе 1 MiB'
    if ($aligned -ne $parts.Count) {
        $alignStatus = 'FAIL'
        $alignNote   = 'нарушения: ' + ($unaligned -join '; ')
    }
    Add-Result -Id 'V3' -Check 'Выравнивание 1 MiB (PAT-NEW-6)' -Expected ('{0}/{0}' -f $parts.Count) -Actual ('{0}/{1}' -f $aligned, $parts.Count) -Status $alignStatus -Note $alignNote

    # W1: ESP без буквы диска (ADR-0011)
    $espPart = $parts | Where-Object { $_.GptType.ToString().ToLowerInvariant() -eq $script:GptEfi } | Select-Object -First 1
    if ($null -ne $espPart) {
        if ($null -eq $espPart.DriveLetter) {
            Add-Result -Id 'W1' -Check 'ESP без буквы диска (ADR-0011)' -Expected 'нет буквы' -Actual 'скрытая' -Status 'PASS'
        }
        else {
            $status = 'FAIL'
            if ($AllowEspLetter) { $status = 'WARN' }
            Add-Result -Id 'W1' -Check 'ESP без буквы диска (ADR-0011)' -Expected 'нет буквы' -Actual ('{0}:' -f $espPart.DriveLetter) -Status $status -Note 'легализовано только флагом -AllowEspLetter (не рекомендуется)'
        }
    }
    else {
        Add-Result -Id 'W1' -Check 'ESP без буквы диска (ADR-0011)' -Expected 'нет буквы' -Actual 'раздел EFI не найден' -Status 'FAIL'
    }

    # V4: размеры (байтовые эталоны, ADR-0011)
    if ($null -ne $espPart) {
        $verdict = Compare-Size -ActualBytes $espPart.Size -ExpectedBytes ($EspSizeMiB * $script:MiB) -ToleranceBytes (16 * $script:MiB)
        Add-Result -Id 'V4.ESP' -Check ('ESP (#{0})' -f $espPart.PartitionNumber) -Expected ('{0} MiB ({1:N0} Б)' -f $EspSizeMiB, ($EspSizeMiB * $script:MiB)) -Actual (Format-Size -Bytes $espPart.Size) -Status $verdict.Status -Note $verdict.Note
    }

    $msrPart = $parts | Where-Object { $_.GptType.ToString().ToLowerInvariant() -eq $script:GptMsr } | Select-Object -First 1
    if ($null -ne $msrPart) {
        $verdict = Compare-Size -ActualBytes $msrPart.Size -ExpectedBytes ($MsrSizeMiB * $script:MiB) -ToleranceBytes (4 * $script:MiB)
        Add-Result -Id 'V4.MSR' -Check ('MSR (#{0})' -f $msrPart.PartitionNumber) -Expected ('{0} MiB ({1:N0} Б)' -f $MsrSizeMiB, ($MsrSizeMiB * $script:MiB)) -Actual (Format-Size -Bytes $msrPart.Size) -Status $verdict.Status -Note $verdict.Note
    }
    else {
        Add-Result -Id 'V4.MSR' -Check 'MSR' -Expected ('{0} MiB' -f $MsrSizeMiB) -Actual 'раздел MSR не найден' -Status 'FAIL'
    }

    $winPart = $parts | Where-Object { $_.GptType.ToString().ToLowerInvariant() -eq $script:GptBasic -and $_.DriveLetter -eq 'C' } | Select-Object -First 1
    if ($null -ne $winPart) {
        $verdict = Compare-Size -ActualBytes $winPart.Size -ExpectedBytes ($SystemSizeGiB * $script:GiB) -ToleranceBytes ($SizeToleranceMiB * $script:MiB)
        Add-Result -Id 'V4.C' -Check 'Раздел Windows (C:)' -Expected ('{0} GiB ({1:N0} Б)' -f $SystemSizeGiB, ($SystemSizeGiB * $script:GiB)) -Actual (Format-Size -Bytes $winPart.Size) -Status $verdict.Status -Note $verdict.Note
    }
    else {
        Add-Result -Id 'V4.C' -Check 'Раздел Windows (C:)' -Expected ('{0} GiB' -f $SystemSizeGiB) -Actual 'не найден по букве C:' -Status 'FAIL'
    }

    $dataPart = $parts | Where-Object { $_.GptType.ToString().ToLowerInvariant() -eq $script:GptBasic -and $_.DriveLetter -eq 'D' } | Select-Object -First 1
    if ($null -ne $dataPart) {
        $verdict = Compare-Size -ActualBytes $dataPart.Size -ExpectedBytes ($DataSizeGiB * $script:GiB) -ToleranceBytes ($DataToleranceMiB * $script:MiB)
        Add-Result -Id 'V4.D' -Check 'Раздел Data (D:, остаток)' -Expected ('≈{0} GiB' -f $DataSizeGiB) -Actual (Format-Size -Bytes $dataPart.Size) -Status $verdict.Status -Note $verdict.Note
    }
    else {
        Add-Result -Id 'V4.D' -Check 'Раздел Data (D:, остаток)' -Expected ('≈{0} GiB' -f $DataSizeGiB) -Actual 'не найден по букве D:' -Status 'FAIL'
    }

    return $parts
}

# --- V5 ----------------------------------------------------------------------
function Test-VolumeScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Partitions
    )

    $targets = @(
        @{ Id = 'V5.ESP'; Name = 'ESP'; Letter = $null; FileSystem = 'FAT32'; UnitSize = 4096 },
        @{ Id = 'V5.C';   Name = 'C:';  Letter = 'C';   FileSystem = 'NTFS';  UnitSize = 4096 },
        @{ Id = 'V5.D';   Name = 'D:';  Letter = 'D';   FileSystem = 'NTFS';  UnitSize = 65536 }
    )

    foreach ($t in $targets) {
        if ($null -ne $t.Letter) {
            $part = $Partitions | Where-Object { $_.DriveLetter -eq $t.Letter } | Select-Object -First 1
        }
        else {
            $part = $Partitions | Where-Object { $_.GptType.ToString().ToLowerInvariant() -eq $script:GptEfi } | Select-Object -First 1
        }

        if ($null -eq $part) {
            Add-Result -Id $t.Id -Check ('ФС/кластер {0}' -f $t.Name) -Expected ('{0}, кластер {1} Б' -f $t.FileSystem, $t.UnitSize) -Actual 'раздел не найден' -Status 'FAIL'
            continue
        }

        $vol = $null
        try {
            $vol = $part | Get-Volume -ErrorAction Stop
        }
        catch {
            Add-Result -Id $t.Id -Check ('ФС/кластер {0}' -f $t.Name) -Expected ('{0}, кластер {1} Б' -f $t.FileSystem, $t.UnitSize) -Actual 'том недоступен для чтения' -Status 'WARN' -Note $_.Exception.Message
            continue
        }

        if ($null -eq $vol) {
            Add-Result -Id $t.Id -Check ('ФС/кластер {0}' -f $t.Name) -Expected ('{0}, кластер {1} Б' -f $t.FileSystem, $t.UnitSize) -Actual 'том не смонтирован' -Status 'WARN'
            continue
        }

        $fsOk      = ($vol.FileSystem -eq $t.FileSystem)
        $unitSize  = $vol.AllocationUnitSize
        $unitKnown = ($null -ne $unitSize)
        $unitOk    = ($unitKnown -and ([int]$unitSize -eq $t.UnitSize))

        $status = 'FAIL'
        $note   = ''
        if ($fsOk -and $unitOk) { $status = 'PASS' }
        elseif ($fsOk -and -not $unitKnown) { $status = 'WARN'; $note = 'AllocationUnitSize недоступен (проверить fsutil fsinfo ntfsinfo)' }
        elseif ($fsOk -and $unitKnown) { $note = ('фактический кластер {0} Б' -f $unitSize) }

        Add-Result -Id $t.Id -Check ('ФС/кластер {0}' -f $t.Name) -Expected ('{0}, кластер {1} Б' -f $t.FileSystem, $t.UnitSize) -Actual ('{0}, кластер {1}' -f $vol.FileSystem, $(if ($unitKnown) { ('{0} Б' -f $unitSize) } else { 'н/д' })) -Status $status -Note $note
    }
}

# --- V6 ----------------------------------------------------------------------
function Test-NtfsOptions {
    [CmdletBinding()]
    param()

    $checks = @(
        @{ Id = 'V6.1'; Name = 'disablelastaccess'; Pattern = 'disablelastaccess'; Expected = '1' },
        @{ Id = 'V6.2'; Name = 'disable8dot3 (D:)'; Pattern = 'disable8dot3'; Expected = '1' }
    )

    foreach ($c in $checks) {
        try {
            $raw = (& fsutil.exe behavior query $c.Pattern) 2>&1 | Out-String
        }
        catch {
            Add-Result -Id $c.Id -Check ('NTFS: {0}' -f $c.Name) -Expected $c.Expected -Actual 'fsutil недоступен' -Status 'WARN' -Note $_.Exception.Message
            continue
        }

        $matched = $false
        $found   = $null
        foreach ($line in ($raw -split "`r?`n")) {
            if ($line -match [Regex]::Escape($c.Pattern)) {
                if ($c.Pattern -eq 'disable8dot3') {
                    if ($line -match 'D:\s*.*?=\s*(\d+)') { $found = $Matches[1]; $matched = $true }
                }
                else {
                    if ($line -match '=\s*(\d+)') { $found = $Matches[1]; $matched = $true }
                }
            }
        }

        if (-not $matched) {
            Add-Result -Id $c.Id -Check ('NTFS: {0}' -f $c.Name) -Expected $c.Expected -Actual 'не удалось разобрать вывод (локаль/формат)' -Status 'WARN' -Note 'проверить вручную: fsutil behavior query'
            continue
        }

        $status = 'FAIL'
        if ($found -eq $c.Expected) { $status = 'PASS' }
        Add-Result -Id $c.Id -Check ('NTFS: {0}' -f $c.Name) -Expected $c.Expected -Actual $found -Status $status
    }
}

# --- Отчёты ------------------------------------------------------------------
function Write-ConsoleReport {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '========== STAGE 1: ВЕРИФИКАЦИЯ РАЗМЕТКИ =========='
    foreach ($r in $script:Results) {
        $color = 'Gray'
        if ($r.Status -eq 'PASS') { $color = 'Green' }
        if ($r.Status -eq 'FAIL') { $color = 'Red' }
        if ($r.Status -eq 'WARN') { $color = 'Yellow' }
        Write-Host ('{0,-6} {1,-36} ожидание: {2,-30} факт: {3}' -f $r.Status, $r.Check, $r.Expected, $r.Actual) -ForegroundColor $color
        if ($r.Note) { Write-Host ('       └─ {0}' -f $r.Note) -ForegroundColor DarkGray }
    }

    $fail = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count
    $pass = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
    Write-Host '---------------------------------------------------'
    Write-Host ('PASS: {0}; FAIL: {1}; WARN: {2}' -f $pass, $fail, $warn)
    if ($fail -gt 0) { Write-Host 'ИТОГ: FAIL — схема не соответствует ADR-0007 (rev.2) / ADR-0011.' -ForegroundColor Red }
    else { Write-Host 'ИТОГ: PASS — схема соответствует ADR-0007 (rev.2) / ADR-0011.' -ForegroundColor Green }
}

function Export-MarkdownReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$DiskNumber
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $scriptName = 'Stage1_DiskGenius_Partition.ps1'
    if ($PSCommandPath) { $scriptName = Split-Path -Leaf $PSCommandPath }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Stage 1 — отчёт верификации разметки (сгенерировано скриптом)')
    $lines.Add('')
    $lines.Add('| Поле | Значение |')
    $lines.Add('|---|---|')
    $lines.Add(('| Дата (UTC) | {0} |' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')))
    $lines.Add(('| Скрипт | {0} |' -f $scriptName))
    $lines.Add(('| Диск | {0} |' -f $DiskNumber))
    $lines.Add(('| Хост | {0} |' -f $env:COMPUTERNAME))
    $lines.Add(('| Схема | ADR-0007 rev.2 / ADR-0011 (единицы MiB/GiB) |'))
    $lines.Add('')
    $lines.Add('| ID | Проверка | Ожидание | Факт | Статус | Примечание |')
    $lines.Add('|---|---|---|---|---|---|')
    foreach ($r in $script:Results) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $r.ID, $r.Check, $r.Expected, $r.Actual, $r.Status, $r.Note))
    }
    $lines.Add('')
    $lines.Add('> Сгенерировано `scripts/Stage1_DiskGenius_Partition.ps1` (read-only). Результат подлежит переносу в `docs/artifacts/Stage1_Report.md`.')

    # AR-101/AR-102: .md — UTF-8 БЕЗ BOM и LF. Set-Content в PS 5.1 добавил бы BOM и CRLF,
    # поэтому файл пишется напрямую через .NET с явной кодировкой.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $content   = ($lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

# --- Точка входа -------------------------------------------------------------
try {
    if (-not (Test-Elevated)) {
        Write-Host 'FAIL: требуются права администратора (чтение сведений о разделах).' -ForegroundColor Red
        exit $script:ExitPrecondition
    }

    $mod = Get-Module -ListAvailable -Name Storage
    if (-not $mod) {
        Write-Host 'FAIL: модуль Storage недоступен (запустите на установленной ОС или в WinPE с PowerShell).' -ForegroundColor Red
        exit $script:ExitPrecondition
    }

    Write-Host ('Stage 1 verification. Диск {0}; единицы MiB/GiB (ADR-0011).' -f $DiskNumber)

    $partitions = Test-DiskScheme -DiskNumber $DiskNumber
    Test-VolumeScheme -Partitions $partitions

    if ($SkipNtfsOptions) {
        Add-Result -Id 'V6' -Check 'NTFS-параметры (fsutil)' -Expected '1 / 1' -Actual 'пропущено по -SkipNtfsOptions' -Status 'SKIP'
    }
    else {
        Test-NtfsOptions
    }

    Add-Result -Id 'V7' -Check 'hiberfil.sys отсутствует (Stage 4)' -Expected 'n/a на Stage 1' -Actual 'проверяется на Stage 4' -Status 'SKIP' -Note 'PAT-14, вне области Stage 1'

    Write-ConsoleReport

    if ($ExportReport) {
        Export-MarkdownReport -Path $ExportReport -DiskNumber $DiskNumber
        Write-Host ('Отчёт выгружен: {0}' -f $ExportReport)
    }

    $failCount = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    if ($failCount -gt 0) { exit $script:ExitFail }
    exit $script:ExitOk
}
catch {
    Write-Host ('FATAL: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 99
}
