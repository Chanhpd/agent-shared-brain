# Category Navigation Latency, Missing In-Memory Cache & Race Condition Mitigation

- **Ngày ghi nhận:** 2026-10-23
- **Phân loại:** Flutter / State Management / Bloc & Cubit / Architecture
- **Mức độ nghiêm trọng:** Major (Gây cảm giác app giật lag, đơ thao tác, hiển thị sai lệch hoặc mất trắng dữ liệu)
- **Dự án phát hiện lần đầu:** LED Keyboard (`led_keyboard`)
- **Môi trường:** Máy thật & Máy ảo / Android & iOS / Flutter 3.x

---

## 1. Triệu Chứng (Symptom & Error Logs)

- **Độ trễ lặp lại vô nghĩa:** Người dùng chuyển từ tab *LED* sang tab *Gradient*, sau đó bấm lại tab *LED* (vừa xem cách đó 3 giây) vẫn phải chờ từ 1 đến 2 giây màn hình mới tải xong.
- **Hiện tượng đơ giao diện (UX Freeze):** Khi chạm vào một category mới, pill category đổi màu nhưng danh sách thẻ bên dưới giữ nguyên nội dung cũ và không có bất kỳ hiệu ứng loading nào. Người dùng ngỡ rằng app bị treo nên bấm loạn xạ.
- **Race Condition (Màn hình trắng hoặc đè sai dữ liệu):** Khi người dùng vuốt/chạm nhanh liên tiếp qua nhiều tab (Tab A -> Tab B -> Tab C), màn hình đôi khi bị trắng tinh (không có item nào) hoặc hiển thị nội dung của Tab A dù chỉ mục đang chọn là Tab C.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Thiếu bộ đệm RAM phiên làm việc (In-Memory Session Cache):**
   - Tầng Repository không lưu trữ kết quả phân loại đã lấy. Mỗi lần gọi `getThemes(categoryId)` là một lần gọi mạng mới: bắt tay TLS -> gửi request -> giải mã payload mã hóa -> JSON decode.
   - Thao tác này gây hao tốn tài nguyên CPU và lãng phí băng thông mạng liên tục.
2. **Khuyết thiếu trạng thái phản hồi UI (`isCategoryLoading`):**
   - Trong Cubit, khi người dùng chọn danh mục, state `HomeLoaded` chỉ cập nhật trường `selectedCategoryId` nhưng giữ nguyên list `themes` của danh mục trước đó và không phát cờ loading.
   - Giao diện không dựng Shimmer Placeholder, khiến người dùng không nhận biết được tiến trình tải dữ liệu.
3. **Hiện tượng Race Condition giữa các tác vụ bất đồng bộ:**
   - Khi bấm liên tiếp Tab 1 -> Tab 2 -> Tab 3: Có 3 Future bất đồng bộ cùng chạy.
   - Nếu request của Tab 1 gặp độ trễ mạng và phản hồi SAU request của Tab 3, Cubit sẽ nhận dữ liệu của Tab 1 cuối cùng và `emit` đè lên giao diện, khiến tab đang chọn là 3 nhưng dữ liệu bên dưới lại là của 1.
   - Nếu một request trước bị timeout hoặc rớt mạng, nó quăng lỗi và gán list rỗng `[]`, làm mất sạch dữ liệu của tab hiện tại.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### A. In-Memory Session Cache tại Tầng Data Repository
Lưu kết quả danh mục đã fetch trong bộ nhớ RAM của Repository:
```dart
class HomeRepositoryImpl implements HomeRepository {
  final Map<String, List<KeyboardThemeItem>> _categoryThemesCache = {};

  @override
  Future<Result<List<KeyboardThemeItem>>> getThemes({
    String? categoryId,
    int page = 1,
    int limit = 20,
    bool refresh = false,
  }) => safeCall(() async {
    final key = '${categoryId ?? "all"}_page_$page';
    
    // 1. Trả về ngay lập tức 0ms nếu đã có trong phiên
    if (!refresh && page == 1 && _categoryThemesCache.containsKey(key)) {
      return _categoryThemesCache[key]!;
    }

    // 2. Fetch từ RemoteDataSource nếu chưa có
    final items = await remoteDataSource.getThemes(categoryId: categoryId, page: page, limit: limit);
    if (page == 1 && items.isNotEmpty) {
      _categoryThemesCache[key] = items;
    }
    return items;
  });
}
```

### B. Cơ chế Phản hồi UI tức thì (Zero-flicker vs Shimmer)
Trong Cubit, kiểm tra danh mục đã cache hay chưa để quyết định trạng thái hiển thị:
```dart
Future<void> selectCategory(String categoryId) async {
  final currentState = state;
  if (currentState is! HomeLoaded) return;
  if (currentState.selectedCategoryId == categoryId && !currentState.isCategoryLoading) return;

  final isCached = _getThemes.isCategoryCached(categoryId);
  _activeCategoryRequestId++;
  final currentRequestId = _activeCategoryRequestId;

  // Nếu đã cache -> chuyển tab 0ms không nháy. Nếu chưa -> bật Shimmer Grid phản hồi ngay
  emit(
    currentState.copyWith(
      selectedCategoryId: categoryId,
      page: 1,
      hasReachedMax: false,
      isCategoryLoading: !isCached,
    ),
  );

  final themesResult = await _getThemes(GetHomeThemesParams(categoryId: categoryId));

  // C. Chống Race Condition: Chỉ chấp nhận kết quả nếu đây là request mới nhất
  if (currentRequestId != _activeCategoryRequestId) return;

  if (state is HomeLoaded && (state as HomeLoaded).selectedCategoryId == categoryId) {
    themesResult.fold(
      (themes) => emit((state as HomeLoaded).copyWith(
        themes: themes,
        isCategoryLoading: false,
      )),
      (failure) => emit((state as HomeLoaded).copyWith(isCategoryLoading: false)),
    );
  }
}
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Đối với dữ liệu danh mục / phân loại ít thay đổi trong phiên, **BẮT BUỘC phải có In-Memory Cache** tại Repository để chuyển tab đạt tốc độ 0ms.
- [ ] Luôn có cờ loading chuyên biệt cho việc đổi tab (ví dụ: `isCategoryLoading`) tách rời với `isLoading` toàn màn hình để kích hoạt Shimmer Grid phản hồi thao tác.
- [ ] Mọi tác vụ chuyển tab hoặc search bất đồng bộ đều phải có **Request ID Guard** (`_requestId++`) hoặc `CancellationToken` để triệt tiêu 100% rủi ro Race Condition đè dữ liệu cũ.
- [ ] Không xóa sạch data cũ khi đang tải data mới nếu không cần thiết, trừ khi chuyển đổi ngữ cảnh hoàn toàn khác.

---

## 5. Tài Liệu Tham Khảo (References)
- [Cubit State Management Patterns - Resilient Async Updates](https://bloclibrary.dev)
- Mã nguồn mẫu: `lib/features/home/presentation/cubit/home_cubit.dart` & `lib/features/home/data/repositories/home_repository_impl.dart`
