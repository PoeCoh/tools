# iex "& {$(irm git.poecoh.com/tools/zig/download-release.ps1)}"
# If you just want to download and use the release directly, you can add -Path
# iex "& {$(irm git.poecoh.com/tools/zig/download-release.ps1)} -Path"
# to add the folder to your user path variable
# Downloads newest release build to $Env:TEMP\ziglang\release
[CmdletBinding()]
param (
    [parameter()]
    [switch]$Path
)
try {
    Write-Host -Object "Downloading release build..."
    $ziglang = "$Env:LOCALAPPDATA\ziglang"
    if (-not (Test-Path -Path $ziglang)) { New-Item -Path $ziglang -ItemType Directory -Force | Out-Null }
    if (Test-Path -Path "$ziglang\release") { Remove-Item -Path "$ziglang\release" -Recurse -Force }
    $response = Invoke-WebRequest -Uri "https://ziglang.org/download#release-master"
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        $url = $response.Links.Where({$_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64'}).href
    } else {
        $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
        $url = [regex]::new("<a href=(https://[^"">]+)>").Match($href).Groups[1].Value
    }
    Invoke-WebRequest -Uri $url -OutFile "$ziglang\release.zip"
    $release = Expand-Archive -Path "$ziglang\release.zip" -DestinationPath $ziglang -Force -PassThru
    $release = $release.FullName.where({$_ -match 'zig\.exe'})
    $release = Resolve-Path -Path "$release\.."
    Rename-Item -Path $release -NewName "release"
    Get-ChildItem -Path $ziglang -Filter "*.zip" | Remove-Item -Recurse -Force
    if ($Path.IsPresent) {
        $paths = [Environment]::GetEnvironmentVariable('Path', 'User').TrimEnd(';').Split(';').TrimEnd('\')
        if (-not $paths.Contains("$ziglang\release")) {
            $paths += "$ziglang\release"
            [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
            $Env:Path = $Env:Path + ';' + "$ziglang\release" + ';'
        }
    }
    Write-Host -Object 'Done'
    return $true
}
catch {
    return $false
}
