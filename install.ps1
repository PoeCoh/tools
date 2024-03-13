# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"
# Based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
# To pass flags to the script, append them like this:
# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Debug"

# I don't want to the "IEX is dangerous" argument, a large chunk of linux
# install scripts follow this pattern and the world hasn't burned yet.
[CmdletBinding()]
param ()
$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
trap {
    Write-Host -Object $_.Exception.Message -ForegroundColor Red
    Write-Host -Object 'Waiting for any running jobs to finish...'
    Get-Job | Wait-Job | Remove-Job
    Write-Host -Object 'Exiting.'
    return
}

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"
$builtFromSource = $true

function Start-SmartJob {
    param ( $Name = $Null, $ScriptBlock, $ArgumentList )
    if (Get-Command -Name 'Start-ThreadJob' 2>$null) {
        Start-ThreadJob -Name $Name -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
        Start-Job -Name $Name -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}

$downloadBlock = {
    param ( $Uri, $Destination, $OutFile )
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    $folders = Expand-Archive -Path $OutFile -DestinationPath $Destination -Force -PassThru
    $folders = $folders -split '\\'
    $index = [array]::IndexOf($folders, 'ziglang') + 1
    $folders[0..$index] -join '\'
}

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

Write-Host -Object 'Fetching devkit and latest release build...'
$release = Start-SmartJob -Name 'Fetching Release' -ScriptBlock $downloadBlock -ArgumentList @(
    $releaseUrl
    $ziglang
    "$ziglang\release.zip"
)
$devkit = Start-SmartJob -Name 'Fetching Devkit' -ScriptBlock $downloadBlock -ArgumentList @(
    $devkitUrl
    $ziglang
    "$ziglang\devkit.zip"
)

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
Write-Host -Object 'Got devkit and release build.'
$releaseDir = Receive-Job -Job $release
$devkitDir = Receive-Job -Job $devkit
Copy-Item -Path "$releaseDir\lib" -Destination "$devkitDir\lib" -Recurse -Force
Copy-Item -Path "$releaseDir\zig.exe" -Destination "$devkitDir\bin\zig.exe" -Force

Start-SmartJob -Name 'Removing Files' -ScriptBlock {
    param ( $Files )
    Remove-Item -Path $Files -Recurse -Force
} -ArgumentList @(
    @( $releaseDir, "$ziglang\devkit.zip", "$ziglang\release.zip" )
) | Out-Null

$gitZig.WaitForExit()
if ($gitZig.ExitCode -ne 0) { throw 'Failed to clone or pull zig.' }
Write-Host -Object "$(if ($cloneZig) { 'Cloned' } else { 'Pulled' }) zig."

# Build zig with devkit
Write-Host -Object 'Building zig...'
$buildArgs = @{
    FilePath         = "$devkitDir\bin\zig.exe"
    WorkingDirectory = $zig
    ArgumentList     = @(
        'build'
        '-p'
        'stage3'
        '--search-prefix'
        $devkitDir
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
    Write-Host -Object 'Failed. Building ZLS with release build for now.'
    $builtFromSource = $false
}

if ($build.ExitCode -eq 0) {
    Write-Host -Object 'Built zig.'
    Start-SmartJob -Name 'Removing File' -ScriptBlock {
        param ( $File )
        Remove-Item -Path $File -Recurse -Force
    } -ArgumentList $devkitDir | Out-Null
}

# We need git to finish before we can build zls
$gitZls.WaitForExit()
if ($gitZls.ExitCode -ne 0) { throw 'Failed to clone or pull zls.' }
Write-Host -Object "$(if ($cloneZls) { 'Cloned' } else { 'Pulled' }) zls."

# build zls
Write-Host -Object 'Building zls...'
$buildArgs = @{
    ArgumentList     = 'build', '-Doptimize=ReleaseSafe'
    WorkingDirectory = $zls
    FilePath         = $(
        if ($builtFromSource) { "$zig\stage3\bin\zig.exe" }
        else { "$ziglang\release\zig.exe" }
    )
}
$building = Start-Process @buildArgs -PassThru -NoNewWindow
$building.WaitForExit()
if ($building.ExitCode -ne 0) { throw 'Failed building zls.' }
Write-Host -Object 'Built zls.'

# add paths
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
$newPaths = @(
    "$zls\zig-out\bin"
    if ($builtFromSource) { "$zig\stage3\bin" }
)
foreach ($path in $newPaths) {
    if (-not $paths.Contains($path)) {
        Write-Host -Object "Adding '$path' to path"
        $paths += $path
        $Env:Path = $Env:Path + "$path;"
    }
}
[Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User')

# Set environment variables
Write-Host -Object 'Setting Environment Variables...'
if ($Env:ZIG -ne $zig) {
    [Environment]::SetEnvironmentVariable('ZIG', $zig, 'User')
    Write-Host -Object "`$Env:ZIG -> '$zig'"
}
if ($Env:ZLS -ne $zls) {
    [Environment]::SetEnvironmentVariable('ZLS', $zls, 'User')
    Write-Host -Object "`$Env:ZLS -> '$zls'"
}

# Wait for any loose ends to finish
Get-Job | Wait-Job | Remove-Job
Write-Host -Object 'Finished.' -ForegroundColor Green