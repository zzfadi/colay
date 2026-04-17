# Releasing colay

## One-time setup

### 1. Apple Developer credentials (for trusted / notarized releases)

From [developer.apple.com](https://developer.apple.com/account):

1. Create a **Developer ID Application** certificate. Download the `.cer`, double-click to add to your login keychain, then export it as `.p12` from Keychain Access (right-click → Export). Give it a password.
2. Create an **app-specific password** at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords. Label it "colay notary".
3. Note your **Team ID** — visible at the top-right of developer.apple.com.

Convert the `.p12` to base64 so it fits in a GitHub secret:

```bash
base64 -i colay-developer-id.p12 | pbcopy
```

Add these as repository secrets (`gh secret set …` or Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12` | base64 from above |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | password used when exporting |
| `KEYCHAIN_PASSWORD` | any random string (used only on the CI runner) |
| `APPLE_ID` | your Apple developer email |
| `APPLE_ID_PASSWORD` | the app-specific password from step 2 |
| `APPLE_TEAM_ID` | 10-char team ID |

CLI form:

```bash
gh secret set DEVELOPER_ID_APPLICATION_P12          < /tmp/p12.b64
gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD -b 'YOUR_P12_PASSWORD'
gh secret set KEYCHAIN_PASSWORD                     -b "$(openssl rand -hex 16)"
gh secret set APPLE_ID                              -b 'you@example.com'
gh secret set APPLE_ID_PASSWORD                     -b 'xxxx-xxxx-xxxx-xxxx'
gh secret set APPLE_TEAM_ID                         -b 'ABCD123456'
```

The release workflow runs with or without these secrets. Without them you still get a DMG, but it's ad-hoc signed and triggers the "unidentified developer" warning on macOS.

### 2. Homebrew tap (optional, for `brew install`)

Follow [docs/homebrew-tap.md](homebrew-tap.md) to create the `zzfadi/homebrew-colay` repo once.

## Cutting a release

```bash
# 1. Make sure main is green
gh run list --limit 1

# 2. Bump version references if any (README, CHANGELOG, etc.)

# 3. Tag and push
git tag -a v0.1.0 -m "first public release"
git push origin v0.1.0
```

The `release` workflow will:

1. Build a universal (arm64 + x86_64) `colay.app`
2. Sign with the Developer ID (or ad-hoc if secrets missing)
3. Notarize + staple (if all Apple credentials are set)
4. Package into `colay-<version>.dmg`
5. Emit `colay-<version>.dmg.sha256`
6. Publish a GitHub Release with both files attached + auto-generated notes

## Updating the Homebrew cask

After the release is live, copy the SHA-256 from the release asset and bump `Casks/colay.rb` in `zzfadi/homebrew-colay`:

```bash
curl -sL https://github.com/zzfadi/colay/releases/download/v0.1.0/colay-0.1.0.dmg.sha256
```

## Testing the pipeline locally

```bash
scripts/build-app.sh 0.1.0-dev
scripts/sign-and-notarize.sh          # ad-hoc unless env vars set
scripts/make-dmg.sh 0.1.0-dev
open build/colay-0.1.0-dev.dmg
```

> If you get "resource fork, Finder information, or similar detritus not allowed" when signing locally, your working directory is inside iCloud Drive / a FileProvider-synced folder that re-stamps `com.apple.FinderInfo` on every directory. Either build inside `/tmp` or ignore it — the CI runner is not synced, so the release workflow is clean.

## Rolling back

If a release is broken:

```bash
gh release delete v0.1.0 --yes --cleanup-tag
# then fix the underlying code, re-tag
```
