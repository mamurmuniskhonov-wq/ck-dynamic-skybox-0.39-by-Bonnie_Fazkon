# CK Dynamic Skybox for BeamNG.drive 0.39

**English** | [Русский](#русский)

A port of CK Dynamic Skybox by **Car_Killer** to BeamNG.drive 0.39.4.

BeamNG 0.39 replaced the old gradient-based sky with a physically based atmosphere. The mod's presets were built for 0.38 and look noticeably different on 0.39: skies are darker, height fog washes out the horizon, and low-sun scenes lose their brightness. This port adapts the mod's controller to the new renderer so the presets look as close as possible to how the author intended.

Only the Lua controller is in this repository. The presets, HDR cubemaps and textures (~520 MB) come from the original release and are unchanged.

## What the port changes

**Exposure.** 0.39 meters exposure on the physical sky, which makes the presets about 1.2 EV darker than on 0.38. The mod now offsets exposure on top of the player's own EV setting while a preset is active, and restores it when the mod is paused, the editor opens or the level unloads.

**Height fog.** Preset fog heights (2500-5500 m) produce a full whiteout under the new lit height fog. They are clamped to 150 m.

**Sun colour.** 0.39 ignores the `sunScale` gradients. The colour difference between a preset and plain daylight is reproduced through extra ozone absorption along the sun ray.

**Low sun brightness.** The physical sky dims a low sun much more than 0.38 did. Below 30° elevation the exposure is raised gradually, up to +0.75 EV at 15° and below, then fades out between 3° and -2° so nights are not affected. `shirakaba` is excluded because its warm look is intentional.

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

- The mod window title reads `CK Dynamic Skybox - 0.5.1-port039`.
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

## Calibration

Presets were compared with the author's 0.38 screenshots from the mod page. Similarity is `100 - mean ΔE` (CIE76) over a 64×32 colour grid, with the camera matched to each screenshot.

| Scene | Preset | Similarity |
|---|---|---|
| Johnson Valley, day | Partly Cloudy 1 | 91.5 % (79 % before the port) |
| West Coast USA, sunset | daysky008b | 85.2 % |
| Utah, sunset | daysky008b | 74 % |

The Utah screenshot does not match. Reproduced on the same preset and at a similar sun height as the West Coast one, its reference sky is much darker (L\* 69 vs 96), so the author most likely used a different manual EV. One exposure curve cannot match both screenshots, and it is tuned for West Coast.

## Known issues

- Utah sunsets are more saturated than in the original screenshot (see above).
- With the sun in frame at around 15°, the sky next to the sun can clip to white.
- With *Freeze time* off, the static cubemap clouds do not follow the sun.

## Credits

CK Dynamic Skybox, its presets and assets are made by Car_Killer. This repository contains only the compatibility changes for BeamNG 0.39. All rights to the original mod remain with its author.

See [CHANGELOG.md](CHANGELOG.md) for the version history.

---

## Русский

Порт мода CK Dynamic Skybox (автор **Car_Killer**) на BeamNG.drive 0.39.4.

В версии 0.39 старое небо на градиентах заменили физической моделью атмосферы. Пресеты мода делались под 0.38 и на 0.39 выглядят иначе: небо темнее, высотный туман засвечивает горизонт, сцены с низким солнцем теряют яркость. Порт подстраивает скрипт мода под новый рендер, чтобы пресеты выглядели как можно ближе к задумке автора.

В репозитории лежит только Lua-скрипт мода. Пресеты, HDR-кубмапы и текстуры (~520 МБ) берутся из оригинального архива и не изменены.

### Что изменено

**Экспозиция.** В 0.39 экспозиция считается по физическому небу, из-за чего пресеты примерно на 1.2 EV темнее, чем в 0.38. Пока пресет активен, мод добавляет поправку поверх настройки EV игрока. При паузе мода, открытии редактора или выгрузке карты значение возвращается.

**Высотный туман.** Высоты тумана из пресетов (2500–5500 м) при новой модели дают сплошную белую пелену. Они ограничены 150 м.

**Цвет солнца.** 0.39 игнорирует градиенты `sunScale`. Разница в цвете между пресетом и обычным дневным светом передаётся через дополнительное поглощение озоном на пути солнечного луча.

**Яркость при низком солнце.** Физическое небо затемняет низкое солнце гораздо сильнее, чем 0.38. Ниже 30° экспозиция плавно поднимается, до +0.75 EV на 15° и ниже, а между 3° и −2° поправка плавно исчезает, чтобы не трогать ночь. `shirakaba` исключён: его тёплый вид задуман автором.

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

- В заголовке окна мода написано `CK Dynamic Skybox - 0.5.1-port039`.
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

### Калибровка

Пресеты сравнивались со скриншотами автора из 0.38 со страницы мода. Сходство считается как `100 − средний ΔE` (CIE76) по сетке цветов 64×32, камера выставлена по каждому скриншоту.

| Сцена | Пресет | Сходство |
|---|---|---|
| Johnson Valley, день | Partly Cloudy 1 | 91.5 % (79 % до порта) |
| West Coast USA, закат | daysky008b | 85.2 % |
| Utah, закат | daysky008b | 74 % |

Скриншот Utah не совпадает. При том же пресете и похожей высоте солнца, что и на West Coast, эталонное небо на нём намного темнее (L\* 69 против 96): вероятно, автор снимал с другим ручным EV. Одна кривая экспозиции не может подойти к обоим скриншотам, она настроена под West Coast.

### Известные проблемы

- Закаты в Utah насыщеннее, чем на оригинальном скриншоте (см. выше).
- Когда солнце в кадре на высоте около 15°, небо рядом с ним может засвечиваться в белый.
- При выключенной заморозке времени облака на статической кубмапе не следуют за солнцем.

### Авторы

CK Dynamic Skybox, его пресеты и ресурсы созданы Car_Killer. В этом репозитории только изменения для совместимости с BeamNG 0.39. Все права на оригинальный мод принадлежат его автору.

История версий — в [CHANGELOG.md](CHANGELOG.md).
