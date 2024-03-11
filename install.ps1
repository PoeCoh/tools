<#
iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"

based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
Sets environment variables ZIG and ZLS to thier respective repositories
This script doubles as an update script

to pass flags to the script, append them like this:
iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Test -Legacy -ReleaseSafe"

I split the download sections off into their own thing so they can be used independently
#>
[CmdletBinding()]
param (
    [parameter()]
    [switch]$Test,

    [parameter()]
    [switch]$ReleaseSafe,

    [parameter()]
    [switch]$Legacy
)

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"
$temp = "$Env:TEMP\ziglang"

if ($PSVersionTable.PSVersion.Major -eq 5 -and -not $Legacy.IsPresent) {
    Write-Host -Object "Legacy powershell takes drastically longer, please install and use powershell 7+."
    # No, really, legacy was shockingly slow.
    Write-Host -Object "If you must use legacy powershell, add -Legacy to the command to ignore this."
    Write-Host -Object 'iex "& { $(irm git.poecoh.com/tools/zig/install.ps1) } -Legacy"' -ForegroundColor DarkYellow
    exit 1
}

if (-not (Test-Path -Path $ziglang)) { New-Item -Path $ziglang -ItemType Directory -Force | Out-Null }
try {
    Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/ziglang/zig" -Wait -NoNewWindow -WorkingDirectory $ziglang
} catch {
    Start-Process -FilePath "git" -ArgumentList "pull", "origin" -Wait -NoNewWindow -WorkingDirectory $zig
}
$result = iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)} -RepoPath '$zig'"
if (-not $result) {
    Remove-Item -Path $temp -Recurse -Force
    Write-Host -Object "Failed to download devkit, exiting"
    exit 1
}
Write-Host -Object "Building zig from source"
$argList = @(
    'build'
    '-p'
    'stage3'
    "--search-prefix $temp\devkit"
    '--zig-lib-dir lib'
    '-Dstatic-llvm'
    '-Duse-zig-libcxx'
    '-Dtarget=x86_64-windows-gnu'
)
if ($ReleaseSafe.IsPresent) { $argList += '-Doptimize=ReleaseSafe' }
Start-Process -FilePath "$temp\devkit\bin\zig.exe" -ArgumentList $argList -Wait -NoNewWindow -WorkingDirectory $zig
if (-not (Test-Path -Path "$zig\stage3\bin\zig.exe")) {
    Write-Host -Object "Build failed, using latest release to build"
    $result = iex "& {$(irm git.poecoh.com/tools/zig/download-release.ps1)}"
    if (-not $result) {
        Remove-Item -Path $temp -Recurse -Force
        Write-Host -Object "Failed to download release, exiting"
        exit 1
    }
    Start-Process -FilePath "$temp\release\zig.exe" -ArgumentList $argList -Wait -NoNewWindow -WorkingDirectory $zig
}
Remove-Item -Path $temp -Recurse -Force
if (-not (Test-Path -Path "$zig\stage3\bin\zig.exe")) {
    Write-Host -Object "Build failed, exiting cleaning up and exiting"
    exit 1
}
Write-Host -Object "Build successful, adding to path"
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
if (-not $paths.Contains("$zig\stage3\bin")) {
    $paths += "$zig\stage3\bin"
    [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
    $Env:Path = $Env:Path + ';' + "$zig\stage3\bin" + ';'
}
Write-Host -Object "Building zls from source"
try {
    Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/zigtools/zls" -Wait -NoNewWindow -WorkingDirectory $ziglang
} catch {
    Start-Process -FilePath "git" -ArgumentList "pull", "origin" -Wait -NoNewWindow -WorkingDirectory $zls
}
Start-Process -FilePath "$zig\stage3\bin\zig.exe" -ArgumentList 'build', '-Doptimize=ReleaseSafe' -Wait -NoNewWindow -WorkingDirectory $zls
Write-Host -Object "Adding zls to path"
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
if (-not $paths.Contains("$zls\zig-out\bin")) {
    $paths += "$zls\zig-out\bin"
    [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
    $Env:Path = $Env:Path + ';' + "$zls\zig-out\bin" + ';'
}
Write-Host -Object "Creating environment variables ZIG and ZLS"
[Environment]::SetEnvironmentVariable('ZIG', $zig, 'User') | Out-Null
[Environment]::SetEnvironmentVariable('ZLS', $zls, 'User') | Out-Null
if ($Test.IsPresent) {
    Write-Host -Object "Running zig build test"
    Start-Process -FilePath "zig" -ArgumentList "build", "test" -Wait -NoNewWindow -WorkingDirectory $zig
}
Write-Host -Object "Done" -ForegroundColor Green
Exit 0
