# Image Network Fallback Bug & Resilient Disk Caching Architecture

- **Ngày ghi nhận:** 2026-10-23
- **Phân loại:** Flutter / Performance / Network / Image Caching
- **Mức độ nghiêm trọng:** Major (Ảnh hiển thị sai lệch, rớt về icon fallback vĩnh viễn, tốn băng thông)
- **Dự án phát hiện lần đầu:** LED Keyboard (`led_keyboard`)
- **Môi trường:** Máy thật & Máy ảo / Android & iOS / Flutter 3.x

---

## 1. Triệu Chứng (Symptom & Error Logs)

- Khi mở màn hình danh sách (như Wallpaper, Themes, Stickers), một số lượng lớn card hiển thị chậm hoặc lập tức nhảy về **icon fallback mặc định** (ví dụ: icon bàn phím xám).
- Giao diện trông như bị lỗi dữ liệu, tạo ấn tượng app bị đơ/hỏng.
- **Nghịch lý:** Khi người dùng bấm vào xem chi tiết (Detail Screen / BottomSheet), ảnh của item đó lại hiển thị sắc nét và đầy đủ 100% bình thường.

Logcat / Flutter DevTools error:
```text
SocketException: OS Error: Connection timed out, errno = 110, address = cdn.example.com, port = 443
HTTP request failed, statusCode: 504 / ClientException: Connection closed before full header was received
```

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Hạn chế cố hữu của `Image.network` mặc định:**
   - `Image.network` chỉ lưu trữ tạm trên RAM (`PaintingBinding.instance.imageCache`). Khi ứng dụng tắt đi mở lại hoặc RAM đầy bị dọn dẹp, toàn bộ ảnh phải tải lại từ đầu qua Internet.
   - Không có bộ đệm lưu trữ đĩa (Persistent Disk Cache).
2. **Nghẽn đường truyền do tải ồ ạt đồng thời (Socket Exhaustion):**
   - Khi SliverGrid dựng 20 item trong danh mục, 20 kết nối HTTP được bắn ra cùng 1 thời điểm.
   - Trên mạng 4G/3G hoặc Wi-Fi chập chờn, hàng loạt request bị nghẽn (packet drop, TCP timeout), dẫn đến `SocketException`.
3. **Flutter `errorBuilder` không tự phục hồi (No Auto-Retry):**
   - Khi `ImageStreamListener.onError` được kích hoạt bởi lỗi mạng tức thời (transient glitch), Flutter đánh dấu ảnh bị lỗi và chuyển vĩnh viễn sang `errorBuilder`.
   - Flutter không bao giờ tự động thử lại (retry) nếu không có sự can thiệp từ State bên ngoài.
4. **Tại sao BottomSheet lại tải thành công?**
   - Ở màn hình danh sách, 20 ảnh tranh chấp băng thông nên bị nghẽn.
   - Khi vào BottomSheet chi tiết, chỉ có **duy nhất 1 request** đơn lẻ chạy trên đường truyền mạng đang rảnh rỗi nên tải thành công lập tức.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

Thay thế hoàn toàn `Image.network` thô bằng component cache ảnh độc lập chuẩn hóa `AppCachedNetworkImage`:

### A. Kiến trúc Bộ nhớ đệm 2 tầng (Memory Index + Persistent Disk)
1. Tra cứu siêu tốc trên RAM bằng `Map<String, String> _diskCacheIndex` (O(1)).
2. Nếu chưa có trên index RAM, kiểm tra file trên ổ đĩa (`theme_image_cache/<hash>_<filename>`).
3. Nếu đã có file: Nạp thẳng qua `FileImage(file)` kết hợp `ResizeImage` theo kích thước hiển thị thực tế (`cacheWidth: 360`) để tối ưu GPU/RAM Rasterization.

### B. Giới hạn luồng tải đồng thời (Concurrency Queue)
Chống nghẽn socket bằng cơ chế hàng đợi bất đồng bộ:
```dart
static const int _maxConcurrentDownloads = 8;
static int _activeDownloads = 0;
static final List<Completer<void>> _downloadWaitQueue = [];

static Future<File?> _queuedDownload(String url, File targetFile) async {
  while (_activeDownloads >= _maxConcurrentDownloads) {
    final waiter = Completer<void>();
    _downloadWaitQueue.add(waiter);
    await waiter.future;
  }
  _activeDownloads++;
  try {
    return await _downloadToFile(url, targetFile);
  } finally {
    _activeDownloads--;
    if (_downloadWaitQueue.isNotEmpty) {
      _downloadWaitQueue.removeAt(0).complete();
    }
  }
}
```

### C. Tự động Retry ngầm trước khi hiển thị Fallback
Khi gặp lỗi rớt mạng tạm thời, không hiển thị icon fallback ngay mà hẹn giờ tự động thử lại 2 lần:
```dart
onError: (error, stackTrace) {
  if (_retryCount < _maxRetries) {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _retryCount++;
          _hasError = false;
        });
        _resolveAndListen();
      }
    });
    return;
  }
  if (mounted) {
    setState(() => _hasError = true);
  }
}
```

### D. Chuẩn hóa canh lề hiển thị (Alignment)
Đặt mặc định `Alignment.bottomCenter` cho ảnh preview bàn phím để khi co giãn tỉ lệ (Aspect Ratio) trên nhiều kích thước màn hình khác nhau, phần chân phím quan trọng không bị cắt cụt.

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Tuyệt đối **KHÔNG dùng `Image.network` trực tiếp** trong các danh sách cuộn (GridView / ListView) chứa nhiều hơn 4 ảnh.
- [ ] Mọi component ảnh mạng đều phải có cơ chế **Disk Cache nội bộ** để tiết kiệm băng thông và hỗ trợ offline.
- [ ] Phải có cơ chế **Concurrency Throttle** giới hạn số kết nối đồng thời từ 4 đến 8 để bảo vệ socket pool.
- [ ] Luôn có cơ chế **Auto-Retry có độ trễ (Backoff)** trước khi hiển thị UI trạng thái lỗi `errorBuilder`.
- [ ] Luôn truyền `cacheWidth` / `cacheHeight` tương ứng với kích thước hiển thị thực tế trên UI để tránh nhồi bitmap khổng lồ vào RAM.

---

## 5. Tài Liệu Tham Khảo (References)
- [Flutter Painting ImageCache Documentation](https://api.flutter.dev/flutter/painting/ImageCache-class.html)
- Code chuẩn triển khai: `lib/core/widgets/app_cached_network_image.dart`
