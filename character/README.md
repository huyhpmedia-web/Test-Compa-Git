# Nhân vật Blender dựng từ 3 ảnh tham chiếu

Nhân vật được dựng hoàn toàn bằng script Blender Python (`bpy` 5.2 LTS) từ ba ảnh trong
`reference/` (chính diện, nghiêng phải, cận mặt).

| Tệp | Nội dung |
|---|---|
| `character.blend` | Cảnh hoàn chỉnh: thân + rig, da, mắt, tóc, áo, dây choker, bối cảnh, đèn, 3 camera |
| `renders/front.png`, `profile.png`, `closeup.png` | Render đúng 3 góc ảnh gốc |
| `renders/compare_*.jpg` | Ảnh gốc (trái) đặt cạnh render (phải) |
| `textures/skin_albedo.png` | Texture da 4096² vẽ thủ tục theo hình khối (không dán ảnh) |
| `data/face_params.json` | Màu môi / mống mắt / lông mày và cỡ mống mắt lấy mẫu từ ảnh |
| `data/fit_head.npz` | Hình học đầu đã khớp với ảnh + ma trận camera của từng ảnh |
| `scripts/` | Toàn bộ pipeline, chạy lại được từ đầu |

## Mở file

Mở `character.blend` bằng Blender 5.2 trở lên, engine Cycles. Timeline có 3 frame, mỗi frame
gắn một camera và một tư thế đầu: **1 = front, 2 = profile, 3 = closeup**. Chuyển frame rồi
bấm F12 để render góc tương ứng.

## Cách dựng

1. **Lưới gốc**: lưới người MakeHuman (CC0, `mh_data/`) với các macro nữ / trẻ / dáng người.
2. **Khớp khuôn mặt** (`02_fit_head.py`): render đầu từ camera ước lượng, dò 478 điểm mốc
   (MediaPipe) trên cả ảnh thật lẫn ảnh render, đổi sai lệch pixel thành dịch chuyển 3D và nắn
   lưới bằng RBF; xen kẽ với bước khớp đường viền trán–mũi–môi–cằm lấy từ ảnh nghiêng.
3. **Khớp mí mắt** (`02b_fit_eyes.py`): đo khe mắt của lưới theo từng cột điểm ảnh (tia nào chạm
   nhãn cầu trước da) và nắn mí cho đến khi trùng đường viền mắt trong ảnh cận mặt.
4. **Da** (`03_paint_skin.py`): texture được vẽ từ chính hình khối — tông da lấy mẫu từ ảnh, môi theo
   mặt nạ môi của lưới, má hồng, phấn mắt, đường kẻ mắt chạy dọc mép mí đã khớp, tàn nhang, da đầu.
   Không có điểm ảnh chụp nào trên mặt nên nét mặt không thể lệch khỏi hình khối 3D.
   (`03_bake_skin.py` là cách cũ — chiếu ảnh lên lưới — giữ lại để tham khảo.)
5. **Lắp ráp** (`04_build_character.py`): rig + tạo dáng (tay xuôi, đầu nghiêng như ảnh), nhãn cầu
   3D có giác mạc khúc xạ và mống mắt thủ tục (`eyes.py`), lông mày + lông mi bằng sợi (`facehair.py`),
   tóc dạng Curves ~57 nghìn sợi (`hairgen.py`), áo thun cắt từ bề mặt thân (`outfit.py`),
   choker thắt nơ + dây yếm + khuyên tai (`outfit_posed.py`), nền phác thảo (`env.py`), nắng + trời.
6. **Render** (`05_render.py`): 3 góc + ảnh so sánh.

## Chạy lại từ đầu

```bash
./setup_env.sh .venv
```

```bash
for s in 01_analyze_refs 02_fit_head 02b_fit_eyes 03_paint_skin 04_build_character 05_render; do .venv/bin/python scripts/$s.py; done
```

`02_fit_head.py` chỉ cần chạy lại nếu muốn khớp đầu lại từ đầu (~10 phút); kết quả đã lưu ở
`data/fit_head.npz`.

## Giới hạn đã biết

- Đây là nhân vật CG dựng thủ tục từ 3 ảnh, không phải bản quét: tỉ lệ khuôn mặt, dáng mắt, đường
  nghiêng trán–mũi–môi–cằm khớp theo ảnh, nhưng da và nét mặt là 3D tổng hợp nên **na ná chứ không
  giống hệt người trong ảnh**.
- Tóc sinh theo quy tắc (rẽ ngôi lệch, gợn sóng, đuôi vểnh): dáng tổng thể giống, từng lọn thì không.
- Nửa phải khuôn mặt bị tóc che trong ảnh chính diện được suy ra đối xứng từ nửa trái.
- Thân dưới áo không có ảnh tham chiếu; giữ dáng MakeHuman. Nền chỉ là phác thảo.

## Giấy phép dữ liệu

Lưới gốc, targets và rig của MakeHuman/MPFB2 trong `mh_data/` là CC0 (xem `mh_data/LICENSE.CC0.md`).
Các mô hình MediaPipe được tải về lúc cài đặt, không nằm trong repo.
