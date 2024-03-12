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
$buildFromSource = $Source.IsPresent
$windowStyle = if ($PSBoundParameters.ContainsKey('Debug')) { 'Normal' } else { 'Hidden' }

# create ziglang directory if it doesn't exist
New-Item -Path $ziglang -ItemType Directory -Force | Out-Null

Write-Host -Object "Downloading latest release build..."
$release = Start-Job -WorkingDirectory $zig -ScriptBlock {
    $ziglang = $using:ziglang
    $dir = "$ziglang\release"
    $zip = "$dir`.zip"
    $hash = if (Test-Path -Path $zip) {
        Get-FileHash -Path $zip -Algorithm SHA256
        Remove-Item -Path $zip -Recurse -Force | Out-Null
    } else { $null }
    $response = Invoke-WebRequest -Uri 'https://ziglang.org/download#release-master'
    $url = if ($PSVersionTable.PSVersion.Major -eq 5) {
        $response.Links.Where({ $_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64' }).href
    } else {
        $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
        [regex]::new('<a href=(https://[^">]+)>').Match($href).Groups[1].Value
    }
    Invoke-WebRequest -Uri $url -OutFile $zip
    if (
        $null -ne $hash -and
        $hash.Hash -eq $(Get-FileHash -Path $zip -Algorithm SHA256).Hash -and
        (Test-Path -Path $dir)
    ) { return }
    if (Test-Path -Path $dir) { Remove-Item -Path $dir -Recurse -Force }
    $folder = Expand-Archive -Path $zip -DestinationPath $ziglang -Force -PassThru |
        Where-Object -FilterScript { $_.FullName -match 'zig\.exe$' }
    Resolve-Path -Path "$folder\.." | Rename-Item -NewName 'release'
}

# for use later
$devkitBlock = {
    $ziglang = $using:ziglang
    $zig = $using:zig
    $dir = "$ziglang\devkit"
    $zip = "$ziglang\devkit.zip"
    $content = Get-Content -Path "$zig\ci\x86_64-windows-debug.ps1"
    $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
    $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
    $hash = if (Test-Path -Path $zip) {
        $hash = Get-FileHash -Path $zip -Algorithm SHA256
        Remove-Item -Path $zip -Recurse -Force | Out-Null
    } else {$null}
    Invoke-WebRequest -Uri $url -OutFile $zip
    if (
        $null -ne $hash -and
        $hash.Hash -eq $(Get-FileHash -Path $zip -Algorithm SHA256).Hash -and
        (Test-Path -Path $dir)
    ) { return }
    if (Test-Path -Path $dir) { Remove-Item -Path $dir -Recurse -Force }
    $folder = Expand-Archive -Path $zip -DestinationPath $ziglang -Force -PassThru |
        Where-Object -FilterScript { $_.FullName -match 'zig\.exe$' }
    Resolve-Path -Path "$folder\..\.." | Rename-Item -NewName 'devkit'
}

$gitSplat = @{
    FilePath = 'git'
    WorkingDirectory = ''
    ArgumentList = $null
    WindowStyle = $windowStyle
}

# Start cloning/pulling zig
if ($buildFromSource) {
    $cloneZig = (Test-Path -Path "$zig\.git") -eq $false
    $gitSplat.WorkingDirectory = if ($cloneZig) { $ziglang } else { $zig }
    $gitSplat.ArgumentList = $(
        if ($cloneZig) { 'clone', 'https://github.com/ziglang/zig' }
        else { 'pull', 'origin' }
    )
    Write-Host -Object "$(if ($cloneZig) { 'Cloning' } else { 'Pulling' }) zig..."
    $gitZig = Start-Process @gitSplat -PassThru
}

# Start cloning/pulling zls
$cloneZls = (Test-Path -Path "$zls\.git") -eq $false
$gitSplat.WorkingDirectory = if ($cloneZls) { $ziglang } else { $zls }
$gitSplat.ArgumentList = $(
    if ($cloneZls) { 'clone', 'https://github.com/zigtools/zls' }
    else { 'pull', 'origin' }
)
Write-Host -Object "$(if ($cloneZls) { 'Cloning' } else { 'Pulling' }) zls..."
$gitZls = Start-Process @gitSplat -PassThru

# build zig
if ($BuildFromSource) {
    # we need zig cloned/updated to get the version for devkit
    $gitZig.WaitForExit()
    if ($gitZig.ExitCode -ne 0) { throw "Failed to clone or pull zig." }
    Write-Host -Object "$(if ($cloneZig) { 'Cloned' } else { 'Pulled' }) zig."

    # Download devkit, requires data from zig repo
    Write-Host -Object "Downloading devkit..."
    Start-Job -ScriptBlock $devkitBlock | Wait-Job | Out-Null
    Write-Host -Object "Extracted devkit."

    # Build zig with devkit
    Write-Host -Object "Building Zig with devkit..."
    $buildArgs = @{
        FilePath = "$ziglang\devkit\bin\zig.exe"
        WorkingDirectory = $zig
        WindowStyle = $windowStyle
        ArgumentList = @(
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
        )
    }
    if ($ReleaseSafe.IsPresent) { $buildArgs.ArgumentList += '-Doptimize=ReleaseSafe' }
    $build = Start-Process @buildArgs -PassThru
    $build.WaitForExit()

    # try building with release
    if ($build.ExitCode -ne 0) {
        Write-Host -Object "Failed. Building Zig with latest release."
        Wait-Job -Job $release | Out-Null
        $buildArgs.FilePath = "$ziglang\release\zig.exe"
        $build = Start-Process @buildArgs -PassThru
        $build.WaitForExit()
    }

    # fallback to just using release build
    if ($build.ExitCode -ne 0) {
        Write-Host -Object "Failed. Falling back to release build"
        $buildFromSource = $false
    }

    if ($build.ExitCode -eq 0) { Write-Host -Object "Built Zig." }
} else {
    Wait-Job -Job $release | Out-Null
    Write-Host -Object "Extracted release build."
}

# We need git to finish before we can build zls
$gitZls.WaitForExit()
if ($gitZls.ExitCode -ne 0) { throw "Failed to clone or pull zls." }
Write-Host -Object "$(if ($cloneZls) { 'Cloned' } else { 'Pulled' }) zls."

# build zls
Write-Host -Object "Building zls..."
$buildArgs = @{
    ArgumentList = 'build', '-Doptimize=ReleaseSafe'
    WorkingDirectory = $zls
    WindowStyle = $windowStyle
    FilePath = if ($buildFromSource) { "$zig\stage3\bin\zig.exe" }
               else { "$ziglang\release\zig.exe" }
}
$building = Start-Process @buildArgs -PassThru
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
[Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null

# Set environment variables
Write-Host -Object "Setting Environment Variables..."
if ($buildFromSource -and $Env:Zig -ne $zig) { [Environment]::SetEnvironmentVariable('ZIG', $zig, 'User') | Out-Null }
if ($buildFromSource) { Write-Host -Object "`$Env:ZIG -> '$zig'" }
if ($Env:ZLS -ne $zls) { [Environment]::SetEnvironmentVariable('ZLS', $zls, 'User') | Out-Null }
Write-Host -Object "`$Env:ZLS -> '$zls'"
