Base Layout Pro iOS V7.4.0+6

Fix: iOS long-background WKWebView/Firebase freeze.

V7.3 only checked DOM health. A WKWebView can still have a valid DOM while
its JavaScript/Firebase runtime is stale after iOS reclaims/suspends the web
content process.

V7.4 behavior:
- Background < 15 seconds: preserve seamless resume; no forced reload.
- Background >= 15 seconds: ALWAYS perform a real WKWebView reload.
- This recreates website JavaScript and Firebase runtime from scratch.
- reload() has a 6-second timeout.
- If reload fails/hangs, fallback to fresh loadRequest(last known internal URL).
- Fresh navigation has an 8-second timeout.
- Network/main-frame recovery still probes WebView, but probe itself has a
  3-second timeout so a hung JS process cannot block recovery forever.
- Last valid CocBasePro URL is preserved.
- Existing navigation/menu/ads/news/theme logic is otherwise unchanged.
