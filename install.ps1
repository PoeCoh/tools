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
    return
}

if (-not (Test-Path -Path $ziglang)) { New-Item -Path $ziglang -ItemType Directory -Force | Out-Null }
if (Test-Path -Path "$zig\.git") {
    Write-Debug -Message "Updating zig"
    Start-Process -FilePath "git" -ArgumentList "pull", "origin" -Wait -NoNewWindow -WorkingDirectory $zig
} else {
    Write-Debug -Message "Cloning zig"
    Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/ziglang/zig" -Wait -NoNewWindow -WorkingDirectory $ziglang
}
$result = iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)} -RepoPath '$zig'"
if (-not $result) { throw "Failed to download devkit." }
Write-Debug -Message "Building zig from source"
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
if (Test-Path -Path "$zig\stage3\bin\zig.exe") { Remove-Item -Path "$zig\stage3\bin\zig.exe" -Force }
$building = Start-Process -FilePath "$temp\devkit\bin\zig.exe" -ArgumentList $argList -WorkingDirectory $zig -PassThru
$building.WaitForExit()
Write-Debug -Message "Exit Code: $($building.ExitCode)"
if ($building.ExitCode -ne 0) {
    Write-Debug -Message "Build failed, using latest release to build"
    $result = iex "& {$(irm git.poecoh.com/tools/zig/download-release.ps1)}"
    if (-not $result) { throw "Failed to download release." }
    $building = Start-Process -FilePath "$temp\release\zig.exe" -ArgumentList $argList -WorkingDirectory $zig -PassThru
    $building.WaitForExit()
    Write-Debug -Message "Exit Code: $($building.ExitCode)"
}
if ($building.ExitCode -ne 0) { throw "Zig build failed." }
Write-Debug -Message "Build successful, adding to path"
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
if (-not $paths.Contains("$zig\stage3\bin")) {
    $paths += "$zig\stage3\bin"
    [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
    $Env:Path = $Env:Path + ';' + "$zig\stage3\bin" + ';'
}
Write-Debug -Message "Building zls from source"
if (Test-Path -Path "$zls\.git") {
    Write-Debug -Message "Updating zls"
    Start-Process -FilePath "git" -ArgumentList "pull", "origin" -Wait -NoNewWindow -WorkingDirectory $zls
} else {
    Write-Debug -Message "Cloning zls"
    Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/zigtools/zls" -Wait -NoNewWindow -WorkingDirectory $ziglang
}
$building = Start-Process -FilePath "$zig\stage3\bin\zig.exe" -ArgumentList 'build', '-Doptimize=ReleaseSafe' -WorkingDirectory $zls -PassThru
$building.WaitForExit()
Write-Debug -Message "Exit Code: $($building.ExitCode)"
Write-Debug -Message "Adding zls to path"
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
if (-not $paths.Contains("$zls\zig-out\bin")) {
    $paths += "$zls\zig-out\bin"
    [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
    $Env:Path = $Env:Path + ';' + "$zls\zig-out\bin" + ';'
}
Write-Debug -Message "Creating environment variables ZIG and ZLS"
[Environment]::SetEnvironmentVariable('ZIG', $zig, 'User') | Out-Null
[Environment]::SetEnvironmentVariable('ZLS', $zls, 'User') | Out-Null
if ($Test.IsPresent) {
    Write-Host -Object "Running zig build test"
    Start-Procenss -FilePath "zig" -ArgumentList "build", "test" -Wait -NoNewWindow -WorkingDirectory $zig
}
Write-Host -Object "Done" -ForegroundColor Green
return
