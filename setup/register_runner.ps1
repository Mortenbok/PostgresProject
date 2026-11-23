<#
.SYNOPSIS
  Installs and registers a self-hosted GitHub Actions runner for this repo on
  this PC, running as the current user (so dbt can read your pgpass.conf).

.DESCRIPTION
  Get a registration token (valid ~1 hour) from:
    GitHub repo > Settings > Actions > Runners > New self-hosted runner
  (the token is in the "Configure" step: --token XXXXX), then run:

    powershell -ExecutionPolicy Bypass -File setup\register_runner.ps1 -Token XXXXX

  The runner is installed in %USERPROFILE%\actions-runner, labelled
  'postgres-local', and started now plus at every logon via a scheduled task
  named 'GitHub Actions runner (PostgresProject)'. It only runs while you are
  logged in.

  -DownloadOnly downloads and verifies the runner without registering it.
#>
param(
    [string]$Token,
    [string]$RepoUrl = 'https://github.com/Mortenbok/PostgresProject',
    [string]$RunnerDir = "$env:USERPROFILE\actions-runner",
    [string]$RunnerName = "$env:COMPUTERNAME-postgres",
    [switch]$DownloadOnly
)
$ErrorActionPreference = 'Stop'
$taskName = 'GitHub Actions runner (PostgresProject)'

# 1. Download + verify the latest runner (skipped if already installed).
if (-not (Test-Path "$RunnerDir\config.cmd")) {
    $headers = @{ 'User-Agent' = 'runner-setup' }
    $release = Invoke-RestMethod https://api.github.com/repos/actions/runner/releases/latest -Headers $headers
    $asset = $release.assets | Where-Object name -like 'actions-runner-win-x64-*.zip' | Select-Object -First 1
    if (-not $asset) { throw "No Windows x64 runner found in release $($release.tag_name)" }

    New-Item -ItemType Directory -Force $RunnerDir | Out-Null
    $zip = Join-Path $RunnerDir $asset.name
    Write-Host "Downloading $($asset.name) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing

    if ($asset.digest -match '^sha256:(?<h>[0-9a-f]{64})$') {
        $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $Matches.h) { Remove-Item $zip; throw "SHA256 mismatch for $($asset.name)" }
        Write-Host "SHA256 verified."
    } else {
        Write-Warning "Release did not publish a digest; skipping hash check."
    }
    Expand-Archive $zip -DestinationPath $RunnerDir -Force
    Remove-Item $zip
}
Write-Host "Runner files in $RunnerDir"
if ($DownloadOnly) { return }

# 2. Register with GitHub.
if (-not $Token) { throw 'Pass -Token (see the help at the top of this script).' }
Push-Location $RunnerDir
try {
    & .\config.cmd --unattended --replace `
        --url $RepoUrl --token $Token `
        --name $RunnerName --labels postgres-local --work _work
    if ($LASTEXITCODE) { throw "config.cmd failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

# 3. Start at logon (as you, hidden) and start now.
$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$RunnerDir\run.cmd`"" -WorkingDirectory $RunnerDir
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "Runner '$RunnerName' registered and started (scheduled task '$taskName')."
