[CmdletBinding()]
param(
    [ValidateSet('smoke', 'unit', 'ui', 'runtime-ui', 'desktop-ui', 'service-ui', 'simulation-ui', 'full')]
    [string]$Profile = 'full',

    [string]$SshHost = 'filius-mac',
    [string]$RemoteRepo = '~/src/filius',
    [string]$Branch,
    [string]$Revision,
    [string]$SimulatorUdid,
    [string]$ArtifactsRoot = '~/FiliusTestArtifacts',
    [int]$UiTimeoutMinutes = 120,

    [switch]$NoSync,
    [switch]$InstallRuntime,
    [switch]$KeepSimulatorRunning,
    [switch]$DownloadArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-PosixLiteral {
    param([Parameter(Mandatory)][string]$Value)

    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $escapedQuote = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + $Value.Replace($singleQuote, $escapedQuote) + $singleQuote
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command exited with status $LASTEXITCODE"
    }
}

foreach ($command in 'ssh', 'scp', 'git') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $command"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$macRunner = Join-Path $PSScriptRoot 'run-tests.sh'
if (-not (Test-Path -LiteralPath $macRunner)) {
    throw "Mac runner is missing: $macRunner"
}

if (-not $NoSync) {
    $status = @(git -C $repoRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect the local Git checkout.'
    }
    if ($status.Count -gt 0) {
        throw 'The local checkout is dirty. Commit and push it first, or use -NoSync to test the existing Mac checkout.'
    }

    if (-not $Branch) {
        $Branch = (git -C $repoRoot branch --show-current).Trim()
        if (-not $Branch) {
            $Branch = 'main'
        }
    }
    if (-not $Revision) {
        $Revision = (git -C $repoRoot rev-parse HEAD).Trim()
    }
}

$remoteRunner = "/tmp/filius-run-tests-$([Guid]::NewGuid().ToString('N')).sh"
Invoke-NativeChecked scp -q $macRunner "${SshHost}:$remoteRunner"

$remoteArguments = [System.Collections.Generic.List[string]]::new()
$remoteArguments.Add('--repo')
$remoteArguments.Add($RemoteRepo)
$remoteArguments.Add('--profile')
$remoteArguments.Add($Profile)
$remoteArguments.Add('--artifacts-root')
$remoteArguments.Add($ArtifactsRoot)
$remoteArguments.Add('--ui-timeout-minutes')
$remoteArguments.Add($UiTimeoutMinutes.ToString())

if (-not $NoSync) {
    $remoteArguments.Add('--sync')
    $remoteArguments.Add('--branch')
    $remoteArguments.Add($Branch)
    $remoteArguments.Add('--revision')
    $remoteArguments.Add($Revision)
}
if ($SimulatorUdid) {
    $remoteArguments.Add('--simulator-udid')
    $remoteArguments.Add($SimulatorUdid)
}
if ($InstallRuntime) {
    $remoteArguments.Add('--install-runtime')
}
if ($KeepSimulatorRunning) {
    $remoteArguments.Add('--keep-simulator-running')
}

$quotedRunner = ConvertTo-PosixLiteral $remoteRunner
$quotedArguments = $remoteArguments | ForEach-Object { ConvertTo-PosixLiteral $_ }
$remoteCommand = "chmod 700 $quotedRunner && $quotedRunner " + ($quotedArguments -join ' ')

$output = [System.Collections.Generic.List[string]]::new()
$sshExitCode = 1
try {
    & ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=120 $SshHost $remoteCommand 2>&1 |
        ForEach-Object {
            $line = $_.ToString()
            $output.Add($line)
            Write-Host $line
        }
    $sshExitCode = $LASTEXITCODE
}
finally {
    & ssh -o BatchMode=yes $SshHost "rm -f $(ConvertTo-PosixLiteral $remoteRunner)" 2>$null | Out-Null
}

$artifactLine = $output | Where-Object { $_ -like 'ARTIFACTS_DIR=*' } | Select-Object -Last 1
if ($artifactLine) {
    $remoteArtifacts = $artifactLine.Substring('ARTIFACTS_DIR='.Length)
    Write-Host "Remote artifacts: $remoteArtifacts"

    if ($DownloadArtifacts) {
        $downloadRoot = Join-Path $repoRoot 'tmp\mac-test-artifacts'
        New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
        Invoke-NativeChecked scp -r "${SshHost}:$remoteArtifacts" $downloadRoot
        Write-Host "Downloaded artifacts: $downloadRoot"
    }
}

if ($sshExitCode -ne 0) {
    throw "Mac test runner exited with status $sshExitCode"
}
