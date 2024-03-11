# iex "& {$(irm git.poecoh.com/tools/zig/download-release.ps1)}"
[CmdletBinding()]
param ()
try {
    $temp = "$Env:TEMP\ziglang"
    if (-not (Test-Path -Path $temp)) { New-Item -Path $temp -ItemType Directory -Force | Out-Null }
    $response = Invoke-WebRequest -Uri "https://ziglang.org/download#release-master"
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        $url = $response.Links.Where({$_.innerHTML -ne 'minisig' -and $_.href -match 'builds/zig-windows-x86_64'}).href
    } else {
        $href = $response.Links.Where({ $_ -match 'builds/zig-windows-x86_64' -and $_ -notmatch 'minisig' }).outerHTML
        $url = [regex]::new("<a href=(https://[^"">]+)>").Match($href).Groups[1].Value
    }
    Invoke-WebRequest -Uri $url -OutFile "$temp\release.zip"
    Expand-Archive -Path "$temp\release.zip" -DestinationPath $temp -Force
    Rename-Item -Path (Get-ChildItem -Path $temp).where({ $_.PSIsContainer -and $_.Name -ne 'devkit' }).FullName -NewName "release"
    Get-ChildItem -Path $temp -Filter "*.zip" | Remove-Item -Recurse -Force
    return $true
}
catch {
    return $false
}