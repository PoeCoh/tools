# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"
# Based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
# To pass flags to the script, append them like this:
# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Debug"
[CmdletBinding()]
param ()
$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
trap {
    Write-Host -Object $_.Exception.Message
    Write-Host -Object "Waiting for any running jobs to finish..."
    Get-Job | Wait-Job | Out-Null
    Write-Host -Object "Exiting."
    return
}

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"
$buildFromSource = $true


$downloadBlock = {
    param ( $Url, $WorkingDirectory, $OutFile )
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
    $folders = Expand-Archive -Path $OutFile -DestinationPath $WorkingDirectory -Force -PassThru
    $folders = $folders -split '\\'
    $index = [array]::IndexOf($folders, 'ziglang') + 1
    $folders[0..$index] -join '\'
}

$cleanupBlock = {
    param ( $items )
    Remove-Item -Path $items -Recurse -Force
}

$threads = $null -ne (Get-Command -Name 'Start-ThreadJob')

# create ziglang directory if it doesn't exist
New-Item -Path $ziglang -ItemType Directory -Force | Out-Null

# DevKit URL
$raw = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/ziglang/zig/master/ci/x86_64-windows-debug.ps1'
$version = [regex]::new('(?s)(?<=\$TARGET-).+?(?="\n)').Match($raw).Value
$devkitUrl = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu-$version.zip"

#Release URL
$response = Invoke-WebRequest -Uri 'https://ziglang.org/download#release-master'
$releaseUrl = if ($PSVersionTable.PSVersion.Major -eq 5) {
    $response.Links.Where({ $_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64' }).href
}
else {
    $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
    [regex]::new('<a href=(https://[^">]+)>').Match($href).Groups[1].Value
}

Write-Host -Object "Fetching devkit and latest release build..."
if ($threads) {
    $release = Start-ThreadJob -ScriptBlock $downloadBlock -ArgumentList $releaseUrl, $ziglang, "$ziglang\release.zip"
    $devKit = Start-ThreadJob -ScriptBlock $downloadBlock -ArgumentList $devkitUrl, $ziglang, "$ziglang\devkit.zip"
}
else {
    $release = Start-Job -ScriptBlock $downloadBlock -ArgumentList $releaseUrl, $ziglang, "$ziglang\release.zip"
    $devkit = Start-Job -ScriptBlock $downloadBlock -ArgumentList $devkitUrl, $ziglang, "$ziglang\devkit.zip"
}

$gitSplat = @{
    FilePath         = 'git'
    WorkingDirectory = ''
    ArgumentList     = $null
    WindowStyle      = $(
        if ($PSBoundParameters.ContainsKey('Debug')) { 'Normal' }
        else { 'Hidden' }
    )
}

# Start cloning/pulling zig
$cloneZig = (Test-Path -Path "$zig\.git") -eq $false
$gitSplat.WorkingDirectory = if ($cloneZig) { $ziglang } else { $zig }
$gitSplat.ArgumentList = $(
    if ($cloneZig) { 'clone', 'https://github.com/ziglang/zig' }
    else { 'pull', 'origin' }
)
Write-Host -Object "$(if ($cloneZig) { 'Cloning' } else { 'Pulling' }) zig..."
$gitZig = Start-Process @gitSplat -PassThru

# Start cloning/pulling zls
$cloneZls = (Test-Path -Path "$zls\.git") -eq $false
$gitSplat.WorkingDirectory = if ($cloneZls) { $ziglang } else { $zls }
$gitSplat.ArgumentList = $(
    if ($cloneZls) { 'clone', 'https://github.com/zigtools/zls' }
    else { 'pull', 'origin' }
)
Write-Host -Object "$(if ($cloneZls) { 'Cloning' } else { 'Pulling' }) zls..."
$gitZls = Start-Process @gitSplat -PassThru

# Wait for release and devkit to finish
Wait-Job -Job $release, $devkit | Out-Null
Write-Host -Object "Got devkit and release build."
$releaseDir = Receive-Job -Job $release
$devkitDir = Receive-Job -Job $devkit
Copy-Item -Path "$releaseDir\lib" -Destination "$devkitDir\lib" -Recurse -Force
Copy-Item -Path "$releaseDir\zig.exe" -Destination "$devkitDir\bin\zig.exe" -Force
Write-Host -Object "Copied files."
$trash = @(
    $releaseDir,
    "$releaseDir.zip",
    "$devkitDir.zip"
)
if ($threads) {
    Start-ThreadJob -ScriptBlock $cleanupBlock -ArgumentList $trash
}
else {
    Start-Job -ScriptBlock $cleanupBlock -ArgumentList $trash
}

$gitZig.WaitForExit()
if ($gitZig.ExitCode -ne 0) { throw "Failed to clone or pull zig." }
Write-Host -Object "$(if ($cloneZig) { 'Cloned' } else { 'Pulled' }) zig."

# Build zig with devkit
Write-Host -Object "Building zig..."
$buildArgs = @{
    FilePath         = "$ziglang\devkit\bin\zig.exe"
    WorkingDirectory = $zig
    ArgumentList     = @(
        'build'
        '-p'
        'stage3'
        '--search-prefix'
        "$ziglang\devkit"
        '--zig-lib-dir'
        'lib'
        '-Dstatic-llvm'
        '-Duse-zig-libcxx'
        '-Dtarget=x86_64-windows-gnu'
        '-Doptimize=ReleaseSafe'
    )
}
$build = Start-Process @buildArgs -PassThru -NoNewWindow
$build.WaitForExit()

# fallback to just using release build
if ($build.ExitCode -ne 0) {
    Write-Host -Object "Failed. Falling back to release build for ZLS"
    $buildFromSource = $false
}

if ($build.ExitCode -eq 0) {
    Write-Host -Object "Built zig."
    Start-Job -WorkingDirectory $ziglang -ScriptBlock {
        Remove-Item -Path "$using:ziglang\devkit" -Recurse -Force
    }
}

# We need git to finish before we can build zls
$gitZls.WaitForExit()
if ($gitZls.ExitCode -ne 0) { throw "Failed to clone or pull zls." }
Write-Host -Object "$(if ($cloneZls) { 'Cloned' } else { 'Pulled' }) zls."

# build zls
Write-Host -Object "Building zls..."
$buildArgs = @{
    ArgumentList     = 'build', '-Doptimize=ReleaseSafe'
    WorkingDirectory = $zls
    FilePath         = $(
        if ($buildFromSource) { "$zig\stage3\bin\zig.exe" }
        else { "$ziglang\release\zig.exe" }
    )
}
$building = Start-Process @buildArgs -PassThru -NoNewWindow
$building.WaitForExit()
if ($building.ExitCode -ne 0) { throw "Failed building zls." }
Write-Host -Object "Built zls."

# add paths
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
$newPaths = @(
    "$zls\zig-out\bin"
    if ($buildFromSource) { "$zig\stage3\bin" } else { "$ziglang\release" }
)
foreach ($path in $newPaths) {
    if (-not $paths.Contains($path)) {
        Write-Host -Object "Adding '$path' to path"
        $paths += $path
        $Env:Path = $Env:Path + "$path;"
    }
}

# remove old paths
$removePath = if ($buildFromSource) { "$ziglang\release" } else { "$zig\stage3\bin" }
if ($paths.Contains($removePath)) {
    Write-Host -Object "Removing '$removePath' from path"
    $paths = $paths -ne $removePath
}
[Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User')

# Set environment variables
Write-Host -Object "Setting Environment Variables..."
if ($buildFromSource -and $Env:ZIG -ne $zig) {
    [Environment]::SetEnvironmentVariable('ZIG', $zig, 'User')
    Write-Host -Object "`$Env:ZIG -> '$zig'"
}
if ($Env:ZLS -ne $zls) {
    [Environment]::SetEnvironmentVariable('ZLS', $zls, 'User')
    Write-Host -Object "`$Env:ZLS -> '$zls'"
}
Get-Job | Wait-Job | Out-Null
Write-Host -Object "Finished." -ForegroundColor Green
