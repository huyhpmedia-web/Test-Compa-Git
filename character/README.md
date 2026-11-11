# Nhân vật Blender dựng từ 3 ảnh tham chiếu

Nhân vật được dựng hoàn toàn bằng script Blender Python (`bpy` 5.2 LTS) từ ba ảnh trong
`reference/` (chính diện, nghiêng phải, cận mặt).

| Tệp | Nội dung |
|---|---|
| `character.blend` | Cảnh hoàn chỉnh: thân + rig, da, mắt, tóc, áo, dây choker, bối cảnh, đèn, 3 camera |
| `renders/front.png`, `profile.png`, `closeup.png` | Render đúng 3 góc ảnh gốc |
| `renders/compare_*.jpg` | Ảnh gốc (trái) đặt cạnh render (phải) |
| `textures/skin_albedo.png` | Texture da 4096² chiếu từ ảnh tham chiếu |
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
3. **Da** (`03_bake_skin.py`): chiếu 3 ảnh lên atlas UV bằng chính các camera đã khớp, kiểm tra
   che khuất, chỉ lấy điểm ảnh là da, phần bị tóc che lấy đối xứng từ bên kia, khử bóng đổ có sẵn.
4. **Lắp ráp** (`04_build_character.py`): rig + tạo dáng (tay xuôi, đầu nghiêng như ảnh), nhãn cầu
   có giác mạc khúc xạ (`eyes.py`), tóc dạng Curves ~58 nghìn sợi (`hairgen.py`), áo thun cắt từ
   bề mặt thân (`outfit.py`), choker thắt nơ + dây yếm + khuyên tai (`outfit_posed.py`),
   bối cảnh cổng sắt / trụ gạch / tán cây (`env.py`), nắng + trời.
5. **Render** (`05_render.py`): 3 góc + ảnh so sánh.

## Chạy lại từ đầu

```bash
./setup_env.sh .venv
```

```bash
for s in 01_analyze_refs 02_fit_head 03_bake_skin 04_build_character 05_render; do .venv/bin/python scripts/$s.py; done
```

`02_fit_head.py` chỉ cần chạy lại nếu muốn khớp đầu lại từ đầu (~10 phút); kết quả đã lưu ở
`data/fit_head.npz`.

## Giới hạn đã biết

- Đây là bản dựng thủ tục từ 3 ảnh, không phải bản quét: hình khối khuôn mặt khớp theo điểm mốc
  (sai lệch khoảng 2,5–3,5 px so với ảnh) nhưng không trùng khít tuyệt đối.
- Tóc được sinh theo quy tắc (rẽ ngôi lệch, gợn sóng, đuôi vểnh) nên dáng tổng thể giống,
  từng lọn tóc thì không trùng với ảnh.
- Phần bên phải khuôn mặt bị tóc che trong ảnh chính diện được suy ra từ nửa trái (đối xứng) và
  ảnh nghiêng.
- Thân dưới áo không có ảnh tham chiếu; giữ nguyên dáng MakeHuman.

## Giấy phép dữ liệu

Lưới gốc, targets và rig của MakeHuman/MPFB2 trong `mh_data/` là CC0 (xem `mh_data/LICENSE.CC0.md`).
Các mô hình MediaPipe được tải về lúc cài đặt, không nằm trong repo.
