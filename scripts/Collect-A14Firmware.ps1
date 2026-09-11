<# Collect existing Windows firmware. Does not download or modify drivers. #>
[CmdletBinding()]
param(
    [string[]]$Source = @("$env:windir\System32\DriverStore\FileRepository"),
    [Parameter(Mandatory = $true)][string]$Destination,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -Raw (Join-Path $PSScriptRoot '..\firmware-manifest.json') | ConvertFrom-Json
$candidates = @{}
foreach ($item in $manifest.files) { $candidates[$item.name.ToLowerInvariant()] = @() }
foreach ($directory in $Source) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Not a directory: $directory" }
    # Unreadable subdirectories are reported; missing required files still fail below.
    Get-ChildItem -LiteralPath $directory -Recurse -File -ErrorAction Continue | ForEach-Object {
        $key = $_.Name.ToLowerInvariant()
        if ($candidates.ContainsKey($key) -and $_.Length -gt 0) { $candidates[$key] += $_.FullName }
    }
}
$selected = @{}
$hashes = @{}
$failures = @()
$knownBytes = @{}
foreach ($paths in $candidates.Values) {
    foreach ($path in $paths) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $knownBytes[$hash] = $path
    }
}
foreach ($item in $manifest.files) {
    $versions = @{}
    foreach ($path in $candidates[$item.name.ToLowerInvariant()]) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $versions[$hash] = $path
    }
    $reference = $item.referenceSha256
    $optional = [bool]$item.optional
    if ($null -ne $reference -and $versions.ContainsKey($reference)) { $hash = $reference }
    elseif ($versions.Count -eq 1) { $hash = @($versions.Keys)[0] }
    elseif ($versions.Count -eq 0 -and $null -ne $reference -and $knownBytes.ContainsKey($reference)) {
        # Only reproduce an absent alias when the bytes match its reference.
        $hash = $reference
        $versions[$hash] = $knownBytes[$hash]
    }
    elseif ($versions.Count -eq 0 -and $optional) { Write-Warning "Optional file not found, skipping: $($item.name)"; continue }
    elseif ($versions.Count -eq 0) { $failures += "Missing: $($item.name)"; continue }
    else { $failures += "Multiple versions of $($item.name); narrow -Source to the chosen driver directory."; continue }
    if ($null -ne $reference -and $hash -ne $reference) {
        if ($Strict) { $failures += "Hash differs from reference: $($item.name)"; continue }
        Write-Warning "Hash differs from the tested reference: $($item.name). This version needs hardware testing."
    }
    $selected[$item.name] = $versions[$hash]
    $hashes[$item.name] = $hash
}
if ($failures.Count -gt 0) { throw ($failures -join "`n") }
foreach ($name in $selected.Keys) {
    $target = Join-Path $Destination $name
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hashes[$name]) {
            throw "Refusing to overwrite different firmware: $target. Use a new destination."
        }
    }
}
# All required files and destination conflicts have been checked first.
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($name in $selected.Keys) {
    $target = Join-Path $Destination $name
    if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $selected[$name] -Destination $target }
}
Write-Host "Collected $($selected.Count) files into $Destination. Keep a backup for future rebuilds."
