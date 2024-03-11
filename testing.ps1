<#
iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)}"

based off of https://github.com/ziglang/zig/wiki/Building-Zig-on-Windows
Sets environment variables ZIG and ZLS to thier respective repositories
This script doubles as an update script

to pass flags to the script, append them like this:
iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Source -Test -Legacy -ReleaseSafe -Debug"

I split the download sections off into their own thing so they can be used independently
#>
[CmdletBinding()]
param (    
    # Bypasses Legacy check
    [parameter()]
    [switch]$Legacy,
    
    # Builds zig from source
    [parameter()]
    [switch]$Source,
    
    # Passes ReleaseSafe to zig build
    [parameter()]
    [switch]$ReleaseSafe,
    
    # Runs zig build test
    [parameter()]
    [switch]$Test
)

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"
$pwshExe = [Diagnostics.Process]::GetCurrentProcess().Path

if ($PSVersionTable.PSVersion.Major -eq 5 -and -not $Legacy.IsPresent) {
    Write-Host -Object "Legacy powershell takes drastically longer, please install and use powershell 7+."
    # No, really, legacy was shockingly slow.
    Write-Host -Object "If you must use legacy powershell, add -Legacy to the command to ignore this."
    Write-Host -Object 'iex "& {$(irm git.poecoh.com/tools/zig/install.ps1)} -Legacy"' -ForegroundColor DarkYellow
    return
}

# create ziglang directory if it doesn't exist
if (-not (Test-Path -Path $ziglang)) {
    New-Item -Path $ziglang -ItemType Directory -Force | Out-Null
}

# Start downloading release build
Write-Host -Object "Starting release build download..."
$dlReleaseArgs = @{
    FilePath = $pwshExe
    ArgumentList = @(
        "-Command"
        "
            Set-Location -Path $ziglang;
            iex ""& {
                `$(irm git.poecoh.com/tools/zig/download-release.ps1)
            } $(if (-not $Source.IsPresent) { "-Path" })"";
        "
    )
}
$dlRelease = Start-Process $dlReleaseArgs -PassThru

# Start cloning/pulling zig
if ($Source.IsPresent) {
    $cloneZig = (Test-Path -Path "$zig\.git") -eq $false
    $gitZigArgs = @{
        FilePath = 'git'
        WorkingDirectory = if ($cloneZig) { $ziglang } else { $zig }
        ArgumentList = if ($cloneZig) { 'clone', 'https://github.com/ziglang/zig' }
                       else { 'pull', 'origin' }
        # WindowStyle = 'Hidden'
    }
    $gitZig = Start-Process @gitZigArgs -PassThru
}

# Start cloning/pulling zls
$cloneZls = (Test-Path -Path "$zls\.git") -eq $false
$gitZlsArgs = @{
    FilePath = 'git'
    WorkingDirectory = if ($cloneZls) { $ziglang } else { $zls }
    ArgumentList = if ($cloneZls) { 'clone', 'https://github.com/zigtools/zls' }
                   else { 'pull', 'origin' }
    # WindowStyle = 'Hidden'
}
$gitZls = Start-Process @gitZlsArgs -PassThru

# build zig
if ($Source.IsPresent) {
    # we need the git cloned/updated to get the version for the devkit
    $gitZig.WaitForExit()
    if ($gitZig.ExitCode -ne 0) { throw "Failed to clone or pull zig." }
    
    # Download devkit
    $result = iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)} -RepoPath '$zig'"
    if (-not $result) { throw "Failed to download devkit." }

    # We need the release build to build zig (usually)
    $dlRelease.WaitForExit()
    if ($dlRelease.ExitCode -ne 0) { throw "Failed to download release build." }

    # Build zig
    Write-Host -Object "Building Zig..."
    $buildingArgs = @{
        FilePath = "$ziglang\release\zig.exe"
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
    if ($ReleaseSafe.IsPresent) { $buildingArgs.ArgumentList += '-Doptimize=ReleaseSafe' }
    $building = Start-Process @buildingArgs -PassThru
    $building.WaitForExit()
    Write-Debug -Message "Exit Code: $($building.ExitCode)"
    if ($building.ExitCode -ne 0) { throw "Failed to build zig." }

    # Clean up
    Get-ChildItem -Path $ziglang | ForEach-Object -Process {
        if ($_.Name -match 'devkit|release') {
            Remove-Item -Path $_.FullName -Recurse -Force
        }
    }
    Write-Host -Object "Done"

    # Set zig path and environment variable
    $paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
    if (-not $paths.Contains("$zig\stage3\bin")) {
        Write-Host -Object "Adding zig to path"
        $paths += "$zig\stage3\bin"
        [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
        $Env:Path = $Env:Path + ';' + "$zig\stage3\bin" + ';'
    }
    [Environment]::SetEnvironmentVariable('ZIG', $zig, 'User') | Out-Null
    Write-Host -Object "`$Env:ZIG -> '$zig'"
}

# We need git to finish before we can build zls
$gitZls.WaitForExit()
if ($gitZls.ExitCode -ne 0) { throw "Failed to clone or pull zls." }

# build zls
Write-Host -Object "Building zls..."
$buildArgs = @{
    FilePath = if ($Source.IsPresent) { "$zig\stage3\bin\zig.exe" }
               else { "$ziglang\release\zig.exe" }
    ArgumentList = 'build', '-Doptimize=ReleaseSafe'
    WorkingDirectory = $zls
}
$building = Start-Process @buildArgs -PassThru
$building.WaitForExit()
Write-Debug -Message "Exit Code: $($building.ExitCode)"
if ($building.ExitCode -ne 0) { throw "Failed building zls." }
Write-Host -Object "Done"

# Set zls path and environment variable
$paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
if (-not $paths.Contains("$zls\zig-out\bin")) {
    Write-Debug -Message "Adding zls to path"
    $paths += "$zls\zig-out\bin"
    [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
    $Env:Path = $Env:Path + ';' + "$zls\zig-out\bin" + ';'
}
[Environment]::SetEnvironmentVariable('ZLS', $zls, 'User') | Out-Null
Write-Host -Object "`$Env:ZLS -> '$zls'"

# Run zig build test
if ($Test.IsPresent) {
    Write-Host -Object "Running zig build test"
    Start-Procenss -FilePath "zig" -ArgumentList "build", "test" -Wait -NoNewWindow -WorkingDirectory $zig
}
Write-Host -Object "Done" -ForegroundColor Green

# Open ziglang directory
Start-Process -FilePath 'explorer' -ArgumentList $ziglang