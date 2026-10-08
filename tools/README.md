# Standalone Diagnostic Tools

Thư mục chứa các công cụ độc lập phục vụ việc kiểm tra, chẩn đoán và xác thực các thành phần cốt lõi (Core Components & SDKs) trên thiết bị thật và máy ảo.

---

## Danh Sách Công Cụ

### 1. `admob_diagnostic_runner.dart`
- **Mục đích:** Kiểm tra tính hợp lệ của **Google AdMob Ad Unit IDs** độc lập 100%, không bị ảnh hưởng bởi logic Remote Config, VIP, Navigation hay UMP Consent của ứng dụng.
- **Tính năng nổi bật:**
  - Nạp song song cả 2 định dạng `RewardedAd` và `RewardedInterstitialAd` để phát hiện lỗi **Format Mismatch** (lệch cấu hình giữa AdMob Console và Code).
  - Nạp `InterstitialAd` và Google Sample Test ID để xác nhận kết nối mạng & Google Play Services.
  - Hiển thị trực tiếp log chi tiết (Error code, domain, message) lên màn hình điện thoại.
- **Tài liệu hướng dẫn & giải mã mã lỗi:** [GUIDE_DIAGNOSE_ADMOB_UNIT_IDS.md](./GUIDE_DIAGNOSE_ADMOB_UNIT_IDS.md)

### Cách chạy trong bất kỳ dự án Flutter nào:
```bash
# Chạy trực tiếp chỉ định file runner
flutter run -t tools/admob_diagnostic_runner.dart
# Hoặc copy vào lib/tools/ của dự án rồi chạy:
flutter run -t lib/tools/admob_diagnostic_runner.dart
```
