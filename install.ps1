# iex "& {$(iwr 'https://raw.githubusercontent.com/PoeCoh/tools/zig/install.ps1')}
[CmdletBinding()]
param (
    [parameter()]
    [string]$Path = "./"
)

$ziglang = "$Env:LOCALAPPDATA\ziglang"
$zig = "$ziglang\zig"
$zls = "$ziglang\zls"
$temp = "$Env:TEMP\ziglang"

if (-not (Test-Path -Path $ziglang)) { New-Item -Path $ziglang -ItemType Directory -Force | Out-Null }
Start-Process -FilePath "git" -ArgumentList "clone", "https://github.com/ziglang/zig" -Wait -NoNewWindow -WorkingDirectory $ziglang
$content = Get-Content -Path "$zig\ci\x86_64-windows-debug.ps1"
$version = ($content[1] -Split 'TARGET')[1].TrimEnd('"')
$url = "https://ziglang.org/deps/zig+llvm+lld+clang-x86_64-windows-gnu$version.zip"
if (-not (Test-Path -Path $temp)) { New-Item -Path $temp -ItemType Directory -Force | Out-Null }
Invoke-WebRequest -Uri $url -OutFile "$temp\devkit.zip"
Expand-Archive -Path "$temp\devkit.zip" -DestinationPath $temp -Force
Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer }).FullName -NewName "devkit"
Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
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
Start-Process -FilePath "$temp\devkit\bin\zig.exe" -ArgumentList $argList -Wait -NoNewWindow -WorkingDirectory $zig
if (-not (Test-Path -Path "$zig\stage3\bin\zig.exe")) {
    $response = Invoke-WebRequest -Uri "https://ziglang.org/download#release-master"
    $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
    $url = [regex]::new("<a href=(https://[^"">]+)>").Match($href).Groups[1].Value
    Invoke-WebRequest -Uri $url -OutFile "$temp\release.zip"
    Expand-Archive -Path "$temp\release.zip" -DestinationPath $temp -Force
    Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer -and $_.Name -ne 'devkit' }).FullName -NewName "release"
    Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
}
$paths = [System.Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
if (-not $paths.Contains("$zig\stage3\bin")) {
    $paths += "$zig\stage3\bin"
    [System.Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
}
Start-Process -FilePath "git" -ArgumentList "clone", "https://gitbub.com/zigtools/zls" -Wait -NoNewWindow -WorkingDirectory $ziglang
Start-Process -FilePath "$zig\stage3\bin\zig.exe" -ArgumentList 'build', '-Doptimize=ReleaseSafe' -Wait -NoNewWindow -WorkingDirectory $zls
