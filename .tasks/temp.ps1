    
        







$tokens = $null; 
$errs = $null; 
[System.Management.Automation.Language.Parser]::ParseFile("C:\Users\attila\Projects\R-Agent\.Tools\Invoke-RcloneAutomation.ps1", [ref]$tokens, [ref]$errs) | Out-Null
if ($null -ne $errs -and $errs.Count -gt 0) {
    "PWSH_PARSE=ERROR"
    $errs | ForEach-Object { $_.Message }
    exit 1 
}
"PWSH_PARSE=OK"
$cfgPath = "C:\Users\attila\.Secrets\RClone.Secrets.json"
$scriptPath = "C:\Users\attila\Projects\R-Agent\.Tools\Invoke-RcloneAutomation.ps1"
$cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
$sync = @($cfg.facts.automation.syncs | Where-Object { $_.id -eq "s3" }) | Select-Object -First 1
if ($null -eq $sync) { 
    throw "Sync mit id s3 nicht gefunden." 
}
$jobName = [string]$sync.name
Write-Output ("SYNC_ID=s3")
Write-Output ("SYNC_NAME=" + $jobName)
& $scriptPath -Kind sync -JobName $jobName -LiveRun
$code = $LASTEXITCODE
Write-Output ("RUN_EXIT=" + $code)
exit $code

PWSH_PARSE=OK
SYNC_ID=s3
SYNC_NAME=opencode-localshare-to-gdrive
[SYNC] opencode-localshare-to-gdrive -> C:\Users\attila\.local\share\opencode => gdrive:Backups/OpenCode/.local/share/opencode
[SYNC] C:\Program Files\rclone\rclone.exe sync C:\Users\attila\.local\share\opencode gdrive:Backups/OpenCode/.local/share/opencode --transfers 8 --checkers 32 --drive-chunk-size 64M --skip-links --stats 30s --stats-one-line-date --config C:\Users\attila\AppData\Roaming\rclone\rclone.conf --log-file C:\Users\attila\Projects\R-Agent\.logs\20260215_021846_s3.log














        
        
rclone mount pcdrive: P: --vfs-cache-mode full -v --links
rclone mount gdrive: G: --vfs-cache-mode full -v --links

rclone sync "C:\Users\attila\Projects" "gdrive:Backups/OpenCode/Projects" --transfers 8 --checkers 32 --drive-chunk-size 64M --skip-links --progress
rclone sync "C:\Users\attila\.config\opencode" "gdrive:Backups/OpenCode/.config/opencode" --transfers 8 --checkers 32 --drive-chunk-size 64M --skip-links --progress
rclone sync "C:\Users\attila\.local\share\opencode" "gdrive:Backups/OpenCode/.local/share/opencode" --transfers 8 --checkers 32 --drive-chunk-size 64M --skip-links --progress
rclone sync "C:\Users\attila\" "pcdrive:Attila" --exclude-from "<s.u.>" --transfers 8 --checkers 32 --drive-chunk-size 64M --skip-links --progress

Exludes für C:\Users\attila\:

.bun/**
.cache/**
.codex/tmp/**
.codex/tmp/**
.nuget/**
.vscode/extensions/**
AppData/Local/Autodesk/**
AppData/Local/Comms/UnistoreDB/**
AppData/Local/docker-secrets-engine/**
AppData/Local/Docker/**
AppData/Local/ElevatedDiagnostics
AppData/Local/Google/**
AppData/Local/Microsoft/**
AppData/Local/Mozilla/**
AppData/Local/Packages/**
AppData/Local/PowerToys/**
AppData/Local/Programs/**
AppData/Local/Razer/**
AppData/Local/rclone/**
AppData/Local/Spotify/**
AppData/Local/Temp/**
AppData/Local/uv/**
AppData/Local/wsl/**
AppData/LocalLow/**
AppData/Roaming/**
AppData/Roaming/Code/**
Projects/*/.git/**
/NTUSER*
/ntuser*


/Neue_Aufgabe Wenn alle Tools stehen muss eine Übersichtstabelle in der AGENTS.me geschriebenwerden mit Tool-Name/Aufruf und Beschreibung.
