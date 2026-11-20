# NT547 - LAB 06 - BÁO CÁO (TỰ ĐIỀN)

**MSSV:** 25520343  | **Họ tên:** Tạ Minh Đức | **Lớp:** ATTT2025.1
**Session code tự sinh:** SC-1DB280 | **Tên contract:** ...
**Solidity / Slither:** ... / ... | **Ngày hoàn thành:** ...
**URL GitHub repository:** ...

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json`:
  - High: 4; Medium: 1; Low: 1; Informational: 4; Optimization: 1
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: Configured có: High 4; Medium 1; Low 0; Informational 0; Optimization 1 (tổng 6). Nhận xét: config chỉ lọc bớt Low/Informational (timestamp, low-level-calls, naming-convention), còn 4 High + 1 Medium vẫn giữ nguyên, nên đổi config không làm biến mất lỗi nghiêm trọng.
- 3 detector **khác tên**: `reentrancy-eth`, `tx-origin`, `unchecked-transfer`
  (ngoài ra raw còn có: weak-prng, uninitialized-state, timestamp, low-level-calls, naming-convention, constable-states, tổng cộng 9 detector khác nhau)

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | reentrancy-eth | High | Medium | AuditTarget.sol: `exitPool()` dòng 58-64 (external call dòng 61, ghi state dòng 63) | Contract độc hại gọi `exitPool()` -> ETH được gửi đi bằng `.call` ở dòng 61 trước khi `ledger[msg.sender]` về 0 ở dòng 63 -> hàm fallback gọi lại `exitPool()` nhiều lần và rút vượt số dư của mình |
| F02 | tx-origin | Medium | Medium | AuditTarget.sol: `updateOwner(address)` dòng 66-70 (dòng 67) | Owner bị dụ gọi một contract trung gian -> `require(tx.origin == owner)` vẫn thỏa vì `tx.origin` là owner thật -> contract trung gian gọi `updateOwner` và chiếm quyền owner |
| F03 | unchecked-transfer | High | Medium | AuditTarget.sol: `convertRewards(uint256)` dòng 48-52 (dòng 51) | Người dùng gọi `convertRewards` -> `stableCoin.transfer` có thể trả `false` mà giao dịch không revert, hàm không kiểm tra -> hệ thống coi như đã trả thưởng nhưng người dùng không nhận được token |

## 2. Triage và sửa lỗi (2,5 điểm)

Đọc toàn bộ AuditTarget.sol: nhận diện **4 mẫu lỗi thật + 2 đoạn cần đánh giá ngữ cảnh**,
kể cả khi Slither không hiển thị đủ 6 cảnh báo. Với mẫu không có detector,
ghi “Manual review / Not reported”, KHÔNG sửa slither.json hoặc tạo finding giả.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| reentrancy-eth (High) – `exitPool()` dòng 58-64 | TP | Hàm `external`, không có quyền hạn chế; `.call` ở dòng 61 chạy trước `ledger[msg.sender]=0` ở dòng 63 nên contract độc hại gọi lại được | Fix: áp dụng Checks-Effects-Interactions, đặt `ledger[msg.sender]=0` trước `.call` | [...] |
| unchecked-transfer (High) – `convertRewards()` dòng 48-52 | TP | Hàm `external`, `points` bị trừ ở dòng 50 nhưng kết quả `transfer` ở dòng 51 không được kiểm tra | Fix: `require(stableCoin.transfer(msg.sender, amount), "transfer failed")` | [...] |
| uninitialized-state (High) – `beneficiary` dòng 15, dùng trong `moveToTreasury()` dòng 54-56 | TP | Không có dòng nào ghi `beneficiary` nên luôn là `address(0)`; `transfer` gửi ETH vào địa chỉ 0 | Fix: gán `beneficiary = payable(msg.sender)` trong constructor, thêm `require(beneficiary != address(0))` | [...] |
| tx-origin (Medium) – `updateOwner()` dòng 66-70 | TP | Quyền kiểm tra bằng `tx.origin` (dòng 67) nên bị lợi dụng qua contract trung gian | Fix: đổi thành `require(msg.sender == owner, "not owner")` | [...] |
| weak-prng (High) – `dayOfWeek()` dòng 39-41 | Accepted (không khai thác được) | Hàm `view`, không ghi state, không chuyển tiền, không cấp quyền; chỉ trả về thứ trong tuần | Accept: `// slither-disable-next-line weak-prng` đúng dòng 40, lý do ở bên dưới | [...] |
| timestamp (Low) – `releaseTenth()` dòng 72-77 | Accepted | Hàm có `onlyOwner`; cooldown 1 ngày nên miner chỉ lệch vài giây, không ảnh hưởng điều kiện | Accept: không đổi code (mức Low, không chặn CI ở ngưỡng Medium) | [...] |

- Kịch bản khai thác TP (reentrancy): kẻ tấn công deploy contract có `fallback` gọi lại `exitPool()` -> gọi `fund()` gửi một ít ETH rồi gọi `exitPool()` -> `.call` gửi ETH ở dòng 61 trước khi `ledger` về 0, `fallback` gọi `exitPool()` lần nữa với `ledger` vẫn còn giá trị cũ -> lặp lại cho tới khi pool cạn ETH của người dùng khác.
- Finding severity cao nhưng risk thực tế thấp: `weak-prng` được Slither xếp High, nhưng `dayOfWeek()` là hàm `view` chỉ để hiển thị thứ trong tuần. Không có tiền hay quyền nào phụ thuộc vào kết quả, và miner chỉ lệch được timestamp vài giây, không đủ để đổi sang ngày khác một cách có lợi. Vì vậy risk thực tế thấp hơn nhiều so với nhãn High.
- Bằng chứng: `git diff -- AuditTarget.sol` (đính kèm ảnh), scan before: High 4 / Medium 1 / Low 1 / Info 4 / Opt 1; scan after: [...]. Cảnh báo còn lại sau sửa: [điền theo kết quả thật, ví dụ low-level-calls, naming-convention, timestamp và giải thích vì sao chấp nhận].
- Lý do `slither-disable-next-line`: detector `weak-prng`, đặt ngay trước dòng 40 trong `dayOfWeek()`. Kiểm soát bù trừ: hàm `view`, không ghi state, không chuyển ETH/token, không dùng kết quả làm nguồn ngẫu nhiên cho quyền hoặc tiền.

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy: ...
- Ảnh `evidence/architecture/inheritance.png` (hoặc .dot, nếu Graphviz chưa có): ...
- Access control nằm ở ...; logic số dư nằm ở ...; contract triển khai nằm ở ...
- Giải thích 3–5 câu điểm audit cần bắt đầu: ...

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | | | RED | |
| Patched | | | GREEN | |

- So sánh local `--fail-none` (thu thập findings) với CI `fail-on: medium`: ...
- `exclude_low/informational` thay đổi kết quả hiển thị ra sao: ...

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation một dòng: `require(msg.sender == owner, "not owner")` -> `require(tx.origin == owner, "not owner")` trong `modifier onlyOwner`.
- Detector kỳ vọng: `tx-origin` (mức Medium); xác nhận của em từ CI: ...

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | | | RED |
| Revert mutation | | | GREEN |

- Giải thích sự thay đổi về nguồn định danh/authorization: ...

## 6. Bằng chứng, tự kiểm

- [ ] `AuditTarget.sol`, `lab_identity.json`
- [ ] `evidence/before_raw/` và `evidence/before_configured/`
- [ ] `evidence/after_raw/` và `evidence/after_configured/`
- [ ] `evidence/architecture/`
- [ ] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA
- [ ] Link repo và ảnh màn hình có terminal / URL / commit SHA; không cắt mất ngữ cảnh
- [ ] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [ ] Tuyệt đối không có seed phrase, private key, credentials

**Nhận xét cuối cùng (5–7 câu):** ...
