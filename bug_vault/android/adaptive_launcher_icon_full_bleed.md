# Android Adaptive Launcher Icon Full Bleed (Khắc Phục Icon Bị Thu Nhỏ, Lọt Thỏm & Viền Trắng)

- **Ngày ghi nhận:** 2026-10-10
- **Phân loại:** Android / Flutter / UI & UX Branding
- **Mức độ nghiêm trọng:** Major (Ảnh hưởng trực tiếp đến nhận diện thương hiệu trên màn hình chính của người dùng)
- **Dự án áp dụng thành công:** App Keyboard, Clock Watch App
- **Môi trường:** Android 8.0+ (API 26+) đến Android 15+, Pixel Launcher, Samsung OneUI, Xiaomi MIUI, ColorOS.

---

## 1. Triệu Chứng (Symptom & Error Logs)

Khi build app Flutter với cấu hình mặc định của `flutter_launcher_icons`:
```yaml
flutter_launcher_icons:
  android: "ic_launcher"
  ios: true
  image_path: "assets/images/logo.png"
```

Người dùng và developer quan sát thấy:
1. **Lỗi Icon lọt thỏm viền trắng (White Plate / Badge):** Trên Android 8.0+ (99% thiết bị hiện nay), icon ứng dụng hiển thị bé tí xíu ở giữa, bị bọc bởi một vòng tròn hoặc khung vuông bo góc màu trắng dày cộp rất mất thẩm mỹ.
2. **Lỗi Icon bị cắt cụt (Edge Cropping):** Nếu cấu hình `adaptive_icon_foreground: "assets/logo.png"` mà không xử lý safe zone, launcher của các dòng máy (Samsung, Pixel, Xiaomi) sẽ đè mask cắt xén mất 16.66% ở 4 cạnh, làm cụt chữ và mất chi tiết viền ngoài.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Chuẩn Adaptive Icons của Android (từ API 26):**
   - Kích thước canvas của icon hệ điều hành quy định là **108dp × 108dp**.
   - Tuy nhiên, **Vùng an toàn hiển thị (Safe Zone)** chỉ là hình tròn đường kính **72dp** ở chính giữa (chiếm 66.6% canvas).
   - Khoảng viền ngoài **18dp** mỗi bên (`18 / 108 = 16.66%`) được hệ thống dùng cho hiệu ứng dịch chuyển 3D (parallax), rung lắc và làm vùng đệm cho các loại mặt nạ mask khác nhau (hình tròn, squircle, rounded square, teardrop).
2. **Fallback của Android OS khi thiếu Adaptive Icon:**
   - Nếu app chỉ có icon dạng legacy bitmap (`mipmap-*/ic_launcher.png`), Android OS tự động tạo một nền trắng 108dp và dán icon cũ vào giữa ở tỉ lệ co nhỏ, gây ra hiện tượng **"icon bé tí lọt thỏm trong đĩa trắng"**.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution - Bí Quyết "To Full Viền" 3 Bước)

Phương pháp này đảm bảo icon **to tối đa**, **tràn viền full bleed** (không viền trắng), và **an toàn 100% không bao giờ bị cắt xén**:

### Bước 1: Cấu hình `pubspec.yaml`
Trích xuất mã màu nền (Background Hex) tại 4 góc mép của logo (ví dụ `#090D12` cho nền đen, hoặc `#80A3A8` cho nền xanh):

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.4

flutter_launcher_icons:
  android: "ic_launcher"
  ios: true
  image_path: "assets/images/logo.png"
  min_sdk_android: 21
  remove_alpha_ios: true
  # Tách nền & tiền tố adaptive:
  adaptive_icon_background: "#090D12" # Mã màu nền viền logo
  adaptive_icon_foreground: "assets/images/logo.png"
```

### Bước 2: Sinh tự động các Density Drawable
Chạy lệnh CLI:
```bash
dart run flutter_launcher_icons
```
Lệnh sẽ tự động:
- Sinh các file mật độ ảnh `drawable-mdpi`, `drawable-hdpi`, `drawable-xhdpi`, `drawable-xxhdpi`, `drawable-xxxhdpi` chứa `ic_launcher_foreground.png`.
- Sinh file `android/app/src/main/res/values/colors.xml` với màu nền tương ứng.
- Sinh thư mục `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.

### Bước 3: Tinh chỉnh Ma Thuật `<inset android:inset="16%" />`
Mở file `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` (và tạo thêm `ic_launcher_round.xml` song song):

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="16%" />
  </foreground>
</adaptive-icon>
```

#### Tại sao kỹ thuật này hoạt động hoàn hảo?
1. **Background tràn viền 100% (`108dp`):** Dùng màu `@color/ic_launcher_background` trải đều toàn bộ diện tích icon, xóa bỏ hoàn toàn viền trắng mặc định.
2. **Foreground co đúng chuẩn (`inset="16%"`):** Co lớp chi tiết chính vừa khít vào đường tròn/squircle `72dp` của Android.
3. **Hiệu ứng thị giác liền mạch:** Do màu nền của logo và `@color/ic_launcher_background` đồng nhất, phần 16% co lại tự hòa tan vào nền, làm cho toàn bộ icon trông to kín, tràn viền và sắc nét trên mọi loại máy (Samsung, Pixel, Oppo, Xiaomi)!

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Lấy chính xác mã màu hex tại mép ngoài cùng (0,0) của file `logo.png`.
- [ ] Luôn kiểm tra sự tồn tại của `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.
- [ ] Đảm bảo thẻ `<foreground>` được bọc bởi `<inset android:drawable="@drawable/ic_launcher_foreground" android:inset="16%" />`.
- [ ] Luôn sao chép thêm file `ic_launcher_round.xml` trong `mipmap-anydpi-v26` để hỗ trợ tròn tuyệt đối trên các launcher đặc thù.
- [ ] Chạy `flutter analyze` sau khi sinh để đảm bảo không bị lỗi build XML.

---

## 5. Tài Liệu Tham Khảo (References)
- [Android Developers: Adaptive Icons Guidelines](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive)
- [Flutter Launcher Icons Package](https://pub.dev/packages/flutter_launcher_icons)
