[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("sync", "mount")]
    [string]$Kind,

    [string[]]$JobName = @(),

    [switch]$LiveRun,

    [switch]$ContinueOnError,

    [ValidateRange(1, 10)]
    [int]$MaxParallel = 10,

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

function Resolve-RcloneConfigPath {
    param([Parameter(Mandatory = $true)][object]$ConfigData)

    if ($null -ne $ConfigData.facts -and $null -ne $ConfigData.facts.rclone) {
        $fromConfig = [string]$ConfigData.facts.rclone.config_path
        if (-not [string]::IsNullOrWhiteSpace($fromConfig) -and (Test-Path -LiteralPath $fromConfig)) {
            return $fromConfig
        }
    }

    $defaultPath = Join-Path $env:APPDATA "rclone\rclone.conf"
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    throw "rclone.conf nicht gefunden."
}

function Assert-WinFspForMount {
    $svc = Get-Service -Name "WinFsp.Launcher" -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        throw "WinFsp ist nicht installiert oder der Dienst 'WinFsp.Launcher' fehlt. Mounts benoetigen WinFsp."
    }
}

function Resolve-ExcludeFromPath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return $Value
    }

    return (Join-Path $RepoRoot $Value)
}

function Build-Options {
    param(
        [Parameter(Mandatory = $false)][object]$Options,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    $result = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Options) {
        return $result
    }

    if ($Options -is [System.Array]) {
        $optionArray = @($Options)
        for ($i = 0; $i -lt $optionArray.Count; $i++) {
            $current = [string]$optionArray[$i]

            if ($current -eq "--exclude-from") {
                if ($i + 1 -ge $optionArray.Count) {
                    throw "Option '--exclude-from' ohne Wert in Konfiguration."
                }

                $next = [string]$optionArray[$i + 1]
                $resolved = Resolve-ExcludeFromPath -Value $next -RepoRoot $RepoRoot
                if (-not (Test-Path -LiteralPath $resolved)) {
                    throw "Exclude-Datei nicht gefunden: $resolved"
                }

                $result.Add($current)
                $result.Add($resolved)
                $i++
                continue
            }

            if ($current -eq "--progress") {
                continue
            }

            $result.Add($current)
        }
    }
    elseif ($Options -is [pscustomobject] -or $Options -is [System.Collections.IDictionary]) {
        foreach ($prop in $Options.PSObject.Properties) {
            $key = [string]$prop.Name
            $value = $prop.Value

            if ($key -eq "verbose") {
                if ($value -is [bool] -and $value) {
                    $result.Add("-v")
                }
                continue
            }

            if ($key -eq "progress") {
                continue
            }

            $flag = "--$key"

            if ($value -is [bool]) {
                if ($value) {
                    $result.Add($flag)
                }
                continue
            }

            if ($null -eq $value) {
                continue
            }

            $stringValue = [string]$value
            if ([string]::IsNullOrWhiteSpace($stringValue)) {
                continue
            }

            if ($key -eq "exclude-from") {
                $stringValue = Resolve-ExcludeFromPath -Value $stringValue -RepoRoot $RepoRoot
                if (-not (Test-Path -LiteralPath $stringValue)) {
                    throw "Exclude-Datei nicht gefunden: $stringValue"
                }
            }

            $result.Add($flag)
            $result.Add($stringValue)
        }
    }
    else {
        throw "Optionstyp wird nicht unterstuetzt fuer Job-Konfiguration."
    }

    return $result
}

function Select-Jobs {
    param(
        [Parameter(Mandatory = $true)][object[]]$All,
        [string[]]$Names = @()
    )

    $enabled = @($All | Where-Object { $_.enabled -eq $true })
    if ($Names.Count -eq 0) {
        return $enabled
    }

    $selected = @($enabled | Where-Object {
        $name = [string]$_.name
        $id = ""
        if ($null -ne $_.PSObject.Properties["id"]) {
            $id = [string]$_.id
        }

        ($Names -contains $name) -or (-not [string]::IsNullOrWhiteSpace($id) -and ($Names -contains $id))
    })

    if ($selected.Count -eq 0) {
        throw "Keine aktiven Jobs fuer die Namen/IDs gefunden: $($Names -join ', ')"
    }

    return $selected
}

function Get-JobId {
    param([Parameter(Mandatory = $true)][object]$Job)

    if ($null -ne $Job.PSObject.Properties["id"]) {
        $id = [string]$Job.id
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            return $id
        }
    }

    return [string]$Job.name
}

function Get-JobPriority {
    param([Parameter(Mandatory = $true)][object]$Job)

    if ($null -ne $Job.PSObject.Properties["priority"]) {
        $parsed = 0
        if ([int]::TryParse([string]$Job.priority, [ref]$parsed)) {
            return $parsed
        }
    }

    return 9999
}

function Test-HasVerboseFlag {
    param([Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Args)

    return ($Args -contains "-v" -or $Args -contains "-vv" -or $Args -contains "-vvv")
}

function Convert-ToMountPointPath {
    param([Parameter(Mandatory = $true)][string]$Drive)

    $trimmed = $Drive.Trim()
    if ($trimmed -match "^[A-Za-z]:$") {
        return ("{0}\" -f $trimmed)
    }

    return $trimmed
}

function Test-MountPointInUse {
    param([Parameter(Mandatory = $true)][string]$Drive)

    $mountPoint = Convert-ToMountPointPath -Drive $Drive
    if ([string]::IsNullOrWhiteSpace($mountPoint)) {
        return $false
    }

    return (Test-Path -LiteralPath $mountPoint)
}

function New-SyncSpec {
    param(
        [Parameter(Mandatory = $true)][object]$Job,
        [Parameter(Mandatory = $true)][string]$RunStamp,
        [Parameter(Mandatory = $true)][string]$LogRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RcloneConf,
        [Parameter(Mandatory = $true)][bool]$LiveRun
    )

    $jobName = [string]$Job.name
    $jobId = Get-JobId -Job $Job
    $priority = Get-JobPriority -Job $Job
    $safeJobId = [regex]::Replace($jobId, "[^A-Za-z0-9_-]", "_")
    $jobLog = Join-Path $LogRoot ("{0}_{1}.log" -f $RunStamp, $safeJobId)
    $options = Build-Options -Options $Job.options -RepoRoot $RepoRoot -Kind "sync"

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add("sync")
    $args.Add([string]$Job.source)
    $args.Add([string]$Job.destination)
    foreach ($opt in $options) { $args.Add($opt) }

    if (-not ($args -contains "--stats")) {
        $args.Add("--stats")
        $args.Add("30s")
    }

    if (-not ($args -contains "--stats-one-line-date")) {
        $args.Add("--stats-one-line-date")
    }

    if (-not ($args -contains "--log-level") -and -not (Test-HasVerboseFlag -Args $args)) {
        $args.Add("--log-level")
        $args.Add("INFO")
    }

    $args.Add("--config")
    $args.Add($RcloneConf)
    $args.Add("--log-file")
    $args.Add($jobLog)

    if (-not $LiveRun) {
        $args.Add("--dry-run")
    }

    return [pscustomobject]@{
        Name = $jobName
        Id = $jobId
        Priority = $priority
        LogPath = $jobLog
        Args = @($args)
    }
}

function Format-Duration {
    param([Parameter(Mandatory = $true)][timespan]$Span)

    if ($Span.TotalHours -ge 1) {
        return ("{0:hh\:mm\:ss}" -f $Span)
    }

    if ($Span.TotalMinutes -ge 1) {
        return ("{0:mm\:ss}" -f $Span)
    }

    return ("{0:N1}s" -f $Span.TotalSeconds)
}

function Get-SyncReportFromLog {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    $report = [ordered]@{
        Transferred = "n/a"
        Checks = "n/a"
        Elapsed = "n/a"
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return [pscustomobject]$report
    }

    $matches = @(Select-String -LiteralPath $LogPath -Pattern "Transferred:", "Checks:", "Elapsed time:" -SimpleMatch -ErrorAction SilentlyContinue)

    $lastTransferred = @($matches | Where-Object { $_.Line -like "*Transferred:*" } | Select-Object -Last 1)
    if ($lastTransferred.Count -gt 0) {
        $report.Transferred = (($lastTransferred[0].Line -replace '^.*Transferred:\s*', '').Trim())
    }

    $lastChecks = @($matches | Where-Object { $_.Line -like "*Checks:*" } | Select-Object -Last 1)
    if ($lastChecks.Count -gt 0) {
        $report.Checks = (($lastChecks[0].Line -replace '^.*Checks:\s*', '').Trim())
    }

    $lastElapsed = @($matches | Where-Object { $_.Line -like "*Elapsed time:*" } | Select-Object -Last 1)
    if ($lastElapsed.Count -gt 0) {
        $report.Elapsed = (($lastElapsed[0].Line -replace '^.*Elapsed time:\s*', '').Trim())
    }

    return [pscustomobject]$report
}

function Invoke-SyncPriorityGroup {
    param(
        [Parameter(Mandatory = $true)][object[]]$Specs,
        [Parameter(Mandatory = $true)][int]$MaxParallel,
        [Parameter(Mandatory = $true)][string]$RcloneExe,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Reports,
        [Parameter(Mandatory = $true)][bool]$ContinueOnError
    )

    $queue = New-Object System.Collections.ArrayList
    foreach ($spec in $Specs) {
        [void]$queue.Add($spec)
    }

    $running = New-Object System.Collections.ArrayList
    $haltLaunch = $false

    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        while (-not $haltLaunch -and $queue.Count -gt 0 -and $running.Count -lt $MaxParallel) {
            $spec = $queue[0]
            $queue.RemoveAt(0)

            Write-Host "[SYNC] Starte Job '$($spec.Name)' (ID=$($spec.Id), Priority=$($spec.Priority))"
            Write-Host "[SYNC] $RcloneExe $($spec.Args -join ' ')"

            $job = Start-Job -Name ("rclone-sync-" + $spec.Id) -ArgumentList $RcloneExe, @($spec.Args) -ScriptBlock {
                param($exe, $argList)
                & $exe @argList *> $null
                [pscustomobject]@{ ExitCode = $LASTEXITCODE }
            }

            [void]$running.Add([pscustomobject]@{ Spec = $spec; Job = $job; StartedAt = (Get-Date) })
        }

        if ($running.Count -eq 0) {
            continue
        }

        $runningJobs = @($running | ForEach-Object { $_.Job })
        $null = Wait-Job -Job $runningJobs -Any -Timeout 2

        for ($i = $running.Count - 1; $i -ge 0; $i--) {
            $entry = $running[$i]
            $job = $entry.Job

            if ($job.State -notin @("Completed", "Failed", "Stopped")) {
                continue
            }

            $spec = $entry.Spec
            $exitCode = 1
            $duration = (Get-Date) - $entry.StartedAt

            try {
                $payload = Receive-Job -Job $job -ErrorAction SilentlyContinue
                $exitObj = @($payload | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["ExitCode"] }) | Select-Object -Last 1
                if ($null -ne $exitObj) {
                    $exitCode = [int]$exitObj.ExitCode
                }
                elseif ($job.State -eq "Completed") {
                    $exitCode = 0
                }
            }
            catch {
                $exitCode = 1
            }
            finally {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }

            $running.RemoveAt($i)

            $logMetrics = Get-SyncReportFromLog -LogPath $spec.LogPath
            $report = [pscustomobject]@{
                Name = $spec.Name
                Id = $spec.Id
                Priority = $spec.Priority
                Duration = (Format-Duration -Span $duration)
                DurationSeconds = [math]::Round($duration.TotalSeconds, 1)
                Transferred = [string]$logMetrics.Transferred
                Checks = [string]$logMetrics.Checks
                ElapsedFromLog = [string]$logMetrics.Elapsed
                ExitCode = $exitCode
                LogPath = $spec.LogPath
            }
            $Reports.Add($report)

            Write-Host "[ABSCHLUSS] Job '$($report.Name)' (ID=$($report.Id)) Dauer=$($report.Duration) Geaendert=$($report.Transferred) ExitCode=$($report.ExitCode)"

            if ($job.State -ne "Completed" -or $exitCode -ne 0) {
                $msg = "[SYNC] Job '$($spec.Name)' (ID=$($spec.Id), Priority=$($spec.Priority)) fehlgeschlagen mit ExitCode $exitCode. Log: $($spec.LogPath)"
                Write-Warning $msg
                $Errors.Add($msg)
                if (-not $ContinueOnError) {
                    $haltLaunch = $true
                }
            }
            else {
                Write-Host "[SYNC] Job '$($spec.Name)' erfolgreich. Log: $($spec.LogPath)"
            }
        }
    }
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
$rcloneExe = Resolve-RclonePath -ConfigData $configData
$rcloneConf = Resolve-RcloneConfigPath -ConfigData $configData

if ($null -eq $configData.facts -or $null -eq $configData.facts.automation) {
    throw "Abschnitt facts.automation fehlt in $ConfigJsonPath"
}

if ($Kind -eq "mount") {
    Assert-WinFspForMount
    $allJobs = @($configData.facts.automation.mounts)
}
else {
    $allJobs = @($configData.facts.automation.syncs)
}

if ($allJobs.Count -eq 0) {
    throw "Keine Jobs fuer Kind '$Kind' in der Konfiguration vorhanden."
}

$jobs = Select-Jobs -All $allJobs -Names $JobName

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runStartedAt = Get-Date

$errors = New-Object System.Collections.Generic.List[string]
$syncReports = New-Object System.Collections.Generic.List[object]

if ($Kind -eq "mount") {
    foreach ($job in $jobs) {
        $jobName = [string]$job.name
        $jobId = Get-JobId -Job $job
        $safeJobId = [regex]::Replace($jobId, "[^A-Za-z0-9_-]", "_")
        $jobLog = Join-Path $LogRoot ("{0}_{1}.log" -f $runStamp, $safeJobId)
        $options = Build-Options -Options $job.options -RepoRoot $repoRoot -Kind "mount"

        $remote = [string]$job.remote
        $drive = [string]$job.drive_letter

        if (Test-MountPointInUse -Drive $drive) {
            Write-Warning "[MOUNT] Job '$jobName' uebersprungen: Mountpoint bereits belegt ($drive)."
            continue
        }

        $args = New-Object System.Collections.Generic.List[string]
        $args.Add("mount")
        $args.Add($remote)
        $args.Add($drive)
        foreach ($opt in $options) { $args.Add($opt) }
        if (-not ($args -contains "--log-level") -and -not (Test-HasVerboseFlag -Args $args)) {
            $args.Add("--log-level")
            $args.Add("INFO")
        }
        $args.Add("--config")
        $args.Add($rcloneConf)
        $args.Add("--log-file")
        $args.Add($jobLog)

        Write-Host "[MOUNT] $jobName -> $remote => $drive"
        Write-Host "[MOUNT] $rcloneExe $($args -join ' ')"

        if ($LiveRun) {
            $proc = Start-Process -FilePath $rcloneExe -ArgumentList $args -PassThru -WindowStyle Hidden
            Write-Host "[MOUNT] Gestartet mit PID $($proc.Id). Log: $jobLog"
        }
        else {
            Write-Host "[MOUNT] Dry-Mode: Befehl nur angezeigt. Fuer Ausfuehrung -LiveRun setzen."
        }
    }
}
else {
    $syncSpecs = @($jobs |
        Sort-Object @{ Expression = { Get-JobPriority -Job $_ } }, @{ Expression = { [string]$_.name } } |
        ForEach-Object {
            New-SyncSpec -Job $_ -RunStamp $runStamp -LogRoot $LogRoot -RepoRoot $repoRoot -RcloneConf $rcloneConf -LiveRun:$LiveRun
        })

    $priorities = @($syncSpecs | ForEach-Object { [int]$_.Priority } | Sort-Object -Unique)

    foreach ($priority in $priorities) {
        $groupSpecs = @($syncSpecs | Where-Object { [int]$_.Priority -eq $priority })
        Write-Host "[SYNC] Prioritaet ${priority}: $($groupSpecs.Count) Job(s), MaxParallel=$MaxParallel"

        Invoke-SyncPriorityGroup -Specs $groupSpecs -MaxParallel $MaxParallel -RcloneExe $rcloneExe -Errors $errors -Reports $syncReports -ContinueOnError:$ContinueOnError

        if ($errors.Count -gt 0 -and -not $ContinueOnError) {
            break
        }
    }
}

if ($errors.Count -gt 0) {
    if ($Kind -eq "sync") {
        $runDuration = (Get-Date) - $runStartedAt
        $okCount = @($syncReports | Where-Object { $_.ExitCode -eq 0 }).Count
        $failCount = $syncReports.Count - $okCount
        $changedInfo = @($syncReports | ForEach-Object { "$($_.Id)=$($_.Transferred)" }) -join "; "
        if ([string]::IsNullOrWhiteSpace($changedInfo)) {
            $changedInfo = "n/a"
        }

        Write-Host "[ABSCHLUSS] Gesamtlauf Dauer=$(Format-Duration -Span $runDuration) Jobs=$($syncReports.Count) Erfolgreich=$okCount Fehler=$failCount Geaendert=$changedInfo ExitCode=1"
    }
    exit 1
}

if ($Kind -eq "sync") {
    $runDuration = (Get-Date) - $runStartedAt
    $okCount = @($syncReports | Where-Object { $_.ExitCode -eq 0 }).Count
    $failCount = $syncReports.Count - $okCount
    $changedInfo = @($syncReports | ForEach-Object { "$($_.Id)=$($_.Transferred)" }) -join "; "
    if ([string]::IsNullOrWhiteSpace($changedInfo)) {
        $changedInfo = "n/a"
    }

    Write-Host "[ABSCHLUSS] Gesamtlauf Dauer=$(Format-Duration -Span $runDuration) Jobs=$($syncReports.Count) Erfolgreich=$okCount Fehler=$failCount Geaendert=$changedInfo ExitCode=0"
}

exit 0
