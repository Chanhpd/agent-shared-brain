# CẨM NANG TRIỆT TIÊU LỖI ANR & TỐI ƯU CHỈ SỐ ANDROID VITALS (ANR / ARN PLAYBOOK)
> **Dự án áp dụng:** Ứng dụng Android Native, Flutter Platform Channels, Custom Views, InputMethodService, Background Services.  
> **Mục tiêu:** Đưa tỷ lệ ANR (Application Not Responding) về **0.00%** (thỏa mãn tiêu chuẩn Google Play Vitals < 0.47%), loại bỏ 100% hiện tượng khựng lag (Frame Jank) và khóa luồng UI (Main Thread Block).

---

## MỤC LỤC
1. [Bản Chất ANR & Tiêu Chuẩn Google Play Vitals](#1-bản-chất-anr--tiêu-chuẩn-google-play-vitals)
2. [Nguyên Nhân Gây ANR & Crash Phổ Biến (Case Studies)](#2-nguyên-nhân-gây-anr--crash-phổ-biến-case-studies)
   - [2.1. Thao tác Database / File I/O đồng bộ trên Main Thread](#21-thao-tác-database--file-io-đồng-bộ-trên-main-thread)
   - [2.2. Nạp Font (Typeface) & Quét Asset đồng bộ khi vẽ giao diện](#22-nạp-font-typeface--quét-asset-đồng-bộ-khi-vẽ-giao-diện)
   - [2.3. Khởi tạo đối tượng đồ họa liên tục trong vòng lặp 60 FPS (`onDraw`)](#23-khởi-tạo-đối-tượng-đồ-họa-liên-tục-trong-vòng-lặp-60-fps-ondraw)
   - [2.4. Rò rỉ Vòng lặp Animation khi Ẩn Giao diện (Lifecycle Leak)](#24-rò-rỉ-vòng-lặp-animation-khi-ẩn-giao-diện-lifecycle-leak)
   - [2.5. Xử lý Clipboard & IPC Binder Call trên Luồng Chính](#25-xử-lý-clipboard--ipc-binder-call-trên-luồng-chính)
   - [2.6. Khởi tạo AdMob & Custom Tabs Service đồng bộ trên Main Thread (`b.b.i` / `J.N.*`)](#26-khởi-tạo-admob--custom-tabs-service-đồng-bộ-trên-main-thread-bbi--jn)
   - [2.7. Kẹt Window Focus & Chạm dồn dập khi chuyển Activity/Ad (`No focused window`)](#27-kẹt-window-focus--chạm-dồn-dập-khi-chuyển-activityad-no-focused-window)
   - [2.8. Khởi tạo Third-Party SDK không có Timeout trong Splash (RevenueCat/IAP)](#28-khởi-tạo-third-party-sdk-không-có-timeout-trong-splash-revenuecatiap)
   - [2.9. Crash thiếu thư viện native `libflutter.so` (`MissingLibraryException`)](#29-crash-thiếu-thư-viện-native-libflutterso-missinglibraryexception)
   - [2.10. Crash `PlatformViewsController resize NPE` trên AdWidget / PlatformView](#210-crash-platformviewscontroller-resize-npe-trên-adwidget--platformview)
3. [Mã Nguồn Khắc Phục Chuẩn (Reference Implementation)](#3-mã-nguồn-khắc-phục-chuẩn-reference-implementation)
   - [3.1. Asynchronous SQLite Helper với ThreadPool Executor](#31-asynchronous-sqlite-helper-với-threadpool-executor)
   - [3.2. Background Typeface & Asset Loading Engine](#32-background-typeface--asset-loading-engine)
   - [3.3. Shader & Matrix Caching cho Custom View Render](#33-shader--matrix-caching-cho-custom-view-render)
   - [3.4. Lifecycle Safe Guards cho Services & Views](#34-lifecycle-safe-guards-cho-services--views)
   - [3.5. Cấu hình AdMob Background Optimization trong AndroidManifest](#35-cấu-hình-admob-background-optimization-trong-androidmanifest)
   - [3.6. Triple Guard Chống `PlatformViewsController resize NPE`](#36-triple-guard-chống-platformviewscontroller-resize-npe)
   - [3.7. Bộ 3 Cấu Hình Chống Crash `libflutter.so`](#37-bộ-3-cấu-hình-chống-crash-libflutterso)
   - [3.8. Re-entrancy Lock & Window Insets Attach Check](#38-re-entrancy-lock--window-insets-attach-check)
4. [Xử Lý Tác Vụ Nặng Trong Flutter (Dart Isolates & Compute)](#4-xử-lý-tác-vụ-nặng-trong-flutter-dart-isolates--compute)
5. [Quy Trình Debug, Phân Tích Trace & Giám Sát ANR](#5-quy-trình-debug-phân-tích-trace--giám-sát-anr)
6. [Checklist Phòng Chống ANR & Crash Cho Dự Án Mới](#6-checklist-phòng-chống-anr--crash-cho-dự-án-mới)

---

## 1. Bản Chất ANR & Tiêu Chuẩn Google Play Vitals

### 1.1. Các Ngưỡng Thời Gian Kích Hoạt ANR của Hệ Điều Hành Android
Hệ điều hành Android bắn hộp thoại ANR (*"App isn't responding"*) khi luồng chính (Main/UI Thread) bị khóa vượt quá các ngưỡng sau:

| Loại thành phần (Component) | Ngưỡng kích hoạt ANR | Hành vi gây lỗi điển hình |
|:---|:---:|:---|
| **Input Event Dispatching** (Chạm màn hình, gõ phím, click nút) | **5 giây** | Xử lý DB, parse JSON, nạp ảnh, nạp font trực tiếp trong `onClick`, `onTouch`, `onKey`. |
| **BroadcastReceiver** | **10 giây** (foreground) / **60 giây** (background) | Thực hiện gọi API mạng hoặc đọc ghi file trong `onReceive()`. |
| **Service Execution** (`startService`, `bindService`, `onCreate`) | **20 giây** (foreground) / **200 giây** (background) | Khởi tạo tài nguyên nặng, nạp dữ liệu lớn trong hàm vòng đời Service. |

### 1.2. Tiêu chuẩn Google Play Vitals
* **Bad Behavior Threshold:** $\ge 0.47\%$ tổng số phiên người dùng bị ANR.
* **Hậu quả:** Nếu app vượt quá ngưỡng $0.47\%$, Google Play Console sẽ **hạ bậc hiển thị (de-ranking)** trên bảng xếp hạng tìm kiếm và mục đề xuất, giảm nghiêm trọng lượng cài đặt tự nhiên (organic installs).

---

## 2. 5 Nguyên Nhân Gây ANR Phổ Biến & Bài Học Từ Thực Tế

### 2.1. Thao tác Database / File I/O đồng bộ trên Main Thread
* **Cơ chế lỗi:** Khi người dùng copy text hoặc gõ chữ, hàm lắng nghe Clipboard hoặc lưu lịch sử gõ phím thực hiện `db.insert(...)`, `db.query(...)` trực tiếp trên Main Thread.
* **Hậu quả:** Khi database phình to hoặc bộ nhớ flash của máy bị nghẽn (đặc biệt trên các dòng máy Android phân khúc thấp), thao tác I/O mất từ 2-6 giây $\rightarrow$ **Kích hoạt ANR ngay lập tức**.
* **Giải pháp:** Bắt buộc đẩy toàn bộ thao tác SQLite / SharedPreferences / File I/O sang luồng nền (`ExecutorService` hoặc Kotlin Coroutines với `Dispatchers.IO`).

---

### 2.2. Nạp Font (Typeface) & Quét Asset đồng bộ khi vẽ giao diện
* **Cơ chế lỗi:**
  * Gọi `Typeface.createFromAsset(context.assets, fontPath)` trên luồng UI khi thay đổi theme hoặc vẽ text.
  * Sử dụng `context.assets.list("flutter_assets/...")` để tìm kiếm font động. Hàm `list()` quét toàn bộ thư mục trong file APK (thực chất là giải nén zip header), gây khóa luồng từ 300ms đến 2500ms.
* **Giải pháp:**
  * Loại bỏ hoàn toàn `assets.list()`. Khai báo bảng tra cứu trực tiếp (direct mapping).
  * Chuyển toàn bộ việc nạp Typeface và decode Bitmap sang Background Executor. Khi nạp xong mới chuyển kết quả về Main Thread để `invalidate()`.

---

### 2.3. Khởi tạo đối tượng đồ họa liên tục trong vòng lặp 60 FPS (`onDraw`)
* **Cơ chế lỗi:**
  * Trong hàm `onDraw(canvas: Canvas)` hoặc trong hàm cập nhật hiệu ứng LED chạy 60 lần/giây:
    ```kotlin
    // NGUY HIỂM: Khởi tạo đối tượng mới mỗi frame (60 lần/giây)
    val matrix = Matrix()
    matrix.setRotate(progress * 360f, cx, cy)
    val shader = LinearGradient(...)
    val bgShader = RadialGradient(...)
    ```
* **Hậu quả:** Bộ thu gom rác (Garbage Collector - GC) liên tục kích hoạt `GC_CONCURRENT` và `GC_FOR_ALLOC`, tạm dừng mọi luồng (Stop-The-World) $\rightarrow$ Khựng hình nghiêm trọng (Scroll Jank / Frame Drops) và nghẽn Main Thread.
* **Giải pháp:** Caching Shader (`updateBackgroundShader`), tái sử dụng biến `animMatrix`, chỉ tính toán lại khi kích thước View (`viewWidth`, `viewHeight`) hoặc màu sắc thực sự thay đổi.

---

### 2.4. Rò rỉ Vòng lặp Animation khi Ẩn Giao diện (Lifecycle Leak)
* **Cơ chế lỗi:** Một Service (ví dụ `InputMethodService` hoặc Floating Overlay View) khởi chạy `ValueAnimator` với `INFINITE` repeat. Khi người dùng ẩn bàn phím hoặc thoát app, Service không dừng Animator.
* **Hậu quả:** Animator tiếp tục chạy ngầm trên Main Looper với tần số 60-120 Hz, làm máy nóng ran, tụt pin, chiếm dụng Main Thread và gây ANR khi người dùng mở lại app.
* **Giải pháp:** Lắng nghe chặt chẽ các sự kiện vòng đời: `onWindowHidden()`, `onFinishInput()`, `onWindowShown()` để dừng và khởi động lại luồng vẽ hoạt họa.

---

### 2.5. Xử lý Clipboard & IPC Binder Call trên Luồng Chính
* **Cơ chế lỗi:** Khi `ClipboardManager.OnPrimaryClipChangedListener` kích hoạt, việc truy cập `clipboard.primaryClip` thực hiện gọi IPC (Inter-Process Communication) qua hệ thống Android. Nếu dịch vụ hệ thống bị nghẽn, Main Thread sẽ bị treo vô thời hạn.
* **Giải pháp:** Bao bọc trong `try/catch` an toàn và xử lý trích xuất dữ liệu bên trong luồng bất đồng bộ.

---

### 2.6. Khởi tạo AdMob & Custom Tabs Service đồng bộ trên Main Thread (`b.b.i` / `J.N.*`)
* **Cơ chế lỗi:**
  * Lỗi `SourceFile - b.b.i`: De-obfuscate thành `android.support.customtabs.ICustomTabsService$Stub$Proxy.warmup()`. Google Mobile Ads SDK (AdMob) tự động kết nối với Chrome Custom Tabs để chuẩn bị cho click landing page. Khi kết nối, SDK gọi `CustomTabsClient.warmup()` đồng bộ qua Binder IPC trên Main Thread. Khi Chrome đang cold-start hoặc máy tải nặng, lệnh gọi này block > 5s $\rightarrow$ Kích hoạt ANR *"Lệnh gọi Binder có khả năng bị chậm"*.
  * Lỗi `Native method - J.N.*`: Các creative HTML5/WebView khởi tạo và tính toán layout trên Main Thread lúc chuyển màn hình $\rightarrow$ Kẹt luồng UI trong hàm C++ JNI của Chromium engine.
* **Giải pháp:** Bật 2 cờ meta-data chính thức `OPTIMIZE_INITIALIZATION` và `OPTIMIZE_AD_LOADING` trong `AndroidManifest.xml` để chuyển toàn bộ sang background thread pool.

---

### 2.7. Kẹt Window Focus & Chạm dồn dập khi chuyển Activity/Ad (`No focused window`)
* **Cơ chế lỗi:**
  * Xuất hiện khi mở/đóng quảng cáo toàn màn hình (Interstitial/Rewarded) hoặc mở Cài đặt hệ thống. Activity cũ đang bị pause nhưng Activity/Ad mới chưa hoàn tất gắn cờ focus.
  * Nếu người dùng bấm phím liên tục hoặc spam tap trên màn hình, Android `WindowManagerService` nhận được sự kiện nhưng không có cửa sổ nào giữ `focused window`. Sau 5 giây, hệ thống kích hoạt ANR với stack trace tại `android.view.RoundedCorners$1.createFromParcel` (truyền insets bo góc).
* **Giải pháp:**
  * Cài đặt Re-entrancy Lock trong `AdsNavigationHelper` để bỏ qua các cú tap spam liên tiếp.
  * Bọc overlay chờ ad bằng `AbsorbPointer` tại tầng Flutter để hấp thụ toàn bộ sự kiện chạm.
  * Chỉ gọi `ViewCompat.requestApplyInsets()` khi view đã thực sự attach vào window (`addOnAttachStateChangeListener`).

---

### 2.8. Khởi tạo Third-Party SDK không có Timeout trong Splash (RevenueCat/IAP)
* **Cơ chế lỗi:** Khi mở app, `SplashCubit` gọi `Purchases.init()` hoặc Firebase RemoteConfig đồng bộ không có timeout bảo vệ. Khi kết nối mạng chập chờn (mạng 3G/4G chập chờn hoặc server bên thứ 3 chậm phản hồi), luồng khởi tạo bị treo vô thời hạn, giữ chân người dùng ở Splash > 5s $\rightarrow$ ANR `Input dispatching timed out`.
* **Giải pháp:** Áp dụng timeout cứng $\le 2500\text{ms}$ cho mọi lời gọi SDK bên thứ 3 tại Splash; cờ `_isInitialized` chỉ bật khi thành công và app luôn có fallback an toàn để chuyển vào màn hình chính.

---

### 2.9. Crash thiếu thư viện native `libflutter.so` (`MissingLibraryException`)
* **Cơ chế lỗi:** Khi người dùng cài đặt ứng dụng trên các thiết bị Android từ các nguồn APK hoặc cấu hình App Bundle mới, Android Package Manager có thể không giải nén thư viện `.so` ra ổ đĩa mà đọc trực tiếp từ APK nén. Trên một số dòng máy (Xiaomi MIUI, Oppo ColorOS), cơ chế nén này dẫn đến `java.lang.UnsatisfiedLinkError: Cannot find libflutter.so`.
* **Giải pháp:** Ép `android:extractNativeLibs="true"` trong `AndroidManifest.xml`, khai báo tường minh `ndk.abiFilters`, tắt `enableSplit = false` cho language, và cấu hình ProGuard giữ nguyên `FlutterJNI` & ReLinker.

---

### 2.10. Crash `PlatformViewsController resize NPE` trên AdWidget / PlatformView
* **Cơ chế lỗi:** Khi widget hiển thị AdWidget hoặc WebView bị dispose, `PlatformView` native bị hủy nhưng Flutter engine vẫn đang trong pha layout/resize frame cuối cùng. Engine gọi xuống `PlatformViewsController.onResize`, truy cập `LayoutParams.width` trên một view đã null $\rightarrow$ `NullPointerException` làm văng ứng dụng lập tức.
* **Giải pháp:** Áp dụng cơ chế Triple Guard: Safe Factory với persistent fallback view ở Android Native + Hoãn `disposeSlot()` qua `WidgetsBinding.addPostFrameCallback` ở Flutter + Global Error Filter tại `main.dart`.

---

## 3. Mã Nguồn Khắc Phục Chuẩn (Reference Implementation)

### 3.1. Asynchronous SQLite Helper với ThreadPool Executor

```kotlin
// android/app/src/main/kotlin/.../ClipboardDatabaseHelper.kt
package com.mediatech.ledkeyboardtheme

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

class ClipboardDatabaseHelper private constructor(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    // ThreadPool cố định 1 luồng riêng để đảm bảo tuần tự, không nghẽn UI
    private val dbExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val DATABASE_NAME = "clipboard.db"
        private const val DATABASE_VERSION = 1
        private const val TABLE_CLIPS = "clips"
        private const val COL_ID = "id"
        private const val COL_TEXT = "text"
        private const val COL_TIMESTAMP = "timestamp"

        @Volatile
        private var instance: ClipboardDatabaseHelper? = null

        fun getInstance(context: Context): ClipboardDatabaseHelper =
            instance ?: synchronized(this) {
                instance ?: ClipboardDatabaseHelper(context.applicationContext).also { instance = it }
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_CLIPS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_TEXT TEXT NOT NULL UNIQUE,
                $COL_TIMESTAMP INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE_CLIPS")
        onCreate(db)
    }

    /// Thêm clip bất đồng bộ - KHÔNG BAO GIỜ chặn Main Thread
    fun addClipAsync(text: String, callback: ((Boolean) -> Unit)? = null) {
        dbExecutor.execute {
            try {
                val db = writableDatabase
                val values = ContentValues().apply {
                    put(COL_TEXT, text.trim())
                    put(COL_TIMESTAMP, System.currentTimeMillis())
                }
                // Thay thế nếu trùng text để cập nhật timestamp mới nhất
                val id = db.insertWithOnConflict(
                    TABLE_CLIPS,
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                val success = id != -1L
                if (callback != null) {
                    mainHandler.post { callback(success) }
                }
            } catch (e: Exception) {
                if (callback != null) {
                    mainHandler.post { callback(false) }
                }
            }
        }
    }

    /// Đọc toàn bộ danh sách bất đồng bộ
    fun getAllClipsAsync(callback: (List<String>) -> Unit) {
        dbExecutor.execute {
            val clips = mutableListOf<String>()
            try {
                val db = readableDatabase
                val cursor = db.query(
                    TABLE_CLIPS,
                    arrayOf(COL_TEXT),
                    null,
                    null,
                    null,
                    null,
                    "$COL_TIMESTAMP DESC",
                    "50" // Giới hạn 50 bản ghi gần nhất
                )
                cursor.use {
                    while (it.moveToNext()) {
                        clips.add(it.getString(0))
                    }
                }
            } catch (_: Exception) {}
            // Chuyển kết quả về Main Thread để render UI
            mainHandler.post { callback(clips) }
        }
    }
}
```

---

### 3.2. Background Typeface & Asset Loading Engine

```kotlin
// android/app/src/main/kotlin/.../KeyboardThemeEngine.kt
class KeyboardThemeEngine(private val context: Context) {
    // Thread pool dùng riêng cho việc nạp Theme, nạp Font và Bitmap
    private val themeExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    var themeTypeface: Typeface? = null
        private set

    fun applyTheme(themeJsonStr: String, onLoaded: (() -> Unit)? = null) {
        themeExecutor.execute {
            try {
                val json = JSONObject(themeJsonStr)
                val fontName = json.optString("font", "")

                // 1. Nạp Typeface hoàn toàn trong luồng nền
                val loadedTypeface = if (fontName.isNotEmpty()) {
                    loadTypefaceInBackground(fontName)
                } else {
                    null
                }

                // 2. Cập nhật vào biến tham chiếu
                themeTypeface = loadedTypeface

                // 3. Thông báo cho UI Thread cập nhật giao diện
                mainHandler.post {
                    onLoaded?.invoke()
                }
            } catch (e: Exception) {
                mainHandler.post { onLoaded?.invoke() }
            }
        }
    }

    private fun loadTypefaceInBackground(fontName: String): Typeface? {
        val candidates = listOf(
            "fonts/$fontName.ttf",
            "fonts/$fontName.otf",
            "flutter_assets/assets/fonts/$fontName.ttf",
            fontName
        )
        for (path in candidates) {
            try {
                return Typeface.createFromAsset(context.assets, path)
            } catch (_: Exception) {
                // Thử ứng viên tiếp theo
            }
        }
        return null
    }
}
```

---

### 3.3. Shader & Matrix Caching cho Custom View Render

```kotlin
// Caching Shader & Matrix để triệt tiêu việc cấp phát bộ nhớ trong 60 FPS onDraw
class KeyboardThemeEngine(...) {
    private val animMatrix = Matrix()
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private var lastBgW: Float = -1f
    private var lastBgH: Float = -1f
    private var lastBgStartColor: Int = 0
    private var lastBgFinishColor: Int = 0
    private var lastBgDegree: Float = -1f

    /// Chỉ tính toán lại Background Shader khi kích thước hoặc thông số đổi
    fun updateBackgroundShader(w: Float, h: Float) {
        if (w <= 0f || h <= 0f) return
        if (w == lastBgW && h == lastBgH &&
            bgStartColor == lastBgStartColor &&
            bgFinishColor == lastBgFinishColor &&
            bgDegree == lastBgDegree &&
            bgPaint.shader != null
        ) {
            return // Đã có shader hợp lệ, KHÔNG cấp phát lại!
        }

        lastBgW = w
        lastBgH = h
        lastBgStartColor = bgStartColor
        lastBgFinishColor = bgFinishColor
        lastBgDegree = bgDegree

        val linearShader = LinearGradient(
            0f, 0f, w, h,
            bgStartColor, bgFinishColor,
            Shader.TileMode.CLAMP
        )
        bgPaint.shader = linearShader
    }

    /// Vẽ khung LED: Tái sử dụng Matrix có sẵn, không new Matrix() mỗi frame
    fun updateLedAnimation(progress: Float, w: Float, h: Float) {
        val cx = w / 2f
        val cy = h / 2f
        
        // Tái sử dụng animMatrix
        animMatrix.setRotate(progress * 360f, cx, cy)
        currentLedShader?.setLocalMatrix(animMatrix)
        borderPaint.shader = currentLedShader
    }
}
```

---

### 3.4. Lifecycle Safe Guards cho Services & Views

```kotlin
// android/app/src/main/kotlin/.../LedInputMethodService.kt
class LedInputMethodService : InputMethodService() {
    private var keyboardView: FullRgbKeyboardView? = null

    override fun onWindowHidden() {
        super.onWindowHidden()
        // DỪNG ngay animation khi bàn phím bị che/ẩn
        keyboardView?.stopAnimation()
    }

    override fun onWindowShown() {
        super.onWindowShown()
        // KHỞI ĐỘNG lại khi bàn phím xuất hiện
        keyboardView?.startAnimation()
    }

    override fun onFinishInput() {
        super.onFinishInput()
        // Dừng animation khi kết thúc phiên nhập liệu
        keyboardView?.stopAnimation()
    }

    override fun onDestroy() {
        keyboardView?.stopAnimation()
        keyboardView = null
        super.onDestroy()
    }
}
```

---

### 3.5. Cấu hình AdMob Background Optimization trong AndroidManifest
Chuyển việc kết nối `ICustomTabsService.warmup()` và Chromium WebView context sang background thread:
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application ...>
    <!-- Offload Google Mobile Ads SDK initialization and Custom Tabs / WebView tasks to background threads -->
    <meta-data
        android:name="com.google.android.gms.ads.flag.OPTIMIZE_INITIALIZATION"
        android:value="true" />
    <meta-data
        android:name="com.google.android.gms.ads.flag.OPTIMIZE_AD_LOADING"
        android:value="true" />
</application>
```

---

### 3.6. Triple Guard Chống `PlatformViewsController resize NPE`
Để ngăn chặn hoàn toàn exception `ViewGroup$LayoutParams.width` khi AdWidget hoặc PlatformView unmount:

#### Lớp 1 (Android Native): `SafeAdWidgetPlatformViewFactory` trong `MainActivity.kt`
```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
private class SafeAdWidgetPlatformViewFactory(
    private val delegate: PlatformViewFactory
) : PlatformViewFactory(delegate.createArgsCodec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val originalPlatformView = try {
            delegate.create(context, viewId, args)
        } catch (_: Throwable) { null }

        return object : PlatformView {
            private var stableView: View? = null
            private val fallbackView: View by lazy {
                View(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }
            }

            override fun getView(): View {
                val view = try {
                    stableView ?: originalPlatformView?.view ?: fallbackView
                } catch (_: Throwable) { fallbackView }
                if (stableView == null) stableView = view
                if (view.layoutParams == null) {
                    view.layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }
                return view
            }

            override fun dispose() {
                try { originalPlatformView?.dispose() } catch (_: Throwable) {}
                // Không null hóa stableView/fallbackView để late resize calls không bị NPE
            }
        }
    }
}
```

#### Lớp 2 (Flutter Lifecycle): Hoãn giải phóng Slot qua `addPostFrameCallback`
```dart
// lib/core/components/app_native_ad_card.dart
@override
void dispose() {
  _adsSubscription?.cancel();
  final slotKey = widget.slotKey;
  final hasMounted = _hasMountedAd;
  final shouldDispose = widget.disposeOnUnmount;

  if (shouldDispose && hasMounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!NativeAdArbiter.isClaimed(slotKey)) {
        MonetizationManager.instance.nativeFeedAdGroup?.disposeSlot(slotKey);
      }
    });
  }
  super.dispose();
}
```

#### Lớp 3 (Global Error Barrier): Hấp thụ benign race trong `main.dart`
```dart
// lib/main.dart
final originalOnError = PlatformDispatcher.instance.onError;
PlatformDispatcher.instance.onError = (error, stack) {
  if (error is PlatformException &&
      ((error.message?.contains(r'android.view.ViewGroup$LayoutParams.width') ?? false) ||
       (error.message?.contains('PlatformViewsController') ?? false))) {
    debugPrint('[PlatformViewsController] Intercepted benign resize race: $error');
    return true; // Mark as handled to prevent fatal crash
  }
  return originalOnError?.call(error, stack) ?? false;
};
```

---

### 3.7. Bộ 3 Cấu Hình Chống Crash `libflutter.so`

1. **`AndroidManifest.xml`:**
   ```xml
   <application
       android:extractNativeLibs="true" ...>
   ```
2. **`build.gradle.kts`:**
   ```kotlin
   android {
       defaultConfig {
           ndk {
               abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
           }
       }
       bundle {
           language { enableSplit = false }
       }
   }
   ```
3. **`proguard-rules.pro`:**
   ```proguard
   -keep class io.flutter.embedding.engine.FlutterJNI { *; }
   -keep class com.getkeepsafe.relinker.** { *; }
   -dontwarn com.getkeepsafe.relinker.**
   ```

---

### 3.8. Re-entrancy Lock & Window Insets Attach Check

1. **Re-entrancy Guard trong điều hướng Ad:**
   ```dart
   static bool _isNavigatingWithAd = false;
   if (_isNavigatingWithAd) return;
   _isNavigatingWithAd = true;
   try { ... } finally { _isNavigatingWithAd = false; }
   ```
2. **Attach-Safe Window Insets (Android Native):**
   ```kotlin
   root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
       override fun onViewAttachedToWindow(v: View) {
           ViewCompat.requestApplyInsets(v)
       }
       override fun onViewDetachedFromWindow(v: View) {}
   })
   if (root.isAttachedToWindow) {
       ViewCompat.requestApplyInsets(root)
   }
   ```

---

## 4. Xử Lý Tác Vụ Nặng Trong Flutter (Dart Isolates & Compute)

Trong Flutter, Dart chạy theo mô hình đơn luồng (Single-threaded Event Loop). Mọi tác vụ tính toán nặng (parse JSON hàng ngàn phần tử, mã hóa/giải mã file, xử lý chuỗi ký tự lớn) nếu chạy trên luồng chính sẽ gây drop frame và đơ giao diện.

### Quy tắc: Dùng `compute` hoặc `Isolate.run` cho tác vụ > 10ms
```dart
// lib/core/utils/isolate_helper.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Hàm parse JSON lớn chạy trên Isolate riêng biệt
Future<List<KeyboardThemeModel>> parseThemesInBackground(String jsonString) async {
  return compute(_decodeThemeList, jsonString);
}

List<KeyboardThemeModel> _decodeThemeList(String rawJson) {
  final list = jsonDecode(rawJson) as List<dynamic>;
  return list
      .map((item) => KeyboardThemeModel.fromJson(item as Map<String, dynamic>))
      .toList();
}
```

---

## 5. Quy Trình Debug, Phân Tích Trace & Giám Sát ANR

### 5.1. Lấy File ANR Trace từ Thiết Bị Thật
Khi xảy ra ANR trên thiết bị Android, hệ điều hành tự động ghi lại stack trace của toàn bộ các luồng vào file `/data/anr/traces.txt`.
```bash
# Kéo file trace về máy tính để phân tích
adb root
adb pull /data/anr/traces.txt ./anr_trace.txt

# Hoặc dùng bugreport trên các phiên bản Android mới (Android 10+)
adb bugreport ./bugreport.zip
```

### 5.2. Cách Đọc Dấu Hiệu ANR trong Stack Trace
Tìm kiếm luồng **`main`** trong file trace:
* Nếu thấy trạng thái `SUSPENDED` hoặc `BLOCKED` chờ khóa (lock):
  ```
  "main" prio=5 tid=1 Blocked
    waiting to lock <0x0a1b2c3d> (a android.database.sqlite.SQLiteDatabase)
    at com.mediatech.ledkeyboardtheme.ClipboardDatabaseHelper.addClip(...)
  ```
  $\rightarrow$ **Kết luận:** Main Thread đang bị khóa bởi thao tác Database.

* Nếu thấy trạng thái `RUNNABLE` ở tầng Native Binder / Assets:
  ```
  "main" prio=5 tid=1 Runnable
    at android.content.res.AssetManager.list(...)
    at com.mediatech.ledkeyboardtheme.KeyboardThemeEngine.loadTypeface(...)
  ```
  $\rightarrow$ **Kết luận:** Main Thread bị nghẽn do gọi `AssetManager.list()`.

---

## 6. Checklist Phòng Chống ANR & Crash Cho Dự Án Mới

| STT | Quy tắc kiểm tra phòng chống ANR & Crash | Đạt |
|:---:|:---|:---:|
| **1** | Toàn bộ các câu lệnh SQLite / Room Database / SharedPreferences đều thực thi qua Background Executor hoặc Coroutine (`Dispatchers.IO`). | [ ] |
| **2** | Không có bất kỳ lệnh `context.assets.list()` hoặc `File.readBytes()` nào chạy trên Main Thread. | [ ] |
| **3** | Typeface và Bitmap được decode hoàn toàn trên luồng nền trước khi chuyển về View. | [ ] |
| **4** | Trong hàm `onDraw` của Custom View, không khởi tạo `new Matrix()`, `new Paint()`, `new Shader()`. | [ ] |
| **5** | Mọi Service / Custom View đều cài đặt `stopAnimation()` tại `onWindowHidden()` và `onDestroy()`. | [ ] |
| **6** | Các hàm parse JSON lớn trong Flutter đều được bọc qua `compute()` hoặc `Isolate.run()`. | [ ] |
| **7** | Không thực hiện network call hay disk I/O trong `BroadcastReceiver.onReceive()`. | [ ] |
| **8** | ProGuard/R8 rules đã giữ nguyên các class SQLite, Service, JNI và Entry Point an toàn. | [ ] |
| **9** | Đã cấu hình meta-data `OPTIMIZE_INITIALIZATION` và `OPTIMIZE_AD_LOADING` trong `AndroidManifest.xml`. | [ ] |
| **10** | Đã bật `android:extractNativeLibs="true"`, khai báo `ndk.abiFilters`, giữ `FlutterJNI` để chống `MissingLibraryException`. | [ ] |
| **11** | Cài đặt Triple Guard chống `PlatformViewsController resize NPE`: Safe Factory + PostFrameCallback dispose + Global Error Filter. | [ ] |
| **12** | Khóa Re-entrancy trong `AdsNavigationHelper` và bọc `AbsorbPointer` trên overlay chờ ad chống ANR `No focused window`. | [ ] |
| **13** | Mọi SDK bên thứ ba (RevenueCat, IAP, RemoteConfig) trong Splash đều có timeout cứng $\le 2500\text{ms}$ và fallback an toàn. | [ ] |

