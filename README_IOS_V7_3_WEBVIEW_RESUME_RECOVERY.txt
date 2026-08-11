Base Layout Pro iOS V7.3 — WKWebView Background Resume Recovery

Problem:
After iOS keeps the app in background for a while, WKWebView's content process can be reclaimed. The Flutter controller may still exist while page JavaScript and Firebase runtime are gone.

Fix:
- Track when the app enters background.
- On resume after 20s+, probe the live WKWebView document with JavaScript.
- Detect blank/about:blank/missing body/non-ready/empty document or probe failure.
- Healthy page: keep it and reapply iOS web mode + News badge.
- Unhealthy page: automatically reopen the last valid CocBasePro URL.
- Persist the last successful internal URL with SharedPreferences.
- Main-frame errors and network-restored events also trigger a health check.
- Recovery cooldown prevents reload loops.
- Short app switches do not force reload.
- Existing seamless navigation, native menu, ads, theme and News logic are preserved.

Version: 7.3.0+5
