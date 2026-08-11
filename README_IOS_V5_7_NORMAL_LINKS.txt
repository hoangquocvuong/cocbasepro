Base Layout Pro iOS V5.7

Simplified link handling:
- Removed all Buy Me a Coffee interception from the iOS app.
- News article links open normally like any other external URL.
- Premium /e/ links are no longer parsed or mapped by the app.
- The website remains responsible for premium-link mapping.
- Removed premium-map.json logic from the app.
- Removed unused http dependency.

Navigation:
- cocbasepro.com stays inside WebView.
- firebaseio.com page navigations are blocked.
- all other external URLs open normally in the external browser.

Version: 5.7.0+21
