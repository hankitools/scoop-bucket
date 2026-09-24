<#
.SYNOPSIS
Points bucket/hanki-tools.json at the newest Hanki Tools release.

.DESCRIPTION
Reads the newest published release of hankitools/hankitools-windows, previews included (tagged
vVERSION-preview, such as v0.18.0-rc.7-preview), finds its Windows x64 ZIP and the matching .sha256
file, and updates the manifest's version, URL, hash and extract folder. The ZIP's top folder has the
same name as the ZIP. Nothing changes when the manifest is already current. Run by
.github/workflows/update.yml; works in Windows PowerShell 5.1 and PowerShell 7.
#>
$ErrorActionPreference = 'Stop'
$manifestPath = [IO.Path]::Combine($PSScriptRoot, '..', 'bucket', 'hanki-tools.json')
$headers = @{ 'User-Agent' = 'hanki-scoop-bucket'; 'Accept' = 'application/vnd.github+json' }
if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }

# The newest published release, previews included; the website's download button offers the same one.
# Assigned first: Windows PowerShell 5.1 returns a JSON array as one object, which piping the variable unrolls.
$releases = Invoke-RestMethod 'https://api.github.com/repos/hankitools/hankitools-windows/releases?per_page=20' -Headers $headers
$release = @($releases | Where-Object { -not $_.draft } | Sort-Object { [DateTimeOffset]$_.published_at } -Descending)[0]
if (-not $release) { throw 'No published Hanki Tools release found.' }
$version = $release.tag_name -replace '^v', '' -replace '-preview$', ''
if ($version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$') { throw "Unexpected release tag '$($release.tag_name)'." }
# The portable x64 ZIP; a signed release may drop "unsigned" from the name, and previews add "preview".
$zip = @($release.assets | Where-Object { $_.name -match '^HankiTools-\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?-win-x64[\w-]*\.zip$' })[0]
$sum = @($release.assets | Where-Object { $zip -and $_.name -eq "$($zip.name).sha256" })[0]
if (-not $zip -or -not $sum) { throw "Release $($release.tag_name) has no Windows x64 ZIP with a .sha256 file." }
$checksum = Invoke-WebRequest $sum.browser_download_url -Headers @{ 'User-Agent' = 'hanki-scoop-bucket' } -UseBasicParsing
$text = if ($checksum.Content -is [byte[]]) { [Text.Encoding]::ASCII.GetString($checksum.Content) } else { [string]$checksum.Content }
$hash = ($text.Trim() -split '\s+')[0].ToLowerInvariant()
if ($hash -notmatch '^[0-9a-f]{64}$') { throw "The checksum file for $($zip.name) is not a SHA-256 hash." }

$raw = [IO.File]::ReadAllText($manifestPath)
$manifest = $raw | ConvertFrom-Json
$x64 = $manifest.architecture.'64bit'
if ($manifest.version -eq $version -and $x64.hash -eq $hash -and $x64.url -eq $zip.browser_download_url) { "hanki-tools $version is up to date."; return }

# The ZIP's layout decides extract_dir: Scoop extracts from a single top folder, and previews keep their files
# at the root. The ZIP is read in memory (about 65 MB, only when the version changes) and checked against its hash.
Add-Type -AssemblyName System.IO.Compression
$download = Invoke-WebRequest $zip.browser_download_url -Headers @{ 'User-Agent' = 'hanki-scoop-bucket' } -UseBasicParsing
$stream = $download.RawContentStream; $stream.Position = 0
$actual = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($stream) | ForEach-Object { $_.ToString('x2') })
if ($actual -ne $hash) { throw "$($zip.name) doesn't match its published SHA-256 checksum." }
$stream.Position = 0
$archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read)
try {
    $tops = @($archive.Entries | ForEach-Object { ($_.FullName -split '[\\/]')[0] } | Sort-Object -Unique)
    $nested = @($archive.Entries | Where-Object { $_.FullName -notmatch '[\\/]' }).Count -eq 0
    if (@($archive.Entries | Where-Object { $_.FullName -match '(^|[\\/])HankiTools\.exe$' }).Count -eq 0) { throw "$($zip.name) has no HankiTools.exe." }
} finally { $archive.Dispose() }
$folder = if ($tops.Count -eq 1 -and $nested) { $tops[0] } else { $null }

# Edit the values in place so the file keeps its layout.
$raw = $raw.Replace("""version"": ""$($manifest.version)""", """version"": ""$version""")
$raw = $raw.Replace("""url"": ""$($x64.url)""", """url"": ""$($zip.browser_download_url)""")
$raw = $raw.Replace("""hash"": ""$($x64.hash)""", """hash"": ""$hash""")
if ($folder -and $x64.extract_dir) { $raw = $raw.Replace("""extract_dir"": ""$($x64.extract_dir)""", """extract_dir"": ""$folder""") }
elseif ($folder) { $raw = $raw.Replace("""hash"": ""$hash""", """hash"": ""$hash"",`n            ""extract_dir"": ""$folder""") }
elseif ($x64.extract_dir) { $raw = $raw -replace (',\r?\n\s*"extract_dir": "' + [regex]::Escape($x64.extract_dir) + '"'), '' }
$check = $raw | ConvertFrom-Json
if ($check.version -ne $version -or $check.architecture.'64bit'.hash -ne $hash -or $check.architecture.'64bit'.extract_dir -ne $folder) { throw 'Manifest update did not apply cleanly.' }
[IO.File]::WriteAllText($manifestPath, $raw, (New-Object Text.UTF8Encoding $false))
"hanki-tools updated from $($manifest.version) to $version ($($zip.name))."
