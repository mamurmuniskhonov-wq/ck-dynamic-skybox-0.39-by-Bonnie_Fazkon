# CK Dynamic Skybox for BeamNG.drive 0.39

**English** | [Русский](#русский)

A port of CK Dynamic Skybox by **Car_Killer** to BeamNG.drive 0.39.4.

BeamNG 0.39 replaced the old gradient-based sky with a physically based atmosphere. The mod's presets were built for 0.38 and look noticeably different on 0.39: skies are darker, height fog washes out the horizon, and low-sun scenes lose their brightness. This port adapts the mod's controller to the new renderer.

Only the Lua controller is in this repository. The presets, HDR cubemaps and textures (~520 MB) come from the original release and are unchanged.

## What the port changes

**Exposure.** The mod does not force the exposure. It is left to the game's auto exposure and the player's own EV setting in the graphics options. Only a preset's own brightness value is kept as a small relative offset, so dimmer presets such as *Misty* stay darker.

**Height fog.** The preset fog height and density are applied as they are. Squeezing the fog into a thin layer near the ground made the lit 0.39 fog glow white. After sunset the fog is gradually blended to the map's own fog, reaching it at nautical twilight, so the night sky is dark and shows the stars instead of a glowing haze.

**Sky brightness and sun flare.** The presets were made for 0.38 with a sky brightness of 280, while stock 0.39 levels use 40. It is scaled down by 40/280, and the lens flare is set to scale 1 instead of the level's 5, so looking towards the sun no longer turns the sky and the car white. Both are restored when the mod is turned off.

**Sun colour.** 0.39 ignores the `sunScale` gradients. The colour difference between a preset and plain daylight is reproduced through extra ozone absorption along the sun ray.

**Freeze time.** Every preset is locked to the time of day its cubemap was made for. A *Freeze time* checkbox in the *Current Info* tab lets the player release the lock and change the time freely, for example to get a sunset on any preset. It is on by default, so the original behaviour is unchanged. The setting is not saved and is back on after a restart.

## Requirements

- BeamNG.drive 0.39.4
- The original CK Dynamic Skybox archive (version 0.5)
- [7-Zip](https://www.7-zip.org/) or another archiver that can edit zip files

## Installation

1. **Close the game.**
2. **Find the original archive.** Mods live in the user folder:
   ```
   %LocalAppData%\BeamNG\BeamNG.drive\current\mods\
   ```
   Paste this path into the Explorer address bar. If you installed the mod from the in-game repository, the archive is in the `repo` subfolder.
3. **Make a backup** of the archive, for example `ckdynamicskybox.zip.bak`, outside the `mods` folder.
4. **Replace the controller.** Open the archive in 7-Zip, go to `lua\ge\extensions\util\` and drag the downloaded `cktodbox.lua` into that folder, confirming the replacement. The path inside the archive must stay exactly `lua/ge/extensions/util/cktodbox.lua`. Do not add an extra top-level folder.
5. **Remove duplicates.** There must be only one copy of the mod in `mods` (and `mods\repo`). Two archives, or an unpacked copy in `mods\unpacked`, will conflict.
6. **Clear the cache** from the BeamNG launcher (*Clear cache*), so the game does not keep the old script.
7. **Start the game**, open *Mods* and make sure CK Dynamic Skybox is enabled, then load a map.

### Checking that it works

- The mod window (key `\`) title reads `CK Dynamic Skybox - 0.5.7-port039`.
- The *Current Info* tab has the *Freeze time* checkbox.
- The preset list is not empty. If it is, the log (`%LocalAppData%\BeamNG\BeamNG.drive\current\beamng.log`) will have `Version mismatch` or `Cubemaps are missing` lines with the `addon_ck_cktodbox` tag. That means the archive is not the original 0.5 release or its files are damaged.

### Uninstalling

Put the backup archive back and clear the cache.

## Scripting

```lua
extensions.util_cktodbox.setFreezeTime(false) -- release the preset time of day
extensions.util_cktodbox.getFreezeTime()      -- current state
extensions.util_cktodbox.toggle()             -- show or hide the mod window
```

## Brightness

The presets look darker on 0.39 than on the author's 0.38 screenshots. An earlier version of this port pushed the exposure up to match them, but in normal driving that blew the sky out to white. If you prefer a brighter look, adjust the EV compensation in the game's graphics options.

## Known issues

- With *Freeze time* off, the static cubemap clouds do not follow the sun.
- With *Freeze time* off, the cubemap sky is switched off at sunset and the game's own night sky is shown, without the preset clouds.

## Credits

CK Dynamic Skybox, its presets and assets are made by Car_Killer. This repository contains only the compatibility changes for BeamNG 0.39. All rights to the original mod remain with its author.

See [CHANGELOG.md](CHANGELOG.md) for the version history.

---

## Русский

Порт мода CK Dynamic Skybox (автор **Car_Killer**) на BeamNG.drive 0.39.4.

В версии 0.39 старое небо на градиентах заменили физической моделью атмосферы. Пресеты мода делались под 0.38 и на 0.39 выглядят иначе: небо темнее, высотный туман засвечивает горизонт, сцены с низким солнцем теряют яркость. Порт подстраивает скрипт мода под новый рендер.

В репозитории лежит только Lua-скрипт мода. Пресеты, HDR-кубмапы и текстуры (~520 МБ) берутся из оригинального архива и не изменены.

### Что изменено

**Экспозиция.** Мод не трогает экспозицию: ею управляют автоэкспозиция игры и настройка EV игрока в графических настройках. Сохраняется только собственная яркость пресета как небольшая относительная поправка, поэтому тусклые пресеты вроде *Misty* остаются темнее.

**Высотный туман.** Высота и плотность тумана из пресета применяются как есть. Сжатие тумана в тонкий слой у земли заставляло освещённый туман 0.39 светиться белым. После заката туман плавно переходит к туману самой карты и достигает его к навигационным сумеркам, поэтому ночное небо тёмное и со звёздами, а не затянуто светящейся дымкой.

**Яркость неба и блик солнца.** Пресеты делались под 0.38 с яркостью неба 280, а стоковые карты 0.39 используют 40. Яркость уменьшается в 40/280 раз, а блик линзы ставится с масштабом 1 вместо 5 у карты, поэтому при взгляде на солнце небо и машина больше не выгорают в белое. При выключении мода обе настройки возвращаются.

**Цвет солнца.** 0.39 игнорирует градиенты `sunScale`. Разница в цвете между пресетом и обычным дневным светом передаётся через дополнительное поглощение озоном на пути солнечного луча.

**Заморозка времени.** Каждый пресет привязан ко времени суток, под которое сделана его кубмапа. Флажок *Freeze time* на вкладке *Current Info* снимает привязку, и время можно менять свободно, например чтобы получить закат на любом пресете. По умолчанию флажок включён, поведение оригинала не меняется. Настройка не сохраняется и после перезапуска снова включена.

### Что нужно

- BeamNG.drive 0.39.4
- Оригинальный архив CK Dynamic Skybox (версия 0.5)
- [7-Zip](https://www.7-zip.org/) или другой архиватор, который умеет редактировать zip

### Установка

1. **Закройте игру.**
2. **Найдите оригинальный архив.** Моды лежат в папке пользователя:
   ```
   %LocalAppData%\BeamNG\BeamNG.drive\current\mods\
   ```
   Вставьте этот путь в адресную строку Проводника. Если мод ставился из встроенного репозитория игры, архив лежит в подпапке `repo`.
3. **Сделайте резервную копию** архива, например `ckdynamicskybox.zip.bak`, вне папки `mods`.
4. **Замените скрипт.** Откройте архив в 7-Zip, перейдите в `lua\ge\extensions\util\` и перетащите туда скачанный `cktodbox.lua`, подтвердив замену. Путь внутри архива должен остаться ровно `lua/ge/extensions/util/cktodbox.lua`. Лишнюю папку верхнего уровня не добавляйте.
5. **Уберите дубликаты.** В `mods` (и `mods\repo`) должна быть только одна копия мода. Два архива или распакованная копия в `mods\unpacked` будут конфликтовать.
6. **Очистите кэш** в лаунчере BeamNG (*Clear cache*), чтобы игра не держала старый скрипт.
7. **Запустите игру**, откройте *Моды*, убедитесь, что CK Dynamic Skybox включён, и загрузите карту.

### Как проверить, что всё работает

- В заголовке окна мода (клавиша `\`) написано `CK Dynamic Skybox - 0.5.7-port039`.
- На вкладке *Current Info* есть флажок *Freeze time*.
- Список пресетов не пустой. Если пустой, в логе (`%LocalAppData%\BeamNG\BeamNG.drive\current\beamng.log`) будут строки `Version mismatch` или `Cubemaps are missing` с меткой `addon_ck_cktodbox`. Это значит, что архив не оригинальный 0.5 или файлы в нём повреждены.

### Удаление

Верните резервную копию архива и очистите кэш.

### Команды для консоли

```lua
extensions.util_cktodbox.setFreezeTime(false) -- снять привязку ко времени пресета
extensions.util_cktodbox.getFreezeTime()      -- текущее состояние
extensions.util_cktodbox.toggle()             -- показать или скрыть окно мода
```

### Яркость

На 0.39 пресеты темнее, чем на скриншотах автора из 0.38. В одной из прошлых версий порта экспозиция поднималась, чтобы совпасть со скриншотами, но в обычной езде из-за этого небо выгорало в белый. Если хочется светлее, измените компенсацию EV в графических настройках игры.

### Известные проблемы

- При выключенной заморозке времени облака на статической кубмапе не следуют за солнцем.
- При выключенной заморозке времени на закате кубмапа неба выключается и показывается ночное небо игры, без облаков пресета.

### Авторы

CK Dynamic Skybox, его пресеты и ресурсы созданы Car_Killer. В этом репозитории только изменения для совместимости с BeamNG 0.39. Все права на оригинальный мод принадлежат его автору.

История версий — в [CHANGELOG.md](CHANGELOG.md).
