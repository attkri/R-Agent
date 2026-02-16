[CmdletBinding()]
param(
    [string[]]$JobName = @(),
    [switch]$LiveRun,
    [switch]$DetachedViaTask,
    [string]$ConfigJsonPath = ""
)

function Resolve-CurrentUserId {
    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        return ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    }

    return [string]$env:USERNAME
}

function Get-TaskLastRunAgeSeconds {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $info) {
        return $null
    }

    if ($info.LastRunTime -lt [datetime]"2000-01-01") {
        return $null
    }

    return [math]::Round(((Get-Date) - $info.LastRunTime).TotalSeconds, 1)
}

function Test-ShouldDebounceTaskStart {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][int]$DebounceSeconds
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return $false
    }

    if ([string]$task.State -eq "Running") {
        Write-Host "[MOUNT] Entprellt: Task '$TaskName' laeuft bereits."
        return $true
    }

    $ageSeconds = Get-TaskLastRunAgeSeconds -TaskName $TaskName
    if ($null -ne $ageSeconds -and $ageSeconds -lt $DebounceSeconds) {
        Write-Host "[MOUNT] Entprellt: letzter Start vor ${ageSeconds}s (< ${DebounceSeconds}s)."
        return $true
    }

    return $false
}

$automationScript = Join-Path (Split-Path -Parent $PSCommandPath) "Invoke-RcloneAutomation.ps1"

if ($DetachedViaTask) {
    if (-not $LiveRun) {
        throw "DetachedViaTask erfordert -LiveRun."
    }

    $taskName = "RcloneMountsOnDemand"
    $debounceSeconds = 20

    if (Test-ShouldDebounceTaskStart -TaskName $taskName -DebounceSeconds $debounceSeconds) {
        exit 0
    }

    $pwshCmd = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
    if ($null -eq $pwshCmd) {
        $pwshCmd = Get-Command "pwsh" -ErrorAction Stop
    }

    $argumentList = @(
        "-NoProfile",
        "-WindowStyle",
        "Hidden",
        "-File",
        ('"{0}"' -f $PSCommandPath),
        "-LiveRun"
    )
    $argumentString = [string]::Join(" ", $argumentList)

    $action = New-ScheduledTaskAction -Execute $pwshCmd.Source -Argument $argumentString
    $principal = New-ScheduledTaskPrincipal -UserId (Resolve-CurrentUserId) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Description "Startet rclone Mounts auf Anforderung (detached)." -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "[MOUNT] Detached-Start ausgelöst über Scheduled Task: $taskName"
    exit 0
}

$params = @{
    Kind = "mount"
    JobName = $JobName
    ConfigJsonPath = $ConfigJsonPath
}

if ($LiveRun) {
    $params.LiveRun = $true
}

& $automationScript @params
exit $LASTEXITCODE
