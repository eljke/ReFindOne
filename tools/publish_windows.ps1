#Requires -Version 5.1
<#
.SYNOPSIS
  First publication or subsequent updates of ReFind One from Windows 11.
.DESCRIPTION
  Needs Git, GitHub CLI and gh auth login. Creates a private GitHub repo by default.
  Uploads ONLY project files, then prints the Actions link. Building the IPA is manual.
.EXAMPLE
  .\tools\publish_windows.ps1
  .\tools\publish_windows.ps1 -Visibility public
#>
param(
    [ValidateSet('private', 'public')]
    [string]$Visibility = 'private',
    [string]$RepoName = 'ReFindOne'
)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Install Git for Windows: winget install --id Git.Git -e' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Install GitHub CLI: winget install --id GitHub.cli -e' }

& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Run gh auth login first (GitHub.com / HTTPS / browser).' }

$name = & git config user.name
$email = & git config user.email
if (-not $name -or -not $email) {
    throw 'Set your Git author identity first: git config --global user.name "Your name"; git config --global user.email "you@example.com"'
}

if (-not (Test-Path '.git')) {
    & git init -b main
    if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
}
& git add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0
if ($hasChanges) {
    & git commit -m 'chore: update ReFind One sources'
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
}

$remotes = @(& git remote)
$hasOrigin = $remotes -contains 'origin'
if (-not $hasOrigin) {
    Write-Host "Creating a $Visibility GitHub repository: $RepoName" -ForegroundColor Cyan
    & gh repo create $RepoName "--$Visibility" --source . --remote origin --push
    if ($LASTEXITCODE -ne 0) { throw 'gh repo create failed; check if the repository already exists.' }
} else {
    & git push -u origin HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
}
$repo = & gh repo view --json nameWithOwner --jq '.nameWithOwner'
if ($LASTEXITCODE -ne 0) { throw 'Could not identify GitHub repository.' }
Write-Host "`nProject uploaded: https://github.com/$repo" -ForegroundColor Green
Write-Host "Open https://github.com/$repo/actions/workflows/build-ios-ipa.yml" -ForegroundColor Green
Write-Host 'Click Run workflow -> Run workflow. When green, download artifact ReFindOne-unsigned-iOS27.'
