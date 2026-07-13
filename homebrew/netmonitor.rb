cask "netmonitor" do
  version "1.11.0"
  sha256 :no_check  # replace with actual SHA after first release

  url "https://github.com/pangziqiang/NetMonitor/releases/download/v#{version}/NetMonitor-#{version}.dmg"
  name "NetMonitor"
  desc "macOS menu bar network & system monitor"
  homepage "https://github.com/pangziqiang/NetMonitor"

  depends_on macos: ">= :sonoma"  # macOS 14+

  app "NetMonitor.app"

  # NetMonitor requires Accessibility permission for floating window
  # and reads system network/sensor data via IOKit (no special entitlements)

  zap trash: [
    "~/Library/Application Support/NetMonitor",
    "~/Library/Preferences/com.opencode.NetMonitor.plist",
    "~/Library/Caches/NetMonitor",
  ]
end
