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
  static const String rewardUnlockHighId = 'ca-app-pub-6381606596462640/8519159351';
  static const String rewardUnlockId = 'ca-app-pub-6381606596462640/5088189963';
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

    await RewardedAd.load(
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

    await RewardedInterstitialAd.load(
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

    await InterstitialAd.load(
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
  Widget build(BuildContext context) => Scaffold(
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
