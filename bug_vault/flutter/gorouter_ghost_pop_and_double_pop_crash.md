# GoRouter Desynced Modal Pop (Ghost Pop) & Double-Pop Completer Crash

- **Ngày ghi nhận:** 2026-10-09
- **Phân loại:** Flutter / Navigation / GoRouter / Lifecycle
- **Mức độ nghiêm trọng:** Critical (Crashlytics Fatal Exception, làm sập ứng dụng production)
- **Dự án phát hiện lần đầu:** Emoji Battery Shimeji Pet (`app_emoji_shimeji`)
- **Môi trường:** Production Release APK / Android / Flutter 3.x with GoRouter

---

## 1. Triệu Chứng (Symptom & Error Logs)

Người dùng gặp 2 vụ crash liên tiếp trên cùng 1 phiên làm việc (chỉ cách nhau 15 giây):

### Crash 1: Type Error do Pop nhầm Route cha
```text
Fatal Exception: io.flutter.plugins.firebase.crashlytics.FlutterError: type 'bool' is not a subtype of type 'FutureOr<ProductItem?>' of 'value'. Error thrown Uncaught async error.
       at _AsyncCompleter.complete(dart:async)
       at ImperativeRouteMatch.complete(match.dart:489)
       at GoRouterDelegate._completeRouteMatch(delegate.dart:187)
       at GoRouterDelegate._handlePopPageWithRouteMatch(delegate.dart:154)
       at _CustomNavigatorState._handlePopPage(builder.dart:446)
       at NavigatorState.pop(navigator.dart:5811)
       at _DownloadPetBottomSheetState._startDownload(download_pet_bottom_sheet.dart:132)
```

### Crash 2: Future already completed do Route bị pop lần 2
```text
Fatal Exception: io.flutter.plugins.firebase.crashlytics.FlutterError: Bad state: Future already completed. Error thrown Uncaught async error.
       at _AsyncCompleter.complete(dart:async)
       at Route.didComplete(navigator.dart:485)
       at Route.didPop(navigator.dart:463)
       at GoRouterDelegate.pop(delegate.dart:107)
       at GoRouter.pop(router.dart:587)
       at GoRouterHelper.pop(extensions.dart:73)
       at _ItemDetailScreenState._handleBack(item_detail_screen.dart:96)
```

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

### A. Cơ chế "Ghost Pop" (Desynced Modal Pop)
1. Màn hình cha (ví dụ `ItemDetailScreen`) được điều hướng qua GoRouter dạng có kiểu trả về:
   `context.push<ProductItem>(Routes.itemDetail, ...)`
   GoRouter tạo một `ImperativeRouteMatch<ProductItem>` mong đợi kết quả pop là `ProductItem?`.
2. Trên màn hình cha, người dùng mở một `showModalBottomSheet` để thực hiện tác vụ async (tải file zip, xem Rewarded Ad).
3. Trong lúc tác vụ đang chạy, người dùng **vuốt xuống hoặc chạm vùng ngoài (barrier) để đóng Modal**. Modal đã được tháo khỏi Navigator stack.
4. Khi tác vụ async hoàn thành, code gọi `Navigator.of(context).pop(true)`.
5. **Cơ chế nguy hiểm của Flutter:** `Navigator.of(context).pop()` **không pop widget hiện tại**, mà luôn pop route đang nằm trên đỉnh của stack (`_history.last`). Do Modal đã đóng trước đó, Flutter sẽ **pop nhầm màn hình cha bên dưới** và truyền giá trị `true` (`bool`).
6. GoRouter nhận kết quả `true` cho route `ImperativeRouteMatch<ProductItem>` -> quăng `TypeError: type 'bool' is not a subtype of type 'FutureOr<ProductItem?>' of 'value'`.

### B. Cơ chế "Double-Pop / Corrupted Completer"
1. Khi Crash 1 xảy ra, `Route.didPop()` đã gọi `_popCompleter.complete(true)`. Nhưng do GoRouter bị ngắt bởi TypeError ngay sau đó, màn hình chưa được tháo gỡ hoàn toàn khỏi giao diện (Flutter bắt lỗi qua Crashlytics).
2. Người dùng thấy app không phản hồi nên bấm nút Back trên App Bar.
3. Hàm `_handleBack()` gọi `context.pop()`, kích hoạt lại `Route.didPop()` -> `Route.didComplete()` trên cùng một Route đã hoàn thành dở dang.
4. Dart cấm gọi `complete()` lần 2 trên một `Completer` đã complete -> ném ra `Bad state: Future already completed`.
5. *(Ngoài ra, người dùng nhấp đúp (rapid double-tap) nút Back trên một màn hình không có cờ debounce `_isPopping` cũng sẽ trực tiếp kích hoạt lỗi này).*

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### 1. Luôn kiểm tra `ModalRoute.of(context)?.isCurrent == true` trước khi pop
Không bao giờ gọi `Navigator.pop()` sau các lệnh `await` (tải file, xem ad, gọi API) nếu route không còn là route active trên đỉnh:

```dart
final route = ModalRoute.of(context);
if (mounted && route != null && route.isCurrent) {
  Navigator.of(context).pop(result);
}
```

### 2. Khóa cử chỉ vuốt/back khi Modal đang thực hiện tác vụ async
Bọc nội dung của Modal BottomSheet / Dialog bằng `PopScope(canPop: !isLoading)`:

```dart
@override
Widget build(BuildContext context) => PopScope(
  canPop: !_isLoading,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [ ... ],
  ),
);
```

### 3. Thêm cờ debounce `_isPopping` cho toàn bộ hàm xử lý Back
Mọi hàm Back hoặc nút đóng màn hình phải có cờ chống spam tap:

```dart
bool _isPopping = false;

Future<void> _handleBack(BuildContext context) async {
  if (_isPopping) return;
  _isPopping = true;

  try {
    if (context.mounted && context.canPop()) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        context.pop();
      }
    }
  } finally {
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _isPopping = false;
      });
    }
  }
}
```

### 4. Chuẩn hóa hàm `_safePop` dùng chung (Navigation Helper)
```dart
static void _safePop(BuildContext context, {Object? result}) {
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  // Tuyệt đối không pop nếu route này đã bắt đầu đóng hoặc không phải route hiện tại
  if (route != null && !route.isCurrent) return;

  try {
    if (context.canPop()) {
      context.pop(result);
      return;
    }
  } catch (_) {}

  try {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  } catch (_) {}
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Mọi Modal BottomSheet / Dialog có tác vụ async đều bọc `PopScope(canPop: !isLoading)`.
- [ ] Sau mọi lệnh `await` trong Modal (Ad, download, API), chỉ gọi pop nếu `route != null && route.isCurrent`.
- [ ] Toàn bộ các callback sau khi xem quảng cáo (`onRewardGranted`, `onAdNotReady`) phải kiểm tra `ModalRoute.of(context)?.isCurrent == true`.
- [ ] Mọi nút Back / hàm xử lý Back trên Scaffold đều có cờ debounce `_isPopping` (tối thiểu 300-500ms).
- [ ] Tuyệt đối không dùng `Navigator.of(context).pop()` mà không kiểm tra xem widget còn mounted và route còn isCurrent hay không.

---

## 5. Tài Liệu Tham Khảo (References)
- [Flutter Route.didComplete API Reference](https://api.flutter.dev/flutter/widgets/Route/didComplete.html)
- [GoRouter ImperativeRouteMatch Documentation](https://pub.dev/documentation/go_router/latest/go_router/ImperativeRouteMatch-class.html)
- [Playbook Điều Hướng Ads An Toàn (01_ADS_MONETIZATION_PLAYBOOK.md)](../../playbooks/01_ADS_MONETIZATION_PLAYBOOK.md)
