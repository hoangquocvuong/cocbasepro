BASE LAYOUT PRO iOS 8.0.0+10 — DEVELOPMENT SOURCE
Base: supplied V5_4 archive (pubspec 7.2.0+8). Existing bundle ID preserved.
Backend: https://ios-api.basecoc.net/api/ios (V1.9).

Windows: open cocbasepro in Android Studio. Run flutter pub get, flutter analyze, flutter test.
macOS: Xcode and Flutter required. Add your actual GoogleService-Info.plist to ios/Runner using Xcode, with Runner target membership. Enable Push Notifications and Background Modes > Remote notifications, use matching Apple signing/provisioning. Run flutter pub get; cd ios; pod install; cd ..; flutter build ipa.
Minimum iOS 16 (StoreKit transaction environment). An iOS 15 device is not supported by this draft.

Implemented source: existing WebView UI with basecoc.net, native membership sheet, StoreKit 2 purchase/restore/current entitlement bridge with appAccountToken, HTTPS session in Keychain, server verification, native ad-free VIP and banner for FREE, rewarded SSV claim with retry, notifications settings/inbox/email OTP and opt-in FCM registration. No interstitial implementation. No secret credentials included.

NOT RELEASE READY: Flutter/Dart analyzer and Xcode SDK unavailable in creation environment; Swift syntax parsed only. Actual server contracts for classify/inbox/OTP/register, website paths/JS and premium link interception must be checked on device. Confirm privacy URL and update old WebView navigation routes as needed. Only protected links matching https://seo.cocbaseai.com/api/premium/base/<32 hex> are handled by native unlock. Website must not expose raw VIP links. Firebase plist not supplied. Push tap routing and FREE new-base campaigns not implemented. StoreKit Sandbox not granted production VIP by backend design. Legacy tokenless purchases and lost/expired sessions require backend recovery before release; no unsafe reassignment by transaction ID. Production ad units present; use approved test devices and avoid live ad clicks. Configure consent/privacy requirements before live ads. Verify login/session recovery, user data deletion requirements, StoreKit sandbox, refunds, real SSV, OTP, push, ad behavior, and App Store compliance before distribution.
