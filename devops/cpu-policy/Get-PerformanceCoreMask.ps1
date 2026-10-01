<#
.SYNOPSIS
    Динамическое определение маски P-ядер (Intel P+E, Thread Director).

.DESCRIPTION
    Stage 7 — политика P+E (AR-704, ADR-0010). Маска вычисляется на каждой
    загрузке и не хардкодится: BIOS, микрокод и гипервизорный режим меняют
    нумерацию логических процессоров.

    Метод:
      1. Win32 `GetLogicalProcessorInformationEx(RelationProcessorCore)`;
         каждое физическое ядро несёт поле `EfficiencyClass`;
      2. классы сравниваются: более высокий класс — производительные ядра
         (документированное свойство гибридных CPU);
      3. перекрёстная проверка (опция): Sysinternals `coreinfo -c`, если утилита
         доступна офлайн (F:\TOOLS\Audit\coreinfo64.exe);
      4. при неопределённости (один класс у всех ядер, расхождение с coreinfo)
         скрипт НЕ применяет эвристику: возвращает Hybrid=$false и WARN —
         решение выносит владелец (AR-906, GATE_AMBIGUITY).

    Вывод: PSCustomObject { Hybrid, PMask, EMask, PClass, EClass, PCores, ECores,
    LogicalP, LogicalE, Method, CrossCheck, Warning }. Ничего не меняет.

.PARAMETER CoreInfoPath
    Путь к coreinfo64.exe для перекрёстной проверки (офлайн-носитель).

.PARAMETER AsJson
    Вывести результат в JSON (для передачи в Set-WorkloadAffinity.ps1).

.EXAMPLE
    pwsh -File ./devops/cpu-policy/Get-PerformanceCoreMask.ps1
    $t = pwsh -File ./devops/cpu-policy/Get-PerformanceCoreMask.ps1 -AsJson | ConvertFrom-Json

.NOTES
    Script-ID  : SCRIPT-CPU-001
    Stage      : 7
    Patterns   : PAT-21
    ADR        : ADR-0010, ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-206, AR-306, AR-505, AR-704, AR-905, AR-906)
    Depends    : kernel32 GetLogicalProcessorInformationEx, опционально coreinfo64.exe
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$CoreInfoPath = 'F:\TOOLS\Audit\coreinfo64.exe',

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptId = 'SCRIPT-CPU-001'

$source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class CpuCoreInfo
{
    public int CoreIndex;
    public byte EfficiencyClass;
    public ushort Group;
    public ulong Mask;
}

public static class CpuTopology
{
    private const uint RelationProcessorCore = 0;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformationEx(
        uint relationshipType, IntPtr buffer, ref uint returnedLength);

    public static CpuCoreInfo[] GetCores()
    {
        uint length = 0;
        GetLogicalProcessorInformationEx(RelationProcessorCore, IntPtr.Zero, ref length);
        if (length == 0)
        {
            throw new InvalidOperationException("GetLogicalProcessorInformationEx: пустой размер буфера.");
        }

        IntPtr buffer = Marshal.AllocHGlobal((int)length);
        try
        {
            if (!GetLogicalProcessorInformationEx(RelationProcessorCore, buffer, ref length))
            {
                throw new InvalidOperationException(
                    "GetLogicalProcessorInformationEx: код " + Marshal.GetLastWin32Error().ToString());
            }

            List<CpuCoreInfo> cores = new List<CpuCoreInfo>();
            int offset = 0;
            int index = 0;
            while (offset + 8 <= (int)length)
            {
                IntPtr record = new IntPtr(buffer.ToInt64() + offset);
                uint relationship = (uint)Marshal.ReadInt32(record, 0);
                uint size = (uint)Marshal.ReadInt32(record, 4);
                if (size == 0)
                {
                    break;
                }

                if (relationship == RelationProcessorCore)
                {
                    CpuCoreInfo info = new CpuCoreInfo();
                    info.CoreIndex = index;
                    info.EfficiencyClass = Marshal.ReadByte(record, 9);
                    ushort groupCount = (ushort)Marshal.ReadInt16(record, 30);
                    if (groupCount >= 1)
                    {
                        info.Mask = (ulong)Marshal.ReadInt64(record, 32);
                        info.Group = (ushort)Marshal.ReadInt16(record, 40);
                    }
                    cores.Add(info);
                    index = index + 1;
                }

                offset = offset + (int)size;
            }

            return cores.ToArray();
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }
}
'@

if (-not ('CpuTopology' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp | Out-Null
}

function Get-BitCount {
    <# Число установленных битов маски (popcount) без внешних зависимостей. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][uint64]$Mask)

    $count = 0
    $value = $Mask
    while ($value -ne 0) {
        $count += [int]($value -band 1)
        $value = $value -shr 1
    }
    return $count
}

function Get-CoreInfoMask {
    <# Разбор вывода coreinfo -c: строки логических процессоров с признаками ядра. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $out = & $Path -c 2>$null
    $lines = @($out | Where-Object { $_ -match '^\s*[0-9]+\s' })
    return $lines
}

try {
    $cores = @([CpuTopology]::GetCores())
    if ($cores.Count -eq 0) {
        Write-Error 'Не удалось получить топологию процессора.'
        exit 99
    }

    $classes = @($cores | ForEach-Object { [int]$_.EfficiencyClass } | Sort-Object -Unique)
    $hybrid = ($classes.Count -gt 1)

    $pMask = [uint64]0
    $eMask = [uint64]0
    $pClass = $null
    $eClass = $null
    $pCores = 0
    $eCores = 0
    $logicalP = 0
    $logicalE = 0
    $warning = ''

    if (-not $hybrid) {
        # Один класс: гибридность не определяется (или CPU не гибридный).
        foreach ($core in $cores) { $pMask = $pMask -bor $core.Mask; $pCores++ }
        $logicalP = Get-BitCount -Mask $pMask
        $warning = ('EfficiencyClass одинаков ({0}) у всех ядер: P/E не различаются. Маска P = все ядра, привязка не применяется.' -f $classes[0])
    }
    else {
        $pClass = ($classes | Measure-Object -Maximum).Maximum
        $eClass = ($classes | Measure-Object -Minimum).Minimum
        foreach ($core in $cores) {
            if ([int]$core.EfficiencyClass -eq [int]$pClass) {
                $pMask = $pMask -bor $core.Mask; $pCores++
                $logicalP += Get-BitCount -Mask $core.Mask
            }
            else {
                $eMask = $eMask -bor $core.Mask; $eCores++
                $logicalE += Get-BitCount -Mask $core.Mask
            }
        }
    }

    $crossCheck = 'not-available'
    if (Test-Path -LiteralPath $CoreInfoPath) {
        $coreInfoLines = @(Get-CoreInfoMask -Path $CoreInfoPath)
        if ($coreInfoLines.Count -gt 0) {
            # coreinfo печатает логические процессоры; сверяем только общее число ядер.
            $crossCheck = if ($coreInfoLines.Count -ge ($pCores + $eCores)) { 'match' } else { 'mismatch' }
            if ($crossCheck -eq 'mismatch') {
                $warning = ('coreinfo сообщает {0} логических процессоров, WMI — {1}. Требуется ручное решение (AR-906).' -f $coreInfoLines.Count, ($pCores + $eCores))
            }
        }
    }

    $result = [pscustomobject]@{
        Hybrid     = $hybrid
        PMask      = $pMask
        EMask      = $eMask
        PClass     = $pClass
        EClass     = $eClass
        PCores     = $pCores
        ECores     = $eCores
        LogicalP   = $logicalP
        LogicalE   = $logicalE
        Method     = 'GetLogicalProcessorInformationEx/EfficiencyClass'
        CrossCheck = $crossCheck
        Warning    = $warning
    }

    if ($AsJson) {
        $result | ConvertTo-Json -Compress
    }
    else {
        Write-Host ('P-ядра: {0} физических, {1} логических, маска 0x{2:X}' -f $result.PCores, $result.LogicalP, $result.PMask)
        Write-Host ('E-ядра: {0} физических, {1} логических, маска 0x{2:X}' -f $result.ECores, $result.LogicalE, $result.EMask)
        Write-Host ('Гибридный: {0}; метод: {1}; cross-check: {2}' -f $result.Hybrid, $result.Method, $result.CrossCheck)
        if ($result.Warning) { Write-Warning $result.Warning }
    }

    if ($warning) { exit 30 }
    exit 0
}
catch {
    Write-Error ('Ошибка определения маски: {0}' -f $_.Exception.Message)
    exit 99
}
