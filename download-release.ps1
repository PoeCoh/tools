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
    $temp = "$Env:TEMP\ziglang"
    if (-not (Test-Path -Path $temp)) { New-Item -Path $temp -ItemType Directory -Force | Out-Null }
    if (Test-Path -Path "$temp\release") { Remove-Item -Path "$temp\release" -Recurse -Force }
    $response = Invoke-WebRequest -Uri "https://ziglang.org/download#release-master"
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        $url = $response.Links.Where({$_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64'}).href
    } else {
        $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
        $url = [regex]::new("<a href=(https://[^"">]+)>").Match($href).Groups[1].Value
    }
    Invoke-WebRequest -Uri $url -OutFile "$temp\release.zip"
    $release = Expand-Archive -Path "$temp\release.zip" -DestinationPath $temp -Force -PassThru
    Write-Debug -Message "Release: $($release.FullName.where({$_ -match 'zig\.exe'}))"
    Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer -and $_.Name -match 'zig' }).FullName -NewName "release"
    Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
    return $true
    if ($Path.IsPresent) {
        $paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';').TrimEnd('\').where({ $_ -ne '' })
        if (-not $paths.Contains("$temp\release")) {
            $paths += "$temp\release"
            [Environment]::SetEnvironmentVariable('Path', "$($paths -join ';');", 'User') | Out-Null
            $Env:Path = $Env:Path + ';' + "$temp\release" + ';'
        }
    }
}
catch {
    return $false
}
