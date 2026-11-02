# Timezone LateInitializationError (_local / _TFf) in Flutter Local Notifications

- **Ngày ghi nhận:** 2026-11-02
- **Phân loại:** Flutter / Notifications / Android / iOS / Crashlytics
- **Mức độ nghiêm trọng:** Critical (Làm sụt giảm tỷ lệ Crash-free users từ >99% xuống ~70% trên production)
- **Dự án phát hiện lần đầu:** LED Keyboard (`com.mediatech.ledkeyboardtheme`)
- **Môi trường:** Production Release APK / AAB (bật `--obfuscate`) và Debug

---

## 1. Triệu Chứng (Symptom & Error Logs)

Trên Firebase Crashlytics của ứng dụng production, ghi nhận hàng loạt non-fatal/fatal crash ngay khi người dùng vừa mở app hoặc đổi cài đặt:

* **Trên bản Debug / Unobfuscated (v1.0.28):**
  ```text
  package:led_keyboard/features/notifications/data/services/local_notification_service.dart - LocalNotificationService.scheduleDaily
  io.flutter.plugins.firebase.crashlytics.FlutterError - LateInitializationError: Field '_local@849310200' has not been initialized..
  Error thrown [LocalNotification] Failed to schedule daily: LateInitializationError: Field '_local@849310200' has not been initialized..
  ```

* **Trên bản Release bật Obfuscation (v1.0.30 & v1.0.31):**
  ```text
  .    #00 abs bc733887 virt 009b2887 _kDartIsolateSnapshotInstructions+0x637bc7
  io.flutter.plugins.firebase.crashlytics.FlutterError - LateInitializationError: Field '_TFf@914310200' has not been initialized..
  Error thrown [LocalNotification] Failed to schedule daily: LateInitializationError: Field '_TFf@914310200' has not been initialized..
  ```

Lỗi xảy ra hàng trăm lần đối với người dùng vừa tải hoặc cập nhật app, ảnh hưởng trực tiếp đến trải nghiệm onboarding.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

### 2.1. Cấu trúc nội tại của thư viện `timezone`
Trong package `package:timezone/src/env.dart`:
```dart
late Location _local;
Location get local => _local;

void initializeDatabase(List<int> rawData) {
  // ...
  _local = _UTC;
}

void setLocalLocation(Location location) {
  _local = location;
}
```
Biến `_local` là một biến `late Location _local;`. Nếu hàm getter `tz.local` bị gọi **trước khi** `tz.initializeTimeZones()` hoặc `tz.setLocalLocation(...)` được thực thi, runtime của Dart sẽ ném ra lỗi `LateInitializationError: Field '_local' has not been initialized.`. Khi bật build obfuscation (`--obfuscate`), Dart compiler đổi tên biến `_local` thành ký hiệu rút gọn (ví dụ `_TFf@914310200`).

### 2.2. Xung đột luồng bất đồng bộ (Async Initialization Race Condition)
1. Trong `main.dart`, `NotificationCubit` được tạo kèm `..initialize()` trong `MultiBlocProvider`:
   ```dart
   BlocProvider(create: (_) => locator<NotificationCubit>()..initialize())
   ```
2. Trong `InitializeNotificationsUseCase`:
   ```dart
   await _remote.initialize(); // Đợi FCM FirebaseMessaging (bị hoãn do mạng / IPC Play Services)
   await _local.initialize();  // Local notification bị xếp sau!
   ```
3. Trong khi `_local.initialize()` chưa kịp chạy xong, người dùng vừa mở app đến màn hình chọn ngôn ngữ hoặc onboarding, `LocaleCubit.setLocale()` gọi ngay:
   ```dart
   unawaited(locator<KeyboardNotificationScheduler>().scheduleDailyEngagement());
   ```
4. `KeyboardNotificationScheduler` gọi trực tiếp `_notificationService.scheduleDaily(payload)`.
5. Tại `LocalNotificationService.scheduleDaily`:
   ```dart
   final now = tz.TZDateTime.now(tz.local); // << tz.local chưa được khởi tạo!
   ```
6. Chưa kể, hàm `scheduleDaily` bắt lỗi rồi `rethrow;` ra ngoài khiến tác vụ lập lịch ngầm (background reminder) biến thành unhandled crash gửi lên Crashlytics.

---

## 3. Giải Pháp Đã Xác Thực (5-Layer Defense-in-Depth)

Để đảm bảo 100% không bao giờ gặp lại lỗi này dù trong bất kỳ điều kiện gọi sớm nào, triển khai đồng thời 5 tầng bảo vệ:

### Tầng 1: Khởi tạo Timezone Database đồng bộ ngay tại `main()`
Nạp database múi giờ ngay sau `ensureInitialized()`:
```dart
// lib/main.dart
import 'package:timezone/data/latest.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Nạp đồng bộ và gán _local = _UTC ngay lập tức
  // ...
}
```

### Tầng 2: Khởi tạo sớm trong Constructor của Local Notification Service
```dart
class LocalNotificationService implements ILocalNotificationService {
  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    AppLogger? logger,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _logger = logger {
    _initTimezoneEagerly();
  }

  void _initTimezoneEagerly() {
    try {
      tz.initializeTimeZones();
      try {
        final utc = tz.getLocation('UTC');
        tz.setLocalLocation(utc);
      } catch (_) {}
    } catch (_) {}
  }
}
```

### Tầng 3: Getter an toàn tuyệt đối `_safeLocation`
Không bao giờ đọc trực tiếp `tz.local`. Luôn đọc qua getter bọc `try-catch`:
```dart
tz.Location get _safeLocation {
  try {
    return tz.local;
  } catch (_) {
    try {
      tz.initializeTimeZones();
      final utc = tz.getLocation('UTC');
      tz.setLocalLocation(utc);
      return utc;
    } catch (_) {
      return tz.UTC;
    }
  }
}
```

### Tầng 4: Guard `_ensureInitialized()` có khóa Completer chống Race Condition
```dart
Completer<void>? _initCompleter;

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  await initialize();
}

@override
Future<void> initialize() async {
  if (_initialized) return;
  if (_initCompleter != null) return _initCompleter!.future;
  _initCompleter = Completer<void>();

  try {
    tz.initializeTimeZones();
    await _configureLocalTimeZone();
    await _initializePlatformSettings();
    _initialized = true;
    _initCompleter?.complete();
  } catch (e, st) {
    _logger?.warning('[LocalNotification] Init warning: $e', error: e, stackTrace: st);
    _initCompleter?.complete();
  }
}
```

### Tầng 5: Tách biệt khởi tạo Local/Remote & Triệt tiêu `rethrow`
1. Trong `InitializeNotificationsUseCase`: Luôn cho `_local.initialize()` chạy trước (vì offline, cực nhanh), không bắt nó chờ `_remote.initialize()` (FCM mạng).
2. Trong các hàm lập lịch thông báo (`scheduleDaily`, `scheduleNotification`): Sử dụng `_safeLocation`, bắt lỗi an toàn và log warning, **tuyệt đối không `rethrow;`**. Lập lịch thông báo là tác vụ phụ, không được phép làm gián đoạn trải nghiệm chính của ứng dụng.

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Khi sử dụng package `timezone`, luôn gọi `tz.initializeTimeZones()` ngay tại `main()` trước khi bất kỳ service nào được khởi tạo.
- [ ] Không bao giờ truy cập trực tiếp `tz.local` mà không có fallback an toàn hoặc cơ chế kiểm tra khởi tạo.
- [ ] Local notification service phải có khả năng hoạt động độc lập, không phụ thuộc vào trạng thái kết nối mạng của Remote Push Notification (FCM / OneSignal).
- [ ] Mọi tác vụ background reminder/notification scheduling phải được thiết kế dạng best-effort, không ném unhandled exception ra ngoài (`no rethrow`).
- [ ] Viết unit test gọi `scheduleDaily` / `scheduleNotification` trên instance mới tạo mà KHÔNG gọi `initialize()` để xác thực tính an toàn.
