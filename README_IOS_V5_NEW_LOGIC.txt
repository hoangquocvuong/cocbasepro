COCBASE AI iOS V5 — parity with Android free/ad-supported model

PRODUCT
- All users are free.
- No Premium vs Free distinction.
- No monthly/yearly subscription.
- No per-user search credits.
- No manual/auto level selector.
- Search is image-only.

SEARCH API
POST https://api.cocbasepro.com/image-search/api/search
multipart field: image

SEARCH FLOW
- Cache / Source DB first.
- External web discovery only when local data cannot answer.
- 429 monthly provider capacity does not disable known Source DB searches.

ADS
Production iOS AdMob IDs retained from the uploaded iOS project:
- Banner: ca-app-pub-9371341402256787/4621781605
- Interstitial: ca-app-pub-9371341402256787/2615399517
- Rewarded: ca-app-pub-9371341402256787/2152365082

Ad logic:
- Banner shown to all users unless 15-minute Ad-Free reward is active.
- Interstitial eligible after 4 searches and at least 90 seconds since the previous interstitial.
- Search never requires an ad.
- Voluntary Rewarded Ad -> 15 minutes Ad-Free.
- During Ad-Free: banner hidden and interstitial suppressed.

COMMUNITY
- Compact donation card under the search area.
- Live donation status from https://seo.cocbaseai.com/api/donate-status
- Support button -> https://buymeacoffee.com/cocbase
- Bottom nav: Home / Saved / Support / More with vector Material icons.

REMOVED
- in_app_purchase dependency.
- StoreKit subscription UI.
- Premium paywall.
- Search-credit gating.
- Level picker.
