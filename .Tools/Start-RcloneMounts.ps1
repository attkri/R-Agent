[CmdletBinding()]
param(
    [string[]]$JobName = @(),
    [switch]$LiveRun,
    [switch]$DetachedViaTask,
    [string]$ConfigJsonPath = "C:\Users\attila\.Secrets\RClone.Secrets.json",
    [string]$StatusDir = "C:\Users\attila\.logs\ASO\Status"
)

function Write-MountStatus {
    param(
        [Parameter(Mandatory = $true)][string]$StatusDir,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][object]$ConfigData,
        [object[]]$Results = @()
    )

    if (-not (Test-Path -LiteralPath $StatusDir)) {
        New-Item -Path $StatusDir -ItemType Directory -Force | Out-Null
    }

    $mountedDrives = @()
    $unmountedDrives = @()

    foreach ($m in $ConfigData.facts.automation.mounts) {
        $drive = [string]$m.drive_letter
        $driveName = $drive.TrimEnd(':')
        $isMounted = $null -ne (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue)

        if ($isMounted) {
            $mountedDrives += $drive
        }
        else {
            $unmountedDrives += $drive
        }
    }

    $symbol = ""
    $statusMessage = ""

    if ($mountedDrives.Count -eq 0 -and $unmountedDrives.Count -gt 0) {
        $symbol = "🔴"
        $statusMessage = "{0} sind nicht gemountet." -f ($unmountedDrives -join " und ")
    }
    elseif ($mountedDrives.Count -gt 0 -and $unmountedDrives.Count -eq 0) {
        $symbol = "🟢"
        $statusMessage = "{0} sind gemountet." -f ($mountedDrives -join " und ")
    }
    else {
        $symbol = "🟠"
        $mountedStr = if ($mountedDrives.Count -gt 0) { ($mountedDrives -join " und ") + " sind gemountet" } else { "" }
        $unmountedStr = if ($unmountedDrives.Count -gt 0) { ($unmountedDrives -join " und ") + " sind nicht gemountet" } else { "" }
        $statusMessage = @($mountedStr, $unmountedStr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", "
    }

    $statusObj = [PSCustomObject]@{
        Id = "RCloneMountStatus"
        TaskName = "RClone Mounting"
        TaskDescription = "Zeigt den Status der RClone-Mounts auf diesem System an."
        Symbole = $symbol
        StatusMessage = $statusMessage
        Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $statusPath = Join-Path $StatusDir "RCloneMountStatus.json"
    $statusObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $statusPath -Encoding UTF8 -Force
    Write-Host "[STATUS] Status geschrieben: $statusPath"
}

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
        "-LiveRun",
        "-ConfigJsonPath",
        ('"{0}"' -f $ConfigJsonPath)
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

$params = @{
    Kind = "mount"
    JobName = $JobName
    ConfigJsonPath = $ConfigJsonPath
}

if ($LiveRun) {
    $params.LiveRun = $true
}

& $automationScript @params
$exitCode = $LASTEXITCODE

$configData = Get-ConfigData -Path $ConfigJsonPath
Write-MountStatus -StatusDir $StatusDir -Action "mount" -ConfigData $configData

exit $exitCode
