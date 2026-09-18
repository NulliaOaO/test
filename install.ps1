# install.ps1 — one-line installer for a Claude Code skill hosted as a zip
#
# Usage (one line, nothing to save):
#   irm <RAW_URL_OF_THIS_SCRIPT> | iex
#
# Notes:
#   - Auto-fixes the most common install failure: an extra nested folder
#     (zip/NAME/NAME/SKILL.md instead of zip/NAME/SKILL.md)
#   - Idempotent: re-running replaces the existing install

param(
    [string[]]$ZipUrl = @(
        "https://ghproxy.net/https://raw.githubusercontent.com/NulliaOaO/test/main/retrieval-exam-protocol.zip",
        "https://gh-proxy.com/https://raw.githubusercontent.com/NulliaOaO/test/main/retrieval-exam-protocol.zip"
    ),
    [string]$SkillName = "retrieval-exam-protocol",
    [string]$TargetDir = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Make non-ASCII (skill description) render correctly on Windows PowerShell 5.1
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Die($m)  { Write-Host $m -ForegroundColor Red; exit 1 }

# ---------- resolve target ----------
if ($TargetDir -eq "") {
    $skillsDir = Join-Path $env:USERPROFILE ".claude\skills"
} else {
    $skillsDir = $TargetDir
}
$dest = Join-Path $skillsDir $SkillName

# ---------- uninstall ----------
if ($Uninstall) {
    if (Test-Path $dest) {
        Remove-Item $dest -Recurse -Force
        Ok "Removed: $dest"
    } else {
        Warn "Not installed, nothing to remove: $dest"
    }
    exit 0
}

Info "Installing '$SkillName'"
Info "Target: $skillsDir"
Write-Host ""

# ---------- prepare ----------
if (-not (Test-Path $skillsDir)) {
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    Info "Created skills folder."
}

$tmp = Join-Path $env:TEMP ("skill-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    # ---------- download (try each mirror until one works) ----------
    $zip = Join-Path $tmp "pkg.zip"
    $got = $false
    $i = 0
    foreach ($url in $ZipUrl) {
        $i++
        Info "Downloading (source $i/$($ZipUrl.Count))..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 30
            if ((Get-Item $zip).Length -gt 0) { $got = $true; break }
        } catch {
            Warn "  failed: $($_.Exception.Message)"
        }
    }
    if (-not $got) {
        Write-Host ""
        Die "All download sources failed.`n  Tried:`n    $($ZipUrl -join "`n    ")"
    }
    $size = [math]::Round((Get-Item $zip).Length / 1KB, 1)
    Ok "Downloaded $size KB"

    # ---------- extract ----------
    $extract = Join-Path $tmp "extract"
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    Info "Extracted."

    # ---------- locate SKILL.md (handles extra nesting automatically) ----------
    $skillMd = Get-ChildItem -Path $extract -Filter "SKILL.md" -Recurse -File |
               Select-Object -First 1

    if (-not $skillMd) {
        Die "SKILL.md not found in the package. The zip is not a valid skill."
    }

    $src = $skillMd.Directory.FullName
    $depth = ($src.Substring($extract.Length).TrimStart('\') -split '\\' | Where-Object { $_ }).Count
    if ($depth -gt 1) {
        Warn "Package was nested $depth levels deep; flattening automatically."
    }

    # ---------- install ----------
    if (Test-Path $dest) {
        Remove-Item $dest -Recurse -Force
        Warn "Replaced existing install."
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $src "*") -Destination $dest -Recurse -Force

    # ---------- verify ----------
    $final = Join-Path $dest "SKILL.md"
    if (-not (Test-Path $final)) {
        Die "Install verification failed: SKILL.md missing at $final"
    }

    $head = Get-Content $final -TotalCount 6 -Encoding UTF8
    $descLine = $head | Where-Object { $_ -match '^description:' } | Select-Object -First 1

    Write-Host ""
    Ok "Installed to: $dest"
    $files = (Get-ChildItem $dest -Recurse -File).Count
    Ok "Files: $files"
    if ($descLine) {
        Write-Host ""
        Info "Skill description:"
        Write-Host ("  " + $descLine.Substring(0, [Math]::Min(160, $descLine.Length)))
    }

    Write-Host ""
    Warn "IMPORTANT: fully quit and reopen Claude Code for the skill to load."
    Write-Host ""
    Info "To uninstall:"
    Write-Host "  irm <SAME_URL> | iex -Uninstall"
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
