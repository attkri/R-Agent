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

$jobId = "m1"
$jobName = "pcdrive-p"
$remote = "pcdrive:"
$drive = "P:"
$jobOptions = @{
    "vfs-cache-mode" = "full"
    "verbose" = $true
    "links" = $true
}

$script:lastStatusWriteAt = $null
function Write-WorkerStatus {
    param([string]$Level,[string]$Message)
    if ($null -ne $script:lastStatusWriteAt) {
        $elapsed = ((Get-Date) - $script:lastStatusWriteAt).TotalSeconds
        if ($elapsed -lt $StatusMinIntervalSeconds) {
            Start-Sleep -Seconds ([Math]::Ceiling($StatusMinIntervalSeconds - $elapsed))
        }
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

Write-WorkerStatus -Level "INFO" -Message "Jobstart: Mount wird vorbereitet."

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $LogRoot = Join-Path $repoRoot ".logs"
}
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$logCutoff = (Get-Date).Date.AddDays(-10)
Get-ChildItem -LiteralPath $LogRoot -File -Filter "*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $logCutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $ConfigJsonPath)) {
    Write-WorkerStatus -Level "ERROR" -Message "Config-Datei fehlt."
    throw "Config file not found: $ConfigJsonPath"
}

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

$mountJob = @($cfg.facts.automation.mounts) | Where-Object { [string]$_.id -eq $jobId } | Select-Object -First 1
if ($null -eq $mountJob) {
    Write-WorkerStatus -Level "ERROR" -Message "Mount-Job-Konfiguration fehlt in JSON."
    throw "Mount job '$jobId' not found in config JSON."
}

$enabled = $true
 $enabledValue = Get-ConfigPropertyValue -Object $mountJob -Name "enabled"
if ($null -ne $enabledValue) { $enabled = [bool]$enabledValue }
if (-not $enabled) {
    Write-WorkerStatus -Level "INFO" -Message "Job ist deaktiviert (enabled=false)."
    exit 0
}

$jobNameValue = [string](Get-ConfigPropertyValue -Object $mountJob -Name "name")
if (-not [string]::IsNullOrWhiteSpace($jobNameValue)) { $jobName = $jobNameValue }

$remoteFromConfig = [string](Get-ConfigPropertyValue -Object $mountJob -Name "remote")
if (-not [string]::IsNullOrWhiteSpace($remoteFromConfig)) {
    if ($remoteFromConfig -notmatch ":") {
        $remoteFromConfig = "$remoteFromConfig:"
    }
    $remote = $remoteFromConfig
}

$driveFromConfig = [string](Get-ConfigPropertyValue -Object $mountJob -Name "drive_letter")
if (-not [string]::IsNullOrWhiteSpace($driveFromConfig)) {
    if ($driveFromConfig -notmatch ":$") {
        $driveFromConfig = "$driveFromConfig:"
    }
    $drive = $driveFromConfig
}

$configuredOptions = ConvertTo-FlatHashtable -InputObject (Get-ConfigPropertyValue -Object $mountJob -Name "options")
if ($configuredOptions.Count -gt 0) {
    $jobOptions = $configuredOptions
}

$svc = Get-Service -Name "WinFsp.Launcher" -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-WorkerStatus -Level "ERROR" -Message "WinFsp fehlt."
    throw "WinFsp launcher service not found."
}

$driveName = $drive.TrimEnd(':')
if ($null -ne (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue)) {
    Write-WorkerStatus -Level "INFO" -Message "Laufwerk bereits gemountet."
    exit 0
}

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogRoot ("{0}_{1}.log" -f $runStamp, $jobId)

$args = New-Object System.Collections.Generic.List[string]
$args.Add("mount")
$args.Add($remote)
$args.Add($drive)
foreach ($prop in $jobOptions.GetEnumerator()) {
    $key = [string]$prop.Key
    $value = $prop.Value
    if ($key -eq "verbose") {
        if ($value -eq $true) { $args.Add("-v") }
        continue
    }
    $flag = "--$key"
    if ($value -is [bool]) {
        if ($value) { $args.Add($flag) }
    }
    elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        $args.Add($flag)
        $args.Add([string]$value)
    }
}
$args.Add("--config")
$args.Add($rcloneConf)
$args.Add("--log-file")
$args.Add($logFile)

if (-not $LiveRun) {
    $args.Add("--dry-run")
    Write-WorkerStatus -Level "DEBUG" -Message "Dry-Run gestartet."
    & $rcloneExe @args
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { Write-WorkerStatus -Level "INFO" -Message "Dry-Run abgeschlossen." }
    else { Write-WorkerStatus -Level "ERROR" -Message "Dry-Run fehlgeschlagen (ExitCode $exitCode)." }
    exit $exitCode
}

try {
    Write-WorkerStatus -Level "INFO" -Message "Mount-Prozess wird gestartet."
    $proc = Start-Process -FilePath $rcloneExe -ArgumentList $args -PassThru -WindowStyle Hidden
}
catch {
    Write-WorkerStatus -Level "ERROR" -Message "Start des Mount-Prozesses fehlgeschlagen."
    throw
}

function Wait-MountReady {
    param(
        [Parameter(Mandatory = $true)][string]$DriveName,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int]$TimeoutSeconds = 20
    )

    $until = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $until) {
        $running = $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
        if (-not $running) {
            return $false
        }

        $driveObj = Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue
        if ($null -ne $driveObj) {
            $rootPath = "${DriveName}:\"
            try {
                $null = Get-ChildItem -LiteralPath $rootPath -ErrorAction Stop | Select-Object -First 1
                return $true
            }
            catch {
            }
        }

        Start-Sleep -Milliseconds 500
    }

    return $false
}

$ready = Wait-MountReady -DriveName $driveName -ProcessId $proc.Id -TimeoutSeconds 20
if (-not $ready) {
    Write-WorkerStatus -Level "ERROR" -Message "Mount fehlgeschlagen."
    throw "Mount failed for $drive (PID $($proc.Id)). Check log: $logFile"
}

Write-WorkerStatus -Level "INFO" -Message "Mount erfolgreich gestartet."
exit 0
