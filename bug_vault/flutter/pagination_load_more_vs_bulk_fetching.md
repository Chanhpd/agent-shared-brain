# Clean Architecture Pagination & Load More Thay Thế Bulk Fetching (Chống Giật Lag & Tối Ưu RAM/FPS)

- **Ngày ghi nhận:** 2026-10-12
- **Commit tham chiếu:** `e3ce522e271821b3c2ed016dd7d95075237a08e4` (PR #44 `592dfde`)
- **Phân loại:** Flutter / Performance / Clean Architecture / Network
- **Mức độ nghiêm trọng:** Major (Gây drop FPS khi scroll, tràn RAM, tăng TTFB và giật UI khi tải hàng loạt)
- **Dự án phát hiện lần đầu:** LED Keyboard (`app-keyboard`)
- **Môi trường:** Production & Development / Android & iOS

---

## 1. Triệu Chứng & Rủi Ro Của "Bulk Fetching" (Tải Dữ Liệu Hàng Loạt)

Ở các màn hình hiển thị danh sách lớn (Home Wallpapers, LED Keyboard Themes, Ringtones, Stickers):

### Triệu chứng thường gặp:
1. **First Contentful Paint / TTFB quá chậm:** Màn hình Home phải chờ API trả về 1 payload JSON rất lớn (`limit = 100` hoặc không có limit) chứa hàng trăm item với đầy đủ metadata, preview URL, zip URLs.
2. **Spike RAM & Áp lực Garbage Collection (GC):** Bộ nhớ RAM tăng vọt ngay tại thời điểm parse JSON danh sách khổng lồ, khiến GC của Dart VM phải kích hoạt dọn dẹp liên tục, gây đơ khung hình.
3. **Scroll Jank (Khựng hình khi cuộn):** Mặc dù Flutter có cơ chế viewport ảo, việc nhồi hàng trăm model vào state khiến việc tính toán bố cục, kích hoạt đồng loạt hàng chục request tải thumbnail và cache ảnh gây drop khung hình xuống dưới 30 FPS.
4. **Offline / Fallback chậm:** Khi rớt mạng, LocalDataSource fallback cũng nạp toàn bộ danh sách tĩnh cùng lúc, lặp lại hiện tượng nghẽn tài nguyên.

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

1. **Thiếu cơ chế phân trang xuyên suốt Clean Architecture:** Từ tầng DataSource, Repository, UseCase đến Cubit chỉ chấp nhận truy vấn theo `categoryId` mà không có `page` và `limit`.
2. **Không có Re-entrancy Guard khi cuộn:** Khi người dùng vuốt nhanh hoặc vung tay (fling scroll), sự kiện chạm đáy bị bắn liên tục hàng chục lần trong vài mili-giây, dẫn đến hàng loạt request trùng lặp được gửi lên server.
3. **Thiếu Deduplication (Khử trùng ID):** Nếu server cập nhật dữ liệu mới giữa 2 lần fetch trang, danh sách nạp thêm có thể chứa các ID đã hiển thị ở trang trước, gây trùng lặp phần tử hoặc crash layout do duplicate keys.

---

## 3. Giải Pháp Toàn Diện (Kiến Trúc Chuẩn Từ Commit `e3ce522`)

Kiến trúc Clean Architecture 4 tầng chuẩn hóa cho việc Phân trang (Pagination) & Cuộn vô tận (Infinite Scroll):

```text
[UI Layer: NotificationListener]
       │
       ▼ (extentAfter < 400px)
[Presentation: HomeCubit.loadMoreThemes()] ── Re-entrancy Guard & Deduplication
       │
       ▼
[Domain: GetHomeThemesUseCase(page, limit)]
       │
       ▼
[Data: HomeRepository -> Remote/Local DataSource(page, limit)]
```

### Bước 1: Chuẩn Hóa Tầng Data (Remote & Local DataSource)
- Quy định `pageSize = 20` làm chuẩn mặc định cho mobile screen (đủ hiển thị đầy 1 màn hình và 1 màn hình dự phòng phía dưới).
- Cả `RemoteDataSource` và `LocalDataSource` đều hỗ trợ phân trang:

```dart
// lib/features/home/data/datasources/home_remote_datasource.dart
@override
Future<List<KeyboardThemeModel>> getThemes({
  String? categoryId,
  int page = 1,
  int limit = 20,
}) async {
  final Map<String, dynamic> queryParams = {};
  final apiCatId = _normalizeCategoryIdForApi(categoryId);
  if (apiCatId != null) {
    queryParams['category_id'] = apiCatId;
  }
  queryParams['page'] = page;
  queryParams['limit'] = limit;

  final result = await _networkService.get(themesEndpoint, queryParameters: queryParams);
  // parse và trả về danh sách model...
}
```

- Phân trang an toàn cho `LocalDataSource` (sublist slice):
```dart
// lib/features/home/data/datasources/home_local_datasource.dart
final startIndex = (page - 1) * limit;
if (startIndex >= filtered.length) {
  return const [];
}
final endIndex = (startIndex + limit) > filtered.length
    ? filtered.length
    : startIndex + limit;
return filtered.sublist(startIndex, endIndex);
```

---

### Bước 2: Chuẩn Hóa Tầng Domain (Params & UseCase)
- Sử dụng `Equatable` cho `Params` để đảm bảo tính so sánh bất biến và testability:

```dart
// lib/features/home/domain/usecases/get_home_themes_usecase.dart
class GetHomeThemesParams extends Equatable {
  const GetHomeThemesParams({
    this.categoryId,
    this.page = 1,
    this.limit = 20,
  });

  final String? categoryId;
  final int page;
  final int limit;

  @override
  List<Object?> get props => [categoryId, page, limit];
}
```

---

### Bước 3: Quản Lý State & Re-entrancy Guard Trong Cubit
State phải theo dõi 3 trạng thái phân trang quan trọng:
1. `page`: Trang hiện tại (bắt đầu từ 1).
2. `hasReachedMax`: Đã tải hết dữ liệu từ server (`newItems.length < pageSize`).
3. `isLoadingMore`: Đang thực hiện gọi API trang tiếp theo (chặn gọi trùng).

```dart
// lib/features/home/presentation/cubit/home_cubit.dart
Future<void> loadMoreThemes() async {
  final currentState = state;
  if (currentState is! HomeLoaded) return;

  // 1. RE-ENTRANCY GUARD: Chặn gọi trùng khi đang tải, đã hết dữ liệu, hoặc đang refresh
  if (currentState.isLoadingMore ||
      currentState.hasReachedMax ||
      currentState.isRefreshing) {
    return;
  }

  // 2. Bật cờ isLoadingMore để UI render spinner chân trang
  emit(currentState.copyWith(isLoadingMore: true));

  final nextPage = currentState.page + 1;
  final themesResult = await _getThemes(
    GetHomeThemesParams(
      categoryId: currentState.selectedCategoryId,
      page: nextPage,
    ),
  );

  final activeState = state;
  if (activeState is HomeLoaded &&
      activeState.selectedCategoryId == currentState.selectedCategoryId) {
    switch (themesResult) {
      case Success(data: final newThemes):
        // 3. ID DEDUPLICATION: Khử trùng lặp ID phòng trường hợp server cập nhật dữ liệu
        final existingIds = activeState.themes.map((t) => t.id).toSet();
        final uniqueNewThemes =
            newThemes.where((t) => !existingIds.contains(t.id)).toList();

        emit(
          activeState.copyWith(
            themes: [...activeState.themes, ...uniqueNewThemes],
            page: nextPage,
            hasReachedMax: newThemes.length < pageSize,
            isLoadingMore: false,
          ),
        );
      case Failure(failure: final failure):
        logger.warning('Failed to load more themes: ${failure.message}');
        emit(activeState.copyWith(isLoadingMore: false));
    }
  }
}
```

- **Reset Pagination khi đổi Category:**
```dart
// Khi chuyển tab/category, reset về page 1 và dọn cờ
emit(
  currentState.copyWith(
    selectedCategoryId: categoryId,
    page: 1,
    hasReachedMax: false,
    isLoadingMore: false,
  ),
);
```

---

### Bước 4: Tầng UI Với `NotificationListener` Trải Nghiệm Mượt Mà (Extent Threshold)
Thay vì gắn listener trực tiếp vào `ScrollController` (dễ rò rỉ bộ nhớ hoặc gây rebuild thừa), sử dụng `NotificationListener<ScrollNotification>`:

- **Trigger ngưỡng sớm (`extentAfter < 400`):** Kích hoạt tải trang tiếp theo khi người dùng cách đáy danh sách 400 logical pixels. Giúp nội dung mới xuất hiện liền mạch mà người dùng không phải dừng lại chờ spinner.

```dart
// lib/features/home/presentation/home_screen.dart
NotificationListener<ScrollNotification>(
  onNotification: (notification) {
    if (notification is ScrollUpdateNotification) {
      // Khi khoảng cách tới đáy < 400px thì kích hoạt nạp thêm
      if (notification.metrics.extentAfter < 400) {
        cubit.loadMoreThemes();
      }
    }
    return false;
  },
  child: CustomScrollView(
    slivers: [
      // ... Các slivers nội dung chính ...

      // Spinner hiển thị chân trang khi đang nạp thêm
      if (state is HomeLoaded && state.isLoadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
    ],
  ),
)
```

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

Mỗi khi thiết kế màn hình danh sách nạp từ API:
- [ ] **Không hardcode limit lớn (ví dụ `limit = 100`):** Quy chuẩn kích thước trang là 20 items (`pageSize = 20`).
- [ ] **Phân trang cả Local Fallback:** Nếu có fallback offline, phải hỗ trợ `sublist(start, end)` theo `page` và `limit`.
- [ ] **Re-entrancy Guard trong Cubit:** Luôn kiểm tra `if (isLoadingMore || hasReachedMax) return;` trước khi dispatch request.
- [ ] **Khử trùng ID bằng `Set`:** Luôn lọc `!existingIds.contains(t.id)` trước khi gộp mảng `[...existing, ...newItems]`.
- [ ] **Reset Pagination khi chuyển Filter/Category:** Phải reset `page = 1`, `hasReachedMax = false`.
- [ ] **Ngưỡng tải trước (`extentAfter < 400`):** Sử dụng `ScrollUpdateNotification` kích hoạt tải trước cách đáy 400px để UX cuộn không bị giật cụt.

---

## 5. Tài Liệu Tham Khảo
- Commit: `e3ce522e271821b3c2ed016dd7d95075237a08e4` (PR #44 `592dfde`) - repo `app-keyboard`
- [Flutter Official: Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
