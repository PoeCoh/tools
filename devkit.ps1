# iex "& {$(irm git.poecoh.com/tools/zig/devkit.ps1)} -Path $ZigRepo"
[CmdletBinding()]
param (
    $Path
)

try {
    $temp = "$Env:TEMP\ziglang"
    if (Test-Path -Path $temp) { Remove-Item -Path $temp -Recurse -Force }
    $content = Get-Content -Path "$Path\ci\x86_64-windows-debug.ps1"
    $version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
    $url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    Invoke-WebRequest -Uri $url -OutFile "$temp\devkit.zip"
    Expand-Archive -Path "$temp\devkit.zip" -DestinationPath $temp -Force
    Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer }).FullName -NewName "devkit"
    Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
    return $true
}
catch {
    return $false
}