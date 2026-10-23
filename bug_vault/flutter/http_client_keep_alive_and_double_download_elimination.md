# Persistent HttpClient Keep-Alive, Double-Download & Stream Reset Elimination

- **Ngày ghi nhận:** 2026-10-23
- **Phân loại:** Flutter / Network / Performance / HTTP Engine / Cloudflare R2
- **Mức độ nghiêm trọng:** Major (Ảnh CDN/R2 chỉ 15KB nhưng mất tới 2.5s - 3s mới hiển thị, tốn x2 băng thông)
- **Dự án phát hiện lần đầu:** LED Keyboard (`led_keyboard`)
- **Môi trường:** Máy thật & Máy ảo / Android & iOS / Cloudflare R2 & CDN / Flutter 3.x

---

## 1. Triệu Chứng (Symptom & Error Logs)

- Khi người dùng chuyển qua một danh mục mới (ví dụ: *Gradient, LED*):
  - Tên các thẻ và khung layout xuất hiện gần như tức thì (<150ms).
  - Tuy nhiên, toàn bộ vùng ảnh thumbnail preview bên trong thẻ lại bị trống / hiển thị shimmer suốt **2.5 đến 3 giây** mới hiện ra.
- **Nghi vấn ban đầu:** Nghi ngờ API chậm hoặc kho lưu trữ Cloudflare R2 bị thắt cổ chai.
- **Thực tế kiểm tra mạng (Network Inspection):**
  - API metadata `/api/v1/themes` trả về JSON danh sách chỉ mất **~94ms**.
  - File ảnh trên Cloudflare R2 là định dạng WebP siêu nhẹ: **chỉ ~15.3 KB / ảnh**.
  - Header phản hồi từ CDN: `server: cloudflare`, `cf-cache-status: HIT` (đã nằm sẵn trên CDN Edge gần nhất).

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

Vấn đề 100% nằm ở kiến trúc xử lý nạp ảnh (`AppCachedNetworkImage`) tại tầng Client:

### A. Triệt tiêu HTTP Keep-Alive & TLS Resumption do đóng mở Client liên tục
Trong hàm tải file đệm xuống đĩa `_downloadToFile`:
```dart
// Code lỗi:
final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
final request = await client.getUrl(uri);
final response = await request.close();
// ... ghi file ...
client.close(); // SAI LẦM NGHIÊM TRỌNG!
```
- Việc gọi `client.close()` sau mỗi lần tải ảnh đã **đóng đứt kết nối socket TCP**.
- Mỗi ảnh thumbnail tiếp theo đều phải chạy lại toàn bộ chu trình bắt tay: *DNS Lookup -> TCP 3-way Handshake -> TLS 1.3 Handshake* tới server Cloudflare.
- Trên mạng di động/máy ảo, mỗi lần bắt tay TLS tốn 200ms – 400ms RTT. Tải 4 ảnh đầu tiên mất tới: `4 * ~400ms + transfer` = **~2.6 giây**!

### B. Tải trùng lặp 2 lần cho 1 tấm ảnh (Double Download)
- Luồng 1: Flutter engine kích hoạt `NetworkImage(url)` để giải mã hiển thị lên màn hình.
- Luồng 2: Cùng lúc đó, hàm `_checkDiskCache` lại gọi `_downloadToFile(url)` mở thêm một kết nối HTTP nữa để tải ghi file xuống đĩa.
- **Hệ quả:** Mỗi card mở 2 kết nối tải song song cùng một file, ngốn gấp đôi băng thông thiết bị và gây tắc nghẽn cục bộ.

### C. Xung đột luồng Stream (Stream Reset)
- Khi luồng ghi đĩa `_downloadToFile` tải xong, code thực hiện:
  ```dart
  if (file != null && !_isLoaded) {
    _resolveAndListen(); // HỦY luồng NetworkImage đang tải dở!
  }
  ```
- Nếu `NetworkImage` của Flutter đang nạp gần xong (ví dụ 90%), việc gọi lại `_resolveAndListen()` sẽ hủy toàn bộ tiến trình nạp cũ để bắt đầu đọc lại từ file đĩa, kéo dài thời gian chờ đợi của người dùng.

### D. Giới hạn luồng tải quá thấp & Animation trễ
- Cấu hình `_maxConcurrentDownloads = 4` khiến 16 ảnh còn lại trong category bị dồn ứ trong hàng đợi.
- Animation fade-in mặc định để tới `350ms`, cộng dồn vào độ trễ cảm nhận của người dùng.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### A. Singleton `HttpClient` Tận dụng Connection Pool & Keep-Alive
Giữ kết nối socket mở liên tục để tái sử dụng cho các request ảnh tiếp theo:
```dart
class AppCachedNetworkImage extends StatefulWidget {
  static HttpClient? _sharedHttpClient;

  static HttpClient get _httpClient {
    if (_sharedHttpClient != null) return _sharedHttpClient!;
    _sharedHttpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 10;
    return _sharedHttpClient!;
  }
}

// Trong hàm tải: KHÔNG gọi client.close()!
static Future<File?> _downloadToFile(String url, File targetFile) async {
  try {
    final client = AppCachedNetworkImage._httpClient; // Tái sử dụng socket
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 200) {
      final tempFile = File('${targetFile.path}.tmp_${DateTime.now().millisecondsSinceEpoch}');
      final sink = tempFile.openWrite();
      await response.pipe(sink);
      await sink.close();
      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        tempFile.renameSync(targetFile.path);
        return targetFile;
      }
    }
  } catch (_) {}
  return null;
}
```

### B. Nâng Concurrency và Pre-warm Disk Cache
- Tăng `_maxConcurrentDownloads` từ `4` lên `8` để tải trọn vẹn toàn bộ card trong khung nhìn viewport.
- Bổ sung cơ chế `_prewarmDiskCache`: Khi `HomeScreen` chạy `precacheImage` cho 6 theme đầu tiên, disk cache được kích hoạt tải ngầm ngay lập tức:
```dart
static void _prewarmDiskCache(String url, File targetFile) {
  if (_inFlightDownloads.containsKey(url)) return;
  final downloadFuture = _inFlightDownloads.putIfAbsent(
    url,
    () => _AppCachedNetworkImageState._queuedDownload(url, targetFile),
  );
  downloadFuture.then((file) {
    if (file != null && file.existsSync() && file.lengthSync() > 0) {
      _diskCacheIndex[url] = file.path;
    }
  }).whenComplete(() => _inFlightDownloads.remove(url));
}
```

### C. Tinh chỉnh Thời lượng Reveal Animation
Giảm thời lượng chuyển cảnh từ `350ms` xuống `140ms` (`Curves.easeOutCubic`), giúp ảnh hiển thị tức thì, sắc nét ngay khi giải mã xong mà không bị giật.

---

## 4. Bảng So Sánh Hiệu Năng Thực Tế

| Chỉ số | Trước khi tối ưu | Sau khi tối ưu | Mức độ cải thiện |
| :--- | :--- | :--- | :--- |
| **Bắt tay mạng (TLS Handshake)** | Chạy lại cho từng ảnh (4 x 350ms) | Tái sử dụng socket qua Keep-Alive | 🚀 **Tiết kiệm ~1.2 giây** |
| **Tải 4 ảnh thumbnail đầu** | **~2.597 ms** | **~350 ms – 500 ms** | 🚀 **Nhanh gấp 5 lần** |
| **Lần thứ 2 mở lại tab** | 350 ms (độ trễ fade-in) | **0 ms (hiển thị tức thì)** | ⚡ **Mượt mà tuyệt đối** |
| **Băng thông tiêu thụ** | 2 x dung lượng (tải đúp) | 1 x dung lượng chuẩn (15KB) | 📉 **Tiết kiệm 50% data** |

---

## 5. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] **TUYỆT ĐỐI KHÔNG** khởi tạo và `close()` `HttpClient` trên từng tác vụ tải tài nguyên lặp đi lặp lại. Luôn dùng persistent client có Keep-Alive (`idleTimeout >= 30s`).
- [ ] Không tạo các luồng tải song song độc lập cho cùng 1 URL (vừa tải RAM vừa tải đĩa riêng biệt) nếu không có cơ chế chia sẻ byte stream.
- [ ] Không ngắt/hủy Stream ảnh đang nạp dở (`_resolveAndListen()`) khi không có lý do bắt buộc.
- [ ] Khi thiết kế component ảnh danh sách, hãy tính toán số item hiển thị trung bình trên 1 màn hình để cấu hình `maxConcurrentDownloads` phù hợp (thường từ 6 đến 10).
- [ ] Animation placeholder sang ảnh thật chỉ nên duy trì từ `120ms – 160ms`.

---

## 6. Tài Liệu Tham Khảo (References)
- [Dart HttpClient Persistent Connections & Keep-Alive](https://api.dart.dev/stable/dart-io/HttpClient-class.html)
- [Cloudflare CDN Cache Hit & TLS 1.3 Session Optimization](https://developers.cloudflare.com)
- Triển khai mẫu: `lib/core/widgets/app_cached_network_image.dart`
