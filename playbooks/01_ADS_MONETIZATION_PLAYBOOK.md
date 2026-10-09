# HỆ THỐNG QUẢNG CÁO & MONETIZATION TOÀN DIỆN (ADS PLAYBOOK)
> **Dự án áp dụng:** Mọi dự án Flutter / Android đa nền tảng  
> **Mục tiêu:** Tối ưu hóa Show Rate (>90%), Match Rate (>85-95%), eCPM cao nhất, triệt tiêu 100% Request rác, chống AdMob phạt thuật toán (Low Viewability / Spam Request), và trải nghiệm người dùng mượt mà.

---

## MỤC LỤC
1. [Bài Học Xương Máu & Nguyên Nhân Bị AdMob Phạt (Case Study 20/9 & 25/9)](#1-bài-học-xương-máu--nguyên-nhân-bị-admob-phạt-case-study-209--259)
2. [8 Nguyên Tắc Vàng Trong Triển Khai Ads](#2-8-nguyên-tắc-vàng-trong-triển-khai-ads)
3. [Kiến Trúc Tầng Ads Chuẩn (Clean Architecture Ads Layer)](#3-kiến-trúc-tầng-ads-chuẩn-clean-architecture-ads-layer)
4. [Tối Ưu Từng Định Dạng Quảng Cáo (Format Optimization)](#4-tối-ưu-từng-định-dạng-quảng-cáo-format-optimization)
   - [4.1. Interstitial Ads (Back & Action Triggers)](#41-interstitial-ads-back--action-triggers)
   - [4.2. Rewarded Ads (Unlock Content Flow)](#42-rewarded-ads-unlock-content-flow)
   - [4.3. Native Ads (Lazy Viewport & Static Slot Recycling)](#43-native-ads-lazy-viewport--static-slot-recycling)
   - [4.4. App Resume Interstitial Ads (Anti-Loop & State Preservation)](#44-app-resume-interstitial-ads-anti-loop--state-preservation)
   - [4.5. Banner Ads & Anti-Layout Shift](#45-banner-ads--anti-layout-shift)
5. [Chuẩn Hóa UMP Consent & Tuân Thủ Chính Sách Châu Âu (GDPR & Privacy Options)](#5-chuẩn-hóa-ump-consent--tuân-thủ-chính-sách-châu-âu-gdpr--privacy-options)
   - [5.1. Bốn Rủi Ro Chết Người Khi Triển Khai UMP Sai Cách](#51-bốn-rủi-ro-chết-người-khi-triển-khai-ump-sai-cách)
   - [5.2. Decision Table Phân Loại Trạng Thái Consent](#52-decision-table-phân-loại-trạng-thái-consent)
   - [5.3. Thứ Tự Khởi Tạo Bất Di Bất Dịch (Initialization Order)](#53-thứ-tự-khởi-tạo-bất-di-bất-dịch-initialization-order)
   - [5.4. Lối Vào Privacy Options Bắt Buộc Trong Settings](#54-lối-vào-privacy-options-bắt-buộc-trong-settings)
   - [5.5. Mã Nguồn Mẫu Chuẩn & Testability Pattern](#55-mã-nguồn-mẫu-chuẩn--testability-pattern)
6. [Quy Trình Startup & Đồng Bộ In-App Purchase (IAP)](#6-quy-trình-startup--đồng-bộ-in-app-purchase-iap)
7. [Quản Lý Môi Trường & Remote Config An Toàn](#7-quản-lý-môi-trường--remote-config-an-toàn)
8. [Checklist Trước Khi Release Bản Build](#8-checklist-trước-khi-release-bản-build)

---

## 1. Bài Học Xương Máu & Nguyên Nhân Bị AdMob Phạt (Case Study 20/9 & 25/9)

### 1.1. Hiện tượng & Số liệu sự cố Case Study 20/9
* **Đột biến Request rác:** Số lượng request tăng vọt từ ~200 req/ngày lên **15,187 requests** (gấp 80 lần), nhưng chỉ có **3,428 impressions** (thất thoát >75% ad đã tải).
* **Match Rate sụp đổ:** Match Rate rơi tự do từ **93.6% xuống 48.8%** (Native chỉ match 44%, Banner chỉ match 6%). Show Rate Interstitial chỉ đạt **49%**, Rewarded chỉ **30%**.
* **Thuật toán AdMob trừng phạt:** Google nhận diện app gửi request ảo ồ ạt mà không hiển thị (*Low Viewability / Ad Spam*) $\rightarrow$ **Tự động bóp Fill Rate** và **hạ giá sàn eCPM xuống đáy** ($0.25 cho Native).

```
╔════════════════════════════════════════════════════════════════════════════════════════════╗
║  Định dạng      Requests     Matched     Impressions     Show Rate (Imp/Matched)     eCPM  ║
╠════════════════════════════════════════════════════════════════════════════════════════════╣
║  Native          10,692       4,715         2,154                45.68%             $0.25  ║
║  Interstitial     1,884       1,860           918                49.35%             $1.19  ║
║  Rewarded           463         463           140                30.23%             $2.10  ║
║  Banner (18-19)     450          62            36               ~58.00% (Match 6%)  $0.11  ║
╚════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

### 1.2. Hiện tượng & Số liệu sự cố Case Study 25/9 (Release Bản 1.0.7 - Bùng phát `ad_load_failed`)
* **Số liệu Firebase Analytics:** 16 users (`first_open`), 29 `session_start`, 43 `app_ad_impression`, nhưng có tới **36 `ad_load_failed`** (~45% số lần load bị thất bại).
* **Nguyên nhân chính:** 
  1. **`disposeSlot()` khi đóng Bottom Sheet:** User mở các sheet kích hoạt/xem thử theme rồi đóng lại hoặc chuyển sang Cài đặt hệ thống $\rightarrow$ `dispose()` gọi `nativeGroup.disposeSlot()` hủy ngay lập tức request mạng in-flight $\rightarrow$ AdMob báo `onAdFailedToLoad` / SDK dispatch `ad_load_failed`.
  2. **Timeout On-Demand Interstitial 4s quá ngắn:** Luồng App Resume và Show ad không dialog đặt timeout 4s. Mạng di động 3G/4G (Ấn Độ, Iraq, Algeria) có RTT cao (300–600ms) cần 5–8s để hoàn tất đấu thầu $\rightarrow$ Timeout 4s cắt ngang làm thất thoát ad.
  3. **Eager-load do transient layout exception:** `_checkViewportVisibility` trong khối `catch (_)` kích hoạt tải cả thẻ `index > 0` khi frame đầu tiên chưa hoàn tất layout.
  4. **Spam Native request dồn dập:** Mở Home $\rightarrow$ Theme Preview $\rightarrow$ Theme Test $\rightarrow$ Activate Sheet gửi liên tiếp 4-5 request Native trong 10s $\rightarrow$ AdMob rate-limit và trả về `ERROR_CODE_NO_FILL (3)`.

---

### 1.3. Bảng Tổng Hợp 11 Lỗi Lập Trình Gốc Rễ (Root Causes)

| STT | Lỗi kỹ thuật | Cơ chế gây hại | Hậu quả |
|:---:|:---|:---|:---|
| **1** | **Eager-Loading Native Ad trong `SliverToBoxAdapter`** | `SliverToBoxAdapter` chạy `initState()` ngay khi khởi tạo scroll view, tải toàn bộ 5-6 ad ở đáy trang dù user chưa cuộn. | Hàng ngàn ad tải về nhưng 0 impression. |
| **2** | **Dynamic SlotKey theo Category** | `slotKey: 'home_${category}_$index'`. Khi user đổi tab, widget unmount gọi `disposeSlot()` xóa ad vừa tải và bắn thêm 5 request mới. | 20-25 request rác/10s khi user duyệt tab. |
| **3** | **Splash Prefetch lãng phí cho User cũ** | 100% user cũ mở app (`isOnboardingCompleted == true`) vẫn bị ép tải ngầm ad Onboarding. | 100% request này bị vứt bỏ vì không vào Onboarding. |
| **4** | **Native tự ý Fallback sang Banner** | Khi Native ad chưa load xong, code tự render `AdBannerWidget`. 5 thẻ native cùng bắn request đè vào Ad Unit Banner. | Banner bị throttling, Match Rate rớt xuống 6%. |
| **5** | **Timeout 4s/7s quá ngắn & vứt bỏ Ad về muộn** | Mạng 3G/4G (Ấn Độ, Iraq) RTT 5-8s. Sau 4-7s app timeout, ad về muộn nằm trong RAM bị lệnh xóa ở lần bấm sau. | ~50% Interstitial match bị tiêu hủy vô nghĩa. |
| **6** | **Rewarded Ad tự hủy cache trước khi xem** | `if (rewardGroup.isReady) rewardGroup.dispose();` $\rightarrow$ Tự hủy ad có sẵn rồi bắt user tải lại từ đầu. | Tăng thời gian chờ, Show Rate Rewarded rơi xuống 30%. |
| **7** | **MediaView < 120x120 dp trên Video Creative** | Container Native Ad bị co kéo dưới 120dp. | Google SDK Validator chặn hiển thị video, bắn lỗi validation. |
| **8** | **Gọi `disposeSlot()` trong `Widget.dispose()`** | Khi đóng Bottom Sheet hoặc chuyển route, code xóa slot $\rightarrow$ hủy request in-flight, gây lỗi `ad_load_failed` và xóa RAM cache. | Tăng vọt `ad_load_failed`, mất cache, mở lại phải load lại. |
| **9** | **Timeout Interstitial On-Demand chỉ 4s** | App Resume Interstitial chỉ đợi 4s trước khi bỏ cuộc, trong khi AdMob trên mạng 4G cần 5–8s. | App Resume Ad bị bỏ lỡ, request nền bị trôi rác. |
| **10** | **Eager-Load thẻ `index > 0` trong Catch Block** | `_checkViewportVisibility` khi render object chưa layout xong vội vàng gọi `_loadSlot()` cho mọi thẻ. | Các thẻ dưới đáy trang tự động tải khi chưa cuộn tới. |
| **11** | **Bắn dồn dập 4–5 Native Request cùng lúc** | Luồng xem theme $\rightarrow$ thử theme $\rightarrow$ kích hoạt gửi liên tục 4-5 request trong vài giây. | AdMob rate-limit thiết bị, trả về `No Fill (Code 3)`. |

---

## 2. 8 Nguyên Tắc Vàng Trong Triển Khai Ads

1. **Tuyệt đối không Eager-Load trong Danh Sách (List/Grid/Sliver):**
   * Chỉ tải Native Ad khi user cuộn cách thẻ $\le 400\text{px}$ (Viewport Triggered Lazy-Loading). Trong khối `catch (_)`, chỉ cho phép thẻ `index == 0` kích hoạt load.
2. **Cố định SlotKey tĩnh theo vị trí (Static Slot Recycling):**
   * Đặt key theo vị trí màn hình: `home_feed_native_slot_0`, `sticker_feed_native_slot_1`. Không gắn ID động (`category_id`, `theme_id`) vào SlotKey.
3. **Bảo vệ Ad về muộn & Caching trong RAM:**
   * Ad đã tải về máy thành công phải được lưu giữ trong RAM. Lần bấm/mở sau sẽ show tức thì (0s latency).
4. **Quản Lý Vòng Đời Thông Minh (Smart Lifecycle Management) Cho Native Ad:**
   * **Nếu ad ĐÃ ĐƯỢC HIỂN THỊ (`_hasMountedAd == true`):** Chỉ giải phóng slot (`disposeSlot`) khi thực sự cần làm mới ad ở lần mở sau (`disposeOnUnmount: true`). **TUYỆT ĐỐI KHÔNG** gọi `disposeSlot()` đồng bộ bên trong `State.dispose()` mà **bắt buộc hoãn qua `WidgetsBinding.instance.addPostFrameCallback`** vì `RenderAndroidView` của Flutter vẫn đang unmount/resize frame cuối, tránh kích hoạt fallback `getErrorView()` của Google Mobile Ads gây crash `PlatformViewsController.resize NullPointerException` (Issue #1481).
   * **Nếu ad CHƯA KỊP HIỂN THỊ (`_hasMountedAd == false`):** **GIỮ NGUYÊN trong RAM**, không đánh dấu consumed để bảo vệ request in-flight không bị cancel, tránh lỗi `ad_load_failed` và sẵn sàng show tức thì 0s ở lần mở kế tiếp.
5. **Adaptive Timeout 8–10 giây cho On-Demand Interstitial & Rewarded:**
   * Thích ứng mạng 3G/4G độ trễ cao, tránh tình trạng app timeout bỏ qua trong khi AdMob sắp tải xong.
6. **Không Fallback chéo giữa các Format:**
   * Native Ad lỗi $\rightarrow$ Ẩn bằng `const SizedBox.shrink()`. Tuyệt đối không fallback sang Banner.
7. **Đảm bảo kích thước MediaView cho Native Video $\ge 120\times 120\text{ dp}$:**
   * Container chứa MediaView phải có `minWidth = 120dp`, `minHeight = 120dp` để thỏa mãn Google Policy.
8. **Khởi Tạo Ads Theo Chuẩn Google UMP & Cơ Chế Fail-Open 3s Bảo Vệ Doanh Thu:**
   * Chỉ khởi tạo Mobile Ads SDK sau khi Consent đã được phân giải (Google Policy Mandate).
   * Trạng thái đã lưu `notRequired` / `obtained`: Khởi tạo ad ngay lập tức (0s delay), cập nhật ngầm trong background (`unawaited`).
   * Lần đầu mở (`unknown`): Chờ cập nhật tối đa 3 giây; nếu lỗi mạng hoặc timeout thì **Fail-Open (vẫn cho phép ads)** để bảo vệ 100% doanh thu người dùng ngoài EEA (Tier-3).
   * Người dùng EEA (`required`): Mở form và chờ người dùng, **tuyệt đối không áp dụng timeout khi form đang mở**; chỉ nạp ads nếu `canRequestAds() == true`. Cung cấp lối vào Privacy Options trong Cài đặt nếu `isPrivacyOptionsRequired() == true`.

---

## 3. Kiến Trúc Tầng Ads Chuẩn (Clean Architecture Ads Layer)

```
lib/core/
├── services/ads/
│   ├── ads_repository.dart                # Contract interface chuẩn
│   ├── tomo_ads_repository_impl.dart      # Implementation với Adaptive Timeout, Caching & UMP Gating
│   ├── ads_consent.dart                   # Thin wrapper AdsConsentClient & pure decision table
│   ├── ad_cooldown_manager.dart           # State Machine Cooldown & VIP gate
│   └── app_resume_ad_manager.dart         # Quản lý App Resume Interstitial qua Overlay
├── components/
│   ├── app_native_ad_card.dart            # Native card ngang (Lazy Viewport + Static Key)
│   ├── app_vertical_native_ad_card.dart   # Native card dọc
│   ├── banner_ad_widget.dart              # Banner ad với Stream VIP & Anti-shift
│   └── privacy_options_builder.dart       # Builder kiểm tra và mở form GDPR Privacy Options
└── utils/
    └── ads_navigation_helper.dart         # Helper điều phối Back/Action Interstitial an toàn
```

### Contract Interface: `AdsRepository`
```dart
abstract interface class AdsRepository {
  Future<void> initialize();
  bool get isReady;
  bool get isProduction;
  bool get isPremium;
  bool get isAdsEnabled;

  // Interstitial
  Future<void> loadInterstitial();
  bool get isInterstitialReady;
  bool get canShowInterstitial;
  bool get isBackInterstitialEnabled;
  bool get isActionInterstitialEnabled;
  Future<bool> showInterstitial({
    BuildContext? context,
    String? loadingMessage,
    bool showLoadingDialog = true,
    bool ignoreCooldown = false,
  });

  // Rewarded
  Future<void> loadRewarded();
  bool get isRewardedReady;
  Future<RewardResult> showRewardedAd({
    BuildContext? context,
    String? loadingMessage,
    bool showLoadingDialog = true,
  });

  void setPremium({required bool isPremium});
  Stream<bool> get adsEnabledStream;
  void dispose();
}
```

---

## 4. Tối Ưu Từng Định Dạng Quảng Cáo (Format Optimization)

### 4.1. Interstitial Ads (Back & Action Triggers)

#### A. Nâng Timeout lên 10s & Giữ Ad về muộn (Late Ad Caching)
```dart
// lib/core/services/ads/tomo_ads_repository_impl.dart
await interGroup.showWithLoading(
  context: context,
  loadingMessage: loadingMessage ?? 'Loading...',
  timeout: const Duration(seconds: 10), // Thích ứng mạng 3G/4G
  onAdClosed: () {
    _lastInterstitialShownTime = DateTime.now();
    onAdClosed?.call();
  },
  onAdNotReady: onAdNotReady,
);
```

#### B. Helper Điều Hướng An Toàn (`AdsNavigationHelper`)
```dart
abstract final class AdsNavigationHelper {
  static bool _isNavigatingWithAd = false;
  static bool _isActionWithAd = false;

  /// Back Interstitial (Zero-Freeze & Never Traps User + Re-entrancy Lock)
  static Future<void> popWithInterstitial(
    BuildContext context, {
    AdsRepository? adsRepository,
    VoidCallback? onBeforePop,
  }) async {
    if (_isNavigatingWithAd) return;
    _isNavigatingWithAd = true;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final adsRepo = adsRepository ?? (locator.isRegistered<AdsRepository>() ? locator<AdsRepository>() : null);

      final shouldShowAd = adsRepo != null &&
          adsRepo.isAdsEnabled &&
          adsRepo.isBackInterstitialEnabled &&
          adsRepo.canShowInterstitial;

      if (!shouldShowAd) {
        if (context.mounted) {
          onBeforePop?.call();
          _safePop(context);
        }
        return;
      }

      try {
        await adsRepo.showInterstitial(
          context: context,
          loadingMessage: 'Loading...',
        );
      } catch (_) {
        // Luôn bảo đảm pop được gọi
      } finally {
        if (context.mounted) {
          onBeforePop?.call();
          _safePop(context);
        }
      }
    } finally {
      _isNavigatingWithAd = false;
    }
  }

  static void _safePop(BuildContext context, {Object? result}) {
    if (!context.mounted) return;
    final route = ModalRoute.of(context);
    // Tuyệt đối không pop nếu route này đã bắt đầu đóng hoặc không phải route hiện tại
    if (route != null && !route.isCurrent) return;

    try {
      if (context.canPop()) {
        context.pop(result);
        return;
      }
    } catch (_) {}

    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      }
    } catch (_) {}
  }

  // NOTE (Bug Vault): Chi tiết xem bug_vault/flutter/gorouter_ghost_pop_and_double_pop_crash.md

  /// Action Interstitial (Sau khi Save/Apply/Download + Re-entrancy Lock)
  static Future<void> showActionInterstitial(
    BuildContext context, {
    AdsRepository? adsRepository,
    FutureOr<void> Function()? onActionCompleted,
  }) async {
    if (_isActionWithAd) {
      if (context.mounted) {
        await onActionCompleted?.call();
      }
      return;
    }
    _isActionWithAd = true;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final adsRepo = adsRepository ?? (locator.isRegistered<AdsRepository>() ? locator<AdsRepository>() : null);

      final shouldShowAd = adsRepo != null &&
          adsRepo.isAdsEnabled &&
          adsRepo.isActionInterstitialEnabled &&
          adsRepo.canShowInterstitial;

      if (shouldShowAd && context.mounted) {
        try {
          await adsRepo.showInterstitial(
            context: context,
            loadingMessage: 'Loading...',
          );
        } catch (_) {}
      }

      if (context.mounted) {
        await onActionCompleted?.call();
      }
    } finally {
      _isActionWithAd = false;
    }
  }
}
```

* **Bọc Toàn Bộ Màn Hình với PopScope (`wrapWithBackScope`):**
```dart
static Widget wrapWithBackScope({
  required BuildContext context,
  required Widget child,
  VoidCallback? onBeforePop,
  bool enabled = true,
}) {
  if (!enabled) return child;
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && context.mounted) {
        popWithInterstitial(context, onBeforePop: onBeforePop);
      }
    },
    child: child,
  );
}
```

---

### 4.2. Rewarded Ads (Unlock Content Flow)

* **Xóa bỏ hoàn toàn lệnh `dispose()` trước khi show:**
```dart
// ĐÚNG: Tái sử dụng ad trong RAM nếu có sẵn
Future<RewardResult> showRewardedAd({
  BuildContext? context,
  String? loadingMessage,
  bool showLoadingDialog = true,
}) async {
  if (_isPremium) return RewardResult.earned; // VIP được nhận quà ngay
  if (!_config.isAdsEnabled) return RewardResult.unavailable;

  final completer = Completer<RewardResult>();
  await rewardGroup.showWithLoading(
    context: context,
    loadingMessage: loadingMessage ?? 'Loading...',
    timeout: const Duration(seconds: 10),
    onRewardGranted: () => completer.complete(RewardResult.earned),
    onAdClosed: () => _safeComplete(completer, RewardResult.dismissed),
    onAdNotReady: () => _safeComplete(completer, RewardResult.unavailable),
  );
  return completer.future;
}
```

---

### 4.3. Native Ads (Lazy Viewport & Static Slot Recycling)

#### A. Thuật toán phát hiện Viewport thông minh (400px Threshold)
```dart
// lib/core/components/app_native_ad_card.dart
void _checkViewportVisibility() {
  if (_hasTriggeredLoad || !mounted) return;
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) {
    _hasTriggeredLoad = true;
    _loadSlot();
    return;
  }
  final renderObject = context.findRenderObject() as RenderBox?;
  if (renderObject == null || !renderObject.hasSize) return;

  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport == null) {
    _hasTriggeredLoad = true;
    _loadSlot();
    return;
  }

  try {
    final reveal = viewport.getOffsetToReveal(renderObject, 0.0);
    final currentPixels = scrollable.position.pixels;
    final viewportDimension = scrollable.position.viewportDimension;
    // Chỉ kích hoạt tải khi cách vùng nhìn <= 400px
    if (reveal.offset <= currentPixels + viewportDimension + 400) {
      _hasTriggeredLoad = true;
      _scrollPosition?.removeListener(_checkViewportVisibility);
      _loadSlot();
    }
  } catch (_) {
    // Chỉ kích hoạt tải trong catch nếu là thẻ đầu tiên (index == 0)
    if (widget.index == 0) {
      _hasTriggeredLoad = true;
      _loadSlot();
    }
  }
}
```

#### B. Khai báo SlotKey tĩnh và gắn ValueKey cố định trong List
```dart
// Gắn ValueKey và SlotKey tĩnh theo vị trí (Slot Index)
AppNativeAdCard(
  key: ValueKey('home_native_card_$adIndex'),
  slotKey: 'home_feed_native_slot_$adIndex',
  index: adIndex,
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
)
```

#### C. Xử Lý Vòng Đời Thông Minh & Bảo Toàn RAM Cache Khi Unmount
Chỉ giải phóng slot khi ad **đã được hiển thị** lên màn hình (`_hasMountedAd == true`) và không bị widget khác chiếm giữ (`!NativeAdArbiter.isClaimed`). Nếu ad **chưa kịp hiển thị** (`_hasMountedAd == false`), bắt buộc giữ nguyên trong RAM:

```dart
@override
void dispose() {
  _scrollPosition?.removeListener(_checkViewportVisibility);
  NativeAdArbiter.removeWaiter(widget.slotKey, _onSlotFreed);
  NativeAdArbiter.release(widget.slotKey, _token);
  _adsSubscription?.cancel();

  // ── SMART LIFECYCLE MANAGEMENT FOR NATIVE AD ─────────────────
  // Only dispose slot if explicitly requested via [disposeOnUnmount].
  // By default (disposeOnUnmount: false), loaded ads are preserved in RAM for instant 0s display
  // on next opening, completely preventing AdMob spam and No-Fill load failures (code 3).
  // When disposing, defer to post-frame callback so PlatformView completes unmount
  // before the native AdInstanceManager destroys the ad, eliminating resize NPE race condition.
  final slotKey = widget.slotKey;
  final hasMounted = _hasMountedAd;
  final shouldDispose = widget.disposeOnUnmount;
  if (shouldDispose && hasMounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!NativeAdArbiter.isClaimed(slotKey)) {
        final nativeGroup = HorizontalNativeAdManager.instance.getGroup() ??
            MonetizationManager.instance.nativeFeedAdGroup;
        nativeGroup?.disposeSlot(slotKey);
      }
    });
  }
  // ─────────────────────────────────────────────────────────────

  super.dispose();
}
```

#### D. Chống Crash Chiếm View Bằng Token Arbiter (`NativeAdArbiter`)
Khi chuyển tab hoặc chuyển trang, hai widget có thể render cùng một slotKey trong khoảnh khắc giao thoa. Dùng `NativeAdArbiter` để đảm bảo **chỉ có 1 widget duy nhất gắn `AdWidget` tại một thời điểm**:

```dart
// lib/core/components/native_ad_arbiter.dart
class NativeAdArbiter {
  NativeAdArbiter._();
  static final Map<Object, Object> _owners = <Object, Object>{};
  static final Map<Object, Set<VoidCallback>> _waiters = <Object, Set<VoidCallback>>{};

  static bool claim(Object key, Object token) {
    final owner = _owners[key];
    if (owner == null || owner == token) {
      _owners[key] = token;
      return true;
    }
    return false;
  }

  static void release(Object key, Object token) {
    if (_owners[key] != token) return;
    _owners.remove(key);
    final waiters = _waiters[key];
    if (waiters == null || waiters.isEmpty) return;
    final toNotify = List<VoidCallback>.of(waiters);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final notify in toNotify) {
        notify();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  static bool isClaimed(Object key) => _owners.containsKey(key);
  static void addWaiter(Object key, VoidCallback callback) => (_waiters[key] ??= <VoidCallback>{}).add(callback);
  static void removeWaiter(Object key, VoidCallback callback) {
    _waiters[key]?.remove(callback);
    if (_waiters[key]?.isEmpty ?? false) _owners.remove(key);
  }
}
```

#### E. Chống Khựng Hình Khi Cuộn Nhanh (`ScrollJankGuard`)
Khi vuốt với tốc độ cao, việc nạp một PlatformView sẽ gây drop 10-30 frame. Sử dụng `ScrollJankGuard` để hiện Skeleton khi cuộn và chỉ gắn PlatformView khi người dùng dừng tay:

```dart
// lib/core/components/scroll_jank_guard.dart
class ScrollJankGuard extends InheritedNotifier<ValueNotifier<bool>> {
  const ScrollJankGuard({
    required ValueNotifier<bool> notifier,
    required super.child,
    super.key,
  }) : super(notifier: notifier);

  static bool isScrolling(BuildContext context, {bool listen = true}) {
    if (listen) {
      return context
              .dependOnInheritedWidgetOfExactType<ScrollJankGuard>()
              ?.notifier
              ?.value ??
          false;
    }
    return (context
            .getElementForInheritedWidgetOfExactType<ScrollJankGuard>()
            ?.widget as ScrollJankGuard?)
            ?.notifier
            ?.value ??
        false;
  }
}
```

---

### 4.4. App Resume Interstitial Ads (Anti-Loop & State Preservation)

#### A. Thuật Toán State Machine Chống Lặp Vô Tận (Anti-Ad-Loop)
```
[AppLifecycle: paused/hidden] ──> Lưu _pausedAt = DateTime.now
[AppLifecycle: resumed] 
       │
       ├── _isHandlingAd == true? ──> (Vừa đóng ad) ──> Reset cờ, KHÔNG show
       ├── _isResumeFlowActive == true? ──> Bỏ qua (đang chạy)
       ├── Background time < 5s? ──> Bỏ qua (User bấm nhầm)
       ├── isPremium == true? ──> Bỏ qua
       └── Cooldown < minDelay (30s)? ──> Bỏ qua
              │
              └── [ĐỦ ĐIỀU KIỆN] ──> Chèn ResumeSplashOverlay (OverlayEntry)
                                  ──> Show Interstitial
                                  ──> Gỡ Overlay & Cập nhật Cooldown
```

#### B. Chèn Màn Đệm Qua `OverlayEntry` (Không Mất State Màn Hình Cũ)
```dart
// lib/core/ads/app_resume_ad_manager.dart
Future<void> _startResumeFlow() async {
  final overlayState = _navigatorKey.currentState?.overlay;
  if (overlayState == null) return;

  _isResumeFlowActive = true;
  _isHandlingAd = true;
  AdCooldownManager.instance.isAdShowing = true;

  OverlayEntry? overlayEntry = OverlayEntry(
    builder: (_) => const ResumeSplashOverlay(),
  );
  overlayState.insert(overlayEntry);

  final startTime = DateTime.now();
  try {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _onShowInterstitial();
    final elapsed = DateTime.now().difference(startTime);
    const minDuration = Duration(milliseconds: 1200);
    if (elapsed < minDuration) {
      await Future<void>.delayed(minDuration - elapsed);
    }
  } finally {
    overlayEntry?.remove();
    _isResumeFlowActive = false;
    _adHandlingTimer = Timer(const Duration(milliseconds: 500), () {
      _isHandlingAd = false;
      AdCooldownManager.instance.isAdShowing = false;
    });
  }
}
```

---

### 4.5. Banner Ads & Anti-Layout Shift

* **Nguyên tắc:** Khi Banner đang load hoặc no-fill, render `const SizedBox.shrink()`, không để container cố định 50px gây khoảng trắng xấu.
* **Mã Nguồn Widget Hoàn Chỉnh (`BannerAdWidget`):**
```dart
// lib/core/components/banner_ad_widget.dart
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({
    super.key,
    this.boxed = false,
    this.useSafeArea = true,
  });

  final bool boxed;
  final bool useSafeArea;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  StreamSubscription<bool>? _adsSubscription;

  @override
  void initState() {
    super.initState();
    if (locator.isRegistered<AdsRepository>()) {
      _adsSubscription = locator<AdsRepository>().adsEnabledStream.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _adsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adsRepo = locator.isRegistered<AdsRepository>() ? locator<AdsRepository>() : null;
    if (adsRepo != null && (!adsRepo.isAdsEnabled || adsRepo.isPremium)) {
      return const SizedBox.shrink();
    }

    final bannerGroup = MonetizationManager.instance.bannerHomeAdGroup;
    if (bannerGroup == null || !bannerGroup.isEnabled) {
      return const SizedBox.shrink();
    }

    final ad = AdBannerWidget(
      bannerGroup: bannerGroup,
      loadingPlaceholder: const SizedBox.shrink(),
      errorPlaceholder: const SizedBox.shrink(),
    );

    Widget content = widget.boxed
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ad,
          )
        : ad;

    if (widget.useSafeArea) {
      content = SafeArea(top: false, child: content);
    }

    return content;
  }
}
```

#### B. Chiến Lược Vị Trí Đặt Banner (Dwell Time & Viewability Policy)
* **CẤM đặt Banner Ad cố định ở sub-screens có session < 10–15s:**
  * Các màn hình con của Settings (Vibrate Settings, Sound Settings, Language Selection, Theme Test Bar...) là các màn hình tương tác siêu ngắn. Người dùng chỉ vào bật/tắt một công tắc rồi ấn Back ra ngoài.
  * Đặt Banner Ad tại đây làm phát sinh Impression hợp lệ nhưng **thời gian viewability thực tế không đủ 15–30s** $\rightarrow$ Kéo tụt nghiêm trọng eCPM trung bình của Ad Unit Banner toàn app và kích hoạt thuật toán cảnh báo của Google về *Low Viewability / Unintentional Clicks*.
* **Giải pháp thay thế chuẩn:**
  * Bỏ Banner Ad ở các sub-screen này.
  * Tối ưu hóa doanh thu bằng `AdsNavigationHelper.popWithInterstitial(context)` có Cooldown (mặc định 30s) khi người dùng thoát ra ngoài.
  * Chỉ gắn Banner Ad ở các màn hình mà người dùng có **thời gian dừng lớn (Dwell Time > 30s)** như Home Feed, Reading/Typing View, hoặc Editor Workspace.

---

## 5. Chuẩn Hóa UMP Consent & Tuân Thủ Chính Sách Châu Âu (GDPR & Privacy Options)

> **Cảnh báo sống còn:** Việc triển khai Google UMP (User Messaging Platform) cẩu thả là một trong những nguyên nhân hàng đầu khiến ứng dụng **bị Google AdMob giới hạn quảng cáo (Ad Serving Limit)**, **bị từ chối bản build khi Audit Policy**, hoặc **bị mất trắng 100% doanh thu quảng cáo** ở các thị trường Non-EEA do lỗi chặn mạng / timeout sai!

### 5.1. Bốn Rủi Ro Chết Người Khi Triển Khai UMP Sai Cách

1. **Chặn Màn Hình Splash Của 100% User (Kể cả Non-EEA):**
   * *Sai lầm:* Mỗi lần mở app đều `await` request consent update từ mạng mà không phân loại trạng thái đã lưu (`cached consent status`).
   * *Hậu quả:* Người dùng ở Việt Nam, Mỹ, Ấn Độ mở app lần thứ 2, 3 vẫn bị delay 1–3s tại Splash chỉ để chờ UMP trả về `notRequired`.
2. **Timeout Cắt Ngang Form Đang Điền (Hard Timeout Bug):**
   * *Sai lầm:* Đặt timeout 3s/5s bao trùm toàn bộ hàm consent bao gồm cả lúc `ConsentForm` đang hiển thị.
   * *Hậu quả:* User tại châu Âu (EEA) đang đọc form thì timeout kích hoạt $\rightarrow$ app tự nhảy vào trong khi user chưa bấm Đồng ý $\rightarrow$ AdMob nhận diện request không có Consent $\rightarrow$ Vi phạm chính sách GDPR nghiêm trọng.
3. **Khởi Tạo SDK Mobile Ads Trước Hoặc Song Song Với Consent:**
   * *Sai lầm:* Chạy `Future.wait([MobileAds.initialize(), consentUpdate()])`.
   * *Hậu quả:* Theo quy định của Google, khi SDK quảng cáo khởi tạo, các Ad Network Adapter có thể tự động đọc Advertising ID (IDFA / GAID). Nếu chưa có consent hợp lệ của user EEA, Google sẽ phạt tài khoản AdMob vì thu thập dữ liệu trái phép.
4. **"Fail-Closed" Khi Mạng Lỗi - Tiêu Hủy Doanh Thu Tier-3:**
   * *Sai lầm:* Khi UMP `requestConsentInfoUpdate()` bị timeout hoặc lỗi mạng ở lần đầu mở app, code vội vàng đặt `consentAllowsAds = false` và tắt sạch quảng cáo.
   * *Hậu quả:* Đại đa số người dùng nằm ngoài EEA (Tier-3). Nếu họ gặp mạng chập chờn khi mở app lần đầu, toàn bộ quảng cáo trong phiên đó bị tắt $\rightarrow$ Doanh thu rơi tự do về $0.
   * *Giải pháp chuẩn (Fail-Open cho `unknown`):* Khi trạng thái là `unknown` mà bước cập nhật bị lỗi hoặc timeout sau 3s, **vẫn cho phép tải quảng cáo** (`return true`). Nếu người dùng đó thực sự ở EEA, AdMob sẽ tự động áp dụng chính sách Limited Ads an toàn, và form sẽ được kích hoạt lại ở lần mở app tiếp theo.

---

### 5.2. Decision Table Phân Loại Trạng Thái Consent

Hệ thống sử dụng hàm pure Dart `decideConsent` ánh xạ từ `ConsentStatus` (UMP) sang quyết định hành động `AdsConsentDecision`:

```dart
enum AdsConsentDecision { proceed, awaitUpdate, showForm }

AdsConsentDecision decideConsent(ConsentStatus status) => switch (status) {
  ConsentStatus.notRequired ||
  ConsentStatus.obtained => AdsConsentDecision.proceed,
  ConsentStatus.unknown => AdsConsentDecision.awaitUpdate,
  ConsentStatus.required => AdsConsentDecision.showForm,
};
```

| Trạng thái UMP (`ConsentStatus`) | Ý nghĩa thực tế | Quyết định (`AdsConsentDecision`) | Hành vi hệ thống | Tác động Splash |
|:---|:---|:---:|:---|:---:|
| `notRequired` | User ngoài EEA (Việt Nam, Mỹ, Nhật...) | **`proceed`** | Khởi tạo Ads ngay lập tức. Bắn cập nhật nền `unawaited(client.requestUpdate())` | **0ms (Không delay)** |
| `obtained` | User EEA đã đồng ý/từ chối ở phiên trước | **`proceed`** | Khởi tạo Ads ngay lập tức. Bắn cập nhật nền `unawaited(client.requestUpdate())` | **0ms (Không delay)** |
| `unknown` | Lần đầu mở app, chưa rõ vùng địa lý | **`awaitUpdate`** | Chờ cập nhật mạng **tối đa 3 giây**. Nếu thành công $\rightarrow$ đánh giá lại. Nếu LỖI/TIMEOUT $\rightarrow$ **Fail-Open (Cho phép Ads)** | Chờ $\le 3$s duy nhất lần đầu |
| `required` | User EEA cần thu thập Consent | **`showForm`** | Hiển thị `ConsentForm`. **KHÔNG timeout khi form đang mở**. Chỉ cho phép Ads khi `canRequestAds() == true` | Chờ user tương tác xong form |

---

### 5.3. Thứ Tự Khởi Tạo Bất Di Bất Dịch (Initialization Order)

Trong `TomoAdsRepositoryImpl.initialize()` (hoặc tầng Ads Service của mọi dự án):

```dart
@override
Future<void> initialize() async {
  if (_initialized) return;
  _initialized = true;

  // 1. Kích hoạt resolve consent và các tác vụ độc lập (device info, package info)
  final consentFuture = resolveAdsConsent(_consent);

  await Future.wait([
    _fetchDeviceInfo(),
    _fetchPackageInfo(),
  ]);

  // 2. Chờ kết quả phân giải Consent
  _consentAllowsAds = await consentFuture;
  logger.debug('[Ads] consentAllowsAds: $_consentAllowsAds');

  // 3. CHỈ khởi tạo SDK Mobile Ads khi Consent cho phép (Google UMP mandate)
  if (_consentAllowsAds) {
    try {
      await MonetizationManager.instance.initialize(
        testDeviceIds: _testDeviceIds,
      );
    } catch (e) {
      logger.error('[Ads] Failed to initialize Mobile Ads SDK', error: e);
    }
  }

  // 4. Luôn nạp cấu hình nhóm quảng cáo (kể cả khi ads bị disable)
  // Việc nạp với `enableAllAds: false` giúp các instance AdGroup tồn tại ở trạng thái disabled,
  // caller gọi showInterstitial/showRewarded sẽ tự trả về false/null một cách an toàn mà không crash NPE!
  loadConfig(enableAllAds: _consentAllowsAds && !_isPremium && _config.isAdsEnabled);
}
```

---

### 5.4. Lối Vào Privacy Options Bắt Buộc Trong Settings

* **Chính sách bắt buộc của Google:** Với người dùng thuộc khu vực EEA/UK, ứng dụng **phải cung cấp một tùy chọn trong menu Cài đặt** cho phép họ thay đổi lại lựa chọn quyền riêng tư bất kỳ lúc nào.
* **Nguyên tắc UI/UX:**
  - Không được hardcode luôn hiển thị (vì người dùng ngoài EEA bấm vào sẽ không có tác dụng hoặc lỗi).
  - Sử dụng widget `PrivacyOptionsBuilder` gọi `isPrivacyOptionsRequired()`.
  - Nếu `required == true`: Hiển thị dòng **"Privacy Options"** (hoặc "Lựa chọn quyền riêng tư"). Khi chạm vào, gọi `showPrivacyOptionsForm()`.
  - Nếu `required == false`: Widget trả về callback `null`, caller tự động bỏ qua row đó, không để lại khoảng trống hoặc divider thừa trong Card.

---

### 5.5. Mã Nguồn Mẫu Chuẩn & Testability Pattern

#### A. Lớp Bọc Abstraction `AdsConsentClient`
Tách biệt toàn bộ platform channel của Google UMP thành một client mỏng, giúp kiểm thử 100% không phụ thuộc thiết bị:

```dart
// lib/core/services/ads/ads_consent.dart
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdsConsentDecision { proceed, awaitUpdate, showForm }

AdsConsentDecision decideConsent(ConsentStatus status) => switch (status) {
  ConsentStatus.notRequired ||
  ConsentStatus.obtained => AdsConsentDecision.proceed,
  ConsentStatus.unknown => AdsConsentDecision.awaitUpdate,
  ConsentStatus.required => AdsConsentDecision.showForm,
};

/// Lớp client mỏng bọc lấy Google UMP SDK
class AdsConsentClient {
  const AdsConsentClient();

  Future<ConsentStatus> getStatus() =>
      ConsentInformation.instance.getConsentStatus();

  Future<void> requestUpdate() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      completer.complete,
      (FormError e) => completer.completeError(Exception(e.message)),
    );
    return completer.future;
  }

  /// Hiển thị Form nếu cần. Hoàn tất khi form đóng hoặc không yêu cầu. TUYỆT ĐỐI KHÔNG timeout!
  Future<void> showFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((_) => completer.complete());
    return completer.future;
  }

  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  Future<bool> isPrivacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => completer.complete());
    return completer.future;
  }
}

/// Thuật toán giải quyết Consent chuẩn xác và an toàn doanh thu
Future<bool> resolveAdsConsent(
  AdsConsentClient client, {
  Duration updateTimeout = const Duration(seconds: 3),
}) async {
  try {
    var status = await client.getStatus();
    
    // 1. Trạng thái đã lưu (notRequired / obtained): Cho phép tức thì, cập nhật ngầm
    if (decideConsent(status) == AdsConsentDecision.proceed) {
      unawaited(client.requestUpdate().catchError((Object _) {}));
      return true;
    }

    // 2. Trạng thái unknown (lần đầu mở app): Chờ cập nhật tối đa 3s
    try {
      await client.requestUpdate().timeout(updateTimeout);
      status = await client.getStatus();
    } catch (_) {
      // FAIL-OPEN RULE: Cập nhật lỗi/timeout ở lần đầu -> Vẫn cho phép ads để bảo vệ doanh thu Tier-3.
      if (status == ConsentStatus.unknown) return true;
    }

    // 3. Đánh giá trạng thái sau cập nhật
    return switch (decideConsent(status)) {
      AdsConsentDecision.proceed || AdsConsentDecision.awaitUpdate => true,
      AdsConsentDecision.showForm => await client.showFormIfRequired().then(
        (_) => client.canRequestAds(),
      ),
    };
  } catch (_) {
    // Lỗi platform channel -> Fail-open an toàn
    return true;
  }
}
```

#### B. Component `PrivacyOptionsBuilder` Cho Màn Hình Cài Đặt
```dart
// lib/core/components/privacy_options_builder.dart
import 'package:flutter/widgets.dart';
// Import từ package tomo_monetization (nếu >= 1.3.3)
import 'package:tomo_monetization/tomo_monetization.dart' show AdsConsentClient;
// HOẶC từ file local nếu dự án triển khai nội bộ:
// import '../services/ads/ads_consent.dart';
import '../../di/injection.dart';

class PrivacyOptionsBuilder extends StatefulWidget {
  const PrivacyOptionsBuilder({required this.builder, this.client, super.key});

  final Widget Function(BuildContext context, VoidCallback? openPrivacyOptions) builder;
  final AdsConsentClient? client;

  @override
  State<PrivacyOptionsBuilder> createState() => _PrivacyOptionsBuilderState();
}

class _PrivacyOptionsBuilderState extends State<PrivacyOptionsBuilder> {
  AdsConsentClient? _client;
  bool _required = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? (locator.isRegistered<AdsConsentClient>() ? locator<AdsConsentClient>() : null);
    _client?.isPrivacyOptionsRequired().then((value) {
      if (mounted && value != _required) setState(() => _required = value);
    }).catchError((Object _) {});
  }

  void _open() => _client?.showPrivacyOptionsForm().catchError((Object _) {});

  @override
  Widget build(BuildContext context) => widget.builder(context, _required ? _open : null);
}
```

#### C. Tích Hợp Vào Settings Screen
```dart
PrivacyOptionsBuilder(
  builder: (context, openPrivacyOptions) => SettingGroupCard(
    header: 'Hỗ trợ & Pháp lý',
    children: [
      SettingTile(
        title: 'Chính sách bảo mật',
        icon: AppIcons.policy,
        onTap: () => _openPolicy(context),
      ),
      if (openPrivacyOptions != null)
        SettingTile(
          title: 'Lựa chọn quyền riêng tư',
          icon: AppIcons.privacyOptions,
          onTap: openPrivacyOptions,
        ),
    ],
  ),
)
```

#### D. Bộ Test Mẫu Hoàn Chỉnh (`FakeConsentClient`)
```dart
// test/core/services/ads/ads_consent_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

class FakeConsentClient implements AdsConsentClient {
  FakeConsentClient({
    required this.cached,
    this.afterUpdate,
    this.update,
    this.canRequest = true,
  });

  ConsentStatus cached;
  final ConsentStatus? afterUpdate;
  final Future<void> Function()? update;
  final bool canRequest;
  int updateCalls = 0;
  int formCalls = 0;
  Completer<void>? form;

  @override
  Future<ConsentStatus> getStatus() async => cached;

  @override
  Future<void> requestUpdate() async {
    updateCalls++;
    await (update?.call() ?? Future<void>.value());
    if (afterUpdate != null) cached = afterUpdate!;
  }

  @override
  Future<void> showFormIfRequired() {
    formCalls++;
    return (form ??= Completer<void>()..complete()).future;
  }

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<bool> isPrivacyOptionsRequired() async => false;

  @override
  Future<void> showPrivacyOptionsForm() async {}
}

void main() {
  group('resolveAdsConsent', () {
    test('cached notRequired: cho phép ad ngay, không đợi update mạng', () async {
      final never = Completer<void>();
      final client = FakeConsentClient(
        cached: ConsentStatus.notRequired,
        update: () => never.future,
      );
      expect(await resolveAdsConsent(client), isTrue);
      expect(client.updateCalls, 1);
    });

    test('cached unknown: update mạng lỗi -> vẫn cho phép ad (Fail-Open)', () async {
      final client = FakeConsentClient(
        cached: ConsentStatus.unknown,
        update: () async => throw Exception('Network timeout'),
      );
      expect(await resolveAdsConsent(client), isTrue);
    });

    test('required: chờ form đóng và KHÔNG timeout khi đang mở', () async {
      final client = FakeConsentClient(
        cached: ConsentStatus.required,
        afterUpdate: ConsentStatus.required,
      )..form = Completer<void>();

      var done = false;
      final future = resolveAdsConsent(client, updateTimeout: const Duration(milliseconds: 20))
          .then((v) => done = v);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(done, isFalse, reason: 'Phải tiếp tục chờ khi form đang mở');

      client.form!.complete();
      await future;
      expect(done, isTrue);
    });
  });
}
```

---

## 6. Quy Trình Startup & Đồng Bộ In-App Purchase (IAP)

### Thứ Tự Khởi Tạo Bất Di Bất Dịch tại `SplashCubit`:
1. **Remote Config FIRST:** Timeout tối đa `1500ms` (bọc `try-catch` tại `injection.dart` để không crash DI).
2. **RevenueCat / IAP SECOND:** Khởi tạo với **Timeout cứng `2500ms`**, cờ `_isInitialized` chỉ set true khi thành công; tự động retry an toàn khi gọi Paywall.
3. **Ads Repository THIRD:** Nạp consent, khởi tạo SDK Mobile Ads theo kết quả consent, nạp config thật từ Remote Config và phân quyền theo trạng thái VIP.
4. **KHÔNG Preload Interstitial & Rewarded Ads (100% On-Demand `showWithLoading`):**
   * Tuyệt đối **KHÔNG preload/prefetch** Interstitial hoặc Rewarded Ads tại Splash.
   * Cả 2 định dạng đều chạy **On-Demand kích hoạt kèm Loading Dialog (`showWithLoading`)** do `tomo_monetization` SDK xử lý.
   * Splash chỉ nạp ngầm duy nhất `onboarding_native_ad` cho **User Mới** (`!isOnboardingCompleted`). Đối với User cũ, không gửi bất kỳ request ad nào khi mở app.

```dart
// lib/features/splash/presentation/cubit/splash_cubit.dart
Future<void> _initializeServices() async {
  try {
    await _appConfig.refreshConfig().timeout(const Duration(milliseconds: 1500));
  } catch (_) {}

  if (locator.isRegistered<RevenueCatService>()) {
    try {
      await locator<RevenueCatService>().initialize();
    } catch (_) {}
  }

  if (locator.isRegistered<AdsRepository>()) {
    await locator<AdsRepository>().initialize();
    
    // Chỉ prefetch slot Native Onboarding cho User MỚI
    final isOnboardingCompleted = _preferencesService.readData<bool>(
      StorageKeys.isOnboardingCompleted,
    ) ?? false;
    if (!isOnboardingCompleted) {
      try {
        final slotFuture = (HorizontalNativeAdManager.instance.getGroup() ??
                MonetizationManager.instance.nativeFeedAdGroup)
            ?.loadSlot('onboarding_native_ad');
        if (slotFuture != null) unawaited(slotFuture);
      } catch (_) {}
    }
  }
}
```

---

## 7. Quản Lý Môi Trường & Remote Config An Toàn

### 7.1. Phân biệt Môi Trường Tuyệt Đối
* `_isProduction = kReleaseMode && isPhysicalDevice;`
* **Debug / Simulator / Profile:** Luôn dùng Google Official Test IDs.
* **Release trên thiết bị thật:** Chỉ dùng Ad Unit IDs từ Remote Config. Nếu rỗng $\rightarrow$ Trả về chuỗi rỗng `''` để SDK tự tắt placement, **CẤM fallback về Test IDs trong bản Release**.

### 7.2. Test Device IDs
```dart
await MonetizationManager.instance.initialize(
  testDeviceIds: kReleaseMode
      ? const <String>[]
      : const <String>['DEVICE_HASH_ID_1', 'DEVICE_HASH_ID_2'],
);
```

### 7.3. Tập Trung Hóa Ad Unit IDs vào JSON Remote Config (`admob_units_android`)
Thay vì khai báo 10-15 keys riêng lẻ gây phân mảnh và khó quản lý phiên bản, gom toàn bộ Ad Unit IDs vào một key JSON duy nhất:
```json
{
  "inter_back": "ca-app-pub-.../...",
  "inter_splash": "ca-app-pub-.../...",
  "inter_resume": "ca-app-pub-.../...",
  "inter_action": "ca-app-pub-.../...",
  "reward_unlock": "ca-app-pub-.../...",
  "native_home": "ca-app-pub-.../...",
  "banner_home": "ca-app-pub-.../..."
}
```
* **Cơ chế đọc:** Ưu tiên parse từ JSON template, có fallback về legacy individual keys nếu JSON trống hoặc lỗi.
* **Auto-Reload:** Khi Firebase Remote Config fetch thành công bản mới, tự động thông báo để reset/re-initialize các ad groups tương ứng.

---

## 8. Checklist Trước Khi Release Bản Build

| STT | Hạng mục kiểm tra | Đạt |
|:---:|:---|:---:|
| **1** | Mọi vị trí Native Ad trong danh sách đều có Viewport Lazy-Loading (400px) & Catch block chỉ cho phép `index == 0`. | [ ] |
| **2** | Toàn bộ SlotKey đều là chuỗi tĩnh theo vị trí (không chứa biến category hay theme). | [ ] |
| **3** | Không có bất kỳ lệnh `dispose()` nào được gọi trên Ad đã sẵn sàng trong RAM. | [ ] |
| **4** | Native Ad áp dụng `disposeOnUnmount = false` mặc định trong Bottom Sheet / Dialog / Tabs; khi dispose thì hoãn qua `addPostFrameCallback`. | [ ] |
| **5** | Mọi lệnh hiển thị Interstitial & Rewarded on-demand đều có timeout tối thiểu 8–10s. | [ ] |
| **6** | Toàn bộ điều hướng Back & Action đều dùng `AdsNavigationHelper` có Re-entrancy Lock chống spam click. | [ ] |
| **7** | App Resume Ad đã có cờ chống Ad-Loop, bọc `AbsorbPointer` trên overlay, chèn bằng `OverlayEntry` không mất State. | [ ] |
| **8** | Không đặt Banner Ad ở các sub-screens cài đặt thao tác ngắn (< 15s). | [ ] |
| **9** | Mua VIP / Restore VIP cập nhật realtime qua Stream, tắt toàn bộ ad ngay lập tức. | [ ] |
| **10** | Bản Release không để lộ Test Device IDs và không fallback sang Google Test Ad Units. | [ ] |
| **11** | MediaView của Native Video Ad có kích thước tối thiểu $\ge 120\times 120\text{ dp}$. | [ ] |
| **12** | Mobile Ads SDK chỉ được `initialize()` sau khi UMP Consent đã được giải quyết. | [ ] |
| **13** | User có cache `notRequired`/`obtained` được tải ad tức thì 0s, update consent chạy nền `unawaited`. | [ ] |
| **14** | Khi consent status là `unknown`, bước update chỉ đợi tối đa 3s và áp dụng Fail-Open (vẫn cho phép ads) nếu lỗi mạng. | [ ] |
| **15** | Khi UMP hiển thị form (`required`), không có timeout cắt ngang form; form đóng mới gọi `canRequestAds()`. | [ ] |
| **16** | Màn hình Settings hiển thị mục "Privacy Options" khi UMP báo `required`, chạm vào mở lại form thành công. | [ ] |
| **17** | Chạy `flutter analyze` đạt 0 issues và toàn bộ test suite pass 100%. | [ ] |


