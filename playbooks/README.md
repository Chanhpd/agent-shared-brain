# BỘ TÀI LIỆU CHUẨN HÓA DỰ ÁN: ADS, ANR/ARN & PERFORMANCE
> **Tài liệu chuyển giao công nghệ & Best Practices cho các dự án mới**  
> **Tổng hợp từ:** Dự án `led_keyboard` (Thực tế triển khai, điều tra sự cố, commit lịch sử và báo cáo AdMob)

---

## 📌 TỔNG QUAN HỆ THỐNG PLAYBOOK

Bộ tài liệu này được đúc kết từ các sự cố thực tế, các đợt tối ưu hóa sâu ở cả tầng Flutter (Dart) và tầng Native (Android/Kotlin), giúp các dự án mới:
1. **Đạt Show Rate quảng cáo 90% - 100%, Match Rate 85% - 95%, tối đa hóa eCPM và doanh thu**.
2. **Triệt tiêu 100% lỗi ANR (Application Not Responding), giữ chỉ số Android Vitals ở mức 0.00%**.
3. **Đạt hiệu năng chuẩn 60/120 FPS, tối ưu RAM, giảm dung lượng bộ cài và tăng tốc độ khởi động app**.

---

## 📚 DANH MỤC 3 PLAYBOOK CHI TIẾT

| STT | Tài liệu | Nội dung trọng tâm | Đường dẫn |
|:---:|:---|:---|:---:|
| **1** | **Ads & Monetization Playbook** | - Phân tích nguyên nhân sụt giảm chỉ số AdMob & giải pháp khắc phục.<br>- Viewport Lazy-Loading (400px threshold) & Static Slot Recycling.<br>- Nâng timeout 10s & giữ Ad về muộn trong RAM.<br>- App Resume Interstitial với `OverlayEntry` chống Ad Loop.<br>- Bọc Back Interstitial an toàn (`popWithInterstitial`, `_safePop`).<br>- Chuẩn MediaView Native Video $\ge 120\times 120\text{ dp}$. | [Xem Playbook 1](file:///Users/inhouse/app-keyboard/docs/playbook/01_ADS_MONETIZATION_PLAYBOOK.md) |
| **2** | **ANR / ARN Prevention Playbook** | - Cơ chế kích hoạt ANR của Android (Input 5s, Service 20s, Receiver 10s).<br>- Asynchronous SQLite với ThreadPool Executor.<br>- Nạp Typeface & Asset hoàn toàn trong luồng nền.<br>- Caching Shader & Matrix trong vòng lặp 60 FPS `onDraw`.<br>- Lifecycle Safe Guards dừng Animation khi View bị ẩn.<br>- Xử lý tác vụ nặng qua Dart `compute()` / `Isolate.run()`. | [Xem Playbook 2](file:///Users/inhouse/app-keyboard/docs/playbook/02_ANR_ARN_PREVENTION_PLAYBOOK.md) |
| **3** | **Performance Optimization Playbook** | - Khởi tạo Splash an toàn với Remote Config Timeout (1500ms).<br>- Quản lý Bitmap Native với `safeRecycle` chống lỗi OOM.<br>- Tích hợp Glide nạp ảnh, downsampling và 2 tầng cache.<br>- Chống Scroll Jank PlatformView với `ScrollJankGuard`.<br>- Dọn dẹp font assets thừa (tiết kiệm 12MB).<br>- Cấu hình ProGuard / R8 và build App Bundle (`.aab`) tối ưu. | [Xem Playbook 3](file:///Users/inhouse/app-keyboard/docs/playbook/03_PERFORMANCE_OPTIMIZATION_PLAYBOOK.md) |

---

## 🎯 10 NGUYÊN TẮC BẤT DI BẤT DỊCH CHO MỌI DỰ ÁN MỚI

1. **Tuyệt đối không Eager-Load Native Ad:** Mọi Native Ad trong ListView / GridView / CustomScrollView bắt buộc phải dùng Viewport Trigger (chỉ tải khi cách màn hình $\le 400\text{px}$).
2. **Cố định SlotKey tĩnh theo vị trí:** Dùng `feed_native_slot_0`, không gán ID động của Category hay Item vào SlotKey.
3. **Bảo vệ Ad về muộn trong RAM:** Không bao giờ gọi `dispose()` trên Ad đã tải thành công trong RAM. Lần bấm kế tiếp sẽ chiếu ngay (0s delay).
4. **Không Fallback chéo giữa các Format:** Native lỗi thì ẩn `SizedBox.shrink()`, không tự ý gọi Banner đè lên.
5. **Back Interstitial phải luôn Pop được:** Luôn bọc lệnh điều hướng bằng `finally { _safePop(context); }` để không bao giờ bẫy (trap) người dùng.
6. **Không chạy Database / File I/O trên Main Thread:** Mọi thao tác SQLite / SharedPreferences lớn phải chạy trên Background ThreadPool hoặc `Dispatchers.IO`.
7. **Không nạp Font / Quét `assets.list()` trên UI Thread:** Chuyển toàn bộ việc khởi tạo Typeface và giải mã Bitmap sang ThreadPool nền.
8. **Không `new` đối tượng đồ họa trong 60 FPS `onDraw`:** Tái sử dụng `Matrix`, caching `LinearGradient` và `RadialGradient`.
9. **Dừng Animation khi ẩn View / Service:** Lắng nghe `onWindowHidden()` và `onFinishInput()` để ngắt Animator, tránh nóng máy và cạn pin.
10. **Startup có Timeout 1500ms:** Splash Screen luôn có timeout bảo vệ cho Remote Config trước khi nạp IAP và Ads.

---

## 🔗 TÀI LIỆU THAM KHẢO GỐC TRONG REPOSITORY
- [Báo Cáo Tối Ưu AdMob Thực Tế (ADMOB_OPTIMIZATION_REPORT.md)](file:///Users/inhouse/app-keyboard/ADMOB_OPTIMIZATION_REPORT.md)
- [Hướng Dẫn Tích Hợp Ads Chuẩn (ADS_INTEGRATION_GUIDE.md)](file:///Users/inhouse/app-keyboard/docs/ADS_INTEGRATION_GUIDE.md)
- [Hướng Dẫn App Resume Interstitial (APP_RESUME_INTERSTITIAL_GUIDE.md)](file:///Users/inhouse/app-keyboard/docs/APP_RESUME_INTERSTITIAL_GUIDE.md)
- [Tổng Hợp Logic Interstitial (interstitial_logic_summary.md)](file:///Users/inhouse/app-keyboard/docs/interstitial_logic_summary.md)
