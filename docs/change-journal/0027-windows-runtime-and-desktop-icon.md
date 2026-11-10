# 0027 — Windows на чистой системе и фирменный значок на Windows, Linux и macOS

## Что требовалось

- **#165.** На чистой Windows 11 Caelo 0.3.12 не запускался: «система не обнаружила
  MSVCP140.dll» (и VCRUNTIME140, VCRUNTIME140_1). Установщик не кладёт Visual C++ runtime, а
  на большинстве машин он есть лишь потому, что его поставила другая программа. Нашлось на
  чистой виртуальной машине Windows 11 при проверке ссылок `caelo://` (#163).
- Значок: на Windows у `caelo.exe` и ярлыков был стандартный значок Flutter, на Linux и
  macOS — квадрат без скругления (macOS с Big Sur не скругляет сам, а macOS 26 сажает такой
  значок в серую рамку; скругляет только iOS). Владелец: «фирменным, со скруглёнными углами».

## Как сделано

- `windows/CMakeLists.txt` — `InstallRequiredSystemLibraries` кладёт MSVCP140, VCRUNTIME140
  и VCRUNTIME140_1 рядом с `caelo.exe` (app-local: Microsoft это разрешает). Ни vc_redist,
  ни сети, ни прав администратора; портативный zip получает их так же. `release.yml`
  падает, если трёх файлов нет в сборке.
- `scripts/make-desktop-icons.py` — значки из квадратного фирменного рисунка (1024 px, его
  копия для iOS остаётся квадратной — iOS скругляет сам): скругление 22,5 % стороны,
  прозрачные углы. Пишет `windows/runner/resources/app_icon.ico` (16–256 px, отступ 4 %),
  `packaging/linux/caelo.png` (512 px: пакеты, AppImage), `docs/caelo.png` (экран
  приветствия и значок окна на X11, без отступа) и набор macOS по сетке Apple: фигура
  824 px на холсте 1024 с мягкой тенью.

## Проверка

- Сборка Package на ветке (черновик, ничего не опубликовано) — Windows собрана, проверка
  трёх DLL прошла; её установщик поставлен на чистую Windows 11 в виртуальной машине: Caelo
  запускается. Подробности — в PR.
- `flutter analyze`, `flutter test`.

## Откат

Ветка `165-windows-vc-runtime`. Убрать блок «Visual C++ runtime» из `windows/CMakeLists.txt`
и шаг проверки в `release.yml`; значки — из истории git.
