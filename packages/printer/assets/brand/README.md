# Brand logo

The shop logo printed at the top of every bill, return slip and advance
receipt (D-041) is read from `assets/brand/logo.png` in this package. The
Caramel Cottage logo is committed here.

Expected file:

- Name: `logo.png`, in this directory.
- Format: PNG.
- Size: at least 600 px wide. A wide or square image works; on paper it is
  scaled to the printable width and at most about 120 dots tall.
- Background: clean. Black on white or on transparent is best, because the
  thermal printout is black and white (dithered).

While the file is missing, or if it cannot be decoded, receipts print
exactly as they did before: a text header only. The build does not fail.
This README keeps the directory in git so `pubspec.yaml` can always list it.
