# Hướng Dẫn Kỹ Thuật: Chẩn Đoán Ad Unit ID AdMob Chuyên Sâu (Standalone Diagnostic Runner)

Tài liệu này hướng dẫn kỹ thuật chẩn đoán và kiểm tra tính hợp lệ của **Google AdMob Ad Unit IDs** trực tiếp trên thiết bị (Máy ảo / Máy thật) với độ chính xác 100%, có bằng chứng từ Google Ads Server, giúp loại bỏ phỏng đoán khi gặp lỗi quảng cáo không hiển thị.

---

## 1. Bối Cảnh & Vấn Đề Thường Gặp

Trong quá trình phát triển ứng dụng di động có tích hợp AdMob, đội ngũ thường gặp hiện tượng:
* **Trên máy ảo:** Quảng cáo chạy bình thường, hiển thị tốt.
* **Trên máy thật (Bản Release APK):** Báo lỗi *"Quảng cáo tạm thời không có"* (`videoAdUnavailable`), No-Fill, hoặc timeout.
* **Các quảng cáo khác (Interstitial, Banner) chạy tốt, nhưng duy nhất Rewarded Ads bị lỗi.**

### Nguyên Nhân Gốc Rễ Tiềm Ẩn:
1. **Lệch Ad Format giữa Console và Code:** Ad Unit tạo trên [AdMob Console](https://apps.admob.com/) là **Rewarded Interstitial** (Quảng cáo xen kẽ có thưởng) nhưng code SDK lại gọi **`RewardedAd.load()`** (Quảng cáo có thưởng truyền thống).
2. **eCPM Floor quá cao (High Floor):** Ad Unit đặt giá sàn cao không có inventory fill trong môi trường thử nghiệm.
3. **Phân nhánh môi trường (`_isProduction`):** Máy ảo chạy nhánh test nạp ID mặc định của Google (`ca-app-pub-3940256099942544/...`), còn máy thật nạp ID thật từ Remote Config.

---

## 2. Ưu Điểm Của Kỹ Thuật "Standalone Diagnostic Runner"

Thay vì phải build lại toàn bộ app lớn hoặc debug qua nhiều tầng middleware (Remote Config, UMP Consent, Cooldown, IAP VIP, Navigation):
* **Độc lập 100%:** Tạo một entrypoint Flutter siêu nhẹ (`lib/tools/admob_diagnostic_runner.dart`).
* **Không ảnh hưởng code nghiệp vụ:** Không đụng chạm vào logic production của app.
* **Đầy đủ dữ liệu Google trả về:** Đọc trực tiếp `code`, `domain`, `message`, `responseInfo` từ `LoadAdError`.
* **Đối chứng chéo song song:** Nạp thử cùng 1 ID dưới cả 2 định dạng `RewardedAd` và `RewardedInterstitialAd` để phát hiện ngay lập tức format mismatch.

---

## 3. Mã Nguồn Mẫu: `admob_diagnostic_runner.dart`

Tạo file tại đường dẫn: `lib/tools/admob_diagnostic_runner.dart` (hoặc đặt trong thư mục test):

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AdmobDiagnosticScreen(),
  ));
}

class AdmobDiagnosticScreen extends StatefulWidget {
  const AdmobDiagnosticScreen({super.key});

  @override
  State<AdmobDiagnosticScreen> createState() => _AdmobDiagnosticScreenState();
}

class _AdmobDiagnosticScreenState extends State<AdmobDiagnosticScreen> {
  final List<String> _logs = [];

  // ── ĐIỀN CÁC AD UNIT IDS CẦN KIỂM TRA TẠI ĐÂY ──────────────────
  static const String rewardUnlockHighId = 'ca-app-pub-6381606596462640/1609317831';
  static const String rewardUnlockId = 'ca-app-pub-6381606596462640/9352076483';
  static const String interActionId = 'ca-app-pub-6381606596462640/7596141685';
  static const String sampleRewardTestId = 'ca-app-pub-3940256099942544/5224354917';
  // ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _runAllDiagnostics();
  }

  void _log(String msg) {
    debugPrint('[DIAGNOSTIC] $msg');
    if (mounted) {
      setState(() => _logs.add(msg));
    }
  }

  Future<void> _runAllDiagnostics() async {
    _log('=== BẮT ĐẦU KIỂM TRA ADMOB IDS ===');

    // 1. Thử tải ID dưới dạng RewardedAd chuẩn
    await _testRewardedAd('reward_unlock_high', rewardUnlockHighId);
    await _testRewardedAd('reward_unlock', rewardUnlockId);

    // 2. Thử đối chứng chéo dưới dạng RewardedInterstitialAd
    await _testRewardedInterstitialAd('reward_unlock_high', rewardUnlockHighId);
    await _testRewardedInterstitialAd('reward_unlock', rewardUnlockId);

    // 3. Thử InterstitialAd
    await _testInterstitialAd('inter_action', interActionId);

    // 4. Thử ID mẫu Google để xác nhận SDK và kết nối mạng
    await _testRewardedAd('Google Sample Test ID', sampleRewardTestId);

    _log('=== HOÀN TẤT CHẨN ĐOÁN ===');
  }

  /// Kiểm tra định dạng RewardedAd (Quảng cáo có thưởng truyền thống)
  Future<void> _testRewardedAd(String label, String adUnitId) async {
    _log('----------------------------------------');
    _log('Testing RewardedAd: $label ($adUnitId)...');
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _log('✅ THÀNH CÔNG: RewardedAd [$label] đã LOAD ĐƯỢC 100%!');
          ad.dispose();
          completer.complete();
        },
        onAdFailedToLoad: (error) {
          _log('❌ THẤT BẠI: RewardedAd [$label]');
          _log('   Code: ${error.code}');
          _log('   Domain: ${error.domain}');
          _log('   Message: "${error.message}"');
          completer.complete();
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _log('⏱ TIMEOUT: RewardedAd [$label] quá 15s'),
    );
  }

  /// Kiểm tra định dạng RewardedInterstitialAd (Quảng cáo xen kẽ có thưởng)
  Future<void> _testRewardedInterstitialAd(String label, String adUnitId) async {
    _log('----------------------------------------');
    _log('Testing RewardedInterstitialAd: $label ($adUnitId)...');
    final completer = Completer<void>();

    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _log('✅ THÀNH CÔNG: RewardedInterstitialAd [$label] LOAD ĐƯỢC 100%!');
          _log('   👉 KẾT LUẬN: Đơn vị quảng cáo này trên AdMob Console có dạng REWARDED_INTERSTITIAL!');
          ad.dispose();
          completer.complete();
        },
        onAdFailedToLoad: (error) {
          _log('❌ THẤT BẠI: RewardedInterstitialAd [$label]');
          _log('   Code: ${error.code}');
          _log('   Domain: ${error.domain}');
          _log('   Message: "${error.message}"');
          completer.complete();
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _log('⏱ TIMEOUT: RewardedInterstitialAd [$label] quá 15s'),
    );
  }

  /// Kiểm tra định dạng InterstitialAd
  Future<void> _testInterstitialAd(String label, String adUnitId) async {
    _log('----------------------------------------');
    _log('Testing InterstitialAd: $label ($adUnitId)...');
    final completer = Completer<void>();

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _log('✅ THÀNH CÔNG: InterstitialAd [$label] đã LOAD ĐƯỢC 100%!');
          ad.dispose();
          completer.complete();
        },
        onAdFailedToLoad: (error) {
          _log('❌ THẤT BẠI: InterstitialAd [$label]');
          _log('   Code: ${error.code}');
          _log('   Domain: ${error.domain}');
          _log('   Message: "${error.message}"');
          completer.complete();
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _log('⏱ TIMEOUT: InterstitialAd [$label] quá 15s'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdMob Unit ID Diagnostic'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        itemBuilder: (ctx, i) {
          final log = _logs[i];
          final isSuccess = log.contains('✅');
          final isFail = log.contains('❌');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isSuccess
                    ? Colors.green[800]
                    : isFail
                        ? Colors.red[800]
                        : Colors.black87,
                fontWeight: (isSuccess || isFail) ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
}
```

---

## 4. Hướng Dẫn Thực Thi

### Bước 1: Khởi chạy trên thiết bị (Máy ảo hoặc Máy thật)
Chạy lệnh trực tiếp chỉ định file chẩn đoán:
```bash
# Xem danh sách thiết bị
flutter devices

# Chạy chẩn đoán trên máy ảo hoặc máy thật chỉ định
flutter run -d emulator-5554 -t lib/tools/admob_diagnostic_runner.dart
```

### Bước 2: Theo dõi Logcat thời gian thực
Mở một tab terminal khác để theo dõi log chi tiết:
```bash
adb logcat | grep "\[DIAGNOSTIC\]"
```

---

## 5. Bảng Phân Tích & Giải Mã Mã Lỗi AdMob

| Error Code | Error Message | Nguyên Nhân Bản Chất | Giải Pháp Khắc Phục |
|:---:|:---|:---|:---|
| **Code 3** | `"Ad unit doesn't match format."` | **Format Mismatch:** Loại Ad Unit trên Console khác với hàm SDK gọi (ví dụ Console là `Rewarded Interstitial`, code gọi `RewardedAd.load()`). | **Tạo lại Ad Unit** trên AdMob Console đúng loại hoặc chuyển hàm gọi SDK sang `RewardedInterstitialAd`. |
| **Code 3** | `"ERROR_CODE_NO_FILL"` / `"No ad config."` | 1. Ad Unit mới tạo chưa lan truyền DNS (chờ 1–24h).<br>2. Giá sàn eCPM Floor đặt quá cao không có nhà quảng cáo mua.<br>3. Tài khoản AdMob bị giới hạn quảng cáo (Ad Serving Limit). | 1. Hạ giá sàn xuống Google Optimized hoặc All Prices.<br>2. Kiểm tra Policy Center trong AdMob Console. |
| **Code 1** | `"ERROR_CODE_INVALID_REQUEST"` | 1. Sai App ID AdMob trong `AndroidManifest.xml` hoặc `Info.plist`.<br>2. Ad Unit ID bị thừa khoảng trắng hoặc ký tự lạ. | Kiểm tra thẻ `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID">` và trim() chuỗi ID. |
| **Code 2** | `"ERROR_CODE_NETWORK_ERROR"` | Thiết bị mất kết nối internet, mạng chặn domain `googlesyndication.com`, hoặc VPN chặn quảng cáo. | Đổi mạng WiFi/4G, tắt AdGuard/Pi-hole/VPN. |
| **Code 0** | `"ERROR_CODE_INTERNAL_ERROR"` | Lỗi nội bộ của Google Play Services trên máy hoặc phiên bản SDK quá cũ. | Khởi động lại Google Play Services hoặc cập nhật `google_mobile_ads`. |

---

## 6. Case Study Thực Tế: Phân Tích Sự Cố Rewarded Ads

### Hiện tượng:
Ứng dụng `Clock Watch` nạp 2 ID thật trên máy thật:
* `reward_unlock_high`: `ca-app-pub-6381606596462640/1609317831`
* `reward_unlock`: `ca-app-pub-6381606596462640/9352076483`

Khi gọi bằng `RewardedAd.load()`, Google AdMob trả về:
```
❌ THẤT BẠI: RewardedAd [reward_unlock_high]
   Code: 3
   Domain: com.google.android.gms.ads
   Message: "Ad unit doesn't match format. <https://support.google.com/admob/answer/9905175#4>"
```
Nhưng khi gọi bằng `RewardedInterstitialAd.load()`, kết quả:
```
✅ THÀNH CÔNG: RewardedInterstitialAd [reward_unlock_high] ĐÃ LOAD ĐƯỢC 100%!
✅ THÀNH CÔNG: RewardedInterstitialAd [reward_unlock] ĐÃ LOAD ĐƯỢC 100%!
```

### Kết luận rút ra:
* Khi tạo Ad Unit trên AdMob Console, người tạo đã bấm nhầm vào **"Quảng cáo xen kẽ có thưởng" (Rewarded Interstitial)** thay vì **"Quảng cáo có thưởng" (Rewarded)**.
* Chỉ cần chạy công cụ chẩn đoán này trong **10 giây**, nguyên nhân đã được chứng minh 100% không thể chối cãi.
