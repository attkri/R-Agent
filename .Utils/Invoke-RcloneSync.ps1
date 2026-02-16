[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("gdrive", "pcdrive")]
    [string]$RemoteName,

    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

    [string]$RemoteSubPath = "",

    [ValidateSet("upload", "download")]
    [string]$Direction = "upload",

    [ValidateSet("sync", "copy")]
    [string]$Mode = "sync",

    [int]$Transfers = 4,

    [int]$Checkers = 8,

    [string]$BwLimit = "",

    [switch]$LiveRun,

    [string]$ConfigJsonPath = "",

    [string]$LogRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir ".." )).Path
}

function Get-ConfigData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Resolve-RclonePath {
    param(
        [Parameter(Mandatory = $false)]
        [object]$ConfigData
    )

    if ($null -ne $ConfigData -and $null -ne $ConfigData.facts -and $null -ne $ConfigData.facts.rclone) {
        $fromConfig = [string]$ConfigData.facts.rclone.exe_path
        if (-not [string]::IsNullOrWhiteSpace($fromConfig) -and (Test-Path -LiteralPath $fromConfig)) {
            return $fromConfig
        }
    }

    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    throw "rclone.exe wurde nicht gefunden. Lege rclone in den PATH oder hinterlege den Pfad in .Secrets/config.rclone.json unter facts.rclone.exe_path."
}

function Resolve-RcloneConfigPath {
    param(
        [Parameter(Mandatory = $false)]
        [object]$ConfigData
    )

    if ($null -ne $ConfigData -and $null -ne $ConfigData.facts -and $null -ne $ConfigData.facts.rclone) {
        $fromConfig = [string]$ConfigData.facts.rclone.config_path
        if (-not [string]::IsNullOrWhiteSpace($fromConfig) -and (Test-Path -LiteralPath $fromConfig)) {
            return $fromConfig
        }
    }

    $defaultPath = Join-Path $env:APPDATA "rclone\rclone.conf"
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    throw "rclone.conf wurde nicht gefunden. Prüfe die Anmeldung und den Config-Pfad."
}

function Assert-UnencryptedPolicy {
    param(
        [Parameter(Mandatory = $false)]
        [object]$ConfigData
    )

    if ($null -eq $ConfigData -or $null -eq $ConfigData.facts -or $null -eq $ConfigData.facts.project_policy) {
        return
    }

    $mode = [string]$ConfigData.facts.project_policy.cloud_storage_mode
    if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode -ne "unencrypted") {
        Write-Warning "Project policy cloud_storage_mode='$mode'. Dieses Skript ist fuer unverschluesselte Sync-Workflows ausgelegt."
    }
}

function Build-RemoteTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$SubPath
    )

    $clean = $SubPath.Trim().TrimStart("/").TrimStart("\")
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return "${Name}:"
    }

    $normalized = $clean -replace "\\", "/"
    return "${Name}:$normalized"
}

$repoRoot = Get-RepoRoot

if ([string]::IsNullOrWhiteSpace($ConfigJsonPath)) {
    $ConfigJsonPath = Join-Path $repoRoot ".Secrets\config.rclone.json"
}

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $repoRoot ".logs"
}

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

$configData = Get-ConfigData -Path $ConfigJsonPath
Assert-UnencryptedPolicy -ConfigData $configData

$rcloneExe = Resolve-RclonePath -ConfigData $configData
$rcloneConfigPath = Resolve-RcloneConfigPath -ConfigData $configData

$localResolved = [System.IO.Path]::GetFullPath($LocalPath)
if ($Direction -eq "upload" -and -not (Test-Path -LiteralPath $localResolved)) {
    throw "Lokaler Quellpfad existiert nicht: $localResolved"
}

if (-not (Test-Path -LiteralPath $localResolved)) {
    New-Item -ItemType Directory -Path $localResolved -Force | Out-Null
}

$remoteTarget = Build-RemoteTarget -Name $RemoteName -SubPath $RemoteSubPath

if ($Direction -eq "upload") {
    $source = $localResolved
    $destination = $remoteTarget
}
else {
    $source = $remoteTarget
    $destination = $localResolved
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logId = [regex]::Replace("$RemoteName-$Direction-$Mode", "[^A-Za-z0-9_-]", "_")
$rcloneLogPath = Join-Path $LogRoot ("{0}_{1}.log" -f $timestamp, $logId)

$exitCode = 1

try {
    Write-Host "rclone.exe: $rcloneExe"
    Write-Host "rclone.conf: $rcloneConfigPath"
    Write-Host "Mode: $Mode"
    Write-Host "Direction: $Direction"
    Write-Host "Source: $source"
    Write-Host "Destination: $destination"
    Write-Host "Transfers: $Transfers | Checkers: $Checkers"
    Write-Host "DryRun: $(([string](-not $LiveRun)).ToLowerInvariant())"
    Write-Host "RcloneLog: $rcloneLogPath"

    $args = @(
        $Mode,
        $source,
        $destination,
        "--config", $rcloneConfigPath,
        "--transfers", "$Transfers",
        "--checkers", "$Checkers",
        "--fast-list",
        "--create-empty-src-dirs",
        "--retries", "3",
        "--retries-sleep", "10s",
        "--timeout", "1m",
        "--contimeout", "15s",
        "--stats", "30s",
        "--stats-one-line-date",
        "--log-level", "INFO",
        "--log-file", $rcloneLogPath
    )

    if (-not [string]::IsNullOrWhiteSpace($BwLimit)) {
        $args += @("--bwlimit", $BwLimit)
    }

    if (-not $LiveRun) {
        $args += "--dry-run"
    }

    Write-Host "Command: $rcloneExe $($args -join ' ')"

    & $rcloneExe @args
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "rclone schlug fehl mit ExitCode $exitCode"
    }

    Write-Host "Sync erfolgreich abgeschlossen."
}
catch {
    Write-Error $_
    $exitCode = if ($exitCode -eq 0) { 1 } else { $exitCode }
}

exit $exitCode
