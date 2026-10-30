[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
function Invoke-Git([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree')
# Stage every tracked and untracked, non-ignored file in the repository.
Invoke-Git -Arguments @('add', '--all')

# Commit every staged and working-tree change; do not limit the commit to selected paths.
Invoke-Git -Arguments @('commit', '-m', $Message)
# Push the current branch and its upstream; set upstream automatically if absent.
$branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'Unable to determine the current Git branch.'
}
$upstream = & git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
if ($LASTEXITCODE -eq 0) {
    Invoke-Git -Arguments @('push')
} else {
    Invoke-Git -Arguments @('push', '--set-upstream', 'origin', $branch)
}
