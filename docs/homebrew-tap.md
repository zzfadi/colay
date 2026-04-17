# Homebrew tap for colay

Homebrew expects casks to live in a repo named `homebrew-<tap>`. To make `brew tap zzfadi/colay` work, create a separate public repo named **`homebrew-colay`** with the file below, then tag releases in `zzfadi/colay` — the cask downloads the DMG the release workflow produces.

## One-time setup

```bash
gh repo create zzfadi/homebrew-colay --public --description "Homebrew tap for colay"
git clone https://github.com/zzfadi/homebrew-colay.git
cd homebrew-colay
mkdir -p Casks
```

Create `Casks/colay.rb` with the template below (fill in `version`, `sha256`) and push.

## Cask template — `Casks/colay.rb`

```ruby
cask "colay" do
  version "0.1.0"
  sha256 "REPLACE_ME_WITH_DMG_SHA256"

  url "https://github.com/zzfadi/colay/releases/download/v#{version}/colay-#{version}.dmg"
  name "colay"
  desc "Procedural macOS desktop companion"
  homepage "https://github.com/zzfadi/colay"

  depends_on macos: ">= :ventura"

  app "colay.app"

  zap trash: [
    "~/Library/Preferences/com.zzfadi.colay.plist",
    "~/Library/Caches/com.zzfadi.colay",
  ]
end
```

## Updating after each release

The release workflow writes the SHA-256 next to the DMG (`colay-<ver>.dmg.sha256`). After a new tag is pushed:

```bash
# Grab values from the release
curl -sL https://github.com/zzfadi/colay/releases/download/v0.2.0/colay-0.2.0.dmg.sha256

# Edit Casks/colay.rb: bump `version`, paste the hash into `sha256`
git commit -am "colay 0.2.0"
git push
```

Users then update with `brew update && brew upgrade --cask colay`.

## Automating the bump (optional)

Add a job to `.github/workflows/release.yml` (in this repo) that uses `macauley/action-homebrew-bump-formula` or a small `gh api` script to open a PR against the tap. For a solo maintainer the manual two-line edit is usually faster than wiring up the token plumbing.
