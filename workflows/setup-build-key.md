---
description: "Thiết lập Release Signing Key tự động từ app-keyboard cho dự án mới"
---

# Quy Trình Tự Động Setup Build Key & Gradle

Quy trình tự động hóa sao chép `key.properties` và `upload-keystore.jks` từ dự án chuẩn `app-keyboard` sang dự án hiện tại, đồng thời cập nhật `build.gradle(.kts)` và `.gitignore`.

## Các bước thực hiện:

1. **Chạy Script Tự Động Hóa:**
   Tại thư mục gốc của dự án Flutter hiện tại:
   ```bash
   bash ~/.gemini/config/skills/agent-shared-brain/scripts/setup_signing_keys.sh
   ```

2. **Kiểm Tra Tính Toàn Vẹn Của File Được Copy:**
   - Xác nhận có `android/key.properties`
   - Xác nhận có `android/app/upload-keystore.jks`
   - Kiểm tra `android/app/build.gradle.kts` (hoặc `build.gradle`) đã có khối `signingConfigs` và nạp thuộc tính.

3. **Kiểm Tra Bảo Mật Git:**
   ```bash
   git status --ignored
   ```
   Đảm bảo `key.properties` và `upload-keystore.jks` nằm trong danh sách ignored, **tuyệt đối không commit lên Git**.

4. **Thử Nghiệm Lệnh Build Release:**
   ```bash
   flutter build appbundle --release
   ```
