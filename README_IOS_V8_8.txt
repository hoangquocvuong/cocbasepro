8.8.0+19 — Rewarded unlock recovery and VIP copy
- Rewarded load timeout 12s; native load invocation no longer blocks callback timeout.
- Separate loading, reward verification and external launch status in a reserved top row, not a bottom Snackbar.
- Reward claim polls for approximately 18s (individual storage/launch operations can add time). Retry preserves pending reward and verified link for 23h. No unverified unlock.
- External launch has an 8s timeout. iOS opens the verified layout externally, not a WebView popup.
- Both membership sheets share identical curated VIP link benefit and schedule text.
- Existing StoreKit, AdMob, Firebase and API configuration unchanged.
- Backend SSV configuration and claim endpoint behavior must be validated on TestFlight. Flutter/Xcode unavailable in packaging environment; run flutter pub get, flutter analyze, then TestFlight build.
- Test: no fill, failed show, dismissed ad, earned reward with delayed SSV, launch failure/retry, banner present/absent, VIP instant copy, both membership sheets.
