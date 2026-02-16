[CmdletBinding()]
param(
    [string[]]$JobName = @(),
    [string]$ConfigJsonPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir ".." )).Path
}

function Get-ConfigData {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config-Datei nicht gefunden: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Config-Datei ist leer: $Path"
    }

    return $raw | ConvertFrom-Json
}

function Resolve-RclonePath {
    param([Parameter(Mandatory = $true)][object]$ConfigData)

    if ($null -ne $ConfigData.facts -and $null -ne $ConfigData.facts.rclone) {
        $fromConfig = [string]$ConfigData.facts.rclone.exe_path
        if (-not [string]::IsNullOrWhiteSpace($fromConfig) -and (Test-Path -LiteralPath $fromConfig)) {
            return $fromConfig
        }
    }

    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    throw "rclone.exe nicht gefunden."
}

function Select-MountJobs {
    param(
        [Parameter(Mandatory = $true)][object[]]$All,
        [string[]]$Names = @()
    )

    $enabled = @($All | Where-Object { $_.enabled -eq $true })
    if ($Names.Count -eq 0) {
        return $enabled
    }

    $selected = @($enabled | Where-Object { $Names -contains [string]$_.name })
    if ($selected.Count -eq 0) {
        throw "Keine aktiven Mount-Jobs fuer die Namen gefunden: $($Names -join ', ')"
    }

    return $selected
}

function Stop-ByProcessFallback {
    param(
        [Parameter(Mandatory = $true)][string]$DriveLetter
    )

    $escapedDrive = [regex]::Escape($DriveLetter)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='rclone.exe'" | Where-Object {
        $cmd = [string]$_.CommandLine
        $normalized = $cmd -replace '"', ' ' -replace "'", " "
        $normalized -match '(?i)\bmount\b' -and $normalized -match "(?i)(^|\s)$escapedDrive($|\s)"
    })

    if ($processes.Count -eq 0) {
        Write-Warning "Kein passender mount-Prozess fuer $DriveLetter gefunden."
        return $false
    }

    $stopped = $false
    foreach ($proc in $processes) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host "[STOP] Fallback-Prozess beendet: PID $($proc.ProcessId) fuer $DriveLetter"
            $stopped = $true
        }
        catch {
            Write-Warning "[STOP] Fallback konnte PID $($proc.ProcessId) nicht beenden: $($_.Exception.Message)"
        }
    }

    return $stopped
}

function Remove-LogonMountTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Host "[STOP] Kein Anmelde-Task gefunden: $TaskName"
        return $true
    }

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "[STOP] Anmelde-Task entfernt: $TaskName"
        return $true
    }
    catch {
        Write-Warning "[STOP] Konnte Anmelde-Task '$TaskName' nicht entfernen: $($_.Exception.Message)"
        return $false
    }
}

$repoRoot = Get-RepoRoot

if ([string]::IsNullOrWhiteSpace($ConfigJsonPath)) {
    $ConfigJsonPath = Join-Path $repoRoot ".Secrets\config.rclone.json"
}

$configData = Get-ConfigData -Path $ConfigJsonPath
$rcloneExe = Resolve-RclonePath -ConfigData $configData

if ($null -eq $configData.facts -or $null -eq $configData.facts.automation -or $null -eq $configData.facts.automation.mounts) {
    throw "Abschnitt facts.automation.mounts fehlt in $ConfigJsonPath"
}

$jobs = Select-MountJobs -All @($configData.facts.automation.mounts) -Names $JobName

$errors = New-Object System.Collections.Generic.List[string]

foreach ($job in $jobs) {
    $name = [string]$job.name
    $drive = [string]$job.drive_letter

    try {
        Write-Host "[STOP] Stop starte fuer Job '$name' auf $drive"
        $usedFallback = Stop-ByProcessFallback -DriveLetter $drive

        Start-Sleep -Milliseconds 500
        $stillPresent = $null -ne (Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue)

        if (-not $stillPresent) {
            if ($usedFallback) {
                Write-Host "[STOP] Mount ueber Prozess-Fallback gestoppt: $drive"
            }
            else {
                Write-Host "[STOP] Laufwerk bereits nicht gemountet: $drive"
            }
            continue
        }

        $msg = "[STOP] Laufwerk weiterhin vorhanden nach Stop-Versuch: $drive"
        Write-Warning $msg
        $errors.Add($msg)
    }
    catch {
        $msg = "[STOP] Fehler bei '$name' ($drive): $($_.Exception.Message)"
        Write-Warning $msg
        $errors.Add($msg)
    }
}

$autoMountTaskName = "RcloneMountsAtLogon"
$taskRemoved = Remove-LogonMountTask -TaskName $autoMountTaskName
if (-not $taskRemoved) {
    $errors.Add("[STOP] Geplanter Task konnte nicht entfernt werden: $autoMountTaskName")
}

if ($errors.Count -gt 0) {
    exit 1
}

exit 0
