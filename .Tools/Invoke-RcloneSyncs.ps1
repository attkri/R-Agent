[CmdletBinding()]
param(
    [string[]]$JobName = @(),
    [switch]$LiveRun,
    [switch]$ContinueOnError,
    [ValidateRange(1, 10)]
    [int]$MaxParallel = 10,
    [string]$ConfigJsonPath = ""
)

$automationScript = Join-Path (Split-Path -Parent $PSCommandPath) "Invoke-RcloneAutomation.ps1"

$params = @{
    Kind = "sync"
    JobName = $JobName
    ContinueOnError = $ContinueOnError
    MaxParallel = $MaxParallel
    ConfigJsonPath = $ConfigJsonPath
}

if ($LiveRun) {
    $params.LiveRun = $true
}

& $automationScript @params
exit $LASTEXITCODE
