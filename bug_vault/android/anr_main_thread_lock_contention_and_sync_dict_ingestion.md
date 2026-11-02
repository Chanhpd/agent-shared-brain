# Main Thread Lock Contention (`WaitHoldingLocks`) & Synchronous Large Data Ingestion ANR

- **Ngày ghi nhận:** 2026-11-02
- **Phân loại:** Android / ANR / Performance / Concurrency
- **Mức độ nghiêm trọng:** Blocker (Khiến tỷ lệ ANR tăng vọt từ 0.70% lên 1.03%, vượt ngưỡng Google Play Vitals 0.47%)
- **Dự án phát hiện lần đầu:** `led_keyboard` (LED Keyboard: RGB, Neon Theme)
- **Môi trường:** Android Native / Production Google Play Console (Bản 1.0.29 – 1.0.31)

---

## 1. Triệu Chứng (Symptom & Error Logs)

Trên Google Play Console xuất hiện 2 cụm ANR đồng thời:
1. `com.mediatech.ledkeyboardtheme.LedInputMethodService.handleKeyboardAction` - `Input dispatching timed out` (Chiếm 4.0% các sự kiện ANR).
2. `[libart.so] art::ConditionVariable::WaitHoldingLocks` - `Input dispatching timed out (No focused window)` (Chiếm 2.0% các sự kiện ANR).

Log stack trace từ Play Console:
```text
DALVIK THREADS (main thread suspended):
"main" prio=5 tid=1 Blocked
  | sysTid=12345 nice=-16 cgrp=default sched=0/0 handle=0x...
  at com.mediatech.ledkeyboardtheme.LatinSuggestionEngine.loadDictionary(LatinSuggestionEngine.kt:363)
  - waiting to lock <0x0a1b2c3d> (a com.mediatech.ledkeyboardtheme.LatinSuggestionEngine)
    held by thread 18 (pool-1-thread-1)
  at com.mediatech.ledkeyboardtheme.LatinSuggestionEngine.getSuggestions(LatinSuggestionEngine.kt:430)
  at com.mediatech.ledkeyboardtheme.LedInputMethodService.handleKeyboardAction(LedInputMethodService.kt:385)
  at com.mediatech.ledkeyboardtheme.FullRgbKeyboardView.onKeyDown(...)
```

---

## 2. Nguyên Nhân Gốc Rễ (Root Cause)

Sự cố xuất phát từ **3 sai lầm kinh điển kết hợp** trong thiết kế bộ nạp dữ liệu (Suggestion / Trie / Dictionary Engine):

1. **Fallback nạp đồng bộ (Synchronous Loading) trên Main Thread:**
   Trong hàm tra cứu `getSuggestions()`, khi người dùng vừa gõ phím đầu tiên mà dữ liệu chưa tải xong trong RAM (`trie == null`), hàm tự động kích hoạt `loadDictionary(context, langCode)` ngay trên chính luồng gọi (Main Thread).
2. **Nghẽn phân tích Regex trên tập dữ liệu lớn (Regex Ingestion Stalls):**
   Trong hàm `loadFromJsonStream()`, ứng dụng mở file JSON từ điển (chứa **40.000 dòng**) và thực hiện `Regex.find()` trên từng dòng. Việc quét 40.000 lần Regex trên Main Thread ngốn **800ms đến 3.500ms**, khiến luồng UI bị đơ cứng, không thể tiếp nhận thao tác chạm.
3. **Tranh chấp khóa monitor toàn cục (`WaitHoldingLocks` Lock Contention):**
   Hàm `loadDictionary()` được đánh dấu bằng annotation `@Synchronized` (khóa toàn bộ đối tượng Singleton).
   - Khi app vừa mở, background worker (`executor`) đang chạy `preload()` và giữ khóa monitor để nạp từ điển (mất hàng giây do regex).
   - Cùng lúc đó, người dùng chạm phím để gõ $\rightarrow$ Main Thread nhảy vào `getSuggestions()` $\rightarrow$ gọi `loadDictionary()` và cố gắng giành monitor lock.
   - Main Thread bị block đứng im tại tầng C++ của Android Runtime: `art::ConditionVariable::WaitHoldingLocks`. Khi vượt quá 5 giây, hệ điều hành kích hoạt ANR `Input dispatching timed out`.

---

## 3. Giải Pháp Đã Xác Thực (Verified Solution)

### A. Cam Kết Non-Blocking O(1) Tuyệt Đối Cho Hàm Tra Cứu
Hàm tra cứu gọi từ luồng UI / Input Method **tuyệt đối không bao giờ được phép nạp đĩa đồng bộ**. Nếu dữ liệu chưa sẵn sàng, kích hoạt nạp ngầm và trả ngay fallback (raw input) trong **< 1ms**:

```kotlin
fun getSuggestions(
    context: Context? = null,
    rawInput: String,
    langTag: String,
    maxCount: Int = 3,
    isAutoCap: Boolean = false
): List<String> {
    val cleanInput = rawInput.trim()
    if (cleanInput.isEmpty()) return emptyList()

    val langCode = mapLangCode(langTag)
    val trie = dictionaries[langCode]
    if (trie == null || trie.wordSet.isEmpty()) {
        // Kích hoạt nạp chạy nền nếu chưa sẵn sàng
        if (context != null) {
            preload(context, langCode)
        }
        // Trả ngay input thô - TUYỆT ĐỐI không block Main Thread
        return listOf(cleanInput)
    }
    // Tra cứu trong RAM (< 0.5ms)
    ...
}
```

### B. Loại Bỏ Khóa Toàn Cục `@Synchronized`
- Bỏ từ khóa `@Synchronized` trên hàm nạp.
- Sử dụng `ConcurrentHashMap` lưu trữ cache và tracking trạng thái tải (`loadingLangs`).
- Background worker nạp vào instance Trie cục bộ, sau khi hoàn tất mới đưa vào `dictionaries[langCode]`. Luồng đọc từ Main Thread không bao giờ bị khóa.

### C. Thay Regex Bằng Fast String Slicing Parser (~100x Nhanh Hơn)
Thay vì dùng `Regex.find()` trên 40.000 dòng:
```kotlin
// THAY THẾ:
// val kvPattern = Regex("\"([^\"]+)\"\\s*:\\s*(\\d+)")
// val kvMatch = kvPattern.find(trimmed)

// BẰNG FAST STRING SCANNING:
val colonIdx = trimmed.indexOf(':')
if (colonIdx > 0) {
    val firstQuote = trimmed.indexOf('"')
    if (firstQuote != -1 && firstQuote < colonIdx) {
        val secondQuote = trimmed.indexOf('"', firstQuote + 1)
        if (secondQuote != -1 && secondQuote < colonIdx) {
            val key = trimmed.substring(firstQuote + 1, secondQuote)
            var endIdx = trimmed.length
            if (trimmed.endsWith(',')) endIdx--
            val freqStr = trimmed.substring(colonIdx + 1, endIdx).trim()
            val freq = freqStr.toIntOrNull()
            if (freq != null && key != "word" && key != "freq") {
                trie.insert(key, freq)
            }
        }
    }
}
```
*Kết quả:* Thời gian nạp 40.000 từ giảm từ **2.500ms xuống < 35ms** trên máy thật!

---

## 4. Checklist Phòng Ngừa (Prevention Checklist)

- [ ] Mọi hàm tra cứu (Suggestion, Cache, Lookup) được gọi từ Main Looper / UI Thread có cam kết **Non-Blocking O(1)** (trả fallback ngay nếu RAM chưa sẵn sàng)?
- [ ] Đã kiểm tra không có annotation `@Synchronized` trên các hàm thực hiện Disk I/O hoặc Network Call?
- [ ] Khi parse JSON / text lớn (> 5.000 phần tử), tuyệt đối không dùng Regex trong vòng lặp?
- [ ] Đã viết Unit Test mô phỏng đa luồng (ví dụ 8 thread gõ phím đồng thời trong lúc đang nạp file) để đảm bảo không có Deadlock / Lock Contention?
