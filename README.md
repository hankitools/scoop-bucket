# Hanki Tools for Scoop

**+ A little sisu for your PC.** Install [Hanki Tools](https://hanki.tools/) with
[Scoop](https://scoop.sh/), the command-line installer for Windows.

```powershell
scoop bucket add hanki https://github.com/hankitools/scoop-bucket
scoop install hanki/hanki-tools
```

Scoop downloads the portable app from
[GitHub Releases](https://github.com/hankitools/hankitools-windows/releases), checks it against the
published SHA-256 checksum, unpacks it and adds **Hanki Tools** to the Start menu.

- Update: `scoop update hanki-tools`
- Remove: `scoop uninstall hanki-tools`. Scan history and recovery records stay in
  `%LOCALAPPDATA%\IgezziGuard`; delete that folder too if you want them gone.

Hanki Tools isn't code-signed yet, so Windows may show a SmartScreen warning the first time it
starts. See the [code signing policy](https://github.com/hankitools/hankitools-windows#code-signing-policy).

## How this bucket stays current

`.github/workflows/update.yml` runs every six hours. It reads the newest Hanki Tools release (previews included, as on hanki.tools) and,
when there is a new one, updates `bucket/hanki-tools.json` (version, download URL, checksum) and
commits it. You can also run it from the Actions tab or locally:

```powershell
powershell -ExecutionPolicy Bypass -File bin\update-manifest.ps1
```

The app's source, issues and privacy details live in
[hankitools/hankitools-windows](https://github.com/hankitools/hankitools-windows).
