# iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)}"
# Downloads devkit for version to $Env:TEMP\ziglang\devkit
# Requires path to zig repo (or to be run in the repo directory) to see version
[CmdletBinding()]
param ($RepoPath = './')
try {
    Write-Host -Object "Downloading devkit..."
    $ziglang = "$Env:LOCALAPPDATA\ziglang"
    if (-not (Test-Path -Path $ziglang)) { New-Item -Path $ziglang -ItemType Directory -Force | Out-Null }
    if (Test-Path -Path "$ziglang\devkit") { Remove-Item -Path "$ziglang\devkit" -Recurse -Force }
    $content = Get-Content -Path "$RepoPath\ci\x86_64-windows-debug.ps1"
    $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
    $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
    Invoke-WebRequest -Uri $url -OutFile "$ziglang\devkit.zip"
    $devkit = Expand-Archive -Path "$ziglang\devkit.zip" -DestinationPath $ziglang -Force -PassThru
    $devKit = $devKit.FullName.where({$_ -match 'zig\.exe'})
    $devKit = Resolve-Path -Path "$devKit\..\.."
    Rename-Item -Path $devKit -NewName "devkit"
    Get-ChildItem -Path $ziglang -Filter "*.zip" | Remove-Item -Recurse -Force
    return $true
    Write-Host -Object 'Done'
}
catch {
    return $false
}