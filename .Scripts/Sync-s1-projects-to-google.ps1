[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$JobGuid,
    [switch]$LiveRun,
    [string]$ConfigJsonPath = "C:\Users\attila\.Secrets\RClone.Secrets.json",
    [string]$LogRoot = "",
    [int]$StatusMinIntervalSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$jobId = "s1"
$jobName = "Projects -> Google"
$mode = "sync"
$source = "C:\Users\attila\Projects"
$destination = "gdrive:Attila/OpenCode/Projects"
$jobOptions = @{ "transfers" = 8; "checkers" = 32; "drive-chunk-size" = "64M"; "skip-links" = $true }
$excludes = @("R-Agent/.logs/**")

$script:lastStatusWriteAt = $null
function Write-WorkerStatus {
    param([string]$Level,[string]$Message)
    if ($null -ne $script:lastStatusWriteAt) {
        $elapsed = ((Get-Date) - $script:lastStatusWriteAt).TotalSeconds
        if ($elapsed -lt $StatusMinIntervalSeconds) { Start-Sleep -Seconds ([Math]::Ceiling($StatusMinIntervalSeconds - $elapsed)) }
    }
    $statusPath = Join-Path (Get-Location).Path ("{0}.Status.jsonc" -f $JobGuid)
    ([ordered]@{
        "From.ID" = $JobGuid
        "From.Name" = $jobName
        "Status.Level" = $Level
        "Status.Message" = $Message
        "Status.Timestamp" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 4) | Out-File -FilePath $statusPath -Encoding UTF8 -Force
    $script:lastStatusWriteAt = Get-Date
}

function Get-SyncMetricsFromLog {
    param([Parameter(Mandatory = $true)][string]$LogFile)

    $metrics = [ordered]@{
        Transferred = $null
        Checked = $null
        Deleted = $null
        Affected = $null
    }

    if (-not (Test-Path -LiteralPath $LogFile)) {
        return [pscustomobject]$metrics
    }

    $content = Get-Content -LiteralPath $LogFile -Raw

    $mTransferred = [regex]::Match($content, "Transferred:\s*([0-9,]+)\s*/")
    if ($mTransferred.Success) {
        $metrics.Transferred = [int](($mTransferred.Groups[1].Value) -replace ",", "")
    }

    $mChecked = [regex]::Match($content, "Checks:\s*([0-9,]+)\s*/")
    if ($mChecked.Success) {
        $metrics.Checked = [int](($mChecked.Groups[1].Value) -replace ",", "")
    }

    $mDeleted = [regex]::Match($content, "Deleted:\s*([0-9,]+)")
    if ($mDeleted.Success) {
        $metrics.Deleted = [int](($mDeleted.Groups[1].Value) -replace ",", "")
    }

    if ($null -ne $metrics.Transferred -or $null -ne $metrics.Deleted) {
        $metrics.Affected = [int](($metrics.Transferred ?? 0) + ($metrics.Deleted ?? 0))
    }

    return [pscustomobject]$metrics
}

function ConvertTo-FlatHashtable {
    param($InputObject)

    $result = @{}
    if ($null -eq $InputObject) {
        return $result
    }

    foreach ($prop in $InputObject.PSObject.Properties) {
        $result[[string]$prop.Name] = $prop.Value
    }

    return $result
}

function Get-ConfigPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-LastRcloneErrorFromLog {
    param([Parameter(Mandatory = $true)][string]$LogFile)

    if (-not (Test-Path -LiteralPath $LogFile)) {
        return $null
    }

    $match = Select-String -LiteralPath $LogFile -Pattern "CRITICAL|ERROR\s*:|NOTICE:\s+Failed to bisync|Bisync aborted" -SimpleMatch:$false | Select-Object -Last 1
    if ($null -eq $match) {
        return $null
    }

    return (($match.Line -replace "^[0-9]{4}/[0-9]{2}/[0-9]{2}\s+[0-9:]{8}\s+", "").Trim())
}

Write-WorkerStatus -Level "INFO" -Message "Jobstart: Sync wird vorbereitet."

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $LogRoot = Join-Path $repoRoot ".logs"
}
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$logCutoff = (Get-Date).Date.AddDays(-10)
Get-ChildItem -LiteralPath $LogRoot -File -Filter "*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $logCutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $ConfigJsonPath)) { Write-WorkerStatus -Level "ERROR" -Message "Config-Datei fehlt."; throw "Config file not found: $ConfigJsonPath" }
$cfg = Get-Content -LiteralPath $ConfigJsonPath -Raw | ConvertFrom-Json
$rcloneExe = [string]$cfg.facts.rclone.exe_path
if ([string]::IsNullOrWhiteSpace($rcloneExe) -or -not (Test-Path -LiteralPath $rcloneExe)) {
    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw "rclone.exe not found." }
    $rcloneExe = $cmd.Source
}
$rcloneConf = [string]$cfg.facts.rclone.config_path
if ([string]::IsNullOrWhiteSpace($rcloneConf) -or -not (Test-Path -LiteralPath $rcloneConf)) {
    $defaultConf = Join-Path $env:APPDATA "rclone\rclone.conf"
    if (-not (Test-Path -LiteralPath $defaultConf)) { throw "rclone.conf not found." }
    $rcloneConf = $defaultConf
}

$syncJob = @($cfg.facts.automation.syncs) | Where-Object { [string]$_.id -eq $jobId } | Select-Object -First 1
if ($null -eq $syncJob) {
    Write-WorkerStatus -Level "ERROR" -Message "Sync-Job-Konfiguration fehlt in JSON."
    throw "Sync job '$jobId' not found in config JSON."
}

$enabled = $true
 $enabledValue = Get-ConfigPropertyValue -Object $syncJob -Name "enabled"
if ($null -ne $enabledValue) {
    $enabled = [bool]$enabledValue
}
if (-not $enabled) {
    Write-WorkerStatus -Level "INFO" -Message "Job ist deaktiviert (enabled=false)."
    exit 0
}

$jobNameValue = [string](Get-ConfigPropertyValue -Object $syncJob -Name "name")
$modeValue = [string](Get-ConfigPropertyValue -Object $syncJob -Name "mode")
$sourceValue = [string](Get-ConfigPropertyValue -Object $syncJob -Name "source")
$destinationValue = [string](Get-ConfigPropertyValue -Object $syncJob -Name "destination")

if (-not [string]::IsNullOrWhiteSpace($jobNameValue)) { $jobName = $jobNameValue }
if (-not [string]::IsNullOrWhiteSpace($modeValue)) { $mode = $modeValue }
if (-not [string]::IsNullOrWhiteSpace($sourceValue)) { $source = $sourceValue }
if (-not [string]::IsNullOrWhiteSpace($destinationValue)) { $destination = $destinationValue }

$configuredOptions = ConvertTo-FlatHashtable -InputObject (Get-ConfigPropertyValue -Object $syncJob -Name "options")
if ($configuredOptions.Count -gt 0) {
    $jobOptions = $configuredOptions
}

$excludesValue = Get-ConfigPropertyValue -Object $syncJob -Name "excludes"
if ($null -ne $excludesValue) {
    $excludes = @($excludesValue | ForEach-Object { [string]$_ })
}

if (-not (Test-Path -LiteralPath $source)) { Write-WorkerStatus -Level "ERROR" -Message "Quellpfad fehlt."; throw "Source path not found: $source" }

Write-WorkerStatus -Level "DEBUG" -Message "Konfiguration aktiv: '$source' -> '$destination' (Mode: $mode)."

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogRoot ("{0}_{1}.log" -f $runStamp, $jobId)

$args = New-Object System.Collections.Generic.List[string]
$args.Add($mode); $args.Add($source); $args.Add($destination)
foreach ($prop in $jobOptions.GetEnumerator()) {
    $flag = "--$($prop.Key)"; $value = $prop.Value
    if ($value -is [bool]) { if ($value) { $args.Add($flag) } }
    elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { $args.Add($flag); $args.Add([string]$value) }
}
foreach ($pattern in $excludes) { $args.Add("--exclude"); $args.Add($pattern) }
$args.Add("--config"); $args.Add($rcloneConf)
$args.Add("--retries"); $args.Add("3")
$args.Add("--retries-sleep"); $args.Add("10s")
$args.Add("--timeout"); $args.Add("1m")
$args.Add("--contimeout"); $args.Add("15s")
$args.Add("--stats"); $args.Add("30s")
$args.Add("--stats-one-line-date")
$args.Add("--log-level"); $args.Add("INFO")
$args.Add("--log-file"); $args.Add($logFile)
if (-not $LiveRun) { $args.Add("--dry-run"); Write-WorkerStatus -Level "DEBUG" -Message "Dry-Run gestartet." }

Write-WorkerStatus -Level "INFO" -Message "rclone wird ausgeführt."
& $rcloneExe @args
$exitCode = $LASTEXITCODE
$metrics = Get-SyncMetricsFromLog -LogFile $logFile
$errorDetail = Get-LastRcloneErrorFromLog -LogFile $logFile

if ($exitCode -eq 0) {
    $statusMessage = "Sync erfolgreich abgeschlossen."
    if ($null -ne $metrics.Affected) {
        $statusMessage = "Sync erfolgreich: betroffene Dateien $($metrics.Affected), übertragen $($metrics.Transferred ?? 0), gelöscht $($metrics.Deleted ?? 0), geprüft $($metrics.Checked ?? 0)."
    }
    Write-WorkerStatus -Level "INFO" -Message $statusMessage
}
else {
    $statusMessage = "Sync fehlgeschlagen (ExitCode $exitCode)."
    if ($null -ne $metrics.Affected) {
        $statusMessage = "Sync fehlgeschlagen (ExitCode $exitCode). Letzte Metrik: betroffen $($metrics.Affected), übertragen $($metrics.Transferred ?? 0), gelöscht $($metrics.Deleted ?? 0), geprüft $($metrics.Checked ?? 0)."
    }
    if (-not [string]::IsNullOrWhiteSpace($errorDetail)) {
        if ($errorDetail -match "Must run --resync to recover") {
            $statusMessage = "$statusMessage Bisync benötigt einmalig --resync."
        }
        else {
            $statusMessage = "$statusMessage Detail: $errorDetail"
        }
    }
    Write-WorkerStatus -Level "ERROR" -Message $statusMessage
}
exit $exitCode
