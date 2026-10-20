cask "retrasmetter" do
  version "0.1.0"
  # Replace with the real hash once the release exists:  shasum -a 256 Retrasmetter.dmg
  sha256 :no_check

  url "https://github.com/FrolkinKoticov/retrasmetter/releases/download/v#{version}/Retrasmetter.dmg"
  name "Retrasmetter"
  desc "Dictionary layer for visual novels and JRPGs on macOS"
  homepage "https://github.com/FrolkinKoticov/retrasmetter"

  depends_on macos: ">= :sonoma"

  app "Retrasmetter.app"

  zap trash: [
    "~/Library/Application Support/GameLanguageCompanion",
    "~/Library/Preferences/dev.retrasmetter.app.plist",
  ]
end
