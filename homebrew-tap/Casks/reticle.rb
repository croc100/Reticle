cask "reticle" do
  version "0.1.0"
  sha256 :no_check  # Replace with actual SHA-256 after first release DMG is built

  url "https://github.com/croc100/Reticle/releases/download/v#{version}/Reticle-#{version}.dmg"
  name "Reticle"
  desc "Free, open-source ShareX-style screenshot tool for macOS"
  homepage "https://croc100.github.io/Reticle/"

  # macOS 13 Ventura or later required
  depends_on macos: ">= :ventura"

  app "Reticle.app"

  # Unsigned build — Gatekeeper will block by default.
  # Users must right-click → Open on first launch, or run:
  #   xattr -dr com.apple.quarantine /Applications/Reticle.app
  caveats do
    <<~EOS
      Reticle is not yet notarized. On first launch, right-click the app
      and choose "Open", then confirm in the dialog.

      Alternatively, remove the quarantine flag:
        xattr -dr com.apple.quarantine /Applications/Reticle.app

      Grant Screen Recording permission when prompted — it is required
      for all capture functionality.
    EOS
  end
end
