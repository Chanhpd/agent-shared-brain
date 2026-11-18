# Tối Ưu 60 FPS Scroll Toàn Diện: Isolate AES-GCM Decrypt, GIF Static Poster, Zero-Layout BackdropFilter & RepaintBoundary Cache

- **Ngày ghi nhận:** 2026-11-18
- **Phân loại:** Flutter / Performance / 60 FPS / Network Crypto / GPU Raster
- **Mức độ nghiêm trọng:** Major / Critical (Gây khựng cuộn < 15 FPS trên máy yếu, spike CPU Main Isolate & GPU Overdraw)
- **Dự án phát hiện lần đầu:** LED Keyboard (`app-keyboard`)
- **Môi trường:** Profile & Release APK / Android Low-end & Mid-range / iOS

---

## 1. Triệu Chứng (Symptom & Error Logs)

Khi người dùng cuộn các màn hình nặng nội dung media (`HomeScreen`, `CategoriesScreen`, `StickerStoreScreen`, tab `GIFS`) trên thiết bị Android tầm trung/yếu hoặc emulator chạy bản `--profile`:

1. **Nghẽn Main Isolate khi giải mã API payload mã hóa lớn:**
   - CPU profiler (`getCpuSamples`) trên Main Isolate ghi nhận `DartAesGcm.decrypt` / `DartAesGcm._ghash` + `jsonDecode` đứng #1 mức tiêu thụ CPU app-code (`6.58%` ở Home scroll, `5.09%` ở Sticker pagination), cộng hưởng với `LogInterceptor` dump JSON lớn.
2. **Tụt FPS nghiêm trọng trên lưới GIF / Sticker động (`SliverGrid`):**
   - Vuốt nhanh qua tab `GIFS` khiến khung hình rớt xuống dưới 15 FPS:
     - `UI Jank`: `32.67%` (`buildMs` avg `21.09ms`, max `294.54ms`)
     - `Raster Jank`: `97.03%` (`rasterMs` avg `62.15ms`, max `238.70ms`)
     - `LAYOUT (root)` max: `279.30ms`
     - Logcat liên tục báo bỏ khung hình:
```text
I Choreographer: Skipped 64 frames!  The application may be doing too much work on its main thread.
I Choreographer: Skipped 70 frames!  The application may be doing too much work on its main thread.
```
3. **GPU Overdraw và lệnh OpenGL bùng nổ từ `BackdropFilter`:**
   - Thanh bottom navigation dạng kính mờ (`BackdropFilter`) kết hợp với `BackdropFilter` đặt bên trong từng card `CategoryBannerCard` đẩy `RenderBackdropFilter.paint` lên `1.81%–3.37%` CPU và phát sinh tới **`2,583–2,689` lệnh `ReactorGLES::Operation`** chỉ trong một phiên cuộn `CategoriesScreen`.
4. **Rebuild thừa lúc đang fling & lãng phí tài nguyên ở tab ẩn:**
   - `CategoriesCubit` bắn liên tiếp các `emit()` cập nhật fallback thumbnail ngay giữa lúc đang cuộn.
   - `AnimatedBuilder(animation: scrollController)` rebuild lớp bọc header theo từng pixel cuộn.
   - Các widget có `Timer.periodic` / carousel `autoPlay` (ví dụ `HomeTopBanner`, `FloatingShortcut`) vẫn âm thầm tick khi đang nằm trong nhánh ẩn của `StatefulShellRoute.indexedStack`.

---

## 2. Nguyên Nhân Gốc Rễ & 2 Cạm Bẫy "Tối Ưu Ngược" (Root Cause & Pitfalls)

### Nguyên nhân gốc rễ
1. **Giải mã đối xứng AES-256-GCM bằng pure-Dart trên UI Isolate:** API trả về payload Base64 lớn (`>= 16 KB`), hàm `base64Decode` + `DartAesGcm._ghash` + `utf8.decode` + `jsonDecode` + parse list DTO cùng chạy trên UI Isolate làm nghẽn chu kỳ `VSync` `16.6ms`.
2. **Giải mã đồng thời nhiều ảnh multi-frame `.gif` trong `SliverGrid`:** Khi fling qua danh sách, Flutter khởi tạo `MultiImageStreamCompleter` cho cả loạt GIF động (`cacheExtent` lớn + mỗi card lại bọc `LayoutBuilder`), vừa tốn CPU decode nhiều frame cùng lúc vừa tăng áp lực GC (`TOTAL PSS` lên tới `482 MB`).
3. **`BackdropFilter` luôn bật hoặc lạm dụng trong item lặp lại:** Mỗi `BackdropFilter` buộc Impeller/Skia đọc lại framebuffer offscreen (`saveLayer` / `BlitPassGLES`) ở mỗi frame cuộn, nhân theo số card hiển thị trên màn hình.

### ⚠️ CẢNH BÁO 2 CẠM BẪY "TỐI ƯU NGƯỢC" ĐÃ ĐO BẰNG `--profile` (TUYỆT ĐỐI TRÁNH)

| Cạm bẫy tưởng là tối ưu | Hậu quả thực tế đo được trong `--profile` | Cách làm đúng |
| :--- | :--- | :--- |
| **1. Unmount/remount `BackdropFilter` hoặc toggle `boxShadow` trên card bằng `ScrollJankGuard`**<br>Ví dụ: `isScrolling ? child : BackdropFilter(..., child: child)` hoặc tắt/bật `BoxShadow` trong card bọc `RepaintBoundary`. | - Gỡ/gắn `BackdropFilter` làm đổi cấu trúc cây widget ở mỗi lần chạm vuốt -> vọt **`LAYOUT max` lên `200ms+`**.<br>- Lắng nghe `ScrollJankGuard` trong card bọc `RepaintBoundary` để tắt `boxShadow` làm **hủy cache GPU layer texture** của mọi card ở mỗi lần bắt đầu và dừng fling. | - Dùng `BackdropGroup` + `BackdropFilter.grouped(enabled: ...)` qua `ValueListenableBuilder(child: staticChild)` -> chỉ gọi `markNeedsPaint()`, **0 layout**.<br>- Giữ `BoxShadow` tĩnh bên trong `RepaintBoundary` (GPU raster 1 lần và tái sử dụng texture). |
| **2. Xóa `maxWidthDiskCache` / `maxHeightDiskCache` của `CachedNetworkImage`**<br>Do nhầm tưởng `flutter_cache_manager` dùng pure-Dart `package:image` gây nghẽn UI Isolate. | `ImageCacheManager` thực chất gọi **native C++ codec `ui.instantiateImageCodec`** để lưu thumbnail nhỏ (`resized_w*`) xuống đĩa. Bỏ `maxWidthDiskCache` khiến GPU phải upload ảnh gốc full-res, làm vọt **`UploadTextureToPrivate` từ `90ms` lên `1,518ms` (+17x)**! | - **Giữ nguyên** `memCacheWidth` và `maxWidthDiskCache` (`maxWidth` trên provider).<br>- Thay vào đó đặt `fadeOutDuration: Duration.zero` và tắt `fadeInDuration` khi đang cuộn để loại bỏ `OpacityLayer` kép `1000ms` đè lên shimmer. |

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### 3.1. Offload Giải Mã Envelope Lớn (`>= 16 KB`) + JSON + DTO Sang `Isolate.run`
Gộp toàn bộ chuỗi `base64Decode` $\rightarrow$ `decryptAesGcm` $\rightarrow$ `utf8.decode` $\rightarrow$ `jsonDecode` vào **một lời gọi `Isolate.run` duy nhất** tại interceptor để chỉ tốn 1 lần truyền dữ liệu qua ranh giới isolate, đồng thời tắt `LogInterceptor` dump body.

```dart
// lib/core/network/secure_dio_factory.dart
Future<dynamic> _decryptAndDecodeJsonInIsolate(
  String iv,
  String ciphertext,
  String tag,
  Uint8List key,
) async {
  final decryptedBytes = await const CryptographyEngineImpl().decryptAesGcm(
    ciphertext: base64Decode(ciphertext),
    key: key,
    iv: base64Decode(iv),
    tag: base64Decode(tag),
  );
  return jsonDecode(utf8.decode(decryptedBytes));
}

class _LargePayloadDecryptInterceptor extends Interceptor {
  static const int isolateThresholdBytes = 16 * 1024;
  // ...
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final data = response.data;
    if (!EncryptedPayload.isEncryptedPayload(data)) {
      return handler.next(response);
    }
    final map = data as Map<dynamic, dynamic>;
    final ciphertext = map['ciphertext']?.toString() ?? '';
    if (ciphertext.length < isolateThresholdBytes) {
      return handler.next(response);
    }
    try {
      final payload = EncryptedPayload.fromJson(map);
      final key = payload.isPublic
          ? await _publicKeyProvider.getPublicKey(payload.v!)
          : _sessionManager.sessionKey;
      if (key == null) return handler.next(response);

      response.data = await Isolate.run(
        () => _decryptAndDecodeJsonInIsolate(
          payload.iv,
          ciphertext,
          payload.tag,
          key,
        ),
      );
    } catch (_) {
      // Fall through cho SecureCryptoInterceptor xử lý thống nhất nếu có lỗi
    }
    return handler.next(response);
  }
}
```

* Ở tầng DataSource, tiếp tục offload bước ánh xạ danh sách model khi số lượng phần tử lớn (`>= 12` items):
```dart
if (_countCandidateItems(rawData) >= 12) {
  return Isolate.run(
    () => parsePacksPayload(rawData, categoryId: categoryId, type: type),
  );
}
```
* *Lưu ý Unit Test:* Nếu `JsonMapPublicKeyProvider` nạp `initialKeys` mặc định (ví dụ key `'v1'`), test cho `_LargePayloadDecryptInterceptor` cần dùng key version riêng như `'v_test'` để tránh đọc nhầm key mặc định gây `SecretBoxAuthenticationError`.

---

### 3.2. Kiến Trúc Grid GIF / Sticker Động 2 Tầng (Static Poster Khi Cuộn + Animated WebP Khi Nghỉ)
1. **Đang cuộn (`ScrollJankGuard.isScrolling(context) == true`, giữ debounce `500ms` sau `ScrollEndNotification`):** Chuyển URL sang poster tĩnh nhẹ (`_sm_jpg.jpg`, `~6 KB`) bọc `ResizeImage(..., width: 220)` với `gaplessPlayback: true`.
2. **Khi người dùng dừng tay (idle):** Nâng cấp URL sang bản động tối ưu (`_sm_webp.webp`, `~97 KB` thay cho `.gif` nặng) kèm `gaplessPlayback: true` để chuyển khung mượt không nháy trắng.
3. **Loại bỏ `LayoutBuilder` trong `SliverGrid`:** Truyền `hasBoundedHeight: true` từ `SliverGrid` xuống card.
4. **Giảm `cacheExtent: 180` cho tab `GIFS`:** Không giải mã trước nhiều GIF động nằm ngoài khung nhìn.
5. **Disk Snapshot Trang 1 + Warmup trễ `800ms`:** Lưu JSON trang 1 dưới đĩa để mở tab Sticker tức thì (`0ms`), và warmup API nhẹ sau khi màn Home đã render xong (`HomeLoaded` + `800ms`).

```dart
// Áp dụng quy chuẩn 2 tầng cho URL CDN animated media
static String? resolveGifPosterUrl(String url) {
  final suffix = RegExp(r'_(hd|md|sm|xs)_(gif\.gif|webp\.webp)(\?.*)?$', caseSensitive: false);
  if (!suffix.hasMatch(url)) return null;
  return url.replaceFirstMapped(suffix, (m) => '_sm_jpg.jpg${m.group(3) ?? ''}');
}

static String resolveOptimizedAnimatedUrl(String url) {
  final gifSuffix = RegExp(r'_(hd|md|sm|xs)_gif\.gif(\?.*)?$', caseSensitive: false);
  if (!gifSuffix.hasMatch(url)) return url;
  return url.replaceFirstMapped(gifSuffix, (m) => '_sm_webp.webp${m.group(2) ?? ''}');
}

// Trong widget hiển thị GIF của Grid card:
final isScrolling = ScrollJankGuard.isScrolling(context);
if (isScrolling) {
  final posterUrl = resolveGifPosterUrl(url);
  if (posterUrl != null) {
    return Image(
      image: ResizeImage(CachedNetworkImageProvider(posterUrl, maxWidth: 220), width: 220),
      gaplessPlayback: true,
      fit: BoxFit.contain,
    );
  }
  return ColoredBox(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4));
}

return Image(
  image: CachedNetworkImageProvider(resolveOptimizedAnimatedUrl(url)),
  gaplessPlayback: true,
  fit: BoxFit.contain,
);
```

---

### 3.3. Tạm Dừng Kính Mờ Khi Cuộn Với `BackdropGroup` + `BackdropFilter.grouped(enabled: ...)`
Bọc thanh Bottom Bar trong `RepaintBoundary` + `BackdropGroup`, dùng `ValueListenableBuilder<bool>(child: staticChild)` truyền thẳng xuống `BackdropFilter.grouped(enabled: ...)`:

```dart
class _OptionalAnimatedBlur extends StatelessWidget {
  const _OptionalAnimatedBlur({
    required this.filter,
    required this.enableBackdropBlur,
    required this.blurEnabledListenable,
    required this.child,
  });

  final ImageFilter filter;
  final bool enableBackdropBlur;
  final ValueListenable<bool>? blurEnabledListenable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listenable = blurEnabledListenable;
    if (listenable == null) {
      return BackdropFilter.grouped(
        enabled: enableBackdropBlur,
        filter: filter,
        child: child,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      child: child, // Giữ nguyên child, không rebuild widget con!
      builder: (context, isBlurActive, staticChild) => BackdropFilter.grouped(
        enabled: enableBackdropBlur && isBlurActive,
        filter: filter,
        child: staticChild,
      ),
    );
  }
}
```

Tại `AppShell` (hoặc màn chứa `ScrollView`):
```dart
NotificationListener<ScrollNotification>(
  onNotification: (notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _scrollIdleTimer?.cancel();
      if (_navBlurEnabled.value) _navBlurEnabled.value = false;
    } else if (notification is ScrollEndNotification) {
      _scrollIdleTimer?.cancel();
      _scrollIdleTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted && !_navBlurEnabled.value) {
          _navBlurEnabled.value = true;
        }
      });
    }
    return false;
  },
  child: ...,
)
```
* **Card lặp lại trong danh sách (ví dụ `CategoryBannerCard`):** Mặc định đặt `enableBackdropBlur = false` (dùng gradient scrim nhẹ thay vì blur thời gian thực trên từng card) và giữ `BoxShadow` tĩnh bên trong `RepaintBoundary`.

---

### 3.4. Chuẩn Hóa `AppCachedNetworkImage` Zero-Fade Khi Cuộn
Giữ nguyên `memCacheWidth` + `maxWidthDiskCache` để tận dụng native resize disk cache, nhưng triệt tiêu cross-fade tốn `OpacityLayer` khi đang cuộn:

```dart
final isScrolling = ScrollJankGuard.isScrolling(context, listen: false);

return CachedNetworkImage(
  imageUrl: cleanUrl,
  fit: fit,
  memCacheWidth: cacheWidth,
  memCacheHeight: cacheHeight,
  maxWidthDiskCache: cacheWidth,
  maxHeightDiskCache: cacheHeight,
  fadeOutDuration: Duration.zero,
  fadeInDuration:
      isScrolling ? Duration.zero : const Duration(milliseconds: 100),
  fadeInCurve: Curves.easeOutCubic,
  placeholder: (context, url) => _buildPlaceholder(context),
  errorWidget: (context, url, error) => _buildPlaceholder(context),
);
```

---

### 3.5. Vệ Sinh Tab Ẩn (`TickerMode`), Header Clamped `ValueNotifier` & Gom Batch Emit
1. **Đóng băng timer ở tab ẩn của `StatefulShellRoute.indexedStack`:**
   - Với `StatelessWidget` bọc carousel: `autoPlay: enableAutoScroll && !isReducedMotion && TickerMode.of(context)`.
   - Với `StatefulWidget` (`TickerProviderStateMixin`): kiểm tra `TickerMode.of(context)` trong `didChangeDependencies()`, khi `false` thì `timer?.cancel()` và `controller.stop()`.
2. **Thay `AnimatedBuilder(animation: scrollController)` bằng `ValueNotifier<double>` clamp `[0.0, 1.0]`:** Chỉ cập nhật khi `(nextProgress - value).abs() > 0.004` hoặc chạm mốc biên `0.0` / `1.0`, tránh rebuild toàn cây header khi đang cuộn sâu bên dưới vùng collapse (`offset > 54.0`).
3. **Gom batch fallback emit sau khi cuộn nghỉ:** Thay vì gọi `cubit.resolveFallbackThumbnail(id)` ngay khi card vừa vào viewport và emit từng item một, thu thập ID vào `Set<String> _pendingFallbackCategoryIds` rồi chỉ gọi `resolveFallbackThumbnailsBatch(batch)` 1 lần duy nhất trong timer `ScrollEndNotification` (`200ms`) và emit 1 state sau `Future.wait`.
4. **Static Native Ad `slotKey`:** Luôn đặt slot key tĩnh theo index vị trí (`category_detail_native_slot_$adIndex`), không gắn dynamic category ID.

---

### 3.6. Kết Quả Đo `--profile` (Emulator Android + Dart VM Service)

| Kịch bản / Chỉ số đo | Trước tối ưu (`--profile`) | Sau tối ưu (`--profile`) | Mức cải thiện |
| :--- | :--- | :--- | :--- |
| **Main Isolate `DartAesGcm.decrypt` (Home)** | `6.58%` CPU (`129` samples) | `0.00%` CPU | **-100%** |
| **Main Isolate `DartAesGcm.decrypt` (Sticker)** | `5.09%` CPU (`103` samples) | `0.00%` CPU | **-100%** |
| **Category Cold Scroll `ReactorGLES::Operation`** | `2,583` ops | `396` ops | **-84.7%** |
| **Category Fling `ReactorGLES::Operation`** | `2,689` ops | `401` ops | **-85.1%** |
| **Category `RenderBackdropFilter.paint` CPU** | `1.81%` / `3.37%` (Home) | Đã loại khỏi top hotspot | **Gần như 0%** |
| **GIFS Tab UI Jank %** | `32.67%` | `9.66%` | **-70.4%** |
| **GIFS Tab `buildMs` (avg / max)** | `21.09ms` / `294.54ms` | `6.92ms` / `50.92ms` | **-67% avg / -83% max** |
| **GIFS Tab `rasterMs` (avg / max)** | `62.15ms` / `238.70ms` | `24.67ms` / `138.26ms` | **-60.3% avg** |
| **GIFS Tab `LAYOUT (root)` max** | `279.30ms` | `31.50ms` | **-88.7%** |
| **Tổng RAM `TOTAL PSS` (Home / Category / Sticker / GIFS)** | `370 / 427 / 466 / 482 MB` | `325 / 389 / 430 / 452 MB` | **Giảm 30–45 MB** |

#### Mẹo đo benchmark `--profile` tự động (Dart VM Service + ADB):
- Màn hình thuần `FlutterSurfaceView` không chứa `PlatformView` sẽ trả `0 frames` trong `adb shell dumpsys gfxinfo`. Hãy kết nối WebSocket Dart VM Service trên build `--profile`, gọi `streamListen('Extension')` để thu thập sự kiện `Flutter.Frame` (`build`, `raster`, `elapsed`), kết hợp `getVMTimeline` và `getCpuSamples`.
- Khi tự động hóa thao tác tab bằng `adb shell uiautomator dump`, luôn dùng `uiautomator dump --compressed` (tránh hang nếu còn animation đang tick) và lưu ý ký tự xuống dòng trong `content-desc` được XML encode thành `&#10;`.

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] **Giải mã API & JSON lớn:** Mọi payload mã hóa `ciphertext.length >= 16 * 1024` (hoặc list DTO `>= 12` phần tử) đã được offload vào `Isolate.run` chưa? Đã tắt `LogInterceptor` responseBody chưa?
- [ ] **Cache ảnh mạng:** Vẫn **giữ nguyên** `memCacheWidth` và `maxWidthDiskCache` trên `CachedNetworkImage` để dùng native resize cache; đã set `fadeOutDuration: Duration.zero` và tắt `fadeInDuration` khi đang cuộn chưa?
- [ ] **Lưới GIF / Animated WebP:** Đã tách chế độ ảnh tĩnh poster khi cuộn (`ScrollJankGuard` + debounce `500ms`) và chỉ chạy ảnh động tối ưu (`_sm_webp.webp` + `gaplessPlayback: true`) khi dừng cuộn chưa? Đã hạ `cacheExtent` (`~180`) cho tab GIF chưa?
- [ ] **Loại bỏ `LayoutBuilder` thừa:** Các card trong `SliverGrid` có chiều cao cố định đã truyền cờ `hasBoundedHeight: true` để bỏ qua `LayoutBuilder` chưa?
- [ ] **Kính mờ `BackdropFilter`:** Tuyệt đối **không** mount/unmount `BackdropFilter` theo biến cuộn; dùng `BackdropGroup` + `BackdropFilter.grouped(enabled: ...)` qua `ValueListenableBuilder(child: staticChild)`. Mặc định tắt blur trên item lặp lại trong danh sách.
- [ ] **Bảo toàn `RepaintBoundary`:** Không cho widget con bên trong `RepaintBoundary` của list card lắng nghe `ScrollJankGuard` chỉ để đổi `BoxShadow`.
- [ ] **Tab ẩn `IndexedStack`:** Mọi `Timer.periodic` / `Carousel` `autoPlay` đã kiểm tra `TickerMode.of(context)` để tự ngắt khi chuyển sang tab khác chưa?
- [ ] **Gom Batch & Clamped Progress:** Header co giãn đã dùng `ValueNotifier<double>` clamp `[0.0, 1.0]` chưa? Các fallback thumbnail API có được gom batch và emit sau `ScrollEndNotification` không?

---

## 5. Tài Liệu Tham Khảo (References)
- Dự án tham chiếu: `led_keyboard` (`app-keyboard`) — `secure_dio_factory.dart`, `app_cryptography_engine.dart`, `app_bottom_nav_bar.dart`, `app_shell.dart`, `app_cached_network_image.dart`, `sticker_card_emoji.dart`, `categories_cubit.dart`, `floating_shortcut.dart`.
- [Flutter API: BackdropFilter.grouped & BackdropGroup](https://api.flutter.dev/flutter/widgets/BackdropFilter/BackdropFilter.grouped.html)
- [Flutter Official: Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
