# Homebrew cask for Sidle.
# Publish by putting this file at Casks/sidle.rb in a repository named
# github.com/rp6186030/homebrew-sidle. Users then run:
#   brew install --cask rp6186030/sidle/sidle
cask "sidle" do
  version "1.0.1"
  sha256 :no_check

  url "https://github.com/rp6186030/sidle/releases/download/v#{version}/Sidle-#{version}.zip"
  name "Sidle"
  desc "Volume, brightness and media seek on the trackpad edges"
  homepage "https://github.com/rp6186030/sidle"

  depends_on macos: ">= :sonoma"

  app "Sidle.app"

  uninstall quit: "com.rajpatel.sidle"
  zap trash: "~/Library/Preferences/com.rajpatel.sidle.plist"

  caveats <<~EOS
    Sidle is not notarized. If macOS refuses to open it, run once:
      xattr -dr com.apple.quarantine /Applications/Sidle.app
    Then grant Accessibility when Sidle asks.
  EOS
end
