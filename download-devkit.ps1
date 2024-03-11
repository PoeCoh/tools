# iex "& {$(irm git.poecoh.com/tools/zig/download-devkit.ps1)}"
# Downloads devkit for version to $Env:TEMP\ziglang\devkit
# Requires path to zig repo (or to be run in the repo directory) to see version
[CmdletBinding()]
param ($RepoPath = './')
try {
    $temp = "$Env:TEMP\ziglang"
    if (-not (Test-Path -Path $temp)) { New-Item -Path $temp -ItemType Directory -Force | Out-Null }
    if (Test-Path -Path "$temp\devkit") { Remove-Item -Path "$temp\devkit" -Recurse -Force }
    $content = Get-Content -Path "$RepoPath\ci\x86_64-windows-debug.ps1"
    $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
    $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
    Invoke-WebRequest -Uri $url -OutFile "$temp\devkit.zip"
    $devkit = Expand-Archive -Path "$temp\devkit.zip" -DestinationPath $temp -Force -PassThru
    $devKit = $devKit.FullName.where({$_ -match 'zig\.exe'})
    $devKit = Resolve-Path -Path "$devKit\..\.."
    Write-Debug -Message "Devkit: $devKit"
    Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer -and $_.Name -match 'zig'}).FullName -NewName "devkit"
    Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
    return $true
}
catch {
    return $false
}