# Slow IPC Binder Calls in Flutter Platform/MethodChannel Handler (`configureFlutterEngine$lambda`)

- **Ngày ghi nhận:** 2026-11-02
- **Phân loại:** Android / Flutter / PlatformChannel / IPC Binder / ANR
- **Mức độ nghiêm trọng:** Major (Gây ANR có nhãn cảnh báo chính thức từ Google Play Console: *"Lệnh gọi Binder chậm"*)
- **Dự án phát hiện lần đầu:** `led_keyboard` (LED Keyboard: RGB, Neon Theme)
- **Môi trường:** Android Native / Production Google Play Console (Bản 1.0.30)

---

## 1. Triệu Chứng (Symptom & Error Logs)

Trên Google Play Console xuất hiện cụm sự cố ANR:
- **Cụm lỗi:** `com.mediatech.ledkeyboardtheme.MainActivity.configureFlutterEngine$lambda$1`
- **Loại:** `Input dispatching timed out`
- **Nhãn cảnh báo Google:** ⚠️ **Lệnh gọi Binder chậm** (*The main thread is busy executing a potentially slow Binder call*).

Stack trace minh họa:
```text
"main" prio=5 tid=1 Native
  at android.os.BinderProxy.transactNative(Native Method)
  at android.os.BinderProxy.transact(BinderProxy.java:628)
  at com.android.internal.view.IInputMethodManager$Stub$Proxy.getEnabledInputMethodList(...)
  at android.view.inputmethod.InputMethodManager.getEnabledInputMethodList(...)
  at com.mediatech.ledkeyboardtheme.MainActivity.isKeyboardEnabled(MainActivity.kt:430)
  at com.mediatech.ledkeyboardtheme.MainActivity.configureFlutterEngine$lambda$1(MainActivity.kt:162)
  at io.flutter.plugin.common.MethodChannel$IncomingMethodCallHandler.onMessage(MethodChannel.java:267)
```

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Bản chất của Flutter MethodChannel:**
   Khi Flutter Dart gửi tin nhắn qua `MethodChannel.invokeMethod()`, callback `setMethodCallHandler` ở tầng Android Native được thực thi mặc định trên **Main Looper (UI Thread)** của Android.
2. **Thực thi IPC Binder Call đồng bộ trên Main Thread:**
   Trong handler, developer thường vô tình gọi trực tiếp các API của hệ thống Android:
   - `InputMethodManager.getEnabledInputMethodList` (gọi IPC Binder sang `InputMethodManagerService`).
   - `Settings.Secure.getString(contentResolver, ...)` (gọi IPC Binder sang `SettingsProvider`).
   - `PackageManager.getPackageInfo()` / `getApplicationLabel()` (gọi IPC Binder sang `PackageManagerService`).
3. **Hiện tượng nghẽn Binder (Binder Starvation / Lock Contention):**
   Trên thiết bị Android khi hệ điều hành đang bận (khởi động app, chuyển đổi cấu hình, low memory), các tiến trình `system_server` phản hồi IPC Binder chậm quá 5 giây. Luồng Main Thread của ứng dụng bị giữ chặt ở phương thức native `BinderProxy.transactNative()` $\rightarrow$ Hệ thống kích hoạt ANR với cảnh báo *"Lệnh gọi Binder chậm"*.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### Nguyên Tắc Vàng:
**Mọi lệnh gọi IPC Binder hoặc truy vấn hệ thống trong MethodChannel BẮT BUỘC phải thực thi trên Background Thread (SingleThreadExecutor / Coroutines), sau đó post kết quả về Dart qua `mainHandler`.**

### Mã Nguồn Chuẩn Hóa:
```kotlin
// Trong MainActivity.kt
private val ioExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
        when (call.method) {
            "isImeEnabled" -> {
                // Chuyển toàn bộ IPC Binder sang Background Executor
                ioExecutor.execute {
                    val enabled = isKeyboardEnabled()
                    mainHandler.post {
                        result.success(enabled)
                    }
                }
            }
            "isImeSelected" -> {
                ioExecutor.execute {
                    val selected = isKeyboardSelected()
                    mainHandler.post {
                        result.success(selected)
                    }
                }
            }
            "getDeviceInfo" -> {
                ioExecutor.execute {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        val info = mapOf("version" to (pInfo.versionName ?: ""))
                        mainHandler.post { result.success(info) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(emptyMap<String, String>()) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Trong `configureFlutterEngine()` và mọi `MethodChannel.setMethodCallHandler`, có gọi trực tiếp `packageManager`, `contentResolver`, `inputMethodManager`, `telephonyManager` không?
- [ ] Toàn bộ các lời gọi `getSystemService` có IPC Binder đã được bọc trong `ioExecutor.execute { ... }` chưa?
- [ ] Kết quả trả về cho `result.success()` hoặc `result.error()` đã được post ngược lại Main Thread qua `mainHandler.post` chưa?
