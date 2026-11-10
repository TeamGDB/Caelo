# 0028 — Флаги стран на Windows

## Что требовалось

- **#168.** На Windows в списке серверов вместо флагов — буквы («DE», «NL»). Флаг — пара
  символов regional indicator, которую `SubscriptionNode.flagFor` строит из кода страны;
  в Windows единственный цветной эмодзи-шрифт — Segoe UI Emoji, и флагов в нём нет
  намеренно. Edge на той же машине показывает те же «DE». Нашлось на виртуальной машине
  Windows 11 при проверке 0.3.13.

## Как сделано

- `assets/fonts/CaeloFlags.ttf` — только флаги из Twemoji Mozilla v0.7.0 (COLR, 258 флагов,
  180 КБ): `pyftsubset` по U+1F1E6–U+1F1FF с лигатурами, рисунок не менялся. Откуда и
  как вырезан — `assets/fonts/README.md`; строка в `ATTRIBUTION.md` (рисунки CC-BY-4.0,
  сборка шрифта Apache-2.0).
- `CaeloTheme.flag` — стиль флага: на Windows шрифт `CaeloFlags`, на остальных системах —
  системные эмодзи, как люди привыкли. Не-флаги (глобус у ручного конфига, прочерк)
  уходят в системный шрифт сами. Оба места с флагом в `server_picker_sheet.dart` — через
  него.

## Проверка

- `test/flag_font_test.dart` — сам файл: таблицы COLR, CPAL, GSUB, все 26 букв, размер,
  запись в `pubspec.yaml`. `home_screen_test.dart` — на Windows все флаги экрана берут
  шрифт Caelo, на macOS, Linux, Android, iOS — нет.
- Сборка Package на ветке поставлена в виртуальную машину Windows 11: флаги в списке.
- `flutter analyze`, `flutter test`.

## Откат

Ветка `168-windows-flags`. Убрать `fontFamily` из `CaeloTheme.flag` (или весь стиль) и шрифт
из `pubspec.yaml` и `assets/fonts/`.
