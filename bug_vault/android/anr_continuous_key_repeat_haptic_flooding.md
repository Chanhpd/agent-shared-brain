# Continuous Key Repeat Haptic Flooding & Main Looper Starvation (`triggerHaptic` & `nativePollOnce`)

- **Ngày ghi nhận:** 2026-11-02
- **Phân loại:** Android / Haptics / UI Performance / Looper Starvation / ANR
- **Mức độ nghiêm trọng:** Critical (Cụm `nativePollOnce` chiếm tới 9.8% tổng sự kiện ANR trên bản phát hành chính thức 1.0.31)
- **Dự án phát hiện lần đầu:** `led_keyboard` (LED Keyboard: RGB, Neon Theme)
- **Môi trường:** Android Native / Production Google Play Console (Bản 1.0.26 – 1.0.31)

---

## 1. Triệu Chứng (Symptom & Error Logs)

Trên Google Play Console ghi nhận 2 cụm ANR xuất hiện tần suất cao:
1. `Native method - android.os.MessageQueue.nativePollOnce` - `Input dispatching timed out` (Chiếm 9.8% tổng sự cố ANR bản 1.0.31).
2. `com.mediatech.ledkeyboardtheme.KeyboardFeedbackManager.triggerHaptic` - `Input dispatching timed out` (Chiếm 2.0% bản 1.0.26).

Stack trace minh họa:
```text
"main" prio=5 tid=1 Blocked
  at android.os.SystemVibrator.vibrate(SystemVibrator.java:...)
  at com.mediatech.ledkeyboardtheme.KeyboardFeedbackManager.triggerHaptic(KeyboardFeedbackManager.kt:195)
  at com.mediatech.ledkeyboardtheme.FullRgbKeyboardView$deleteRunnable.run(FullRgbKeyboardView.kt:173)
  at android.os.Handler.handleCallback(Handler.java:938)
  at android.os.Looper.loopOnce(Looper.java:201)
  at android.os.Looper.loop(Looper.java:288)
  at android.app.ActivityThread.main(ActivityThread.java:7876)
```

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Bão rung 20 lần/giây khi giữ phím Backspace / Auto-repeat:**
   Khi người dùng giữ phím Delete, ứng dụng sử dụng một `Runnable` lặp lại mỗi **50ms (20 lần/giây)** để xóa ký tự liên tục:
   ```kotlin
   val deleteRunnable = object : Runnable {
       override fun run() {
           if (isDeleting) {
               onKeyAction(KeyAction.DELETE, null)
               feedbackManager.playSound()
               feedbackManager.triggerHaptic() // BÃO RUNG: 20 LẦN MỖI GIÂY!
               deleteHandler.postDelayed(this, 50)
           }
       }
   }
   ```
2. **IPC Binder quá tải trên từng phím chạm:**
   Trong hàm `triggerHaptic()` cũ:
   - Gọi `context.getSystemService(Context.VIBRATOR_SERVICE)` mỗi lần nhấn.
   - Gọi `vibrator.hasVibrator()` $\rightarrow$ **1 cuộc gọi IPC Binder** sang `IVibratorService`.
   - Gọi `vibrator.vibrate(...)` $\rightarrow$ **thêm 1 cuộc gọi IPC Binder** tiếp theo.
3. Khi người dùng giữ phím xóa trong 2 giây, có tới **40-60 cuộc gọi IPC Binder** được gửi dồn dập vào driver rung của phần cứng.
4. Khi HAL rung hoặc `system_server` bị quá tải, Main Thread bị block trong `SystemVibrator.vibrate()`. Hàng đợi `MessageQueue` của Main Looper bị nghẽn (Looper starvation), dẫn đến việc hệ điều hành không thể phân phát sự kiện chạm người dùng tiếp theo trong vòng 5 giây $\rightarrow$ Kích hoạt ANR `nativePollOnce`.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### A. Tắt Haptic Trong Vòng Lặp Auto-Repeat Của Phím Giữ
Khi người dùng giữ phím (Delete, Space, Arrow keys), haptic feedback **chỉ được phép kích hoạt 1 lần duy nhất khi ngón tay vừa chạm xuống (`ACTION_DOWN`)**. Tuyệt đối không rung lặp lại trong `deleteRunnable`:

```kotlin
val deleteRunnable = object : Runnable {
    override fun run() {
        if (isDeleting) {
            onKeyAction(KeyAction.DELETE, null)
            feedbackManager.playSound()
            // ĐÃ BỎ: feedbackManager.triggerHaptic()
            deleteHandler.postDelayed(this, 50)
        }
    }
}
```

### B. Cache Phần Cứng & Ưu Tiên `View.performHapticFeedback`
Trong `KeyboardFeedbackManager.kt`:
1. Cache đối tượng `Vibrator` một lần duy nhất lúc khởi tạo (hỗ trợ `VibratorManager` trên Android 12+ / API 31+).
2. Cache cờ `hasVibratorHardware` để không bao giờ gọi IPC `vibrator.hasVibrator()` lặp lại.
3. Thêm bộ lọc tần suất (Throttle) tối thiểu **35ms** (`minHapticIntervalMs`).
4. Ưu tiên sử dụng `view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)` vì phương thức này được WindowManager tối ưu ở tầng framework, không gây nghẽn driver rung.

```kotlin
class KeyboardFeedbackManager private constructor(private val context: Context) {
    private val vibrator: Vibrator? by lazy {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? android.os.VibratorManager
                vm?.defaultVibrator ?: (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Exception) { null }
    }

    private val hasVibratorHardware: Boolean by lazy {
        try { vibrator?.hasVibrator() ?: false } catch (_: Exception) { false }
    }

    @Volatile
    private var lastHapticTime: Long = 0L
    private val minHapticIntervalMs = 35L

    fun triggerHaptic(view: View? = null) {
        if (!vibrateEnabled) return

        // 1. Thử View.performHapticFeedback trước (không tốn IPC Binder)
        if (view != null && view.isAttachedToWindow) {
            try {
                val performed = view.performHapticFeedback(
                    HapticFeedbackConstants.KEYBOARD_TAP,
                    HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
                )
                if (performed) return
            } catch (_: Throwable) {}
        }

        // 2. Lọc tần suất gọi (Throttle) chống nghẽn driver
        val now = SystemClock.uptimeMillis()
        if (now - lastHapticTime < minHapticIntervalMs) return
        lastHapticTime = now

        if (!hasVibratorHardware) return
        val v = vibrator ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createOneShot(vibrationDuration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(vibrationDuration)
            }
        } catch (_: Exception) {}
    }
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Trong các hành động giữ phím / chạm lặp lại (Auto-repeat / Continuous delete / Scroll drag), haptic có bị gọi lặp lại không?
- [ ] Cờ `hasVibrator()` và đối tượng `Vibrator` đã được cache một lần duy nhất chưa?
- [ ] Đã có bộ lọc tần suất (Throttle tối thiểu 30-40ms) chống spam lệnh rung khi gõ phím siêu nhanh chưa?
- [ ] Đã ưu tiên `view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)` thay vì gọi trực tiếp `Vibrator` IPC service chưa?
