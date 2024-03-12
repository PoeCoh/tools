# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"
# Based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
# To pass flags to the script, append them like this:
# PS> iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Source -ReleaseSafe -Debug"
[CmdletBinding()]
param (    
    # Builds zig from source
    [parameter()]
    [switch]$Source,

    # Passes ReleaseSafe to zig build
    [parameter()]
    [switch]$ReleaseSafe
)

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"


# create ziglang directory if it doesn't exist
New-Item -Path $ziglang -ItemType Directory -Force | Out-Null

Write-Host -Object "Downloading release build..."

function Get-ReleaseBuild {
    param ( [string]$Dir )
    if (Test-Path -Path "$Dir\release.zip") {
        $hash = Get-FileHash -Path "$Dir\release.zip" -Algorithm SHA256
    }
    if (Test-Path -Path "$Dir\release.zip") {
        Remove-Item -Path "$Dir\release.zip" -Recurse -Force
    }
    $response = Invoke-WebRequest -Uri 'https://ziglang.org/download#release-master'
    $url = if ($PSVersionTable.PSVersion.Major -eq 5) {
        $response.Links.Where({ $_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64' }).href
    } else {
        $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
        [regex]::new('<a href=(https://[^">]+)>').Match($href).Groups[1].Value
    }
    Invoke-WebRequest -Uri $url -OutFile "$Dir\release.zip"
    $hash2 = Get-FileHash -Path "$Dir\release.zip" -Algorithm SHA256
    if ($hash -and $hash2.Hash -eq $hash.Hash -and (Test-Path -Path "$Dir\release")) {
        Write-Host -Object "Release build matches prior, skipping extraction."
        return
    }
    if (Test-Path -Path "$Dir\release") {
        Remove-Item -Path "$Dir\release" -Recurse -Force
    }
    $folder = Expand-Archive -Path "$Dir\release.zip" -DestinationPath $Dir -Force -PassThru |
    Where-Object -FilterScript { $_.FullName -match 'zig\.exe$' }
    Resolve-Path -Path "$folder\.." | Rename-Item -NewName 'release'
}

# Start cloning/pulling zig
if ($Source.IsPresent) {
    $cloneZig = (Test-Path -Path "$zig\.git") -eq $false
    $gitZigSplat = @{
        FilePath = 'git'
        WorkingDirectory = if ($cloneZig) { $ziglang } else { $zig }
        WindowStyle = 'Hidden'
        ArgumentList = if ($cloneZig) { 'clone', 'https://github.com/ziglang/zig' }
                       else { 'pull', 'origin' }
    }
    Write-Host -Object "$(if ($cloneZig) { 'Cloning' } else { 'Pulling' }) zig..."
    $gitZig = Start-Process @gitZigSplat -PassThru
}

# Start cloning/pulling zls
$cloneZls = (Test-Path -Path "$zls\.git") -eq $false
$gitZlsSplat = @{
    FilePath = 'git'
    WorkingDirectory = if ($cloneZls) { $ziglang } else { $zls }
    WindowStyle = 'Hidden'
    ArgumentList = if ($cloneZls) { 'clone', 'https://github.com/zigtools/zls' }
                   else { 'pull', 'origin' }
}
Write-Host -Object "$(if ($cloneZls) { 'Cloning' } else { 'Pulling' }) zls..."
$gitZls = Start-Process @gitZlsSplat -PassThru

if (-not $Source.IsPresent) {
    Write-Host -Object "Downloading release build..."
    Get-ReleaseBuild -Dir $ziglang
}

# build zig
if ($Source.IsPresent) {
    # we need zig cloned/updated to get the version for devkit
    $gitZig.WaitForExit()
    if ($gitZig.ExitCode -ne 0) { throw "Failed to clone or pull zig." }
    Write-Host -Object "$(if ($cloneZig) { 'Cloned' } else { 'Pulled' }) zig."

    # Download devkit
    Write-Host -Object "Downloading devkit..."
    $content = Get-Content -Path "$zig\ci\x86_64-windows-debug.ps1"
    $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
    $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
    if (Test-Path -Path "$ziglang\devkit.zip") {
        $hash = Get-FileHash -Path "$ziglang\devkit.zip" -Algorithm SHA256
    }
    if (Test-Path -Path "$ziglang\devkit.zip") {
        Remove-Item -Path "$ziglang\devkit.zip" -Recurse -Force
    }
    Invoke-WebRequest -Uri $url -OutFile "$ziglang\devkit.zip"
    $hash2 = Get-FileHash -Path "$ziglang\devkit.zip" -Algorithm SHA256
    if (-not ($hash -and $hash2.Hash -eq $hash.Hash -and (Test-Path -Path "$ziglang\devkit"))) {
        if (Test-Path -Path "$ziglang\devkit") {
            Remove-Item -Path "$ziglang\devkit" -Recurse -Force
        }
        $folder = Expand-Archive -Path "$ziglang\devkit.zip" -DestinationPath $ziglang -Force -PassThru |
            Where-Object -FilterScript { $_.FullName -match 'zig\.exe$' }
        Resolve-Path -Path "$folder\..\.." | Rename-Item -NewName 'devkit'
        Write-Host -Object "Extracted devkit."
    } else {
        Write-Host -Object "Devkit hash matches prior, skipping extraction."
    }
    
    # Build zig
    Write-Host -Object "Building Zig..."
    $buildArgs = @{
        FilePath = "$ziglang\devkit\bin\zig.exe"
        ArgumentList = @(
            'build'
            '-p'
            'stage3'
            "--search-prefix $ziglang\devkit"
            '--zig-lib-dir lib'
            '-Dstatic-llvm'
            '-Duse-zig-libcxx'
            '-Dtarget=x86_64-windows-gnu'
        )
        WorkingDirectory = $zig
    }
    if ($ReleaseSafe.IsPresent) { $buildArgs.ArgumentList += '-Doptimize=ReleaseSafe' }
    $build = Start-Process @buildArgs -PassThru

    # Start working on backup
    Write-Host -Object "Downloading release build for secondary build method..."
    Get-ReleaseBuild -Dir $ziglang

    $build.WaitForExit()
    if ($build.ExitCode -ne 0) {
        Write-Host -Object "Failed building zig, using release build."

        # try building with release
        $buildArgs.FilePath = "$ziglang\release\zig.exe"
        $build = Start-Process @buildArgs -PassThru
        $build.WaitForExit()
        if ($build.ExitCode -ne 0) { throw "Failed building zig." }
    }
    Write-Host -Object "Built Zig."
}

# We need git to finish before we can build zls
$gitZls.WaitForExit()
if ($gitZls.ExitCode -ne 0) { throw "Failed to clone or pull zls." }
Write-Host -Object "$(if ($cloneZls) { 'Cloned' } else { 'Pulled' }) zls."

# build zls
Write-Host -Object "Building zls..."
$buildArgs = @{
    FilePath = if ($Source.IsPresent) { "$zig\stage3\bin\zig.exe" }
               else { "$ziglang\release\zig.exe" }
    ArgumentList = 'build', '-Doptimize=ReleaseSafe'
    WorkingDirectory = $zls
}
$building = Start-Process @buildArgs -Wait -NoNewWindow -PassThru
$building.WaitForExit()
if ($building.ExitCode -ne 0) { throw "Failed building zls." }

# add paths
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
$newPaths = @(
    "$zls\zig-out\bin"
    if ($Source.IsPresent) { "$zig\stage3\bin" } else { "$ziglang\release" }
)
foreach ($path in $newPaths) {
    if (-not $paths.Contains($path)) {
        Write-Host -Object "Adding '$path' to path"
        $paths += $path
        $Env:Path = $Env:Path + "$path;"
    }
}
[Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null

# Set environment variables
Write-Host -Object "Setting Environment Variables..."
if ($Source.IsPresent -and $Env:Zig -ne $zig) { [Environment]::SetEnvironmentVariable('ZIG', $zig, 'User') | Out-Null }
if ($Source.IsPresent) { Write-Host -Object "`$Env:ZIG -> '$zig'" }
if ($Env:ZLS -ne $zls) { [Environment]::SetEnvironmentVariable('ZLS', $zls, 'User') | Out-Null }
Write-Host -Object "`$Env:ZLS -> '$zls'"
