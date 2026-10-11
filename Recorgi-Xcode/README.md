# Recorgi — файлы бренда для Xcode

## Что внутри

| Путь | Что это |
| --- | --- |
| `AppIcon.icon/` | Иконка для Icon Composer (macOS 26, Liquid Glass): `icon.json` и пять плоских SVG-слоёв в `Assets/` |
| `Assets.xcassets/AppIcon.appiconset/` | Запасная иконка для macOS 15 и старше: 10 PNG от 16 до 1024 px |
| `Assets.xcassets/Wordmark.imageset/` | Логотип «Recorgi» в кривых, светлый и тёмный варианты |
| `Assets.xcassets/*.colorset/` | Семь фирменных цветов |
| `Fonts/Unbounded-Bold.ttf` | Шрифт логотипа и его лицензия `OFL.txt` |
| `Brand/RecorgiBrand.swift` | Цвета, шрифт и логотип для SwiftUI |
| `Preview/` | Картинки для просмотра, в приложение не кладутся |

## Как подключить

1. **Иконка.** Перетащите `AppIcon.icon` в навигатор проекта и отметьте таргет приложения. В настройках таргета, вкладка General, в поле App Icon укажите `AppIcon`.
2. **Ассеты.** Перетащите содержимое `Assets.xcassets` (папки `AppIcon.appiconset`, `Wordmark.imageset` и все `.colorset`) в каталог ассетов проекта. Если там уже есть пустой `AppIcon`, замените его.
3. **Шрифт.** Добавьте `Fonts/Unbounded-Bold.ttf` в таргет (он должен попасть в Copy Bundle Resources). В `Info.plist` добавьте ключ `ATSApplicationFontsPath` со значением `.` — это «Application fonts resource path».
4. **Код.** Добавьте `Brand/RecorgiBrand.swift` в таргет.

## Что нужно проверить руками

- **`AppIcon.icon` не открывался в Icon Composer.** Файл собран по разобранному сообществом формату, официального описания у Apple нет. Откройте его в Icon Composer и посмотрите все режимы. Если он не откроется, создайте новый документ и перетащите туда SVG из `AppIcon.icon/Assets/` в порядке сзади вперёд: `ears`, `head`, `muzzle`, `eyes`, `rec-dot`. Фон — градиент `#4C7DFF` → `#161F7A`, в тёмном режиме `#343849` → `#0D0E14`.
- **Стекло стоит по умолчанию.** Во всех группах включены блик и нейтральная тень 50 %, прозрачность выключена. Подберите их в Icon Composer на глаз.
- **Запасная иконка для старых macOS.** Одноимённые `AppIcon.icon` и `AppIcon.appiconset` — это приём, найденный сообществом, Apple его не документирует. Если на macOS 15 показывается не PNG-версия, добавьте в Build Settings параметр `ASSETCATALOG_OTHER_FLAGS` со значением `--enable-icon-stack-fallback-generation=disabled` и сделайте чистую сборку. Если фолбэк не нужен, удалите `AppIcon.appiconset`: Xcode сам сгенерирует картинки из `.icon`.
- **Swift-файл не компилировался.** Он короткий, но проверен только глазами.

## Справка по бренду

**Шрифты**

- Логотип и заголовки: Unbounded Bold, трекинг −2 %. PostScript-имя `Unbounded-Bold`. Лицензия SIL Open Font License, шрифт можно встраивать в приложение.
- Подписи на макетах: Onest, 400 и 600. В комплект не входит, для интерфейса macOS подойдёт системный шрифт.

**Логотип**

Буква «o» заменена кнопкой записи: кольцо цвета текста, внутри красная точка `#FF3B30`.

**Цвета**

| Имя в ассетах | Светлая тема | Тёмная тема | Где используется |
| --- | --- | --- | --- |
| `BrandInk` | `#14183A` | `#F4F5FA` | Текст и логотип |
| `BrandBlue` | `#2740C9` | `#4C7DFF` | Акцент, середина градиента |
| `BrandBlueTop` | `#4C7DFF` | — | Верх градиента иконки |
| `BrandBlueBottom` | `#161F7A` | — | Низ градиента иконки |
| `CorgiOrange` | `#FFA63A` | `#F7972B` | Голова корги |
| `CorgiEar` | `#F58A1F` | `#E07A16` | Уши |
| `RecRed` | `#FF3B30` | `#FF453A` | Точка записи |

Остальные цвета знака: внутренняя часть ушей `#FFD9B0`, морда `#FFFFFF`, глаза `#2A1A12`.
