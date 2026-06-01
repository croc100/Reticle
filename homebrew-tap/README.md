# homebrew-reticle

Homebrew tap for [Reticle](https://github.com/croc100/Reticle) — the free, open-source ShareX-style screenshot tool for macOS.

## Install

```bash
brew tap croc100/reticle
brew install --cask reticle
```

## First launch

Reticle is currently unsigned. On first launch:
1. Right-click `Reticle.app` in Applications → **Open**
2. Confirm in the dialog
3. Grant **Screen Recording** permission when prompted

Or remove quarantine via Terminal:
```bash
xattr -dr com.apple.quarantine /Applications/Reticle.app
```

## Update

```bash
brew upgrade --cask reticle
```
