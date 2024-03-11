# iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"
# based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
# to pass flags to the script, append them like this:
# iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Test -Legacy -ReleaseSafe"
# Sets environment variables ZIG and ZLS to thier respective repositories
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
Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/ziglang/zig" -Wait -NoNewWindow -WorkingDirectory $ziglang
$result = iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)} -Path '$zig'"
if (-not $result) {
    Remove-Item -Path $temp -Recurse -Force
    Write-Host -Object "Failed to download devkit, exiting"
    exit 1
}
# $content = Get-Content -Path "$zig\ci\x86_64-windows-debug.ps1"
# $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
# $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
# if (-not (Test-Path -Path $temp)) { New-Item -Path $temp -ItemType Directory -Force | Out-Null }
# Invoke-WebRequest -Uri $url -OutFile "$temp\devkit.zip"
# Expand-Archive -Path "$temp\devkit.zip" -DestinationPath $temp -Force
# Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer }).FullName -NewName "devkit"
# Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
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
        Remove-Item -Path $temp, $ziglang -Recurse -Force
        Write-Host -Object "Failed to download release, exiting"
        exit 1
    }
    # $response = Invoke-WebRequest -Uri "https://ziglang.org/download#release-master"
    # if ($PSVersionTable.PSVersion.Major -eq 5) {
    #     $url = $response.Links.Where({$_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64'}).href
    # } else {
    #     $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
    #     $url = [regex]::new("<a href=(https://[^"">]+)>").Match($href).Groups[1].Value
    # }
    # Invoke-WebRequest -Uri $url -OutFile "$temp\release.zip"
    # Expand-Archive -Path "$temp\release.zip" -DestinationPath $temp -Force
    # Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer -and $_.Name -ne 'devkit' }).FullName -NewName "release"
    # Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
    Start-Process -FilePath "$temp\release\zig.exe" -ArgumentList $argList -Wait -NoNewWindow -WorkingDirectory $zig
}
Remove-Item -Path $temp -Recurse -Force
if (-not (Test-Path -Path "$zig\stage3\bin\zig.exe")) {
    Write-Host -Object "Build failed, exiting cleaning up and exiting"
    Remove-Item -Path $ziglang -Recurse -Force
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
Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/zigtools/zls" -Wait -NoNewWindow -WorkingDirectory $ziglang
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
