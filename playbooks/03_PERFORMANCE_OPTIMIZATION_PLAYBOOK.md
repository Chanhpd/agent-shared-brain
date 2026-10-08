# CẨM NANG TỐI ƯU HIỆU NĂNG TOÀN DIỆN (PERFORMANCE OPTIMIZATION PLAYBOOK)
> **Dự án áp dụng:** Mọi ứng dụng Flutter & Android Native  
> **Mục tiêu:** Tối ưu thời gian khởi động (Cold Start < 1.5s), giữ khung hình ổn định 60/120 FPS, tối ưu hóa RAM & Bitmap, giảm dung lượng bộ cài (APK/AAB), và loại bỏ triệt để hiện tượng tràn bộ nhớ (Out-Of-Memory - OOM).

---

## MỤC LỤC
1. [Tối Ưu Thời Gian Khởi Động Ứng Dụng (Startup Time & Cold Boot)](#1-tối-ưu-thời-gian-khởi-động-ứng-dụng-startup-time--cold-boot)
2. [Quản Lý Bộ Nhớ & Triệt Tiêu Rò Rỉ RAM (Memory & Leak Prevention)](#2-quản-lý-bộ-nhớ--triệt-tiêu-rò-rỉ-ram-memory--leak-prevention)
3. [Tối Ưu Nạp Ảnh Native & Caching với Glide](#3-tối-ưu-nạp-ảnh-native--caching-với-glide)
4. [Tối Ưu Giao Diện Flutter: 60/120 FPS & Chống Scroll Jank](#4-tối-ưu-giao-diện-flutter-60120-fps--chống-scroll-jank)
5. [Tối Ưu Bộ Cài Đặt (App Size Reduction & R8 / ProGuard)](#5-tối-ưu-bộ-cài-đặt-app-size-reduction--r8--proguard)
6. [Checklist Hiệu Năng Trước Khi Phát Hành](#6-checklist-hiệu-năng-trước-khi-phát-hành)

---

## 1. Tối Ưu Thời Gian Khởi Động Ứng Dụng (Startup Time & Cold Boot)

### 1.1. Thứ Tự Khởi Tạo Bất Đồng Bộ Có Timeout (Startup Sequencing)
* **Quy tắc:** Tuyệt đối không để một dịch vụ bên thứ ba (Firebase, AdMob, RevenueCat, Sentry) làm đơ màn hình Splash quá lâu khi người dùng mở app trong điều kiện mạng yếu hoặc mất mạng.
* **Mô hình chuẩn tại `SplashCubit`:**
  1. **Remote Config:** Chạy với timeout tối đa **1500ms**. Nếu quá hạn, tự động fallback về `DefaultConfig` nạp sẵn trong app.
  2. **In-App Purchase / RevenueCat:** Khởi tạo từ cache SharedPreferences trong bộ nhớ cục bộ.
  3. **Ads Engine:** Khởi tạo ngay khi có config.
  4. **Deferred Services (Khởi tạo trễ):** Các dịch vụ không khẩn cấp (Push Notification token, Analytics logging, In-App Review) được đẩy sang thực thi sau khi đã vào màn hình chính (Home Screen).

```dart
// lib/features/splash/presentation/cubit/splash_cubit.dart
Future<void> _initializeServices() async {
  final startTime = DateTime.now();

  // 1. Fetch Remote Config với Timeout bảo vệ 1500ms
  try {
    await _appConfig.refreshConfig().timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    // Timeout hoặc offline -> Tiếp tục với cấu hình mặc định
  }

  // 2. Khởi tạo IAP
  if (locator.isRegistered<RevenueCatService>()) {
    await locator<RevenueCatService>().initialize();
  }

  // 3. Khởi tạo Ads
  if (locator.isRegistered<AdsRepository>()) {
    await locator<AdsRepository>().initialize();
  }

  // 4. Giữ Splash tối thiểu 1200ms để hiệu ứng chuyển cảnh mượt mà
  final elapsed = DateTime.now().difference(startTime);
  const minSplashTime = Duration(milliseconds: 1200);
  if (elapsed < minSplashTime) {
    await Future.delayed(minSplashTime - elapsed);
  }
}
```

---

## 2. Quản Lý Bộ Nhớ & Triệt Tiêu Rò Rỉ RAM (Memory & Leak Prevention)

### 2.1. Giải Phóng Bộ Nhớ Bitmap Native (`safeRecycle`)
* **Vấn đề:** Khi người dùng đổi theme hoặc tải ảnh nền bàn phím có kích thước lớn ($1920\times 1080$), các đối tượng `Bitmap` nằm trong Native Heap không được GC của Java thu gom kịp thời, dẫn đến lỗi `OutOfMemoryError` (OOM).
* **Quy tắc vàng:** Luôn giải phóng `Bitmap` cũ trước khi giải mã (decode) `Bitmap` mới.

```kotlin
// android/app/src/main/kotlin/.../KeyboardThemeEngine.kt
private var bgBitmap: Bitmap? = null

private fun safeRecycle(bitmap: Bitmap?) {
    if (bitmap != null && !bitmap.isRecycled) {
        try {
            bitmap.recycle()
        } catch (_: Exception) {}
    }
}

fun updateBackgroundArtwork(newBitmap: Bitmap?) {
    // 1. Recycle bitmap cũ ngay lập tức
    safeRecycle(bgBitmap)
    // 2. Gán bitmap mới
    bgBitmap = newBitmap
}
```

---

### 2.2. Dọn Dẹp Font Assets Thừa (Font Pruning & Pre-warming)
* **Vấn đề thực tế đã xử lý:** Thư mục `assets/fonts/` chứa 20 font chữ nặng ($>15\text{ MB}$) không còn được sử dụng trong app. Khi Flutter nạp bundle, toàn bộ file này được đóng gói vào APK và chiếm dụng bộ nhớ RAM.
* **Giải pháp đã triển khai:**
  1. Loại bỏ các font chữ không dùng (`comingsoon`, `digital_7`, `ios.otf`, `merry_sugar_snow.ttf`, v.v.), tiết kiệm trực tiếp **12 MB** dung lượng APK.
  2. Pre-warm dữ liệu font chữ chính (`FontHelper.prewarm()`) trong luồng nền để loại bỏ độ trễ khi vẽ ký tự đầu tiên.

```kotlin
// android/app/src/main/kotlin/.../FontHelper.kt
object FontHelper {
    private val fontCache = ConcurrentHashMap<String, Typeface>()

    fun prewarm(context: Context) {
        Executors.newSingleThreadExecutor().execute {
            // Nạp sẵn font mặc định vào cache bộ nhớ
            loadTypeface(context, "default_font")
        }
    }
}
```

---

### 2.3. Hủy Đăng Ký Stream & Listener trong `dispose()`
Mọi `StreamSubscription`, `AnimationController`, `TextEditingController`, `FocusNode` và `ScrollController` trong Flutter bắt buộc phải được hủy tại `dispose()`:

```dart
@override
void dispose() {
  _adsSubscription?.cancel();
  _tabController.dispose();
  _scrollController.dispose();
  _focusNode.dispose();
  super.dispose();
}
```

---

## 3. Tối Ưu Nạp Ảnh Native & Caching với Glide

### 3.1. Tích Hợp Glide cho Tầng Native Android
Khi hiển thị danh sách giao diện bàn phím, nhãn dán (Stickers) hoặc hình ảnh trong Custom Views, sử dụng thư viện **Glide** để tự động:
* Downsampling ảnh về đúng kích thước hiển thị của `ImageView` (tránh nạp ảnh gốc $4\text{K}$ vào view $100\times 100$).
* Caching 2 tầng: Memory Cache (LRU) + Disk Cache.

```kotlin
// Tải ảnh mượt mà với Glide trong Custom View / RecyclerView
Glide.with(context)
    .asBitmap()
    .load(imageUrl)
    .override(targetWidth, targetHeight) // Downsampling chuẩn kích thước
    .diskCacheStrategy(DiskCacheStrategy.ALL)
    .into(object : CustomTarget<Bitmap>() {
        override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
            themeEngine.updateBackgroundArtwork(resource)
            invalidate()
        }
        override fun onLoadCleared(placeholder: Drawable?) {
            themeEngine.clearArtwork()
        }
    })
```

---

## 4. Tối Ưu Giao Diện Flutter: 60/120 FPS & Chống Scroll Jank

### 4.1. Thay Thế `SliverToBoxAdapter` Bằng Lazy List
* **Sai lầm phổ biến:** Đặt nhiều khối `SliverToBoxAdapter` chứa danh sách con hoặc thẻ quảng cáo trong `CustomScrollView`. Điều này ép Flutter phải khởi tạo toàn bộ widget từ đỉnh tới đáy trang.
* **Đúng:** Sử dụng `SliverList.builder` hoặc `ListView.builder` để Flutter chỉ xây dựng các phần tử đang nằm trong viewport màn hình.

### 4.2. Chống Khựng Hình Khi Cuộn Qua PlatformView (`ScrollJankGuard`)
* **Vấn đề:** Khi người dùng đang vuốt danh sách với tốc độ cao, việc nạp và mount một `AndroidView` (PlatformView) sẽ ép GPU đồng bộ lại OpenGL Texture, gây khựng hình (drop 10-30 frames).
* **Giải pháp:** Sử dụng `ScrollJankGuard`:
  * Khi đang cuộn nhanh: Tạm thời hiển thị Shimmer Skeleton nhẹ nhàng.
  * Khi người dùng dừng tay: Mới chính thức khởi tạo `PlatformView`.
  * Khi đã mount thành công 1 lần: Giữ nguyên trong cây widget, không unmount lại.

```dart
// lib/core/components/scroll_jank_guard.dart
class ScrollJankGuard {
  static bool isFastScrolling(BuildContext context) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return false;
    return scrollable.position.activity is BallisticScrollActivity;
  }
}
```

### 4.3. Kỷ Luật Widget `const` & `RepaintBoundary`
1. **Gắn từ khóa `const`:** Giúp Flutter tái sử dụng các instance widget không đổi, bỏ qua hoàn toàn việc tái xây dựng (rebuild) trong cây widget.
2. **Bọc `RepaintBoundary` cho Animation:** Khi một widget có hiệu ứng chuyển động liên tục (LED glow, loading spinner), bọc nó trong `RepaintBoundary` để Render Tree không phải vẽ lại toàn bộ màn hình xung quanh.

```dart
RepaintBoundary(
  child: GlowingLedBorder(
    color: currentColor,
    child: KeycapWidget(...),
  ),
)
```

---

## 5. Tối Ưu Bộ Cài Đặt (App Size Reduction & R8 / ProGuard)

### 5.1. Cấu Hình ProGuard / R8 Chuẩn
Tạo file `android/app/proguard-rules.pro` để R8 loại bỏ mã nguồn thừa (Tree Shaking) và rút gọn tên class:

```proguard
## Flutter Wrapper Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

## Google Mobile Ads & Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep interface com.google.android.gms.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

## Monetization SDK & Native Ad Factories
-keep class com.mediatech.ledkeyboardtheme.ads.** { *; }
-keep class com.tomo.monetization.** { *; }

## Glide Image Loader
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
  <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-dontwarn com.bumptech.glide.load.data.ParcelFileDescriptorRewinder

## SQLite & Services
-keep public class * extends android.inputmethodservice.InputMethodService
-keep class * extends android.database.sqlite.SQLiteOpenHelper { *; }
```

### 5.2. Lệnh Build Release Rút Gọn & Tách Biểu Tượng Gỡ Lỗi
Khi build file phát hành Android App Bundle (`.aab`):
```bash
# Build AAB với obfuscation và tách debug symbols
flutter build appbundle \
  --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols
```
* **Hiệu quả:**
  * Giảm dung lượng file tải về của người dùng từ **45 MB xuống còn 15-18 MB**.
  * Bảo vệ sở hữu trí tuệ, chống dịch ngược mã nguồn (Decompilation Reverse Engineering).

---

## 6. Checklist Hiệu Năng Trước Khi Phát Hành

| STT | Tiêu chí kiểm tra hiệu năng | Đạt |
|:---:|:---|:---:|
| **1** | Màn hình Splash có timeout bảo vệ (1500ms) cho Remote Config. | [ ] |
| **2** | Toàn bộ Bitmap Native đều được thu hồi bằng `safeRecycle` trước khi load ảnh mới. | [ ] |
| **3** | Không còn font chữ thừa, không dùng trong thư mục `assets/fonts/`. | [ ] |
| **4** | Toàn bộ `StreamSubscription` và `Controller` đều có lệnh `cancel()` / `dispose()`. | [ ] |
| **5** | Đã bọc `RepaintBoundary` quanh các widget có hoạt họa lặp vô tận. | [ ] |
| **6** | Bản build phát hành được đóng gói dưới dạng App Bundle (`.aab`) kèm `--obfuscate`. | [ ] |
| **7** | File `proguard-rules.pro` đã cấu hình đầy đủ cho Glide, AdMob, Billing và SQLite. | [ ] |
