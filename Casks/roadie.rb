cask "roadie" do
  version "0.14.0"
  sha256 :no_check

  url "https://github.com/guthubrx/roadie/releases/download/v#{version}/Roadie.dmg"
  name "Roadie"
  desc "Tiling window manager (BSP, Tabbed BSP, Scrolling), stages, switcher and Alfred-compatible launcher for macOS"
  homepage "https://github.com/guthubrx/roadie"

  depends_on macos: ">= :sonoma"

  app "Roadie.app"
  binary "#{appdir}/Roadie.app/Contents/Resources/roadie"

  postflight do
    # Roadie n'est pas encore notarisé par Apple : lever proprement la quarantaine locale.
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Roadie.app"],
                   must_succeed: false
  end

  uninstall launchctl: "com.roadie.roadied",
            quit:      "com.roadie.roadied"

  zap trash: [
    "~/Library/LaunchAgents/com.roadie.roadied.plist",
    "~/.roadies",
    "~/.config/roadie",
  ]

  caveats <<~EOS
    Roadie is not Apple-notarized yet; Homebrew clears the local quarantine attribute on install.
    Quick start (no BetterTouchTool required):
      1. Initialize a default config with autonomous shortcuts (if not already present):
           roadie config init --preset standard
      2. Launch Roadie and grant Accessibility permission in System Settings > Privacy & Security > Accessibility:
           open -a Roadie
      3. Check health:
           roadie daemon health
  EOS
end
