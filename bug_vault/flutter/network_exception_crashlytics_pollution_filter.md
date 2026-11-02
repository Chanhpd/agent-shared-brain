# Network Exception Crashlytics Pollution & Resilient Error Filtering

- **Ngày ghi nhận:** 2026-11-02
- **Phân loại:** Flutter / Network / Clean Architecture / Crashlytics
- **Mức độ nghiêm trọng:** Major (Gây loãng dashboard Crashlytics với hàng trăm issue giả, làm sai lệch chỉ số Crash-free users)
- **Dự án phát hiện lần đầu:** LED Keyboard (`com.mediatech.ledkeyboardtheme`)
- **Môi trường:** Production Release APK / AAB trên Firebase Crashlytics

---

## 1. Triệu Chứng (Symptom & Error Logs)

Bảng điều khiển Firebase Crashlytics bị ngập tràn hàng loạt Non-Fatal issues do lỗi kết nối mạng thông thường của người dùng:

```text
DioException [connection error]: SocketException: Failed host lookup: 'ledkb.zeroshield.xyz' (OS Error: No address associated with hostname)
ClientException: Failed host lookup: 'd1mmsgok7o9j5d.cloudfront.net' (OS Error: No address associated with hostname)
DioException [receive timeout]: The request took longer than 0:00:20.000000 to receive data.
DioException [unknown]: HttpException: Connection closed while receiving data
DioException [connection error]: Connection reset by peer
DioException [unknown]: HandshakeException: Connection terminated during handshake
```

Những lỗi này chiếm hơn 60% tổng số sự cố báo về, dù ứng dụng không hề sập hay có lỗi logic trong code. Tỷ lệ Crash-free users bị tụt từ >99% xuống còn ~75%.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

### 2.1. `BaseRepository.safeCall` log lỗi mù quáng
Trong Clean Architecture, tầng Data Repository thường bọc các hàm gọi qua một wrapper bảo vệ:
```dart
// Code lỗi ban đầu
abstract class BaseRepository {
  Future<Result<T>> safeCall<T>(Future<T> Function() call, {String? operationName}) async {
    try {
      final result = await call();
      return Success(result);
    } on Exception catch (e, stack) {
      if (operationName != null) {
        logger.error('[$operationName] Failed: $e', error: e, stackTrace: stack); // << BẮT TẤT CẢ!
      }
      return Failure(_mapToFailure(e));
    }
  }
}
```
Khi người dùng mất mạng (đi vào thang máy, tắt wifi, bật airplane mode) hoặc mạng chập chờn khi tải file zip/ảnh nặng, thư viện `Dio` hoặc `dart:io` sẽ ném ra `SocketException`, `HttpException`, hay `DioException`.
`safeCall` bắt tất cả các ngoại lệ này và gọi `logger.error(...)`.

### 2.2. `CrashlyticsLogger` đẩy mọi error/warning lên Crashlytics
```dart
class CrashlyticsLogger implements AppLogger {
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _crashlytics.recordError(error ?? message, stackTrace, reason: message);
  }

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    if (error != null) {
      _crashlytics.recordError(error, stackTrace, reason: message); // << Lỗi nghiêm trọng!
    } else {
      _crashlytics.log('WARNING: $message');
    }
  }
}
```
Hàm `_crashlytics.recordError(...)` trong SDK Firebase có nhiệm vụ **tạo ra một Issue mới** trên giao diện điều khiển Crashlytics.
Cả `error` và `warning` (có error) đều gọi `recordError`, khiến mọi sự cố ngắt mạng tạm thời của người dùng bị biến thành một "Crash/Bug" của ứng dụng!

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### 3.1. Bổ sung `NetworkFailure` vào hệ thống Domain Failures
Tách biệt lỗi mạng dự kiến (NetworkFailure) khỏi lỗi bất thường trong code (UnexpectedFailure):
```dart
// lib/core/result/app_failure.dart
final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    String message = 'Network connection failed. Please check your internet connection.',
    super.originalError,
    super.stackTrace,
  }) : super(message);
}
```

### 3.2. Bộ lọc ngoại lệ mạng thông thường `_isNetworkException` trong `BaseRepository`
```dart
// lib/core/base/base_repository.dart
bool _isNetworkException(Object e) {
  if (e is SocketException ||
      e is HttpException ||
      e is HandshakeException ||
      e is TlsException ||
      e is CertificateException) {
    return true;
  }
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      default:
        if (e.error is SocketException ||
            e.error is HttpException ||
            e.error is HandshakeException) {
          return true;
        }
    }
  }
  final msg = e.toString().toLowerCase();
  return msg.contains('failed host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('connection closed') ||
      msg.contains('software caused connection abort') ||
      msg.contains('network is unreachable') ||
      msg.contains('clientexception');
}
```

### 3.3. Phân luồng Log: Warning cho lỗi mạng, Error cho lỗi app
```dart
} on Exception catch (e, stack) {
  stopwatch.stop();

  if (operationName != null) {
    if (_isNetworkException(e)) {
      // Chỉ log warning nội bộ, không tạo Crash Issue trên Crashlytics
      logger.warning(
        '[$operationName] Network issue: $e',
        error: e,
        stackTrace: stack,
      );
    } else {
      // Lỗi logic code / format dữ liệu / 500 server mới ghi nhận error
      logger.error(
        '[$operationName] Failed: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }

  return Failure(_mapToFailure(e));
}
```

### 3.4. Chuẩn hóa `CrashlyticsLogger`: Warning chỉ ghi Breadcrumb
```dart
// lib/core/logger/crashlytic_logger.dart
@override
void warning(String message, {Object? error, StackTrace? stackTrace}) {
  if (error != null) {
    // Ghi breadcrumb log để điều tra nếu về sau app bị crash thật
    _crashlytics.log('WARNING: $message (error: $error)');
  } else {
    _crashlytics.log('WARNING: $message');
  }
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Không bao giờ gọi `Crashlytics.recordError` đối với các ngoại lệ mất mạng thông thường (`SocketException`, timeout, connection reset).
- [ ] Phân định rạch ròi giữa `_crashlytics.log(...)` (Breadcrumbs - dấu vết ngữ cảnh) và `_crashlytics.recordError(...)` (Tạo issue sự cố).
- [ ] Hàm `warning` trong logger chỉ được phép ghi breadcrumb, không được gọi `recordError`.
- [ ] Tại tầng Repository, luôn phân loại lỗi: Lỗi mạng map sang `NetworkFailure` và log warning; lỗi lập trình/dữ liệu hỏng mới log error.
