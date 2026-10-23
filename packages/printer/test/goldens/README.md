# Printer goldens

| File | What it pins | Written by |
|---|---|---|
| `<slip>_<mm80\|mm58>.txt` | The slip as text, exactly as the preview shows it with ₹ | `receipt_layout_test.dart` (PR-2) |
| `<slip>_<mm80\|mm58>_rs.hex` | The ESC/POS bytes on PC437, where ₹ prints as `Rs.` | `escpos_encoder_test.dart` (PR-3) |
| `<slip>_<mm80\|mm58>_rupee.hex` | The same on a character table that has ₹ | `escpos_encoder_test.dart` (PR-3) |
| `test_page_<mm80\|mm58>_<rs\|rupee>.txt` | The test page (PR-5) | `bluetooth_printer_service_test.dart` |

The required set (PR-6) is a normal bill, a discounted split-payment bill, a return slip and a cancelled-bill reprint, each at 80 mm and 58 mm, as text and as bytes. `golden_set_test.dart` checks they are all here and decodes every `.hex` back to text. The decoded text must equal the preview for the same slip and symbol, and for `_rupee` files, the `.txt` golden too.

After an intended layout change, run `flutter test --update-goldens` in `packages/printer` and review the diff before committing.

## Logo and advance slip (PR-8, PR-9)
- `bill_delivery_*`, `order_slip_*`, `order_slip_long_*`, `order_slip_no_advance_*` (`.txt` and `_rs.hex`): the delivery bill (an `Advance paid` line) and the advance slip: a normal one, a long multi-line description, and no advance.
- `*_logo_<width>_rs.hex`: the same slip with the **synthetic** test logo (`syntheticLogo()` in `test/fixtures.dart`, drawn in code, not a brand asset) as a `GS v 0` raster first. `golden_set_test.dart` skips the raster and checks the text after it equals the plain slip's preview.
- `image_*_logo_*.png`: receipt images with the synthetic logo in colour at the top. The `image_*` files without `logo` in the name are the text-only fallback. In `flutter test` the font draws solid blocks, so these pin the grid and the logo, not the wording.

