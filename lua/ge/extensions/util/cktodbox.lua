-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local im = ui_imgui
local logTag = 'addon_ck_cktodbox'
local todBox
local rainSfx
local rainVfx
local thndrLight
local thndrShape

local guiModule = require("ge/extensions/editor/api/gui")
local gui = {setupEditorGuiTheme = nop}

local iconButtonBgColor = im.ImColorByRGB(0, 0, 0, 0)
local iconButtonFgColor = im.ImColorByRGB(255, 255, 255, 255)

--toggle imgui
local showUI = nil

--ts detec for old game
local TorqueScriptLua = TorqueScriptLua

--presets
local skyBoxTable = {}
local presetNames = {}
local presetString = ""
local presetAmnt = 0

--weather
local weatherTable = {}
local weatherNames = {}
local weatherString = ""
local weatherAmnt = 0

--current preset data
local cubemaps = {}
local startTime = {}
local endTime = {}
local material = {}
local materialGeneric = {}
local globalRef = {}
local genericCubemap = {}

local currentPreset

local pauseExecution = false

local lightmgr

local usesLua = 0

local selectedPreset = im.IntPtr(0)

local selectedWeather = im.IntPtr(0)

--level data
local loadedLevel = {}
local levelfolder = nil
local levelname =  nil

--tool stuff
local skyBoxes = "/art/cktodBox/"
local tool_version = "0.5" -- preset format version, must match "version" in the .todbox.json files
local small_version = ".6-port039"
local appTitle = "CK Dynamic Skybox - ".. tool_version .. small_version .." - ".. beamng_arch

local tod = nil
local sunsky = nil

--tod
local seconds
local hours
local mins

--game version
local ver = nil
local bigver = nil

--settings
local waterRes = im.IntPtr(0)
local waterResString = "Lowest\0Low\0Medium\0High\0Very High\0Ultra"
local allowUltra = nil
local fancyWater = nil
local autoLoad = nil
local globalEnabled = nil
local debugEnabled = nil
local settingsTable = {}
local settingsProfiles = {}
local profilesString = ""
local profileName = "global"
local profilesAmnt = 0
local selectedProfile = im.IntPtr(0)
local settingsPath = '/settings/cktodbox-settings.json'

--game version check
local function gameVER()
  ver = beamng_version
  bigver = string.format("%0.4s", ver)
  --print(bigver)
end

local function isGameVersionAtLeast(major, minor)
  local maj, min = string.match(tostring(beamng_versiond or beamng_version or ""), "^(%d+)%.(%d+)")
  maj, min = tonumber(maj), tonumber(min)
  if not maj or not min then return true end
  return maj > major or (maj == major and min >= minor)
end

--0.39 reworked core_environment (time of day state tables, lit height fog)
local newEnvApi = isGameVersionAtLeast(0, 39)

--console variables live in VariableRegistry now, TorqueScriptLua.getVar and setConsoleVariable are deprecated
local function getConsoleVar(name)
  if VariableRegistry and VariableRegistry.get then
    return VariableRegistry.get(name, "")
  end
  return TorqueScriptLua.getVar(name)
end

local function setConsoleVar(name, value)
  if VariableRegistry and VariableRegistry.set then
    VariableRegistry.set(name, value)
  else
    setConsoleVariable(name, value)
  end
end

--0.39 core_environment.setTimeOfDay only accepts a state table, the TimeOfDay object is silently ignored
local function applyTimeOfDay(timeObj)
  if not timeObj then return end
  if newEnvApi then
    core_environment.setTimeOfDay({time = timeObj.time})
  else
    core_environment.setTimeOfDay(timeObj)
  end
end

-- presets lock the time of day to their overrideTod (matching their static cubemap); the player can release it
local freezeTime = true
local function setFreezeTime(value)
  freezeTime = value and true or false
  if freezeTime and tod and currentPreset and currentPreset.overrideTod then
    tod.time = currentPreset.overrideTod
    applyTimeOfDay(tod)
  end
end
M.setFreezeTime = setFreezeTime
M.getFreezeTime = function() return freezeTime end

--the preset fog height and density are applied as they are. Lowering the fog layer to 150 m and scaling the density
--to the player altitude packed the lit 0.39 fog into a dense layer at eye level that glowed white in the sun
local function convertFog(density, height)
  return density, height
end

--0.39 places the sun from latitude/longitude/date (core_celestial) and ignores TimeOfDay.azimuthOverride/axisTilt,
--the presets rely on the legacy override: the sun moves in the vertical plane of azimuthOverride (radians),
--overhead at time 0 (noon) and on the horizon at 0.25. core_celestial.setDriver lets us retarget the sun per frame
local legacySunAzimuth
local function legacySunDriver(ctx)
  if not legacySunAzimuth or type(ctx.time) ~= "number" then return end
  local angle = math.rad(90 - ctx.time * 360)
  ctx.sunEl = math.deg(math.asin(math.sin(angle)))
  ctx.sunAz = (math.deg(legacySunAzimuth) + (math.cos(angle) >= 0 and 180 or 0)) % 360
end

local function setLegacySun(azimuth)
  if not newEnvApi or not core_celestial or not core_celestial.setDriver then return end
  legacySunAzimuth = azimuth
  if azimuth then
    core_celestial.setDriver(legacySunDriver)
  elseif core_celestial.getDriver and core_celestial.getDriver() == legacySunDriver then
    core_celestial.setDriver(nil)
  end
end

--the exposure is left to the player's EV setting and the 0.39 auto exposure; only the legacy sun brightness of the
--preset keeps its relative effect (1.2 is the default preset brightness, a dimmer preset renders darker).
--Forcing the presets brighter to match the 0.38 screenshots blew the sky out to white in normal driving
local exposureOffset
local function updateExposure()
  local obj = scenetree.findObject("PostEffectLocalExposureObject")
  if not obj then return end
  local target = (tonumber(settings.getValue("GraphicEVCompensation", 0)) or 0) + (exposureOffset or 0)
  if math.abs((tonumber(obj.exposureBiasEV) or 0) - target) > 1e-3 then
    obj.exposureBiasEV = target
  end
end

local function setLegacyExposure(preset)
  if not newEnvApi then return end
  if preset then
    local brightness = math.max(tonumber(preset.brightness) or 1.2, 0.1)
    exposureOffset = math.log(1.2 / brightness) / math.log(2)
  elseif exposureOffset then
    exposureOffset = nil
  else
    return
  end
  updateExposure()
end

--0.39 ignores the sunScale gradient (sun colour) of the presets, the sun colour now comes from the atmosphere
--transmittance. With the sunScale of the daylight presets the physical sun already matches 0.38 (compared on
--"Partly Cloudy 1" against a 0.38 screenshot), so only the difference to that colour is reproduced: the ozone column
--along the sun ray is integrated like the engine transmittance LUT and the extra attenuation is added to atmoAbsorption
local daylightSunScale = {241 / 255, 225 / 255, 210 / 255}
local savedAbsorption, sunTintColor, sunTintElevation

local function parseVec3(str)
  local a, b, c = string.match(tostring(str or ""), "(%S+)%s+(%S+)%s+(%S+)")
  a, b, c = tonumber(a), tonumber(b), tonumber(c)
  if a and b and c then return {a, b, c} end
end

local function readGradientColor(path)
  if not path or not GBitmap or not FS:fileExists(path) then return end
  local bmp = GBitmap()
  if not bmp:loadFile(path) then return end
  local width = bmp:getWidth()
  if not width or width < 1 then return end
  local col, sum, n = ColorI(0, 0, 0, 0), {0, 0, 0}, 0
  for i = 0, 7 do
    if bmp:getColor(math.floor((i + 0.5) * width / 8), 0, col) then
      sum[1], sum[2], sum[3] = sum[1] + col.r, sum[2] + col.g, sum[3] + col.b
      n = n + 1
    end
  end
  if n == 0 then return end
  return {sum[1] / (255 * n), sum[2] / (255 * n), sum[3] / (255 * n)}
end

--ozone column (km) along the sun ray from the ground
local function ozoneColumn(sky, elevation)
  local R = tonumber(sky.atmoPlanetRadius) or 6360
  local top = R + (tonumber(sky.atmoThickness) or 100)
  local ozWidth = tonumber(sky.atmoOzoneLayerWidth) or 25
  local c0, l0 = tonumber(sky.atmoOzoneConst0) or -2 / 3, tonumber(sky.atmoOzoneLinear0) or 1 / 15
  local c1, l1 = tonumber(sky.atmoOzoneConst1) or 8 / 3, tonumber(sky.atmoOzoneLinear1) or -1 / 15
  local mu = math.sin(math.rad(elevation))
  local len = -R * mu + math.sqrt(R * R * mu * mu + top * top - R * R)
  local steps = 256
  local ds = len / steps
  local column = 0
  for i = 0, steps - 1 do
    local s = (i + 0.5) * ds
    local h = math.sqrt(R * R + s * s + 2 * R * s * mu) - R
    column = column + math.max(0, math.min(1, h < ozWidth and (l0 * h + c0) or (l1 * h + c1))) * ds
  end
  return column
end

local function applySunTint(elevation)
  if not sunTintColor or not sunsky or not savedAbsorption then return end
  local base = parseVec3(savedAbsorption)
  if not base then return end
  local absorption = base
  if elevation > 0.5 then
    local column = math.max(ozoneColumn(sunsky, elevation), 1e-3)
    local ratio, maxRatio = {}, 0
    for c = 1, 3 do
      ratio[c] = math.max(sunTintColor[c], 1e-3) / daylightSunScale[c]
      maxRatio = math.max(maxRatio, ratio[c])
    end
    absorption = {}
    for c = 1, 3 do
      absorption[c] = base[c] - math.log(ratio[c] / maxRatio) / column
    end
  end
  sunsky:setField("atmoAbsorption", 0, string.format("%.9g %.9g %.9g", absorption[1], absorption[2], absorption[3]))
  sunTintElevation = elevation
end

local function restoreSunTint()
  if savedAbsorption and sunsky then
    sunsky:setField("atmoAbsorption", 0, savedAbsorption)
  end
  savedAbsorption, sunTintColor, sunTintElevation = nil, nil, nil
end

local function setSunTint(preset, elevation)
  if not newEnvApi or not sunsky then return end
  local color
  if preset and preset.sunScale and preset.directory and preset.name then
    color = readGradientColor(preset.directory .. "sky_gradients/" .. preset.name .. "/" .. preset.sunScale)
  end
  if not color then
    restoreSunTint()
    return
  end
  if not savedAbsorption then savedAbsorption = sunsky:getField("atmoAbsorption", 0) end
  sunTintColor = color
  applySunTint(elevation or tonumber(sunsky.elevation) or 45)
end

--the legacy sun elevation for a time of day, see legacySunDriver
local function legacyElevation(time)
  return math.deg(math.asin(math.sin(math.rad(90 - time * 360))))
end

local function settingsSave()
  settingsTable.debugEnabled = debugEnabled
  if not settingsTable.profiles then
    settingsTable.profiles = {}
  end
  settingsTable.profiles["global"] = {
    currentPreset = currentPreset.name,
    autoLoad = autoLoad,
    globalEnabled = globalEnabled,
    allowUltra = allowUltra,
    fancyWater = fancyWater,
    waterRes = waterRes[0],
  }
  jsonWriteFile(settingsPath, settingsTable, true)
end

local function updateProfiles()
  settingsProfiles = {}
  for k,v in pairs(settingsTable.profiles) do
    table.insert(settingsProfiles, k)
  end
  if settingsProfiles then
    profilesAmnt = 0
    profilesString = ""
    local count = 0
    for k,v in ipairs(settingsProfiles) do
      count = count + 1
      profilesString = profilesString..v.."\0"
    end
    profilesAmnt = count
  end
end

local function settingsLoad()
  settingsTable = jsonReadFile(settingsPath)
  if not tableIsEmpty(settingsTable) then
    for k,v in pairs(skyBoxTable) do
      if skyBoxTable[k].name == settingsTable.profiles["global"].currentPreset then
        selectedPreset[0] = k-1
      end
    end
    autoLoad = settingsTable.profiles["global"].autoLoad
    globalEnabled = settingsTable.profiles["global"].globalEnabled
    allowUltra = settingsTable.profiles["global"].allowUltra
    fancyWater = settingsTable.profiles["global"].fancyWater
    if settingsTable.profiles["global"].waterRes ~= nil then
      waterRes[0] = settingsTable.profiles["global"].waterRes
    end
    debugEnabled = settingsTable.debugEnabled
  end
  if autoLoad == nil then autoLoad = true end
  if allowUltra == nil then allowUltra = true end
  if fancyWater == nil then fancyWater = false end
  if waterRes[0] == 0 then waterRes[0] = 2 end
  if globalEnabled == nil then globalEnabled = true end
  if debugEnabled == nil then debugEnabled = false end
  if tableIsEmpty(settingsTable) then
    settingsTable = {}
    settingsSave()
  end
  updateProfiles()
  for k,v in pairs(settingsProfiles) do
    if v == 'global' then selectedProfile[0] = k-1 end
  end
  profileName = 'global'
end

local function verifyPreset(id)
  local pass = true
  if skyBoxTable[id].name then
    if string.lower(skyBoxTable[id].name..'.todbox.json') ~= string.lower(skyBoxTable[id].fileName) then
      log('E', logTag, 'Filename mismatch. Real filename: '..skyBoxTable[id].fileName..'. Expected filename: '..skyBoxTable[id].name..'.todbox.json'..'. Please fix' )
      pass = false
    end
  else
    log('E', logTag, 'Missing name' )
    pass = false
  end
  if skyBoxTable[id].directory then
    if string.lower(skyBoxTable[id].realDir) ~= string.lower(skyBoxTable[id].directory) then
      log('E', logTag, 'Directory mismatch. Real directory: '..skyBoxTable[id].realDir..'. Expected directory: '..skyBoxTable[id].directory..'. Please fix' )
      pass = false
    end
  else
    log('E', logTag, 'Missing directory' )
    pass = false
  end
  if not skyBoxTable[id].presetName then
    log('E', logTag, 'Missing presetName' )
    pass = false
  end
  if pass == true then
    if not FS:fileExists(skyBoxTable[id].directory..skyBoxTable[id].name..'.todbox.json') then
      log('E', logTag, 'File: '..skyBoxTable[id].directory..skyBoxTable[id].name..'.todbox.json is missing' )
      pass = false
    end
    if not FS:directoryExists(skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name) then
      log('E', logTag, 'Directory: '..skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name..' is missing' )
      pass = false
    else
      local materialfiles = FS:findFilesByPattern(skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name, "*materials.json", -1, true, false)
      local data = {CubemapData = {}, Material = {}}
      for  _,f in pairs(materialfiles) do
        local materialData = jsonReadFile(f)
        for k,v in pairs(materialData) do
          if v.class and v.class == 'CubemapData' then
            data.CubemapData[v.name] = true
            if v.cubeFace then
              for l,c in pairs(v.cubeFace) do
                if not FS:fileExists(c) then
                  log('E', logTag, 'File: '..c..' is missing' )
                  pass = false
                end
              end
            end
          end
          if v.class and v.class == 'Material' then
            data.Material[v.name] = true
          end
        end
      end
      if skyBoxTable[id].cubemaps then
        for k,v in pairs(skyBoxTable[id].cubemaps) do
          if v.material then
            if data.Material[v.material] ~= true then
              log('E', logTag, k..' Material: '..v.material..' is missing')
              pass = false
            end
          else
            log('E', logTag, k..' material is missing')
            pass = false
          end
          if v.globalReflection then
            if data.CubemapData[v.globalReflection] ~= true then
              log('E', logTag, k..' CubeMap: '..v.globalReflection..' is missing')
              pass = false
            end
          else
            log('E', logTag, k..' globalReflection is missing')
            pass = false
          end
          if not (skyBoxTable[id].isStatic and skyBoxTable[id].isStatic == true) then
            if not v.startTimeH then
              log('E', logTag, k..' startTimeH is missing' )
              pass = false
            end
            if not v.startTimeM then
              log('E', logTag, k..' startTimeM is missing' )
              pass = false
            end
            if not v.endTimeH then
              log('E', logTag, k..' endTimeH is missing' )
              pass = false
            end
            if not v.endTimeM then
              log('E', logTag, k..' endTimeM is missing' )
              pass = false
            end
          end
        end
      else
        log('E', logTag, 'Cubemaps are missing' )
        pass = false
      end
    end
    if skyBoxTable[id].supportGenericCubemap and skyBoxTable[id].supportGenericCubemap == true then
      if not FS:directoryExists(skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name..'_reflection') then
        log('E', logTag, 'Directory: '..skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name..'_reflection is missing' )
        pass = false
      else
        local materialfiles = FS:findFilesByPattern(skyBoxTable[id].directory.."/cubemaps/"..skyBoxTable[id].name.."_reflection", "*materials.json", -1, true, false)
        local data = {CubemapData = {}, Material = {}}
        for  _,f in pairs(materialfiles) do
          local materialData = jsonReadFile(f)
          for k,v in pairs(materialData) do
            if v.class and v.class == 'CubemapData' then
              data.CubemapData[v.name] = true
              if v.cubeFace then
                for l,c in pairs(v.cubeFace) do
                  if not FS:fileExists(c) then
                    log('E', logTag, 'File: '..c..' is missing' )
                    pass = false
                  end
                end
              end
            end
            if v.class and v.class == 'Material' then
              data.Material[v.name] = true
            end
          end
        end
        if skyBoxTable[id].cubemaps then
          for k,v in pairs(skyBoxTable[id].cubemaps) do
            if v.materialGeneric then
              if data.Material[v.materialGeneric] ~= true then
                log('E', logTag, k..' Material: '..v.materialGeneric..' is missing')
                pass = false
              end
            else
              log('E', logTag, k..' materialGeneric is missing')
              pass = false
            end
            if v.genericCubemap then
              if data.CubemapData[v.genericCubemap] ~= true then
              log('E', logTag, 'CubeMap: '..v.genericCubemap..' is missing')
                pass = false
              end
            else
              log('E', logTag, k..' genericCubemap is missing')
              pass = false
            end
          end
        else
          log('E', logTag, 'Cubemaps are missing' )
          pass = false
        end
      end
    end
  end
  return pass
end

local function onLoadedPreset()
  for k,v in pairs(skyBoxTable) do
    if skyBoxTable[k].version and skyBoxTable[k].version == tool_version then
      log('I', logTag, 'Version matched. Loading preset' )
      if verifyPreset(k) == true then
        table.insert(presetNames, skyBoxTable[k].presetName)
        log('I', logTag, 'Loaded preset '..skyBoxTable[k].presetName)
      else
        log('E', logTag, 'Verification failed...' )
        skyBoxTable[k].failed = true
      end
    else
      log('E', logTag, 'Version mismatch. Skipping...' )
      skyBoxTable[k].failed = true
    end
  end
  if presetNames then
    presetAmnt = 0
    local count = 0
    for k,v in ipairs(presetNames) do
      count = count + 1
      presetString = presetString..v.."\0"
    end
    presetAmnt = count
  end
end

local function registerMaterials(location)
  log('I', logTag, 'Registering Materials' )
  local blacklist = {"forest", "tree", "terrains", "terrain", "trees", "groundcover"}
   -- Loading CS files (0.17 doesnt have any anymore)
  local files = FS:findFiles(location, 'materials.cs', -1, true, false)
  -- log("D","onClientPreStartMission","CS = "..dumps(files))
  for i,v in ipairs(files) do
      if not FS:fileExists(v) then goto continueCs end
      for _,b in ipairs(blacklist) do
          if v:find(b) then
              -- log("E","onClientPreStartMission","skipped = "..dumps(v))
              goto continueCs
          end
      end
      TorqueScriptLua.exec(v)
      log('I', logTag, 'Registering new TS material '..v )
      ::continueCs::
  end

  -- Loading new Json materials
  local materialfiles = FS:findFilesByPattern(location, "*materials.json", -1, true, false)
  -- log("D","onClientPreStartMission","json = "..dumps(materialfiles))
  for  _,v in pairs(materialfiles) do
      if not FS:fileExists(v) then goto continueJ end
      for _,b in ipairs(blacklist) do
          if v:find(b) then
              -- log("D","onClientPreStartMission","skipped = "..dumps(v))
              goto continueJ
          end
      end
      loadJsonMaterialsFile(v)
      log('I', logTag, 'Registering new json material '..v )
      ::continueJ::
  end
end

local function deleteMaterials(mat)
  pauseExecution = true
  local delObj = scenetree.findObject(mat)
  if delObj and delObj.className == 'Material' then
    log('I', logTag, 'Deleting Material '..mat )
    delObj:deleteObject()
  end
  --[[local delObj = scenetree.findObject(mat)
  if delObj and delObj.className == 'CubemapData' then
    log('I', logTag, 'Deleting Cubemap '..mat )
    local parent = delObj:getGroup()
    if parent then
      parent:removeObject(delObj)
    end
    delObj:delete()
  end]]--
  pauseExecution = false
end

local function setCubemap(cubemapname)
  if cubemapname then
    local levelinf
    local infos = scenetree.findClassObjects('LevelInfo')
    for i,v in pairs(infos) do
      local info = scenetree.findObject(v)
      if info.hidden ~= true then
        levelinf = info
      end
    end
    if levelinf then
      log("I", logTag, "Enabling cubemap " ..cubemapname)
      levelinf:setField('globalEnviromentMap', 0, cubemapname)
      levelinf:postApply()
    else
      log("W", logTag, "Enabling fallback cubemap " ..cubemapname)
      setConsoleVar("$defaultLevelEnviromentMap", cubemapname)
    end
  else
    log('E', logTag, 'Invalid cubemap' )
  end
end

local function loadWeatherData()
  if currentPreset and currentPreset.weather then
    local countWeather = 0
    for k,v in pairs(currentPreset.weather) do
      if type(v) == 'table' then
        countWeather = countWeather + 1
        weatherTable[countWeather] = v
        table.insert(weatherNames, v.presetName)
        log('I', logTag, 'Loaded weather preset: '..v.presetName)
        if v.name == 'default' then selectedWeather[0] = countWeather - 1 end
      end
    end
    if weatherNames then
      weatherAmnt = 0
      local count = 0
      for k,v in ipairs(weatherNames) do
        count = count + 1
        weatherString = weatherString..v.."\0"
      end
      weatherAmnt = count
    end
  end
end

--[[local function setMaterialShiny(isTrue)
  if loadedLevel and loadedLevel["weatherMaterials"] then
    for i,v in pairs(loadedLevel["weatherMaterials"]) do
      local mat = scenetree.findObject(i)
      if isTrue == true then
        mat:setField("roughnessFactor", 0, loadedLevel["weatherMaterials"][i].roughnessFactor)
        mat.roughnessFactor = mat.roughnessFactor - 0.4
      else
        mat:setField("roughnessFactor", 0, loadedLevel["weatherMaterials"][i].roughnessFactor)
      end
      mat:flush()
      mat:reload()
    end
  end
end

local function setAsphaltWet(isTrue)
  local materials = scenetree.findClassObjects('Material')
  for i,v in pairs(materials) do
    local mat = scenetree.findObject(v)
    if isTrue == true then
      if mat and mat.groundType and mat.groundType == "ASPHALT" then
        mat.groundType = "ASPHALT_WET"
        mat:reload()
      end
    else
      if mat and mat.groundType and mat.groundType == "ASPHALT_WET" then
        mat.groundType = "ASPHALT"
        mat:reload()
      end
    end
  end
  be:reloadCollision()
end]]--

--the 0.38 presets use skyBrightness 280 (200 for overcast), the stock 0.39 levels use 40 for a clear day.
--At the preset value the forward scattering around the sun and the lens flare glowed white when facing the sun
local skyBrightnessScale = 40 / 280
local legacyFlareScale = 1

local function setSunsky(data)
  if data.sunSize then
    sunsky.sunSize = data.sunSize
  else
    log('W', logTag, 'Missing sunSize' )
  end
  if data.exposure then
    sunsky.exposure = data.exposure
  else
    log('W', logTag, 'Missing exposure' )
  end
  if data.skyBrightness then
    sunsky.skyBrightness = newEnvApi and data.skyBrightness * skyBrightnessScale or data.skyBrightness
  else
    log('W', logTag, 'Missing skyBrightness' )
  end
  if data.brightness then
    sunsky.brightness = data.brightness
  end
  if newEnvApi then
    sunsky.flareScale = data.flareScale or legacyFlareScale
  end
  if data.rayleighScattering then
    sunsky.rayleighScattering = data.rayleighScattering
  else
    log('W', logTag, 'Missing rayleighScattering' )
  end
  if data.logWeight then
    sunsky.logWeight = data.logWeight
  end
  if data.groundAlbedo then
    sunsky:setField('groundAlbedo', 0, data.groundAlbedo)
  end
  if data.sunShadowSoftness then
    sunsky.shadowSoftness = data.sunShadowSoftness
  else
    log('W', logTag, 'Missing sunShadowSoftness' )
  end
  if data.sunShadowDistance then
    sunsky.shadowDistance = data.sunShadowDistance
  else
    log('W', logTag, 'Missing sunShadowDistance' )
  end
  if data.sunShadow then
    sunsky.texSize = data.sunShadow
  else
    log('W', logTag, 'Missing sunShadow' )
  end
end

local function setDefaultWeather(levelinf)
  rainSfx:setField('track', 0, "amb_rain_medium")
  rainSfx.volume = 0
  rainSfx.fileName = ""
  rainSfx:postApply()
  rainVfx.numDrops = 0
  rainVfx.dropSize = 0.1
  rainVfx.minSpeed = 1.5
  rainVfx.maxSpeed = 2
  rainVfx.minMass = 0.75
  rainVfx.maxMass = 0.85
  rainVfx:setField('dataBlock', 0, "rain_medium")
  rainVfx:postApply()
  thndrLight:setField('color', 0, "0.955055594 0.824404299 1 1")
  thndrLight.hidden = true
  thndrLight.isEnabled = true
  thndrLight:postApply()
  thndrShape.hidden = true
  thndrShape.shapeName = "/core/art/shapes/no_mesh.dae"
  thndrShape:postApply()
  setSunsky(currentPreset)
  --setAsphaltWet(false)
  --setMaterialShiny(false)
  if levelinf then
    log('I', logTag, 'Adding theLevelInfo overrides' )
    local changed = false
    local fogDensity, fogHeight = convertFog(currentPreset.fogDensity, currentPreset.atmoshpereHeight)
    if currentPreset.fogOffset then
      levelinf.fogDensityOffset = currentPreset.fogOffset
      changed = true
    else
      log('W', logTag, 'Missing fogOffset' )
    end
    if currentPreset.fogDensity then
      levelinf.fogDensity = fogDensity
      changed = true
    else
      log('W', logTag, 'Missing fogDensity' )
    end
    if currentPreset.atmoshpereHeight then
      levelinf.fogAtmosphereHeight = fogHeight
      changed = true
    else
      log('W', logTag, 'Missing atmoshpereHeight' )
    end
    if changed == true then
      levelinf:postApply()
    end
  end
end

local function setTargetWeather(target)
  log('I', logTag, 'Weather selected, loading data' )
  if currentPreset and currentPreset.weather and weatherTable then
    local levelinf
    local infos = scenetree.findClassObjects('LevelInfo')
    for i,v in pairs(infos) do
      local info = scenetree.findObject(v)
      if info.hidden ~= true then
        levelinf = info
      end
    end
    if rainSfx and rainVfx and thndrLight and thndrShape and sunsky then
      if weatherTable[target].name ~= 'default' then
        setDefaultWeather(levelinf)
        setSunsky(weatherTable[target])
        if levelinf then
          log('I', logTag, 'Adding theLevelInfo overrides' )
          local changed = false
          local fogDensity, fogHeight = convertFog(weatherTable[target].fogDensity, weatherTable[target].atmoshpereHeight)
          if weatherTable[target].fogOffset then
            levelinf.fogDensityOffset = weatherTable[target].fogOffset
            changed = true
          else
            log('I', logTag, 'Missing fogOffset' )
          end
          if weatherTable[target].fogDensity then
            levelinf.fogDensity = fogDensity
            changed = true
          else
            log('I', logTag, 'Missing fogDensity' )
          end
          if weatherTable[target].atmoshpereHeight then
            levelinf.fogAtmosphereHeight = fogHeight
            changed = true
          else
            log('I', logTag, 'Missing atmoshpereHeight' )
          end
          if changed == true then
            levelinf:postApply()
          end
        end
        if weatherTable[target].rain and weatherTable[target].rain == true then
          if weatherTable[target].rainDatablock then
            rainVfx:setField('dataBlock', 0, weatherTable[target].rainDatablock)
          else
            log('I', logTag, 'Missing rainDatablock' )
          end
          if weatherTable[target].rainAmount then
            rainVfx.numDrops = weatherTable[target].rainAmount
          else
            log('I', logTag, 'Missing rainAmount' )
          end
          if weatherTable[target].rainDropSize then
            rainVfx.dropSize = weatherTable[target].rainDropSize
          end
          if weatherTable[target].rainMaxMass then
            rainVfx.maxMass = weatherTable[target].rainMaxMass
          end
          if weatherTable[target].rainMaxSpeed then
            rainVfx.maxSpeed = weatherTable[target].rainMaxSpeed
          end
          if weatherTable[target].rainMinMass then
            rainVfx.minMass = weatherTable[target].rainMinMass
          end
          if weatherTable[target].rainMinSpeed then
            rainVfx.minSpeed = weatherTable[target].rainMinSpeed
          end
          rainVfx:postApply()
        end
        if weatherTable[target].sfxVolume and weatherTable[target].sfxVolume > 0 then
          rainSfx.volume = weatherTable[target].sfxVolume
          rainSfx:postApply()
        end
        if weatherTable[target].sfxLocation then
          rainSfx.fileName = weatherTable[target].sfxLocation
          rainSfx:setField('track', 0, "")
          rainSfx:postApply()
        end
        if weatherTable[target].thunderModel then
          if weatherTable[target].thunderDir then
            registerMaterials(weatherTable[target].thunderDir)
          end
          thndrShape.shapeName = weatherTable[target].thunderModel
          thndrShape:postApply()
        end
        --[[if weatherTable[target].setAsphaltWet and weatherTable[target].setAsphaltWet == true then
          setAsphaltWet(weatherTable[target].setAsphaltWet)
        end
        if weatherTable[target].setMaterialShiny == weatherTable[target].setMaterialShiny == true then
          setMaterialShiny(weatherTable[target].setMaterialShiny)
        end]]--
      else
        setDefaultWeather(levelinf)
      end
    else
      log('E', logTag, 'Weather components are missing' )
    end
  end
end

local function onSelectedPreset(presetID)
  if currentPreset and currentPreset ~= skyBoxTable[presetID] then
    for k,v in pairs(material) do
      deleteMaterials(v)
    end
    for k,v in pairs(materialGeneric) do
      deleteMaterials(v)
    end
    --[[for k,v in pairs(globalRef) do
      deleteMaterials(v)
    end]]--
  end
  local startTimeH = {}
  local startTimeM = {}
  local endTimeH = {}
  local endTimeM = {}

  if presetAmnt > 0 then
    cubemaps = {}
    startTime = {}
    endTime = {}
    material = {}
    materialGeneric = {}
    globalRef = {}
    genericCubemap = {}

    log('I', logTag, 'Preset selected, loading data' )

    currentPreset = skyBoxTable[presetID]

    for k,v in pairs(currentPreset.cubemaps) do
      table.insert(cubemaps, k)
    end
    for k,v in ipairs(cubemaps) do
      for k,v in pairs(currentPreset.cubemaps[v]) do
        if k == "material" then table.insert(material, v) end
        if k == "startTimeH" then table.insert(startTimeH, v) end
        if k == "startTimeM" then table.insert(startTimeM, v) end
        if k == "endTimeH" then table.insert(endTimeH, v) end
        if k == "endTimeM" then table.insert(endTimeM, v) end
        if k == "globalReflection" then table.insert(globalRef, v) end
        if currentPreset.supportGenericCubemap and currentPreset.supportGenericCubemap == true then
          if k == "materialGeneric" then table.insert(materialGeneric, v) end
          if k == "genericCubemap" then table.insert(genericCubemap, v) end
        end
      end
    end
    if startTimeH and startTimeM then
      for k,v in pairs(startTimeH) do
        local Hseconds = v*3600
        local Mseconds = startTimeM[k]*60
        local time = (Hseconds + Mseconds)  --/86400
        --local time = (time-0.5) %1
        table.insert(startTime, time)
      end
    end
    if endTimeH and endTimeM then
      for k,v in pairs(endTimeH) do
        local Hseconds = v*3600
        local Mseconds = endTimeM[k]*60
        local time = (Hseconds + Mseconds)  --/86400
        --local time = (time-0.5) %1
        table.insert(endTime, time)
      end
    end
    local gameMats = scenetree.findClassObjects('Material')
    local missingMat
    for k,v in pairs(material) do
      local mat = v
      for k,v in pairs(gameMats) do
        if v == mat then  else  missingMat = true end
      end
    end
    for k,v in pairs(materialGeneric) do
      local mat = v
      for k,v in pairs(gameMats) do
        if v == mat then  else  missingMat = true end
      end
    end
    if missingMat == true then
      log('W', logTag, 'Materials are missing' )
      if currentPreset.supportGenericCubemap and currentPreset.supportGenericCubemap == true then
        registerMaterials(currentPreset.directory.."/cubemaps/"..currentPreset.name.."_reflection")
      end
      registerMaterials(currentPreset.directory.."/cubemaps/"..currentPreset.name)
    else
      log('I', logTag, 'Materials are registered' )
    end
    weatherTable = {}
    weatherNames = {}
    weatherString = ""
    if currentPreset.weather and currentPreset.weather.enabled and currentPreset.weather.enabled == true then
      loadWeatherData()
    end
  else
    log('E', logTag, 'Presets are missing' )
  end
end

local function onAddWeatherComponents()
  local missionGroup = scenetree.MissionGroup
  if not missionGroup then
    log('E', logTag, 'MissionGroup does not exist')
  else
    rainSfx = scenetree.findObject("rainSfx")
    if not rainSfx then
      log('I', logTag, 'Generating weather Sfx')
      local sfx
      sfx = createObject('SFXEmitter')
      sfx:setPosition(vec3(0, 0, 0))
      sfx:setField('canSave', 0, "0")
      sfx:setField('canSaveDynamicFields', 0, "1")
      sfx:setField('name', 0, "rainSfx")
      sfx:setField('track', 0, "amb_rain_medium")
      sfx:setField('sourceGroup', 0, "AudioChannelEnvironment")
      sfx.canSave = false
      sfx.volume = 0
      sfx.is3D = false
      sfx.playOnAdd = true
      sfx.useTrackDescriptionOnly = false
      sfx.isLooping = true
      sfx.isStreaming = true
      sfx:registerObject("rainSfx")
      missionGroup:addObject(sfx)
      rainSfx = scenetree.findObject("rainSfx")
    end
    rainVfx = scenetree.findObject("rainVfx")
    if not rainVfx then
      log('I', logTag, 'Generating weather vfx')
      local vfx
      vfx = createObject('Precipitation')
      vfx:setPosition(vec3(0, 0, 0))
      vfx:setField('canSave', 0, "0")
      vfx:setField('canSaveDynamicFields', 0, "1")
      vfx:setField('name', 0, "rainVfx")
      vfx.canSave = false
      vfx.numDrops = 0
      vfx.boxWidth = 50
      vfx.boxHeight = 30
      vfx.dropSize = 0.1
      vfx.animateSplashes = false
      vfx.doCollision = false
      vfx.followCam = true
      vfx.rotateWithCamVel = true
      vfx.minSpeed = 1.5
      vfx.maxSpeed = 2
      vfx.minMass = 0.75
      vfx.maxMass = 0.85
      vfx:registerObject("rainVfx")
      missionGroup:addObject(vfx)
      rainVfx = scenetree.findObject("rainVfx")
    end
    thndrLight = scenetree.findObject("thndrLight")
    if not thndrLight then
      log('I', logTag, 'Generating thunder light')
      local light
      light = createObject('PointLight')
      light:setPosition(vec3(0, 0, 0))
      light:setField('canSave', 0, "0")
      light:setField('canSaveDynamicFields', 0, "1")
      light:setField('name', 0, "thndrLight")
      light:setField('color', 0, "0.955055594 0.824404299 1 1")
      light.canSave = false
      light.hidden = true
      light.isEnabled = true
      light.radius = 2000
      light.brightness = 0.8
      light.castShaodws = true
      light.texSize = 2048
      light.shadowSoftness = 0.4
      light:registerObject("thndrLight")
      missionGroup:addObject(light)
      thndrLight = scenetree.findObject("thndrLight")
    end
    thndrShape = scenetree.findObject("thndrShape")
    if not thndrShape then
      log('I', logTag, 'Generating thunder shape')
      local shape
      shape = createObject('TSStatic')
      shape:setPosition(vec3(0, 0, 0))
      shape:setField('canSave', 0, "0")
      shape:setField('canSaveDynamicFields', 0, "1")
      shape:setField('name', 0, "thndrShape")
      shape.canSave = false
      shape.hidden = true
      shape.shapeName = "/core/art/shapes/no_mesh.dae"
      shape:registerObject("thndrShape")
      missionGroup:addObject(shape)
      thndrShape = scenetree.findObject("thndrShape")
    end
  end
end

local function getTod()
  local times = scenetree.findClassObjects('TimeOfDay')
  for i,v in pairs(times) do
    local time = scenetree.findObject(v)
    if time.hidden ~= true then
      tod = time
    end
  end
end

local function onAddComponentsToMission()
  getTod()
  if tod then
    lightmgr = tostring(getConsoleVar("$pref::lightManager"))
    todBox = scenetree.findObject("todbox")
    if not todBox then
    log('I', logTag, 'There is no dynamic skybox in the level, checking...' )
    local skyBoxes = scenetree.findClassObjects('SkyBox')
    for i,v in pairs(skyBoxes) do
      local skyBox = scenetree.findObject(v)
      if skyBox.hidden ~= true then
        todBox = skyBox
      end
    end
    end
    local skies = scenetree.findClassObjects('ScatterSky')
    for i,v in pairs(skies) do
      local sky = scenetree.findObject(v)
      if sky.hidden ~= true then
        sunsky = sky
      end
    end
    if tod and sunsky and not todBox then
    local missionGroup = scenetree.MissionGroup
    if not missionGroup then
      log('E', logTag, 'MissionGroup does not exist')
    else
      log('I', logTag, 'Generating SkyBox')
      local createtodBox
      createtodBox = createObject('SkyBox')
      createtodBox:setPosition(vec3(0, 0, 0))
      createtodBox:setField('canSave', 0, "0")
      createtodBox:setField('canSaveDynamicFields', 0, "1")
      createtodBox:setField('name', 0, "todbox")
      createtodBox.canSave = false
      createtodBox.Material = "empty"
      createtodBox:registerObject("todbox")
      missionGroup:addObject(createtodBox)
      todBox = scenetree.findObject("todbox")
    end
    else
      log('W', logTag, 'There is skybox in the level' )
    end
    if tod and todBox then
    local levelinf
    local infos = scenetree.findClassObjects('LevelInfo')
    for i,v in pairs(infos) do
      local info = scenetree.findObject(v)
      if info.hidden ~= true then
        levelinf = info
      end
    end
    if levelinf then
      log('I', logTag, 'Adding theLevelInfo overrides' )
      local changed = false
      local fogDensity, fogHeight = convertFog(currentPreset.fogDensity, currentPreset.atmoshpereHeight)
      if currentPreset.fogOffset then
        levelinf.fogDensityOffset = currentPreset.fogOffset
        changed = true
      else
        log('W', logTag, 'Missing fogOffset' )
      end
      if currentPreset.fogDensity then
        levelinf.fogDensity = fogDensity
        changed = true
      else
        log('W', logTag, 'Missing fogDensity' )
      end
      if currentPreset.atmoshpereHeight then
        levelinf.fogAtmosphereHeight = fogHeight
        changed = true
      else
        log('W', logTag, 'Missing atmoshpereHeight' )
      end
      if changed == true then
        levelinf:postApply()
      end
    end
    local skydir = "sky_gradients/"
    if currentPreset.name and currentPreset.directory then
      log('I', logTag, 'Checking color ramps' )
      if currentPreset.sunScale then
        sunsky.sunScaleGradientFile = currentPreset.directory..skydir..currentPreset.name.."/"..currentPreset.sunScale
      else
        log('W', logTag, 'Missing sunScale ramp' )
      end
      if currentPreset.ambientScale then
        sunsky.ambientScaleGradientFile = currentPreset.directory..skydir..currentPreset.name.."/"..currentPreset.ambientScale
      else
        log('W', logTag, 'Missing ambientScale ramp' )
      end
      if currentPreset.fogScale then
        sunsky.fogScaleGradientFile = currentPreset.directory..skydir..currentPreset.name.."/"..currentPreset.fogScale
      else
        log('W', logTag, 'Missing fogScale ramp' )
      end
    end
    setSunsky(currentPreset)
    if currentPreset.azimuth and currentPreset.axis then
      log('I', logTag, 'Adding azimuth and axis overrides' )
      tod.azimuthOverride = currentPreset.azimuth
      tod.axisTilt = currentPreset.axis
      tod:postApply()
      setLegacySun(currentPreset.azimuth)
    else
      log('W', logTag, 'Missing azimuth or axis data' )
      setLegacySun(nil)
    end
    setLegacyExposure(currentPreset)
    local presetTime = currentPreset.overrideTod or (tod and tod.time)
    if currentPreset.overrideTod and tod then
      tod.time = currentPreset.overrideTod
      applyTimeOfDay(tod)
    end
    setSunTint(currentPreset, currentPreset.azimuth and presetTime and legacyElevation(presetTime) or nil)
    local cloudLayers = scenetree.findClassObjects('CloudLayer')
    for i,v in pairs(cloudLayers) do
      local cloudLayer = scenetree.findObject(v)
      if cloudLayer.hidden ~= true then
        cloudLayer.hidden = true
      end
    end
    local lightmgr = tostring(getConsoleVar("$pref::lightManager"))
    if lightmgr == "Advanced Lighting 1.5" and allowUltra == true or lightmgr == "Advanced Lighting 1.5" and settingsTable.profiles[levelname] and settingsTable.profiles[levelname].allowUltra == true then
      local materials = scenetree.findClassObjects('Material')
      log('I', logTag, 'Enabling dynamicCubemap' )
      for i,v in pairs(materials) do
        local mat = scenetree.findObject(v)
        if mat and mat.cubemap ~= "" and mat.dynamicCubemap == nil and mat.___type == "class<Material>" and mat.materialTag0 ~= 'Skies' and mat.materialTag2 ~= 'Skies' and mat.materialTag1 ~= 'Skies' and mat.materialTag0 ~= 'BNG_sky' and mat.materialTag2 ~= 'BNG_sky' and mat.materialTag1 ~= 'BNG_sky' then
          mat:setField("dynamicCubemap", 0, "false")
          mat:setField("cubemap", 0, "")
          mat:setField("dynamicCubemap", 0, "true")
          mat:flush()
          mat:reload()
        end
      end
    end
    if currentPreset.weather and currentPreset.weather.enabled and currentPreset.weather.enabled == true then
      onAddWeatherComponents()
      if weatherTable and selectedWeather and weatherTable[selectedWeather[0]+1] then
        setTargetWeather(selectedWeather[0]+1)
      end
    else
      if rainSfx and rainVfx and thndrLight and thndrShape and sunsky then
        setDefaultWeather(levelinf)
      end
    end
    else
      log('W', logTag, 'There is no time of day' )
    end
  else
    log('W', logTag, 'There is no time of day' )
  end
end

local function readLevelData(levelname)
  if tableIsEmpty(loadedLevel) then
    loadedLevel = {}
    log('I', logTag, 'Read level data' )
    loadedLevel["levelname"] = levelname
    loadedLevel["version"] = tool_version
    local filenames = FS:findFiles(levelfolder.."/main/", "*.json", -1, true, false)
    local hashstring = ""
    for _, filename in ipairs(filenames) do
      local hash = FS:hashFileSHA1(filename)
      hashstring = hashstring .. "-" .. hash
    end
    loadedLevel["hash"] = loadedLevel["levelname"] .. hashstring
    local skyBoxes = scenetree.findClassObjects('SkyBox')
    for i,v in pairs(skyBoxes) do
      local skyBox = scenetree.findObject(v)
      if skyBox.hidden ~= true then
        loadedLevel["skyMat"] = skyBox.Material
      end
    end
    local times = scenetree.findClassObjects('TimeOfDay')
    for i,v in pairs(times) do
      local time = scenetree.findObject(v)
      if time.hidden ~= true then
        loadedLevel["azimuthOverride"] = time.azimuthOverride
        loadedLevel["axisTilt"] = time.axisTilt
      end
    end
    local skies = scenetree.findClassObjects('ScatterSky')
    for i,v in pairs(skies) do
      local sky = scenetree.findObject(v)
      if sky.hidden ~= true then
        loadedLevel["sunScaleGradientFile"] = sky.sunScaleGradientFile
        loadedLevel["ambientScaleGradientFile"] = sky.ambientScaleGradientFile
        loadedLevel["fogScaleGradientFile"] = sky.fogScaleGradientFile
        loadedLevel["sunSize"] = sky.sunSize
        loadedLevel["exposure"] = sky.exposure
        loadedLevel["skyBrightness"] = sky.skyBrightness
        loadedLevel["flareScale"] = sky.flareScale
        loadedLevel["brightness"] = sky.brightness
        loadedLevel["rayleighScattering"] = sky.rayleighScattering
        loadedLevel["texSize"] = sky.texSize
        loadedLevel["shadowDistance"] = sky.shadowDistance
        loadedLevel["shadowSoftness"] = sky.shadowSoftness
        loadedLevel["logWeight"] = sky.logWeight
        loadedLevel["groundAlbedo"] = sky:getField('groundAlbedo', 0)
      end
    end
    local infos = scenetree.findClassObjects('LevelInfo')
    for i,v in pairs(infos) do
      local info = scenetree.findObject(v)
      if info.hidden ~= true then
        loadedLevel["fogDensityOffset"] = info.fogDensityOffset
        loadedLevel["fogDensity"] = info.fogDensity
        loadedLevel["fogAtmosphereHeight"] = info.fogAtmosphereHeight
        loadedLevel["globalEnviromentMap"] = info:getField('globalEnviromentMap',0)
      end
    end
    local cloudLayers = scenetree.findClassObjects('CloudLayer')
    for i,v in pairs(cloudLayers) do
      local cloudLayer = scenetree.findObject(v)
      if cloudLayer.hidden ~= true then
        loadedLevel["cloudLayer"] = false
      end
    end
    local materials = scenetree.findClassObjects('Material')
    loadedLevel["materials"] = {}
    --loadedLevel["weatherMaterials"] = {}
    for i,v in pairs(materials) do
      local mat = scenetree.findObject(v)
      if mat and mat.cubemap ~= "" and mat.dynamicCubemap == nil and mat.___type == "class<Material>"then
        loadedLevel["materials"][v] = {}
        loadedLevel["materials"][v].cubemap = mat.cubemap
      end
      --[[if mat and mat.roughnessFactor and mat.roughnessFactor >= 0.5 then
        loadedLevel["weatherMaterials"][v] = {}
        loadedLevel["weatherMaterials"][v].roughnessFactor = mat.roughnessFactor
      end]]--
    end
    local oceans = scenetree.findClassObjects('WaterPlane')
    loadedLevel["WaterPlane"] = {}
    for i,v in pairs(oceans) do
      local ocean = scenetree.findObject(v)
      if ocean and ocean.cubemap ~= "" then
        loadedLevel["WaterPlane"][v] = {}
        loadedLevel["WaterPlane"][v].cubemap = ocean.cubemap
        loadedLevel["WaterPlane"][v].fullReflect = ocean.fullReflect
        loadedLevel["WaterPlane"][v].reflectivity = ocean.reflectivity
        loadedLevel["WaterPlane"][v].reflectPriority = ocean.reflectPriority
        loadedLevel["WaterPlane"][v].reflectMaxRateMs = ocean.reflectMaxRateMs
        loadedLevel["WaterPlane"][v].reflectDetailAdjust = ocean.reflectDetailAdjust
        loadedLevel["WaterPlane"][v].reflectNormalUp = ocean.reflectNormalUp
        loadedLevel["WaterPlane"][v].useOcclusionQuery = ocean.useOcclusionQuery
        loadedLevel["WaterPlane"][v].reflectTexSize = ocean.reflectTexSize
      end
    end
    local rivers = scenetree.findClassObjects('River')
    loadedLevel["River"] = {}
    for i,v in pairs(rivers) do
      local river = scenetree.findObject(v)
      if river and river.cubemap ~= "" then
        loadedLevel["River"][v] = {}
        loadedLevel["River"][v].cubemap = river.cubemap
        loadedLevel["River"][v].fullReflect = river.fullReflect
        loadedLevel["River"][v].reflectivity = river.reflectivity
        loadedLevel["River"][v].reflectPriority = river.reflectPriority
        loadedLevel["River"][v].reflectMaxRateMs = river.reflectMaxRateMs
        loadedLevel["River"][v].reflectDetailAdjust = river.reflectDetailAdjust
        loadedLevel["River"][v].reflectNormalUp = river.reflectNormalUp
        loadedLevel["River"][v].useOcclusionQuery = river.useOcclusionQuery
        loadedLevel["River"][v].reflectTexSize = river.reflectTexSize
      end
    end
    local waterblocks = scenetree.findClassObjects('WaterBlock')
    loadedLevel["WaterBlock"] = {}
    for i,v in pairs(waterblocks) do
      local waterblock = scenetree.findObject(v)
      if waterblock and waterblock.cubemap ~= "" then
        loadedLevel["WaterBlock"][v] = {}
        loadedLevel["WaterBlock"][v].cubemap = waterblock.cubemap
        loadedLevel["WaterBlock"][v].fullReflect = waterblock.fullReflect
        loadedLevel["WaterBlock"][v].reflectivity = waterblock.reflectivity
        loadedLevel["WaterBlock"][v].reflectPriority = waterblock.reflectPriority
        loadedLevel["WaterBlock"][v].reflectMaxRateMs = waterblock.reflectMaxRateMs
        loadedLevel["WaterBlock"][v].reflectDetailAdjust = waterblock.reflectDetailAdjust
        loadedLevel["WaterBlock"][v].reflectNormalUp = waterblock.reflectNormalUp
        loadedLevel["WaterBlock"][v].useOcclusionQuery = waterblock.useOcclusionQuery
        loadedLevel["WaterBlock"][v].reflectTexSize = waterblock.reflectTexSize
      end
    end
    local res = jsonWriteFile('/temp' ..levelfolder.. 'main.skyleveldata.json', loadedLevel, true)
    if not res then
      log('W', logTag, "unable to save Loaded level data")
    else
      log('I', logTag, "Saved Loaded level data in /temp" .. levelfolder .. "main.skyleveldata.json")
    end
  end
  --dump(loadedLevel)
end

local function enableFancyWater()
  log('I', logTag, 'enableFancyWater' )
  if pauseExecution == false then
    local oceans = scenetree.findClassObjects('WaterPlane')
    for i,v in pairs(oceans) do
      local ocean = scenetree.findObject(v)
      if ocean then
        if allowUltra and allowUltra == true and fancyWater and fancyWater == true then
          ocean:setField('reflectPriority', 0, '-1')
          ocean:setField('reflectMaxRateMs', 0, '-1')
          ocean:setField('reflectNormalUp', 0, 'false')
          ocean:setField('useOcclusionQuery', 0, 'true')
          ocean:setField('fullReflect', 0, tostring(fancyWater))
          if waterRes[0] and waterRes[0] == 0 then
            ocean:setField('reflectDetailAdjust', 0, '-1')
            ocean:setField('reflectTexSize', 0, '128')
          end
          if waterRes[0] and waterRes[0] == 1 then
            ocean:setField('reflectDetailAdjust', 0, '0.1')
            ocean:setField('reflectTexSize', 0, '256')
          end
          if waterRes[0] and waterRes[0] == 2 then
            ocean:setField('reflectDetailAdjust', 0, '0.3')
            ocean:setField('reflectTexSize', 0, '512')
          end
          if waterRes[0] and waterRes[0] == 3 then
            ocean:setField('reflectDetailAdjust', 0, '0.5')
            ocean:setField('reflectTexSize', 0, '1024')
          end
          if waterRes[0] and waterRes[0] == 4 then
            ocean:setField('reflectDetailAdjust', 0, '0.6')
            ocean:setField('reflectTexSize', 0, '2048')
          end
          if waterRes[0] and waterRes[0] == 5 then
            ocean:setField('reflectDetailAdjust', 0, '1')
            ocean:setField('reflectTexSize', 0, '4096')
          end
        end
      end
    end
    local rivers = scenetree.findClassObjects('River')
    for i,v in pairs(rivers) do
      local river = scenetree.findObject(v)
      if river then
        if fancyWater and fancyWater == true then
          river:setField('reflectPriority', 0, '-1')
          river:setField('reflectMaxRateMs', 0, '-1')
          river:setField('reflectNormalUp', 0, 'false')
          river:setField('useOcclusionQuery', 0, 'true')
          river:setField('fullReflect', 0, tostring(fancyWater))
          if waterRes[0] and waterRes[0] == 0 then
            river:setField('reflectDetailAdjust', 0, '-1')
            river:setField('reflectTexSize', 0, '128')
          end
          if waterRes[0] and waterRes[0] == 1 then
            river:setField('reflectDetailAdjust', 0, '0.1')
            river:setField('reflectTexSize', 0, '256')
          end
          if waterRes[0] and waterRes[0] == 2 then
            river:setField('reflectDetailAdjust', 0, '0.3')
            river:setField('reflectTexSize', 0, '512')
          end
          if waterRes[0] and waterRes[0] == 3 then
            river:setField('reflectDetailAdjust', 0, '0.5')
            river:setField('reflectTexSize', 0, '1024')
          end
          if waterRes[0] and waterRes[0] == 4 then
            river:setField('reflectDetailAdjust', 0, '0.6')
            river:setField('reflectTexSize', 0, '2048')
          end
          if waterRes[0] and waterRes[0] == 5 then
            river:setField('reflectDetailAdjust', 0, '1')
            river:setField('reflectTexSize', 0, '4096')
          end
        end
        river:postApply()
      end
    end
    local waterblocks = scenetree.findClassObjects('WaterBlock')
    for i,v in pairs(waterblocks) do
      local waterblock = scenetree.findObject(v)
      if waterblock then
        if fancyWater and fancyWater == true then
          waterblock:setField('reflectPriority', 0, '-1')
          waterblock:setField('reflectMaxRateMs', 0, '-1')
          waterblock:setField('reflectNormalUp', 0, 'false')
          waterblock:setField('useOcclusionQuery', 0, 'true')
          waterblock:setField('fullReflect', 0, tostring(fancyWater))
          if waterRes[0] and waterRes[0] == 0 then
            waterblock:setField('reflectDetailAdjust', 0, '-1')
            waterblock:setField('reflectTexSize', 0, '128')
          end
          if waterRes[0] and waterRes[0] == 1 then
            waterblock:setField('reflectDetailAdjust', 0, '0.1')
            waterblock:setField('reflectTexSize', 0, '256')
          end
          if waterRes[0] and waterRes[0] == 2 then
            waterblock:setField('reflectDetailAdjust', 0, '0.3')
            waterblock:setField('reflectTexSize', 0, '512')
          end
          if waterRes[0] and waterRes[0] == 3 then
            waterblock:setField('reflectDetailAdjust', 0, '0.5')
            waterblock:setField('reflectTexSize', 0, '1024')
          end
          if waterRes[0] and waterRes[0] == 4 then
            waterblock:setField('reflectDetailAdjust', 0, '0.6')
            waterblock:setField('reflectTexSize', 0, '2048')
          end
          if waterRes[0] and waterRes[0] == 5 then
            waterblock:setField('reflectDetailAdjust', 0, '1')
            waterblock:setField('reflectTexSize', 0, '4096')
          end
        end
        waterblock:postApply()
      end
    end
  end
end

local function panicLua()
  settingsTable.profiles[levelname] = {}
  settingsTable.profiles[levelname].autoLoad = false
  settingsSave()
  updateProfiles()
  profileName = levelname
end

local function onClientStartMission()
  log('I', logTag, 'Getting current level path' )
  levelname = getCurrentLevelIdentifier()
  --print(levelname)
  log('I', logTag, 'Level is loaded' )
  levelfolder = ("/levels/" .. levelname .. "/")
  --disable level specific presets for now--
  --[[local sbFiles = FS:findFiles(levelfolder, '*todBox.json', 1, true, false)
  for k,filename in pairs(sbFiles) do
    skyBoxTable[k] = jsonReadFile(filename) or {}
    skyBoxTable[k].fileName = filename
  end]]--
  local tempLevelData = FS:findFiles("/temp" ..levelfolder, '*skyleveldata.json', 1, true, false)
  for k,filename in pairs(tempLevelData) do
    loadedLevel = jsonReadFile(filename) or {}
  end
  if tableIsEmpty(loadedLevel) then
    readLevelData(levelname)
  end
  local filenames = FS:findFiles(levelfolder.."/main/", "*.json", -1, true, false)
  local hashstring = ""
  for _, filename in ipairs(filenames) do
    local hash = FS:hashFileSHA1(filename)
    hashstring = hashstring .. "-" .. hash
  end
  local hashname = levelname .. hashstring
  if hashname ~= loadedLevel["hash"] then log('W', logTag, 'Hash mismatch' ) loadedLevel = {} readLevelData(levelname) end
  if loadedLevel["version"] ~= tool_version then log('W', logTag, 'Version mismatch' ) loadedLevel = {} readLevelData(levelname) end
  if globalEnabled == false then
    selectedPreset[0] = 0
    onSelectedPreset(selectedPreset[0]+1)
  end
  if settingsTable.profiles[levelname] ~= nil and settingsTable.profiles[levelname].defaultPresetName ~= nil then
    for k,v in pairs(skyBoxTable) do
      if skyBoxTable[k].name == settingsTable.profiles[levelname].defaultPresetName then
        selectedPreset[0] = k-1
      end
    end
    onSelectedPreset(selectedPreset[0]+1)
  end
  if FS:fileExists('/levels/'..levelname.."/mainLevel.lua") and settingsTable.profiles[levelname] == nil then
    log('W', logTag, 'Level uses custom LUA, we need to report this to user' )
    pauseExecution = true
    usesLua = 1
    panicLua()
  else
    log('I', logTag, 'Level is ok' )
    if settingsTable.profiles[levelname] ~= nil and settingsTable.profiles[levelname].autoLoad ~= nil then
      if settingsTable.profiles[levelname].autoLoad ~= false then
        log('I', logTag, 'Adding components automatically' )
        pauseExecution = false
        onSelectedPreset(selectedPreset[0]+1)
        onAddComponentsToMission()
      else
        pauseExecution = true
      end
    else
      if selectedPreset and presetAmnt > 0 and autoLoad == true then
      pauseExecution = false
      onSelectedPreset(selectedPreset[0]+1)
      onAddComponentsToMission()
      end
    end
  end
end

local function convertTod(todstr)
  seconds = ((todstr + 0.5) % 1) * 86400
  hours = math.floor(seconds / 3600)
  mins = math.floor(seconds / 60 - (hours * 60))
end

local currentSkybox

local function popUp(name, text, action)
  if im.BeginPopupModal(name, nil, im.WindowFlags_AlwaysAutoResize) then
    im.Text(text)
    im.Separator()
    if im.Button("Yes", im.ImVec2(120,0)) then
      im.CloseCurrentPopup()
      if action == 1 then
        autoLoad = true
        globalEnabled = true
        debugEnabled = false
        settingsSave()
      elseif action == 2 then
        for k,v in pairs(settingsTable.profiles) do
          if k ~= settingsTable.profiles["global"] then
            settingsTable.profiles[k] = nil
          end
        end
        settingsSave()
        updateProfiles()
        selectedProfile[0] = 0
        profileName = settingsProfiles[selectedProfile[0]+1]
      elseif action == 3 then
        settingsTable = {}
        autoLoad = true
        globalEnabled = true
        debugEnabled = false
        settingsSave()
        updateProfiles()
        selectedProfile[0] = 0
        profileName = settingsProfiles[selectedProfile[0]+1]
      elseif action == 4 then
        settingsTable.profiles[profileName] = nil
        settingsSave()
        updateProfiles()
        selectedProfile[0] = 0
        profileName = settingsProfiles[selectedProfile[0]+1]
      end
    end
    im.SameLine()
    if im.Button("No", im.ImVec2(120,0)) then im.CloseCurrentPopup() end
    im.EndPopup()
  end
end

local function levelDataTab()
  if usesLua == 1 then
    im.TextColored(im.ImVec4(1, 1, 0, 1), "This level is using custom lua.\nIt might interfere with Dynamic Skybox.\nIf you want to use Dynamic Skybox anyway,\nenable it in settings by toggling skybox activity")
  end
  if levelname then
    im.Text("Level: ")
    im.SameLine()
    im.Text(levelname)
    if selectedPreset and tod and todBox and presetAmnt > 0 and currentSkybox then
      im.Text("Current Skybox: ")
      im.SameLine()
      im.Text(tostring(currentSkybox[1]))
    end
    if tod and hours and mins then
      im.Text("Time of Day (24): ")
      im.SameLine()
      im.Text(string.format("%02.f", hours) .. ":" .. string.format("%02.f", mins))
      im.Text("Time of Day (tod): ")
      im.SameLine()
      im.Text(string.format("%.2f", tod.time))
      local freezePtr = im.BoolPtr(freezeTime)
      if im.Checkbox("Freeze time (preset time of day)", freezePtr) then
        setFreezeTime(freezePtr[0])
      end
      if not freezeTime then
        im.TextWrapped("Time is free: use the game's Environment menu. The static cubemap was made for the preset's time, clouds may not match the sun.")
      end
    end
    if weatherTable and selectedWeather and weatherTable[selectedWeather[0]+1] then
      if weatherTable[selectedWeather[0]+1].presetName then
        im.Text("Current Weather: ")
        im.SameLine()
        im.Text(weatherTable[selectedWeather[0]+1].presetName)
      end
    end
    if (not todBox and usesLua == 0) and not autoLoad == false and not settingsTable.profiles[levelname].autoLoad == false then
      im.TextColored(im.ImVec4(1, 1, 0, 1), "Level is not compatible with Dynamic Skybox.")
    end
  else
    im.Text("Level not loaded")
  end
end

local function weatherTab()
  if weatherNames and weatherAmnt > 0 then
    im.Text("Weather")
    if im.Combo2("##weathers", selectedWeather, weatherString) then
      setTargetWeather(selectedWeather[0]+1)
    end
  else
    im.Text("Weather presets are missing")
  end
end

local notApplied = true

local isTodBoxVis
local function onEditorOpen()
  log('I', logTag, 'Loading original level data' )
  setLegacySun(nil)
  setLegacyExposure(nil)
  restoreSunTint()
  if todBox then todBox.hidden = true end
  if rainSfx then rainSfx.volume = 0 end
  if rainVfx then rainVfx.numDrops = 0 end
  if thndrLight then thndrLight.hidden = true end
  if thndrShape then thndrShape.hidden = true end
  if levelname and loadedLevel and loadedLevel["levelname"] == levelname then
    local skyBoxes = scenetree.findClassObjects('SkyBox')
    for i,v in pairs(skyBoxes) do
      local skyBox = scenetree.findObject(v)
      if skyBox.hidden ~= true then
        skyBox.Material = loadedLevel["skyMat"]
      end
    end
    local times = scenetree.findClassObjects('TimeOfDay')
    for i,v in pairs(times) do
      local time = scenetree.findObject(v)
      if time.hidden ~= true then
        time.azimuthOverride = loadedLevel["azimuthOverride"]
        time.axisTilt = loadedLevel["axisTilt"]
      end
    end
    local skies = scenetree.findClassObjects('ScatterSky')
    for i,v in pairs(skies) do
      local sky = scenetree.findObject(v)
      if sky.hidden ~= true then
        sky.sunScaleGradientFile = loadedLevel["sunScaleGradientFile"]
        sky.ambientScaleGradientFile = loadedLevel["ambientScaleGradientFile"]
        sky.fogScaleGradientFile = loadedLevel["fogScaleGradientFile"]
        sky.sunSize = loadedLevel["sunSize"]
        sky.exposure = loadedLevel["exposure"]
        sky.skyBrightness = loadedLevel["skyBrightness"]
        if loadedLevel["flareScale"] then sky.flareScale = loadedLevel["flareScale"] end
        sky.brightness = loadedLevel["brightness"]
        sky.rayleighScattering = loadedLevel["rayleighScattering"]
        sky.texSize = loadedLevel["texSize"]
        sky.shadowDistance = loadedLevel["shadowDistance"]
        sky.shadowSoftness = loadedLevel["shadowSoftness"]
        sky.rayleighScattering = loadedLevel["rayleighScattering"]
        sky.logWeight = loadedLevel["logWeight"]
        if loadedLevel["groundAlbedo"] then sky:setField('groundAlbedo', 0, loadedLevel["groundAlbedo"]) end
      end
    end
    local infos = scenetree.findClassObjects('LevelInfo')
    for i,v in pairs(infos) do
      local info = scenetree.findObject(v)
      if info.hidden ~= true then
        info.fogDensityOffset = loadedLevel["fogDensityOffset"]
        info.fogDensity = loadedLevel["fogDensity"]
        info.fogAtmosphereHeight = loadedLevel["fogAtmosphereHeight"]
        setCubemap(loadedLevel["globalEnviromentMap"])
      end
    end
    local cloudLayers = scenetree.findClassObjects('CloudLayer')
    for i,v in pairs(cloudLayers) do
      local cloudLayer = scenetree.findObject(v)
      if cloudLayer.hidden == true then
        cloudLayer.hidden = loadedLevel["cloudLayer"]
      end
    end
    local lightmgr = tostring(getConsoleVar("$pref::lightManager"))
    for i,v in pairs(loadedLevel["materials"]) do
      local mat = scenetree.findObject(i)
      if mat then
        mat:setField("cubemap", 0, loadedLevel["materials"][i].cubemap)
        mat:setField("dynamicCubemap", 0, "false")
        mat:flush()
        mat:reload()
      end
    end
    --[[for i,v in pairs(loadedLevel["weatherMaterials"]) do
      local mat = scenetree.findObject(i)
      if mat and mat.version and mat.version == 1.5 then
        mat:setField("roughnessFactor", 0, loadedLevel["weatherMaterials"][i].roughnessFactor)
        mat:flush()
        mat:reload()
      end
    end]]--
    for i,v in pairs(loadedLevel["WaterPlane"]) do
      local ocean = scenetree.findObject(i)
      if ocean then
        ocean:setField('cubemap', 0, loadedLevel["WaterPlane"][i].cubemap)
        ocean:setField('reflectPriority', 0, tostring(loadedLevel["WaterPlane"][i].reflectPriority))
        ocean:setField('reflectMaxRateMs', 0, tostring(loadedLevel["WaterPlane"][i].reflectMaxRateMs))
        ocean:setField('reflectDetailAdjust', 0, tostring(loadedLevel["WaterPlane"][i].reflectDetailAdjust))
        ocean:setField('reflectNormalUp', 0, tostring(loadedLevel["WaterPlane"][i].reflectNormalUp))
        ocean:setField('useOcclusionQuery', 0, tostring(loadedLevel["WaterPlane"][i].useOcclusionQuery))
        ocean:setField('fullReflect', 0, tostring(loadedLevel["WaterPlane"][i].fullReflect))
        ocean:setField('reflectTexSize', 0, tostring(loadedLevel["WaterPlane"][i].fullReflect))
        if ocean.reloadTextures then ocean:reloadTextures() end
      end
    end
    for i,v in pairs(loadedLevel["River"]) do
      local river = scenetree.findObject(i)
      if river then
        river:setField('cubemap', 0, loadedLevel["River"][i].cubemap)
        river:setField('reflectPriority', 0, tostring(loadedLevel["River"][i].reflectPriority))
        river:setField('reflectMaxRateMs', 0, tostring(loadedLevel["River"][i].reflectMaxRateMs))
        river:setField('reflectDetailAdjust', 0, tostring(loadedLevel["River"][i].reflectDetailAdjust))
        river:setField('reflectNormalUp', 0, tostring(loadedLevel["River"][i].reflectNormalUp))
        river:setField('useOcclusionQuery', 0, tostring(loadedLevel["River"][i].useOcclusionQuery))
        river:setField('fullReflect', 0, tostring(loadedLevel["River"][i].fullReflect))
        river:setField('reflectTexSize', 0, tostring(loadedLevel["River"][i].fullReflect))
        if river.reloadTextures then river:reloadTextures() end
        river:postApply()
      end
    end
    for i,v in pairs(loadedLevel["WaterBlock"]) do
      local waterblock = scenetree.findObject(i)
      if waterblock then
        waterblock:setField('cubemap', 0, loadedLevel["WaterBlock"][i].cubemap)
        waterblock:setField('cubemap', 0, loadedLevel["WaterBlock"][i].cubemap)
        waterblock:setField('reflectPriority', 0, tostring(loadedLevel["WaterBlock"][i].reflectPriority))
        waterblock:setField('reflectMaxRateMs', 0, tostring(loadedLevel["WaterBlock"][i].reflectMaxRateMs))
        waterblock:setField('reflectDetailAdjust', 0, tostring(loadedLevel["WaterBlock"][i].reflectDetailAdjust))
        waterblock:setField('reflectNormalUp', 0, tostring(loadedLevel["WaterBlock"][i].reflectNormalUp))
        waterblock:setField('useOcclusionQuery', 0, tostring(loadedLevel["WaterBlock"][i].useOcclusionQuery))
        waterblock:setField('fullReflect', 0, tostring(loadedLevel["WaterBlock"][i].fullReflect))
        waterblock:setField('reflectTexSize', 0, tostring(loadedLevel["WaterBlock"][i].fullReflect))
        if waterblock.reloadTextures then waterblock:reloadTextures() end
        waterblock:postApply()
      end
    end
    applyTimeOfDay(tod)
    notApplied = true
  end
end

local function onSettingsChanged()
  log('I', logTag, 'onSettingsChanged' )
  if todBox and pauseExecution == false then
    if pauseExecution == false then
      log('I', logTag, 'Pausing execution' )
      isTodBoxVis = todBox.hidden
      pauseExecution = true
      onEditorOpen()
    end
    if pauseExecution == true and usesLua == 0 then
      notApplied = true
      log('I', logTag, 'Resuming execution' )
      onAddComponentsToMission()
      todBox.hidden = isTodBoxVis
      pauseExecution = false
      applyTimeOfDay(tod)
    end
  end
end

local function generateGenericCubemap(job, startTime, currentPreset, globalRef, material)
  local tod = nil
  local times = scenetree.findClassObjects('TimeOfDay')
  for i,v in pairs(times) do
    local time = scenetree.findObject(v)
    if time.hidden ~= true then
      tod = time
    end
  end
  if tod then
    for k,v in pairs(startTime) do
      local calculatedTod = ((v/86400)-0.5)
      tod.time = calculatedTod
      applyTimeOfDay(tod)
      job.sleep(1)
      captureCameraCubemap(currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection')
      local f = io.open(currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/main.materials.json', "w")
      f:write('{', '\n')
      f:write('  "'..globalRef[k]..'_reflection" : {', '\n')
      f:write('    "name" : "'..globalRef[k]..'_reflection",', '\n')
      f:write('    "class" : "CubemapData",', '\n')
      f:write('    "cubeFace" : [', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection0.hdr.dds",', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection1.hdr.dds",', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection2.hdr.dds",', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection3.hdr.dds",', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection4.hdr.dds",', '\n')
      f:write('      "'..currentPreset.directory..'cubemaps/'..currentPreset.name..'_reflection/'..globalRef[k]..'_reflection/cubemap/reflection5.hdr.dds"', '\n')
      f:write('    ]', '\n')
      f:write('  },', '\n')
      f:write('  "'..material[k]..'_reflection" : {', '\n')
      f:write('    "name" : "'..material[k]..'_reflection",', '\n')
      f:write('    "mapTo" : "unmapped_mat",', '\n')
      f:write('    "class" : "Material",', '\n')
      f:write('    "Stages" : [ {}, {}, {}, {} ],', '\n')
      f:write('    "cubemap" : "'..globalRef[k]..'_reflection",', '\n')
      f:write('    "materialTag0" : "Skies",', '\n')
      f:write('    "materialTag1" : "car_killer",', '\n')
      f:write('    "materialTag2" : "BNG_sky"', '\n')
      f:write('  }', '\n')
      f:write('}')
      f:close()
    end
  end
end

local thndrcnt = 0
local delay = 0
local isPlayedA = false
local isPlayedB = false
local isPlayedC = false
local isPlayedD = false
local realTime = 0
local rndcont = 0

local randomoffset1 = math.random(-3000, 3000)
local randomoffset2 = math.random(-3000, 3000)
local randomoffset3 = math.random(150, 300)

local function onWeatherThunder(dtSim, dtReal)
  local paused = dtSim < 0.00001
  if not paused then
    local playerWPos
    realTime = realTime + dtReal
    thndrcnt = thndrcnt + dtSim
    if realTime >= 5 then
      rndcont = math.random(5, 60)
      if math.random(1, 8) == 4 then
        randomoffset1 = math.random(-500, 500)
        randomoffset2 = math.random(-500, 500)
        randomoffset3 = math.random(1, 200)
      else
        randomoffset1 = math.random(-3000, 3000)
        randomoffset2 = math.random(-3000, 3000)
        randomoffset3 = math.random(1, 200)
      end
      realTime = 0
    end
    if thndrcnt >= rndcont then
      local veh = be:getPlayerVehicle(0)
      local sounddelay = 0
      local dir = '/art/cktodbox/thndrSound/'
      local sndTable = {dir.."Thunder_a.mp3",dir.."thunder_b.mp3",dir.."thunder_c.mp3",dir.."thunder_d.mp3"}
      if veh then
        playerWPos = vec3(veh:getPosition())
      else
        playerWPos = vec3(core_camera.getPosition())
      end
      local oldplayerPos = playerWPos
      playerWPos = playerWPos + vec3(randomoffset1, randomoffset2, randomoffset3)
      sounddelay = (oldplayerPos - playerWPos):length()
      sounddelay = sounddelay / 331 --sound speed in m/s
      if sounddelay < 0 then sounddelay = -sounddelay end
      thndrShape:setPosition(playerWPos)
      thndrLight.radius = scenetree.theLevelInfo.visibleDistance / 2
      thndrLight:setPosition(playerWPos)
      if isPlayedA ~= true and randomoffset2 then
        thndrLight.hidden = false
        thndrShape.hidden = false
        isPlayedA = true
        delay = 0
      end
      if delay >= math.random(0.05, 0.3) and isPlayedA == true and isPlayedB ~= true then
        thndrLight.hidden = true
        thndrShape.hidden = true
        delay = 0
        isPlayedB = true
      end
      if delay >= math.random(0.05, 0.1) and isPlayedB == true and isPlayedC ~= true then
        thndrLight.hidden = false
        thndrShape.hidden = false
        delay = 0
        isPlayedC = true
      end
      if delay >= math.random(0.05, 0.3) and isPlayedC == true and isPlayedD ~= true then
        thndrLight.hidden = true
        thndrShape.hidden = true
        delay = 0
        isPlayedD = true
      end
      if delay >= sounddelay and isPlayedC == true then
        Engine.Audio.playOnce('AudioEnvironment', sndTable[math.random(1, 4)])
        thndrcnt = 0
        delay = 0
        isPlayedA = false
        isPlayedB = false
        isPlayedC = false
        isPlayedD = false
      end
    end
  end
end

local function settingsTab()
  if settingsProfiles and profilesAmnt > 0 then
    im.Text("Profiles")
    if im.Combo2("##profiles", selectedProfile, profilesString) then
      profileName = settingsProfiles[selectedProfile[0]+1]
    end
    if levelname and not settingsTable.profiles[levelname] then
      im.SameLine()
      local fsize = 24
      if gui.uiIconImageButton(gui.icons.add,{x=fsize, y=fsize}, iconButtonFgColor.Value, nil, iconButtonBgColor.Value) then
        settingsTable.profiles[levelname] = {}
        settingsSave()
        updateProfiles()
        profileName = levelname
      end
    end
    if profileName and profileName ~= "global" then
      local fsize = 24
      im.SameLine()
      popUp("Remove selected profile", "Do you really want to remove "..profileName.." profile??\nThis operation is not reversible.\n", 4)
      if gui.uiIconImageButton(gui.icons.remove,{x=fsize, y=fsize}, iconButtonFgColor.Value, nil, iconButtonBgColor.Value) then
        im.OpenPopup("Remove selected profile")
      end
    end
  else
    im.Text("Profiles are missing")
  end
  if profileName == "global" then
    local autoLoadEnabled = im.BoolPtr(autoLoad)
    if im.Checkbox("Automatically Load Presets", autoLoadEnabled) then
      autoLoad = autoLoadEnabled[0]
      settingsSave()
    end
    im.Separator()
    local allowUltraEnabled = im.BoolPtr(allowUltra)
    if im.Checkbox("Use Ultra features", allowUltraEnabled) then
      allowUltra = allowUltraEnabled[0]
      settingsSave()
      onSettingsChanged()
    end
    if allowUltra == true then
      local fancyWaterEnabled = im.BoolPtr(fancyWater)
      if im.Checkbox("Use Fancy Water", fancyWaterEnabled) then
        fancyWater = fancyWaterEnabled[0]
        settingsSave()
        onSettingsChanged()
        if fancyWater and fancyWater == true then
          enableFancyWater()
        end
      end
      if fancyWater == true then
        im.Text("Water Reflection Quality")
        im.PushItemWidth(160)
        if im.Combo2("##WaterRes", waterRes, waterResString) then
          settingsSave()
          enableFancyWater()
        end
        im.PopItemWidth()
      end
    end
    im.Separator()
    local globalEnabledB = im.BoolPtr(globalEnabled)
    if im.Checkbox("Use current Skybox globally", globalEnabledB) then
      globalEnabled = globalEnabledB[0]
      settingsSave()
    end
    im.Separator()
  elseif profileName then
    local autoLoad
    if settingsTable.profiles[profileName] and not settingsTable.profiles[profileName].autoLoad then
      autoLoad = true
    end
    if settingsTable.profiles[profileName] and settingsTable.profiles[profileName].autoLoad == true then
      autoLoad = true
    elseif settingsTable.profiles[profileName] and settingsTable.profiles[profileName].autoLoad == false then
      autoLoad = false
    end
    local autoLoadEnabled = im.BoolPtr(autoLoad)
    if im.Checkbox("Automatically Load Preset", autoLoadEnabled) then
      settingsTable.profiles[profileName].autoLoad = autoLoadEnabled[0]
      settingsSave()
      if usesLua == 1 and settingsTable.profiles[profileName].autoLoad == true then
        usesLua = 0
      end
    end
    im.Separator()
    local allowUltra
    if settingsTable.profiles[profileName] and not settingsTable.profiles[profileName].allowUltra then
      allowUltra = true
    end
    if settingsTable.profiles[profileName] and settingsTable.profiles[profileName].allowUltra == true then
      allowUltra = true
    elseif settingsTable.profiles[profileName] and settingsTable.profiles[profileName].allowUltra == false then
      allowUltra = false
    end
    local allowUltraEnabled = im.BoolPtr(allowUltra)
    if im.Checkbox("Use Ultra features", allowUltraEnabled) then
      settingsTable.profiles[profileName].allowUltra = allowUltraEnabled[0]
      settingsSave()
    end
    im.Separator()
    local currentPresetDef
    if settingsTable.profiles[profileName] and settingsTable.profiles[profileName].defaultPresetName and settingsTable.profiles[profileName].defaultPresetName ~= nil then
      currentPresetDef = true
    else
      currentPresetDef = false
    end
    local presetEnabled = im.BoolPtr(currentPresetDef)
    if im.Checkbox("Save current sky preset as default", presetEnabled) then
      currentPresetDef = presetEnabled[0]
      if currentPresetDef == true then
        settingsTable.profiles[profileName].defaultPresetName = currentPreset.name
      else
        settingsTable.profiles[profileName].defaultPresetName = nil
      end
      settingsSave()
    end
    im.Separator()
  end
  popUp("Reset global profile", "Do you really want to reset global profile??\nThis operation is not reversible.\n", 1)
  if im.Button("Reset global profile") then
    im.OpenPopup("Reset global profile")
  end
  im.SameLine()
  popUp("Reset all level profiles", "Do you really want to reset all level profiles??\nThis operation is not reversible.\n", 2)
  if im.Button("Reset level profiles") then
    im.OpenPopup("Reset all level profiles")
  end
  im.Separator()
  im.Text("Settings")
  local debugEnabledB = im.BoolPtr(debugEnabled)
  if im.Checkbox("Show advanced debug features", debugEnabledB) then
    debugEnabled = debugEnabledB[0]
    settingsSave()
  end
  im.Separator()
  popUp("Reset all settings", "Do you really want to reset all settings??\nThis operation is not reversible.\n", 3)
  if im.Button("Reset all") then
    im.OpenPopup("Reset all settings")
  end
  im.SameLine()
  if im.Button("Toggle skybox activity") then
    if pauseExecution == false then
      log('I', logTag, 'Pausing execution' )
      onEditorOpen()
      if todBox then isTodBoxVis = todBox.hidden end
      if todBox then pauseExecution = true end
    elseif pauseExecution == true then
      log('I', logTag, 'Resuming execution' )
      onAddComponentsToMission()
      if todBox then todBox.hidden = isTodBoxVis end
      if todBox then
        pauseExecution = false
        applyTimeOfDay(tod)
      end
      if usesLua == 1 then usesLua = 0 end
    end
  end
  im.SameLine()
  if im.Button("Reset cache") then
    if todBox and pauseExecution == false then
      log('I', logTag, 'Pausing execution' )
      isTodBoxVis = todBox.hidden
      pauseExecution = true
      onEditorOpen()
    end
    local cacheFiles = FS:findFiles('/temp/levels/', "*skyleveldata.json", -1, true, false)
    log('D', logTag, dumps(cacheFiles))
    for _, fn in ipairs(cacheFiles) do
      local rem = FS:removeFile(fn)
      if rem == 0 then log('I', logTag, 'Removed: '..fn ) else log('E', logTag, 'Could not remove '..fn ) end
    end
  end
end

local function presetEditorTab()
  im.Text("Coming soon")
  im.Separator()
end

local function debugTab()
  if im.Button("Generate Generic Cubemaps") then
    core_jobsystem.create(generateGenericCubemap, 1, startTime, currentPreset, globalRef, material)
  end
  im.Separator()
end

local function drawImgui()
  if not showUI[0] then
    return
   end

  im.Begin(appTitle, showUI, im.WindowFlags_AlwaysAutoResize+im.WindowFlags_NoResize+im.WindowFlags_NoDocking)

  if presetNames and presetAmnt > 0 then
    im.Text("Loaded skies presets: ")
    im.SameLine()
    im.Text(tostring(presetAmnt))
    if im.Combo2("##Selected Preset", selectedPreset, presetString) then
      --print(selectedPreset[0]+1)
      onSelectedPreset(selectedPreset[0]+1)
      onAddComponentsToMission()
      settingsSave()
    end
  else
    im.Text("Presets are missing")
  end
  if im.BeginTabBar("tabs") then
    if im.BeginTabItem("Current Info", nil, im.TabItemFlags_None) then
      levelDataTab()
      im.EndTabItem()
    end
    if currentPreset.weather and currentPreset.weather.enabled and currentPreset.weather.enabled == true then
      if im.BeginTabItem("Weather", nil, im.TabItemFlags_None) then
        weatherTab()
        im.EndTabItem()
      end
    end
    if im.BeginTabItem("Settings", nil, im.TabItemFlags_None) then
      settingsTab()
      im.EndTabItem()
    end
    if debugEnabled == true then
      if im.BeginTabItem("Preset Editor", nil, im.TabItemFlags_None) then
        presetEditorTab()
        im.EndTabItem()
      end
      if im.BeginTabItem("Debug", nil, im.TabItemFlags_None) then
        debugTab()
        im.EndTabItem()
      end
    end
    im.EndTabBar()
  end
  im.End()
end

local function setWaterReflection(cubemapname)
  log('I', logTag, 'Setting up water static reflection' )
  if cubemapname then
    local oceans = scenetree.findClassObjects('WaterPlane')
    for i,v in pairs(oceans) do
      local ocean = scenetree.findObject(v)
      if ocean then
        ocean:setField('cubemap', 0, cubemapname)
        if ocean.reloadTextures then ocean:reloadTextures() end
      end
    end
    local rivers = scenetree.findClassObjects('River')
    for i,v in pairs(rivers) do
      local river = scenetree.findObject(v)
      if river then
        river:setField('cubemap', 0, cubemapname)
        if river.reloadTextures then river:reloadTextures() end
        river:postApply()
      end
    end
    local waterblocks = scenetree.findClassObjects('WaterBlock')
    for i,v in pairs(waterblocks) do
      local waterblock = scenetree.findObject(v)
      if waterblock then
        waterblock:setField('cubemap', 0, cubemapname)
        if waterblock.reloadTextures then waterblock:reloadTextures() end
        waterblock:postApply()
      end
    end
  end
end

local function setSkyBox(mat, cubemap)
  log('I', logTag, 'Preset selected, loading data' )
  if cubemap ~= nil and (lightmgr == "Advanced Lighting 1.5" and allowUltra == true or lightmgr == "Advanced Lighting 1.5" and settingsTable.profiles[levelname] and settingsTable.profiles[levelname].allowUltra == true) then
    setCubemap(cubemap)
    setWaterReflection(cubemap)
    enableFancyWater()
  end
  todBox.Material = mat
  todBox:postApply()
  applyTimeOfDay(tod)
end

local lastTod = 0
local lastPreset = ""

local function onPreRender()
  if not tod then getTod() end
  if tod and tod.time and tod.time ~= lastTod and pauseExecution == false then notApplied = true end
  if currentPreset and currentPreset.name ~= lastPreset then notApplied = true end
  if currentSkybox and todBox and pauseExecution == false and currentSkybox[1] ~= todBox.Material then notApplied = true end
  if notApplied == true then
    if currentPreset and currentPreset.name then lastPreset = currentPreset.name end
    if tod and tod.time then lastTod = tod.time end
    if selectedPreset and tod and todBox and pauseExecution == false and presetAmnt > 0 then
      if currentPreset.isStatic or currentPreset.isStatic == true then
        if todBox.Material ~= material[1] then
          if currentPreset.supportGenericCubemap and currentPreset.supportGenericCubemap == true then
            setSkyBox(material[1], genericCubemap[1])
            currentSkybox = {material[1], genericCubemap[1]}
          else
            setSkyBox(material[1], globalRef[1])
            currentSkybox = {material[1], globalRef[1]}
          end
          notApplied = false
        else
          notApplied = false
        end
        --the static cubemap is a daylight sky; with the time released it would stay lit, and light the scene, all night
        local t = tod.time % 1
        todBox.hidden = not freezeTime and currentPreset.supportNight ~= true and t >= 0.25 and t <= 0.75
        todBox:postApply()
      else
        for k,v in pairs(startTime) do
          local todCalc = ((tod.time + 0.5) % 1) * 86400
          if todCalc >= v and todCalc < endTime[k] then
            --print(material[k])
            if todBox.Material ~= material[k] then
              if currentPreset.supportGenericCubemap and currentPreset.supportGenericCubemap == true then
                setSkyBox(material[k], genericCubemap[k])
                currentSkybox = {material[k], genericCubemap[k]}
              else
                setSkyBox(material[k], globalRef[k])
                currentSkybox = {material[k], globalRef[k]}
              end
              notApplied = false
            else
              notApplied = false
            end
          end
          if not currentPreset.supportNight or currentPreset.supportNight ~= true then
            if tod.time >= 0.25 and tod.time <= 0.75 then
              todBox.hidden = true
              todBox:postApply()
            else
              todBox.hidden = false
              todBox:postApply()
            end
          else
            todBox.hidden = false
            todBox:postApply()
          end
        end
      end
    end
  end
  if freezeTime and tod and tod.time and currentPreset and currentPreset.overrideTod and pauseExecution == false then
    --tod.time is a float32, an exact compare would re-apply the time every frame
    if math.abs(tod.time - currentPreset.overrideTod) > 1e-5 then
      tod.time = currentPreset.overrideTod
      applyTimeOfDay(tod)
    end
  end
  if pauseExecution == false then
    --the game settings can reset the exposure compensation, and the sun tint depends on the sun elevation
    if exposureOffset then updateExposure() end
    if sunTintColor and sunsky then
      local elevation = tonumber(sunsky.elevation)
      if elevation and (not sunTintElevation or math.abs(elevation - sunTintElevation) > 0.5) then
        applySunTint(elevation)
      end
    end
  end
end

local function onUpdate(dtReal, dtSim)
  if tod and tod.time then convertTod(tod.time) end
  drawImgui()
  if weatherTable and selectedWeather and weatherTable[selectedWeather[0]+1] and pauseExecution == false then
    if weatherTable[selectedWeather[0]+1].thunder and weatherTable[selectedWeather[0]+1].thunder == true then
      delay = delay + dtSim
      if thndrLight and thndrShape then
        onWeatherThunder(dtSim, dtReal)
      end
    end
  end
end

local function onEditorActivated()
  if todBox and pauseExecution == false then
    log('I', logTag, 'Pausing execution' )
    isTodBoxVis = todBox.hidden
    pauseExecution = true
    onEditorOpen()
  end
end

local function onEditorDeactivated()
  if todBox and pauseExecution == true and usesLua == 0 then
    if editor.dirty then
      loadedLevel = {}
      readLevelData(levelname)
    end
    log('I', logTag, 'Resuming execution' )
    onAddComponentsToMission()
    todBox.hidden = isTodBoxVis
    pauseExecution = false
    applyTimeOfDay(tod)
  end
end

local function onWindowMenuItem()
  showUI[0] = true
end

local function openUI()
  showUI[0] = true
end

local function hideUI()
  showUI[0] = false
end

local function toggleUI()
  if showUI[0] then
    hideUI()
  else
    openUI()
  end
end

local function onClientEndMission()
  setLegacySun(nil)
  setLegacyExposure(nil)
  restoreSunTint()
  usesLua = 0
  pauseExecution = true
  loadedLevel = {}
  levelfolder = nil
  levelname =  nil
  tod = nil
  sunsky = nil
  todBox = nil
  rainSfx = nil
  rainVfx = nil
  thndrLight = nil
  thndrShape = nil
  log('I', logTag, 'onClientEndMission' )
end

local function onExtensionLoaded()
  if not TorqueScriptLua then
    TorqueScriptLua = TorqueScript
  end
  log('I', logTag, 'Loading Extension' )
  guiModule.initialize(gui)
  local sbFiles = FS:findFiles(skyBoxes, '*todBox.json', 1, true, false)
  for k,filename in pairs(sbFiles) do
    skyBoxTable[k] = jsonReadFile(filename) or {}
    skyBoxTable[k].realDir = skyBoxes
    skyBoxTable[k].fileName = string.gsub(filename, skyBoxes, "")
  end
  onLoadedPreset()
  onSelectedPreset(selectedPreset[0]+1)
  settingsLoad()
  onSelectedPreset(selectedPreset[0]+1)
  if showUI == nil then
    showUI = ui_imgui.BoolPtr(false)
  end
  levelname = getCurrentLevelIdentifier()
  lightmgr = tostring(getConsoleVar("$pref::lightManager"))
  if levelname ~= nil then
    log('I', logTag, 'We are on the level, loading stuff' )
    onClientStartMission()
  end
end

local function onExtensionUnloaded()
  log('I', logTag, 'Unloading extension' )
  setLegacySun(nil)
  setLegacyExposure(nil)
  restoreSunTint()
  if todBox and pauseExecution == false then
    if currentPreset then
      for k,v in pairs(material) do
        deleteMaterials(v)
      end
    end
    log('I', logTag, 'Pausing execution' )
    isTodBoxVis = todBox.hidden
    pauseExecution = true
    onEditorOpen()
  end
end

M.show = openUI
M.hide = hideUI
M.toggle = toggleUI
M.onExtensionLoaded = onExtensionLoaded
M.onClientStartMission = onClientStartMission
M.onEditorActivated = onEditorActivated
M.onEditorDeactivated = onEditorDeactivated
M.onUpdate = onUpdate
M.onPreRender = onPreRender
M.onClientEndMission = onClientEndMission
M.onExtensionUnloaded = onExtensionUnloaded

return M