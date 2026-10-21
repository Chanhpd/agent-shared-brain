# TRIỆT TIÊU ANR NGHẼN TRÌNH BIÊN DỊCH SHADER GPU ARM MALI VÀ CPU DOUBLE-BUFFERING (cmpbe_v2_compile_multiple_shaders & nativePollOnce)

- **Ngày ghi nhận:** 2026-10-21
- **Phân loại:** Android / Flutter / Performance / Graphics / Vitals
- **Mức độ nghiêm trọng:** Critical
- **Dự án phát hiện lần đầu:** `led_keyboard` (LED Keyboard: RGB, Neon Theme)
- **Môi trường:** Máy thật Android (Samsung Galaxy A/M series, Xiaomi Redmi chạy chip Exynos / MediaTek với chip GPU ARM Mali) - Phiên bản phát hành công khai `1.0.26 (376)`

---

## 1. Triệu Chứng (Symptom & Error Logs)

Trên Google Play Console ghi nhận cụm lỗi ANR người dùng nhận thấy (*User-perceived ANR*), phát sinh ngay sau khi cập nhật engine hiệu ứng ánh sáng bàn phím động (20 Styles LED shaders) trên bản `1.0.26`:

```text
Input dispatching timed out
Lỗi ứng dụng không phản hồi (ANR)
Chữ ký lỗi: [libGLES_mali.so] cmpbe_v2_compile_multiple_shaders
Phiên bản bị ảnh hưởng: 376 (1.0.26)
```

Đi kèm với đó là cụm lỗi phụ chiếm tỷ trọng lớn (26% tổng sự kiện ANR):
```text
Input dispatching timed out
Native method - android.os.MessageQueue.nativePollOnce / [libc.so] __ioctl
```

Người dùng phản ánh: Khi mở bàn phím lên và gõ phím ngay lập tức, ứng dụng bị đơ cứng quá 5 giây và hiện hộp thoại *"Ứng dụng không phản hồi"*.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

Sự cố bắt nguồn từ **3 cơ chế cộng hưởng gây thắt cổ chai tài nguyên CPU & GPU**:

### 2.1. Nghẽn băng thông bộ nhớ do CPU Double-Buffering per-frame
* Trong `FullRgbKeyboardView.kt`, để render chữ phím và viền phím theo màu chuyển động của LED shader, cơ chế cũ cấp phát 2 Bitmap full màn hình (`keyMaskBitmap` và `ledBufferBitmap`) kích thước $1080 \times 700$ ARGB_8888 (~3 MB mỗi bitmap).
* Mỗi frame hoạt ảnh ở 60 FPS:
  1. `bufCanvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)` $\rightarrow$ Ghi 3 MB số 0.
  2. `bufCanvas.drawBitmap(maskBmp, 0f, 0f, maskCopyPaint)` $\rightarrow$ Copy 3 MB bộ nhớ CPU.
  3. `themeEngine.drawLedOverlaySrcIn(bufCanvas, ...)` $\rightarrow$ CPU đọc 3 MB, tính toán gradient và ghi 3 MB.
  4. `canvas.drawBitmap(bufBmp, 0f, 0f, ledBufferPaint)` $\rightarrow$ HWUI upload 3 MB texture qua bus hệ thống lên GPU.
* Tổng băng thông RAM bị chiếm dụng trên luồng chính: **~12 MB/frame $\times$ 60 FPS $\approx$ 720 MB/giây**!
* Trên các thiết bị Android tầm trung và thấp, bus bộ nhớ bị bão hòa hoàn toàn.

### 2.2. Trình điều khiển GPU ARM Mali biên dịch Shader đồng bộ (`cmpbe_v2_compile_multiple_shaders`)
* `cmpbe` (*Compiler Multi-Program Binary Engine*) là trình biên dịch nhị phân shader nội bộ của driver Mali (`libGLES_mali.so`).
* Khi kết hợp CPU texture upload liên tục với việc vẽ dynamic shader (như `SweepGradient` / `LinearGradient` xoay liên tục kết hợp `MaskFilter.blur` trong Flutter `CustomPainter`), driver Mali bị ép phải biên dịch và liên kết nhiều biến thể shader Gaussian blur + gradient rotation một cách **đồng bộ ngay trên luồng chính**.
* Trong lúc CPU bị nghẽn RAM do copy 720 MB/s, việc biên dịch shader của Mali bị trì hoãn vượt quá **5 giây** $\rightarrow$ Kích hoạt ANR ngay khi người dùng chạm vào phím.

### 2.3. Lệnh gọi Binder IPC Clipboard & Invalidation Flooding
* Trong `LedInputMethodService.kt`, hàm `onStartInputView()` gọi trực tiếp `captureCurrentClipboard()`, thực hiện truy cập `clipboardManager?.primaryClip` (lệnh gọi Binder IPC) đồng bộ trên Main Thread.
* Trong `onTouchEvent`, các sự kiện `ACTION_DOWN`, `ACTION_POINTER_DOWN`, `ACTION_MOVE` gọi dồn dập `postInvalidateOnAnimation()` ngay cả khi `ValueAnimator` đã chạy đều đặn ở 60 FPS, làm tràn hàng đợi Choreographer vsync.

---

## 3. Giải Pháp Triệt Để (Verified Solution)

### 3.1. Chuyển sang Hardware `canvas.saveLayer` trực tiếp trên GPU
Loại bỏ hoàn toàn `ledBufferBitmap`, `ledBufferCanvas`, xóa bỏ toàn bộ các lệnh copy 3MB CPU mỗi frame:

```kotlin
// FullRgbKeyboardView.kt
if (canvas.isHardwareAccelerated) {
    // Tận dụng GPU Framebuffer Object (FBO) - 0 MB CPU copy, 0 CPU rasterization
    val layerCount = canvas.saveLayer(0f, 0f, w.toFloat(), h.toFloat(), null)
    canvas.drawBitmap(maskBmp, 0f, 0f, null)
    themeEngine.drawLedOverlaySrcIn(canvas, w.toFloat(), h.toFloat(), cachedKeyBounds)
    canvas.restoreToCount(layerCount)
} else {
    // Fallback an toàn cho canvas không có hardware acceleration
    super.dispatchDraw(canvas)
    themeEngine.drawKeyBorders(canvas, this)
}
```

### 3.2. Caching mặt nạ phím (`keyMaskBitmap`)
Chỉ vẽ lại `keyMaskBitmap` khi thực sự dirty (`isKeyMaskDirty == true`, khi đổi layout hoặc bấm phím). Khi hoạt ảnh LED chạy, mask giữ nguyên trong RAM, GPU chỉ blend shader di động lên mask mà không tốn công rasterize lại 50+ child views.

### 3.3. Loại bỏ `MaskFilter.blur` trên Dynamic Shader trong Flutter
Trong `_RotatingOutlinePainter`, thay vì áp `MaskFilter.blur` lên Paint có dynamic `SweepGradient` xoay 60 FPS (khiến driver Mali stall), chuyển sang kỹ thuật dual-pass stroke outline:

```dart
// interactive_keyboard_preview.dart
// Pass 1: Glow outline với độ dày mở rộng (không dùng MaskFilter.blur trên dynamic shader)
final glowPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = _strokeWidth + 2.0
  ..strokeCap = StrokeCap.round
  ..color = const Color(0x3300FFB2)
  ..shader = shader;
canvas.drawRRect(rrect, glowPaint);

// Pass 2: Core sharp outline
final corePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = _strokeWidth
  ..strokeCap = StrokeCap.round
  ..shader = shader;
canvas.drawRRect(rrect, corePaint);
```

### 3.4. Đẩy Binder IPC Clipboard sang Background Executor
```kotlin
// LedInputMethodService.kt
fun captureCurrentClipboard() {
    initExecutor.execute {
        try {
            val clip = clipboardManager?.primaryClip
            if (clip != null && clip.itemCount > 0) {
                val text = clip.getItemAt(0)?.text?.toString()
                if (!text.isNullOrBlank()) {
                    clipboardDb.addClipAsync(text)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to capture current clipboard", e)
        }
    }
}
```

### 3.5. Chống Invalidation Flooding trên Touch Events
```kotlin
// FullRgbKeyboardView.kt - onTouchEvent
val code = getHitKeyCode(hit)
themeEngine.onKeyTouch(code, ev.x, ev.y)
// Chỉ invalidate nếu animator chưa tự động tick (tránh spam Choreographer)
if (themeEngine.isLedActive && !themeEngine.isAnimationRunning) {
    postInvalidateOnAnimation()
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] **Không CPU Double-Buffering per-frame:** Tuyệt đối không tạo `Bitmap.createBitmap` và gọi `drawBitmap` trên software canvas 60 FPS để làm hiệu ứng mask/blend. Luôn dùng `canvas.saveLayer(bounds, null)` trên Hardware Canvas.
- [ ] **Không `MaskFilter.blur` trên Dynamic Shader trong Flutter:** Không bao giờ kết hợp `MaskFilter.blur` với Paint có Shader động (gradient xoay/di chuyển) vì sẽ kích hoạt driver compile shader đồng bộ trên GPU Mali.
- [ ] **Bảo vệ IPC Binder Calls:** Mọi lệnh gọi hệ thống Android như `clipboardManager.primaryClip`, `connectivityManager`, `packageManager.getInstalledPackages` phải chạy trên Background Executor/Coroutines IO.
- [ ] **Tránh Invalidation Flooding:** Khi `ValueAnimator` đang chạy đều 60 FPS, không gọi thêm `postInvalidateOnAnimation()` trong các hàm xử lý chạm `onTouchEvent`.
- [ ] **Fallback An Toàn:** Mọi cơ chế render cao cấp dùng `saveLayer` hoặc shader phải có fallback `super.dispatchDraw` / `drawKeyBorders` phẳng nếu GPU gặp lỗi.

---

## 5. Tài Liệu Tham Khảo (References)
- [ARM Mali Midgard/Bifrost Architecture - Shader Compilation & Pipeline Caching](https://developer.arm.com/documentation/)
- [Android Hardware Acceleration & Canvas.saveLayer](https://developer.android.com/topic/performance/graphics/hardware-accel)
- [Google Play Vitals - User-perceived ANR Threshold < 0.47%](https://developer.android.com/topic/performance/vitals/anr)
