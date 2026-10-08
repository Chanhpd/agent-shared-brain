---
description: "Chẩn đoán lỗi Ad Unit ID AdMob (kiểm tra định dạng Rewarded/Interstitial, No-Fill)"
---

# Quy Trình Chẩn Đoán Ad Unit ID AdMob

Quy trình sử dụng Standalone Diagnostic Runner để kiểm tra tính hợp lệ của Ad Unit ID độc lập 100% trên thiết bị thật / máy ảo.

## Các bước thực hiện:

1. **Thu thập danh sách Ad Unit IDs cần kiểm tra:**
   - Hỏi người dùng cung cấp Ad Unit IDs cần test (hoặc lấy từ Remote Config / file cấu hình).

2. **Cập nhật công cụ chẩn đoán:**
   - Mở file `lib/tools/admob_diagnostic_runner.dart` (hoặc copy từ `tools/admob_diagnostic_runner.dart`).
   - Cập nhật các ID mục tiêu vào các hằng số kiểm tra (`rewardUnlockHighId`, `interActionId`, ...).

3. **Hướng dẫn khởi chạy Runner trên thiết bị:**
   ```bash
   flutter run -t lib/tools/admob_diagnostic_runner.dart
   ```

4. **Phân tích kết quả:**
   - Đọc kết quả log trên màn hình ứng dụng hoặc qua `adb logcat | grep "\[DIAGNOSTIC\]"`.
   - Đối chiếu với bảng mã lỗi trong `tools/GUIDE_DIAGNOSE_ADMOB_UNIT_IDS.md`:
     - **Code 3 "Ad unit doesn't match format":** Mismatch định dạng (Console là Rewarded Interstitial nhưng code gọi RewardedAd).
     - **Code 3 "ERROR_CODE_NO_FILL":** ID mới chưa DNS propagation hoặc eCPM floor quá cao.
     - **Code 1 "ERROR_CODE_INVALID_REQUEST":** Sai App ID trong AndroidManifest hoặc thừa khoảng trắng.
     - **Code 2 "ERROR_CODE_NETWORK_ERROR":** Lỗi kết nối / DNS / VPN chặn ad.

5. **Kết luận & Hành động:**
   - Hướng dẫn người dùng sửa cấu hình trên AdMob Console hoặc đổi hàm gọi trong code.
