cask "retrasmetter" do
  version "0.1.0"
  sha256 "b1d024025d94704d6c6ce8dfb84c75683cfd2d56e20b4e3eb3e0d2cf0fa58b29"   # shasum -a 256 Retrasmetter.dmg

  url "https://github.com/FrolkinKoticov/retrasmetter/releases/download/#{version}/retrasmetter.dmg"
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
