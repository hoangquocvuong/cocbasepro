Base Layout Pro iOS V5 — Fast Startup + Simple Ads + Web-Matched Menu

STARTUP
- runApp() happens immediately.
- Firebase and AdMob are initialized after the first Flutter frame.
- WebView starts loading cocbasepro.com immediately.
- No subscription initialization at startup.
- No Google Fonts dependency in the native shell.

SUBSCRIPTION
- Removed in_app_purchase dependency and all Monthly / Yearly subscription logic.

ADMOB
- Existing production iOS interstitial: ca-app-pub-9371341402256787/5085734937
- No ad on startup.
- No rewarded gate.
- Interstitial after 5 meaningful internal page loads.
- First interstitial no earlier than 60 seconds.
- 120-second minimum cooldown.
- Browsing never waits for an ad.

PREMIUM LINKS
- /e/<id> links are resolved directly with premium-map.json and open Clash of Clans.
- Regular Buy Me a Coffee donation links are blocked inside iOS.

MENU
- Current cocbasepro.com mobile navigation, with Donate removed:
  Home / News / Find Source / Saved / More
- Native menu height: 52dp.
- More: Town Hall / Builder Hall / Capital Hall / Events / Rankings / Hero Skins / All Bases.

VERSION
- 5.0.0+12
