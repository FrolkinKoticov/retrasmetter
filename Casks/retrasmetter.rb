cask "retrasmetter" do
  version "0.1.0"
  sha256 "0086ab2d397ecfb3a645f1cbd0b5a9197ac2550edbd2b3908436a5f0d0f5af8e"   # shasum -a 256 Retrasmetter.dmg

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
