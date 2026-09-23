<#
.SYNOPSIS
Points bucket/hanki-tools.json at the latest Hanki Tools release.

.DESCRIPTION
Reads the latest (non-pre-release) release of hankitools/hankitools-windows, finds its Windows x64
ZIP and the matching .sha256 file, and updates the manifest's version, URL, hash and extract
folder. The ZIP's top folder has the same name as the ZIP. Nothing changes when the manifest is
already current. Run by .github/workflows/update.yml; works in Windows PowerShell 5.1 and PowerShell 7.
#>
$ErrorActionPreference = 'Stop'
$manifestPath = [IO.Path]::Combine($PSScriptRoot, '..', 'bucket', 'hanki-tools.json')
$headers = @{ 'User-Agent' = 'hanki-scoop-bucket'; 'Accept' = 'application/vnd.github+json' }
if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }

$release = Invoke-RestMethod 'https://api.github.com/repos/hankitools/hankitools-windows/releases/latest' -Headers $headers
$version = $release.tag_name -replace '^v', ''
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Unexpected release tag '$($release.tag_name)'." }
# The portable x64 ZIP; a signed release may drop "unsigned" from the name.
$zip = @($release.assets | Where-Object { $_.name -match '^HankiTools-[\d.]+-win-x64[\w-]*\.zip$' })[0]
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

# Edit the values in place so the file keeps its layout.
$folder = [IO.Path]::GetFileNameWithoutExtension($zip.name)
$raw = $raw.Replace("""version"": ""$($manifest.version)""", """version"": ""$version""")
$raw = $raw.Replace("""url"": ""$($x64.url)""", """url"": ""$($zip.browser_download_url)""")
$raw = $raw.Replace("""hash"": ""$($x64.hash)""", """hash"": ""$hash""")
$raw = $raw.Replace("""extract_dir"": ""$($x64.extract_dir)""", """extract_dir"": ""$folder""")
$check = $raw | ConvertFrom-Json
if ($check.version -ne $version -or $check.architecture.'64bit'.hash -ne $hash) { throw 'Manifest update did not apply cleanly.' }
[IO.File]::WriteAllText($manifestPath, $raw, (New-Object Text.UTF8Encoding $false))
"hanki-tools updated from $($manifest.version) to $version ($($zip.name))."
