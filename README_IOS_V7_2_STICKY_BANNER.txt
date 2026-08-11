Base Layout Pro iOS V7.2 — Sticky AdMob Banner

Added native AdMob banner using the new iOS banner unit:
ca-app-pub-9371341402256787/6534238850

Behavior:
- Banner request starts about 8 seconds after AdMob SDK initialization.
- Keeps cold-start/navigation performance from V7.1.
- Banner is native and sticky at the bottom of the app, directly ABOVE the
  compact native iOS navigation menu.
- It never overlays the WebView or the navigation buttons.
- Banner is hidden when offline, while the More sheet/menu is open, or while
  an interstitial is being shown.
- Existing interstitial and rewarded-support logic is unchanged.
- Existing iOS AdMob app ID in Info.plist already matches:
  ca-app-pub-9371341402256787~7637088103

Version: 7.2.0+3
