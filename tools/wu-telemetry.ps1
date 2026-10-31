<#
.SYNOPSIS
    Log GPU + CPU telemetry while you play, so stutter can be diagnosed with
    data instead of guesswork.

.DESCRIPTION
    Writes a CSV every N seconds containing:

        ts, gpu_temp_c, gpu_clock_mhz, gpu_power_w, gpu_util_pct,
        cpu_total_pct, cpu_max_core_pct, game_cpu_pct, game_running

    Feed the result to analyze-telemetry.py for a verdict.

    Samples are taken while the game runs, but the script logs continuously -
    rows with game_running=0 are ignored by the analyzer.

.PARAMETER Minutes
    How long to log. Default 20. Ctrl+C also works.

.PARAMETER IntervalSeconds
    Sampling interval. Default 2. Lower values cost a little CPU themselves.

.PARAMETER OutFile
    Output CSV path. Defaults to wu-telemetry.csv next to this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wu-telemetry.ps1 -Minutes 10

.NOTES
    Needs nvidia-smi (ships with the NVIDIA driver) and the process name
    Client-Win64-Shipping for per-game CPU accounting.
#>
[CmdletBinding()]
param(
    [int]$Minutes = 20,
    [int]$IntervalSeconds = 2,
    [string]$OutFile
)

$ErrorActionPreference = 'Continue'

$smi = 'C:\Windows\System32\nvidia-smi.exe'
if (-not (Test-Path $smi)) {
    $smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
}
if (-not $smi) {
    Write-Host 'nvidia-smi not found. This script needs an NVIDIA GPU + driver.' -ForegroundColor Red
    exit 1
}

if (-not $OutFile) {
    $OutFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'wu-telemetry.csv'
    if (-not (Test-Path (Split-Path -Parent $PSScriptRoot))) {
        $OutFile = Join-Path $env:TEMP 'wu-telemetry.csv'
    }
}

'ts,gpu_temp_c,gpu_clock_mhz,gpu_power_w,gpu_util_pct,cpu_total_pct,cpu_max_core_pct,game_cpu_pct,game_running' |
    Out-File $OutFile -Encoding utf8

Write-Host ''
Write-Host 'Wuthering Waves - telemetry logger' -ForegroundColor Cyan
Write-Host ('=' * 50)
Write-Host "writing : $OutFile" -ForegroundColor DarkGray
Write-Host "duration: $Minutes minutes, every $IntervalSeconds s" -ForegroundColor DarkGray
Write-Host 'Launch the game and go play. Ctrl+C to stop early.' -ForegroundColor Yellow
Write-Host ''

$deadline = (Get-Date).AddMinutes($Minutes)
$n = 0
$start = Get-Date

while ((Get-Date) -lt $deadline) {

    $gpu = (& $smi --query-gpu=temperature.gpu,clocks.current.graphics,power.draw,utilization.gpu `
                   --format=csv,noheader,nounits 2>$null) -join ','
    $gpu = ($gpu -replace '\s', '')
    if (-not $gpu) { $gpu = ',,,' }

    $cpuTotal = (Get-Counter '\Processor Information(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
    if (-not $cpuTotal) { $cpuTotal = 0 }

    $maxCore = (Get-Counter '\Processor Information(*)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples |
               Where-Object { $_.InstanceName -ne '_total' } |
               Measure-Object -Property CookedValue -Maximum
    $coreVal = if ($maxCore) { $maxCore.Maximum } else { 0 }

    $proc = Get-Process -Name 'Client-Win64-Shipping' -ErrorAction SilentlyContinue
    $gameCpu = 0
    $running = 0
    if ($proc) {
        $running = 1
        $g = (Get-Counter '\Process(Client-Win64-Shipping)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        if ($g) { $gameCpu = [math]::Round($g / [Environment]::ProcessorCount, 1) }
    }

    $line = (Get-Date -Format 'HH:mm:ss') + ',' + $gpu + ',' +
            [math]::Round($cpuTotal, 1) + ',' + [math]::Round($coreVal, 1) + ',' +
            $gameCpu + ',' + $running
    $line | Out-File $OutFile -Append -Encoding utf8
    $n++

    if ($n % 15 -eq 0) {
        $elapsed = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
        $state = if ($running) { 'IN GAME' } else { 'idle' }
        Write-Host ("  {0}  samples={1}  elapsed={2}m  [{3}]  gpu={4}" -f `
            (Get-Date -Format 'HH:mm:ss'), $n, $elapsed, $state, $gpu) -ForegroundColor DarkGray
    }

    Start-Sleep -Seconds $IntervalSeconds
}

Write-Host ''
Write-Host "Done. $n samples written to $OutFile" -ForegroundColor Green
Write-Host "Analyse with:  python .\tools\analyze-telemetry.py `"$OutFile`"" -ForegroundColor Cyan
