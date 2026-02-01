-- Was working early 2023
-- Obviously doesn't work anymore but enjoy the reference

local scriptVersion = 1.4

local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local Tween = game:GetService("TweenService")
local lp = game.Players.LocalPlayer
if lp.Character == nil then
  repeat task.wait(0.1) until lp.Character ~= nil -- wait for character to spawn
  task.wait(2)
end
local function alert(text, color, seconds)
  local newColor = color ~= "rainbow" and color or nil
  getsenv(lp.PlayerScripts.CL_MAIN_GameScript).newAlert(text, newColor, seconds, color)
end

local hrp, hum, playAnim, setAnimSpeed
local function updateCharVar()
  -- update character variables
  hrp = lp.Character:WaitForChild("HumanoidRootPart")
  hum = lp.Character:WaitForChild("Humanoid")
  repeat task.wait(0.1) until getsenv(lp.Character:WaitForChild("Animate")) ~= nil
  playAnim = getsenv(lp.Character.Animate).playAnimation
  local oldSetSpeed = getsenv(lp.Character.Animate).setAnimationSpeed
  getsenv(lp.Character.Animate).setAnimationSpeed = function(speed)
    return oldSetSpeed(math.clamp(speed, -1, 1)) -- fix backjump animation speed
  end
  setAnimSpeed = getsenv(lp.Character.Animate).setAnimationSpeed
end
lp.CharacterAdded:Connect(updateCharVar)
updateCharVar()

local tasFolder
if game.PlaceId == 2198503790 or game.PlaceId == 2198548668 then -- FE2CM / FE2CM Solo
  tasFolder = "FE2CM_TAS"
else
  tasFolder = "FE2_TAS" -- dev version only: works in chaos chill and pro servers
end
if isfolder(tasFolder) == false then
  makefolder(tasFolder)
end

-- antikick (for when afk)
local OldNameCall = nil
OldNameCall = hookmetamethod(game, "__namecall", function(Self, ...)
    local NameCallMethod = getnamecallmethod()
    if tostring(string.lower(NameCallMethod)) == "kick" then
        return nil
    end
    return OldNameCall(Self, ...)
end)
game.ReplicatedStorage.Remote.ReqCharVars.OnClientInvoke = function() return {} end -- disable most of anticheat

local settingsFile = tasFolder .. "/settings.json"
local hasSettings = isfile(settingsFile)
local defaultSettings = {
  keybinds = {
    Pause = "CapsLock",
    AddSavestate = "One",
    RemoveSavestate = "Two",
    GoToSavestate = "Three",
    Rewind = "Four",
    Forward = "Five",
    FrameAdvance = "Seven",
    ViewTAS = "Zero",
    CollideToggle = "C",
    WaterToggle = "G",
    PartsColors = "X",
    PausePlayback = "P",
    LockCamera = "L"
  }
}
if not hasSettings then
  writefile(settingsFile, Http:JSONEncode(defaultSettings)) -- set default settings
end
local tasSettings = Http:JSONDecode(readfile(settingsFile))

local keybinds = {
  Pause = { text = "Pause/Unpause" },
  AddSavestate = { text = "Add Savestate" },
  RemoveSavestate = { text = "Remove Savestate" },
  GoToSavestate = { text = "Go To Savestate" },
  Rewind = { text = "Back Frame" },
  Forward = { text = "Forward Frame" },
  FrameAdvance = { text = "Frame Advance" },
  ViewTAS = { text = "View TAS" },
  CollideToggle = { text = "CanCollide Toggle" },
  WaterToggle = { text = "Water Toggle" },
  PartsColors = { text = "Parts Colors Toggle" },
  PausePlayback = { text = "Pause TAS Playback" },
  LockCamera = { text = "Lock Playback Camera" }
}
for key,_ in pairs(keybinds) do
  keybinds[key].key = (tasSettings.keybinds[key] or defaultSettings.keybinds[key])
end

local keybindGuiOrder = { -- dictionaries are unordered so have to use this table to order the keybinds gui
  "Pause", "AddSavestate", "RemoveSavestate", "GoToSavestate", "Rewind", "Forward", "FrameAdvance",
  "CollideToggle", "WaterToggle", "PartsColors",
  "ViewTAS", "PausePlayback", "LockCamera"
}

local FE2Library = require(game.ReplicatedStorage.Scripts.FE2Library)
local saveSettings = nil
local TASselected = nil
local prevTASselected = nil
local TASoptionSelected = "None"
local currentTasData = {}
local playingtas = false
local PausePlayback = false
local PlaybackPauseTime = 0
local PlaybackPauseTimeWait = 0
local LockCamera = true

UIS.InputBegan:Connect(function(int, gameProcessedEvent)
  if gameProcessedEvent then return end
  if int.KeyCode == Enum.KeyCode[keybinds.PausePlayback.key] and playingtas then
    PausePlayback = not PausePlayback
    if PausePlayback then
      hrp.Anchored = true
      PlaybackPauseTime = os.clock()
      alert("Paused TAS Playback!", Color3.new(1, 0.5, 0), 1)
    else
      hrp.Anchored = false
      PlaybackPauseTimeWait += os.clock() - PlaybackPauseTime
    end
  elseif int.KeyCode == Enum.KeyCode[keybinds.LockCamera.key] then
    LockCamera = not LockCamera
    alert("Toggled Camera Lock!", Color3.new(1, 0.5, 0), 1)
  end
end)

local SaveStates = {}
local tasMap, start

local FE2Anims = {
  "idle", "walk", "run", "jump", "fall", "swimidle", "swim",
  "climb", "sit", "slide", "swing", "wave", "point", "dance1",
  "dance2", "dance3", "laugh", "cheer", "customemote"
}

local function round(x, decimals)
  local factorOfTen = 10 ^ decimals
  return math.floor((x * factorOfTen + 0.5)) / factorOfTen -- only return first requested decimals
end
local function parseVector3(vector)
  if type(vector) == "vector" then return vector end
  return Vector3.new(vector[1], vector[2], vector[3])
end
local function vectorTuple(vector)
  return vector.X, vector.Y, vector.Z
end
local function parseCFrame(cframe)
  if type(cframe) == "userdata" then return cframe end
  return CFrame.new(cframe[1], cframe[2], cframe[3]) * CFrame.Angles(cframe[4], cframe[5], cframe[6])
end
local function cframeTuple(cframe)
  return cframe.X, cframe.Y, cframe.Z, cframe:ToEulerAnglesXYZ()
end
local function roundVector(vector)
  if type(vector) == "vector" then
    return Vector3.new(round(vector.X, 3), round(vector.Y, 3), round(vector.Z, 3))
  else
    local rx, ry, rz = vector:ToEulerAnglesXYZ()
    return CFrame.new(round(vector.X, 3), round(vector.Y, 3), round(vector.Z, 3)) * CFrame.Angles(round(rx, 3), round(ry, 3), round(rz, 3))
  end
end

local tasFileExt = "fe2tas"
local function getFileLocation(filename)
  return tasFolder .. "/" .. filename .. "." .. tasFileExt
end

local compressor = loadstring(game:HttpGet("https://pastebin.com/raw/QvEMrMNi"))()
local binarycompressor = loadstring(game:HttpGet("https://pastebin.com/raw/Lxk41Jq0"))()

local function bytesLen(int)
  return int < 256 and 1
      or int < 65536 and 2
      or int < 16777216 and 3
      or 4
end

local oldFormatFiles = {}
for _, v in ipairs(listfiles(tasFolder)) do
  if v:split("\\")[2]:split(".")[2] == "tas" then
    table.insert(oldFormatFiles, v)
  end
end

if #oldFormatFiles > 0 then
  alert("Updating TAS Files", Color3.new(0.015, 1, 0))

  for _, file in ipairs(oldFormatFiles) do
    local data = Http:JSONDecode(compressor.decompress(readfile(file)))
    local dataLen = #data
    local filesavestates = {}

    for i=1, dataLen do
      if i % 200 == 0 or i == 1 or i == dataLen then
        table.insert(filesavestates, i) -- create a new savestate for every 200 indexes in file data
      end
    end

    local binarydata = table.create(3 + dataLen*9 + #filesavestates)

    table.insert(binarydata, string.pack(">f", scriptVersion))
    table.insert(binarydata, string.pack(">I4", dataLen))
    table.insert(binarydata, string.pack(">I4", #filesavestates))

    for i, frame in ipairs(data) do
      table.insert(binarydata, string.pack(">ffffff", table.unpack(frame.CFrame)))
      table.insert(binarydata, string.pack(">ffffff", table.unpack(frame.camCFrame)))
      table.insert(binarydata, string.pack(">fff", table.unpack(frame.vel)))
      table.insert(binarydata, string.pack(">i1", frame.swimVel))
      table.insert(binarydata, string.pack(">I1", table.find(FE2Anims, frame.anim and frame.anim[1] or "idle")))
      table.insert(binarydata, string.pack(">f", frame.anim and frame.anim[2] or 0.1))
      table.insert(binarydata, string.pack(">I" .. bytesLen(i), frame.animChanged))
      table.insert(binarydata, string.pack(">I1", frame.humState and Enum.HumanoidStateType[frame.humState].Value or Enum.HumanoidStateType.Freefall.Value))
      table.insert(binarydata, string.pack(">f", frame.time))
    end
    local savestateByteLen = bytesLen(dataLen)
    for _, savestate in ipairs(filesavestates) do
      table.insert(binarydata, string.pack(">I" .. savestateByteLen, savestate))
    end

    local tasFileDir = getFileLocation(file:split("\\")[2]:split(".")[1])
    -- compress: binarycompressor.Zlib.Compress
    writefile(tasFileDir, table.concat(binarydata))
    delfile(file)
    alert("Updated " .. tasFileDir, Color3.new(1, 0.5, 0))
  end

  alert("Updated " .. #oldFormatFiles .. " TAS files to new format!", "rainbow")
end

local readbinaryfile
local readbinaryoffset = 0
local function readBinary(format)
  local data = table.pack(string.unpack(format, readbinaryfile, readbinaryoffset))
  readbinaryoffset = table.remove(data) -- last index is offset

  if type(data) == "table" then
    local propLen = #data
    if propLen == 3 then
      return parseVector3(data)
    elseif propLen == 6 then
      return parseCFrame(data)
    end
  end

  return data[1]
end
local function parseBinaryFile()
  -- decompress: binarycompressor.Zlib.Decompress
  readbinaryfile = readfile(getFileLocation(TASselected))
  readbinaryoffset = 0

  -- convert binary data into table
  local fileScriptVersion = readBinary(">f")
  local numOfFrames = readBinary(">I4")
  local numOfSavestates = readBinary(">I4")

  currentTasData = table.create(numOfFrames)
  SaveStates = table.create(numOfSavestates)

  for i=1, numOfFrames do
    table.insert(currentTasData, {
      CFrame = readBinary(">ffffff"),
      camCFrame = readBinary(">ffffff"),
      vel = readBinary(">fff"),
      swimVel = readBinary(">i1"),
      anim = readBinary(">I1"),
      animTransSpeed = readBinary(">f"),
      animChanged = readBinary(">I" .. bytesLen(i)),
      humState = readBinary(">I1"),
      time = readBinary(">f")
    })
  end
  local savestateByteLen = bytesLen(numOfFrames)
  for i=1, numOfSavestates do
    table.insert(SaveStates, readBinary(">I" .. savestateByteLen))
  end
end

local ButtonSelected = nil
local tasButtonSelected = nil
local tasmainGui = lp.PlayerGui.MenuGui.Spectate:Clone()

local function resetTasButtonSelected()
  local noneButton = tasmainGui.ButtonsFolder.None
  ButtonSelected.BackgroundColor3 = Color3.fromRGB(127, 140, 141)
  noneButton.BackgroundColor3 = Color3.fromRGB(88, 98, 98)
  ButtonSelected = noneButton
  TASoptionSelected = "None"
end

local function createTas(editingTas)
  alert("Loading Sandbox...", Color3.fromRGB(100,255,100))

  local TimeSubtractPause = nil
  local TimeForGame = nil
  local PauseTimeWait = nil
  local PressedButtons = {}
  local buttonCount = 0
  local totalButtonCount = 0
  local PauseIt = false
  local AnimationState = nil
  local AnimationHowManyChange = 0
  local FrameGo = {}
  local ToggleFastFrame = false
  local currentFastFrameTime
  local slideCheck = false
  local ziplineCheck = false
  local ViewRun = false
  local toggleCanCollideOnClick = false
  local autosaved = false
  local watertoggle = true
  local partcolors = true
  local partcolorwhitelist = {}

  settings():GetService("NetworkSettings").IncomingReplicationLag = 9999

  local fastFrameCooldown = 0.5   -- time until holding down rewind/forward quickly moves
  local untouchedButtonTransparency = 0.5   -- transparency of button hitbox before being pressed
  local untouchedButtonColor = Color3.fromRGB(0, 93, 253)   -- color of untouched button

  local tasGui = lp.PlayerGui.GameGui.HUD.GameStats
  local mapname = tasMap.Settings.MapName.Value

  tasGui.Ingame.Visible = false
  lp.PlayerGui.GameGui.HUD.MenuButtons.Position = UDim2.new(-0.05, 0, 0, 0)
  for _,v in pairs(game.Players:GetPlayers()) do
    if v ~= lp and v.Character ~= nil then
      v.Character:Destroy()
    end
  end

  pcall(function()
    workspace.Buddies:Destroy()
    lp.PlayerGui.GameGui.HUD.MapEventInfo:Destroy()
  end)

  hum.Changed:Connect(function(prop)
      if prop == "Health" then
          hum.Health = 101
      end
  end)

  -- fix gui positioning (correctly center it)
  tasGui.Position = UDim2.new(0.25, 0, 0, 0)
  tasGui.Size = UDim2.new(0.8, 0, 1, 0)

  local templateLabel = Instance.new("TextLabel")
  templateLabel.BackgroundTransparency = 1
  templateLabel.Font = "Highway"
  templateLabel.TextColor3 = Color3.new(1, 1, 1)
  templateLabel.TextScaled = true

  local labelFolder = Instance.new("Folder", tasGui)
  labelFolder.Name = "TAS"

  local function newLabel(prop)
      local label = templateLabel:Clone()
      label.Name = prop.name
      label.Position = prop.pos
      label.Size = prop.size
      label.Text = (prop.text or "")
      label.AnchorPoint = (prop.anchor or Vector2.new(0, 0.5))
      label.TextXAlignment = Enum.TextXAlignment[(prop.align or "Center")]
      label.Parent = labelFolder
      return label
  end

  local timer = newLabel({
    name = "Timer",
    text = "0:00.000",
    align = "Left",
    pos = UDim2.new(0.01, 0, 0.5, 0),
    size = UDim2.new(0.3, 0, 0.6, 0)
  })
  local savestatesGui = newLabel({
    name = "SavestatesCount",
    text = "Savestates: 0",
    pos = UDim2.new(0.28, 0, 0.2, 0),
    size = UDim2.new(0.2, 0, 0.33, 0)
  })
  local buttonsGui = newLabel({
    name = "ButtonsCount",
    text = "Buttons: 0/0",
    pos = UDim2.new(0.28, 0, 0.5, 0),
    size = UDim2.new(0.2, 0, 0.33, 0)
  })
  local fpsGui = newLabel({
    name = "FPS",
    text = "FPS: 0",
    pos = UDim2.new(0.28, 0, 0.8, 0),
    size = UDim2.new(0.2, 0, 0.33, 0)
  })
  local hVelGui = newLabel({
    name = "HorizontalVelocity",
    text = "Horizontal Velocity: 0",
    align = "Left",
    anchor = Vector2.new(1, .5),
    pos = UDim2.new(1, 0, 0.32, 0),
    size = UDim2.new(0.42, 0, 0.4, 0)
  })
  local vVelGui = newLabel({
    name = "VerticalVelocity",
    text = "Vertical Velocity: 0",
    align = "Left",
    anchor = Vector2.new(1, .5),
    pos = UDim2.new(1, 0, 0.68, 0),
    size = UDim2.new(0.42, 0, 0.4, 0)
  })

  -- save tas gui
  local savetasframe = lp.PlayerGui.MenuGui.Shop.Window.Content.CodeRedeem
  local savetasframe1 = lp.PlayerGui.MenuGui.Spectate:Clone()
  savetasframe1.Name = "Save TAS"
  savetasframe1.IconID.Value = 247422127
  savetasframe1.ListName.Value = "Save TAS"
  savetasframe1.Parent = lp.PlayerGui.MenuGui
  savetasframe1.Content:Destroy()
  local folder = Instance.new("Folder", savetasframe1)
  folder.Name = "RecordingTASGui"
  folder.Parent.Title.Frame.Info.Text = "Save TAS"
  folder.Parent.Title.Frame.Icon.Visible = false
  local CreditsLabel = folder.Parent.Title.Frame.Info:Clone()
  local NewConfirm = savetasframe.Confirm:Clone()
  local DeleteSandboxButton = savetasframe.Confirm:Clone()
  local NewConfirmTwo = savetasframe.Confirm:Clone()
  local TextBox = savetasframe.CodeBox:Clone()
  local blueColor = Color3.fromRGB(52, 152, 219)
  local greenColor = Color3.fromRGB(46, 204, 113)
  CreditsLabel.Parent = folder
  CreditsLabel.Text = "Credits:\nTAS Script: ianIG\nGUI & Helper: AltLexon\nDiscord Server: discord.gg/5G6ed4amtP"
  CreditsLabel.TextXAlignment = "Center"
  CreditsLabel.Position = UDim2.new(0.5, 0, 0.7, 0)
  CreditsLabel.Size = UDim2.new(0.7, 0, 0.2, 0)
  CreditsLabel.AnchorPoint = Vector2.new(.5, 0)
  NewConfirm.Info.Text = "Save TAS With Custom File Name"
  NewConfirm.BackgroundColor3 = greenColor
  NewConfirm.Parent = folder
  NewConfirm.Size = UDim2.new(0.7, 0, 0.07, 0)
  NewConfirm.Position = UDim2.new(0.5, 0, 0.32, 0)
  NewConfirmTwo.Info.Text = "Save TAS With Map Name"
  NewConfirmTwo.BackgroundColor3 = greenColor
  NewConfirmTwo.Parent = folder
  NewConfirmTwo.Size = UDim2.new(0.7, 0, 0.07, 0)
  NewConfirmTwo.Position = UDim2.new(0.5, 0, 0.05, 0)
  DeleteSandboxButton.Info.Text = "Exit The Sandbox"
  DeleteSandboxButton.Size = UDim2.new(0.7, 0, 0.1, 0)
  DeleteSandboxButton.BackgroundColor3 = blueColor
  DeleteSandboxButton.Name = "DeleteSandboxButton"
  DeleteSandboxButton.Position = UDim2.new(0.5, 0, 0.5, 0)
  DeleteSandboxButton.Parent = folder
  TextBox.TextBox.PlaceholderText = ">Enter TAS Name"
  TextBox.Size = UDim2.new(0.7, 0, 0.1, 0)
  TextBox.Position = UDim2.new(0.5, 0, 0.2, 0)
  TextBox.AnchorPoint = Vector2.new(.5, 0)
  TextBox.Parent = folder

  local function textColorAnim(name, color)
    local label = labelFolder[name]
    local tweenStart = Tween:Create(label, TweenInfo.new(0.1), {TextColor3 = color})
    tweenStart:Play()
    tweenStart.Completed:Connect(function()
      Tween:Create(label, TweenInfo.new(0.5), {TextColor3 = Color3.fromRGB(255,255,255)}):Play()
    end)
  end

  local waterParts = {}
  local waterStart = {}

  local MapPartsData = {}

  for _, v in ipairs(workspace.Multiplayer.Map:GetDescendants()) do
    -- button stuff
    if v.Name == "ButtonIcon" and v.Parent:IsA("BillboardGui") and v.Parent.Name ~= "Marker" then
      local buttonModel = v.Parent.Parent
      table.insert(partcolorwhitelist, buttonModel)
      for _,j in pairs(buttonModel:GetChildren()) do
        if j:IsA("Part") then
          local selectBox = Instance.new("SelectionBox")
          selectBox.Name = "SelectionBox"
          selectBox.Adornee = j
          selectBox.Color3 = Color3.fromRGB(100,255,100)
          selectBox.Parent = j
          j.Transparency = untouchedButtonTransparency
          j.Color = Color3.fromRGB(100,255,100)
          v.Parent.Enabled = false
          totalButtonCount += 1

          j.Touched:Connect(function()
            if PressedButtons[j.Name] == nil then
              PressedButtons[j.Name] = {
                button = j,
                time = currentTasData[#currentTasData].time
              }

              j.Transparency = 1
              selectBox.Color3 = Color3.fromRGB(27, 42, 53)
              pcall(function() buttonModel.ColorIndicator.Color = Color3.fromRGB(27, 42, 53) end)
              alert("Button Pressed!", Color3.fromRGB(100,255,100))

              buttonCount += 1
              buttonsGui.Text = "Buttons: ".. buttonCount .. "/" .. totalButtonCount
              textColorAnim("ButtonsCount", Color3.fromRGB(0, 255, 0))
            end
          end)
        elseif j:IsA("UnionOperation") then
          local _, saturation = j.Color:ToHSV() -- base of button is dark (unsaturated) and we tryna get the other part
          if saturation > 0.5 then
            j.Name = "ColorIndicator"
            j.Color = untouchedButtonColor
          end
        end
      end
    end

    -- get water objects (to raise water in tas)
    if v.Name == "WaterState" then
      local waterPart = v.Parent
      if waterPart.Name:find("Water") then
        waterPart.Transparency = 0.4
        waterParts[waterPart.Name] = waterPart
        waterStart[waterPart.Name] = waterPart.Position
      end
      table.insert(partcolorwhitelist, waterPart)
    end

    if v:IsA("BasePart") then
      local partData = {
        part = v,
        color = v.Color,
      }
      table.insert(MapPartsData, partData)
    end
  end

  local waterData
  local canUpdateWater = pcall(function() waterData = Http:JSONDecode(compressor.decompress(game:HttpGet("https://raw.githubusercontent.com/7ih/FE2-TAS-Water-Data/main/" .. mapname:gsub(" ", "%%20")))) end)

  local prevProp = {}
  local lastWaterTime = 0

  if canUpdateWater then
    for itime,_ in pairs(waterData) do
      -- get last time in dataset
      itime = tonumber(itime)
      if itime > lastWaterTime then
        lastWaterTime = itime
      end
    end
  end

  local function getwatercolor(state)
    return  state == 0 and BrickColor.new("Deep blue") or
            state == 1 and BrickColor.new("Lime green") or
            state == 2 and BrickColor.new("Really red")
  end
  local function updateWater()
    if not canUpdateWater or not watertoggle then return end

    local currentTime = PauseIt and not ViewRun and PauseTimeWait or os.clock()
    local tasTimeNum = math.floor((currentTime - TimeForGame - TimeSubtractPause) * 100)
    local tasTime = nil
    if tasTimeNum > lastWaterTime then
      tasTime = tostring(lastWaterTime)
    else
      tasTime = tostring(tasTimeNum)
    end

    if waterData[tasTime] == nil then return end

    for water,prop in pairs(waterData[tasTime]) do
      local waterPart = waterParts[water]
      if not waterPart then break end
      prop.pos = parseVector3(prop.pos)

      if prevProp[water] == nil then
        prevProp[water] = prop
      end

      -- only set properties if a change is detected
      if prop.pos ~= prevProp[water].pos or PauseIt then
        if waterStart[water] then
          waterPart.Position = waterStart[water] + prop.pos
        end
      end
      if prop.st ~= prevProp[water].st or PauseIt then
        waterPart.BrickColor = getwatercolor(prop.st)
      end

      prevProp[water] = prop
    end
  end
  local function updateButtons()
    local countChanged = false
    if currentTasData[1] then
      local currentTime = currentTasData[#currentTasData].time
      for i,v in pairs(PressedButtons) do
        if currentTime < v.time then
          PressedButtons[i] = nil
          buttonCount -= 1

          v.button.Transparency = untouchedButtonTransparency
          v.button.SelectionBox.Color3 = Color3.fromRGB(100,255,100)
          pcall(function() v.button.Parent.ColorIndicator.Color = untouchedButtonColor end)
          countChanged = true
        end
      end
    end

    if countChanged then
      buttonsGui.Text = "Buttons: ".. buttonCount .. "/" .. totalButtonCount
      textColorAnim("ButtonsCount", Color3.fromRGB(255, 0, 0))
    end
  end
  local function setTimer()
    local t = os.clock() - TimeForGame - TimeSubtractPause
    timer.Text = ("%0d:%02d.%03d"):format(t/60,t%60,t*1000%1000)
  end
  local function updateTas()
    setTimer()
    updateButtons()
    updateWater()
  end
  local function roundStr(x, decimals)
    return string.format("%." .. decimals .. "f", tostring(x))
  end

  TimeForGame = os.clock()
  TimeSubtractPause = 0
  local function recordPos()
    local humstate = hum:GetState()
    if humstate == Enum.HumanoidStateType.Jumping then
      humstate = Enum.HumanoidStateType.Freefall -- fix (back)jumping velocity
    end
    table.insert(currentTasData, {
      CFrame = roundVector(hrp.CFrame),
      camCFrame = roundVector(workspace.CurrentCamera.CFrame),
      vel = roundVector(hrp.Velocity),
      swimVel = hrp.SwimVel.Velocity.Y,
      anim = table.find(FE2Anims, AnimationState[1]),
      animTransSpeed = AnimationState[2],
      animChanged = AnimationHowManyChange,
      humState = humstate.Value,
      time = round(os.clock() - TimeForGame - TimeSubtractPause, 3)
    })
  end
  local function addSavestate()
    if (#currentTasData == SaveStates[#SaveStates]) then return end

    table.insert(SaveStates, #currentTasData)

    savestatesGui.Text = "Savestates: " .. #SaveStates - 1
    textColorAnim("SavestatesCount", Color3.fromRGB(0, 255, 0))
  end

  local recordAnim = function(animName, x)
    if ViewRun == false then
      if slideCheck == true then
        AnimationState = {"slide", 0.2}
      elseif ziplineCheck then
        AnimationState = {"swing", 0}
      elseif animName == "climb" then
        AnimationState = {"climb", math.clamp(x, 0.14, 1)} -- fix transition speed
      else
        AnimationState = {animName, x}
      end

      AnimationHowManyChange += 1
      playAnim(animName, x, hum)
    end
  end

  getsenv(lp.Character.Animate).playAnimation = recordAnim

  local function updatePlayer(data)
    hrp.CFrame = data.CFrame
    hrp.Velocity = data.vel
    workspace.CurrentCamera.CFrame = data.camCFrame
    AnimationState = { data.anim, data.animTransSpeed }
    AnimationHowManyChange = data.animChanged
    hrp.SwimVel.Velocity = Vector3.new(0, data.swimVel, 0)
    if data.humState then hum:ChangeState(data.humState) end
    TimeForGame = os.clock() - data.time
    TimeSubtractPause = 0
    PauseTimeWait = os.clock()
  end

  local function goBackFrame()
    if currentTasData[#currentTasData - 1] ~= nil and #currentTasData - 1 >= SaveStates[#SaveStates] then
      table.insert(FrameGo, currentTasData[#currentTasData])
      currentTasData[#currentTasData] = nil
      updatePlayer(currentTasData[#currentTasData])
      updateTas()
    end
  end
  local function goForwardFrame()
    if FrameGo[#FrameGo] ~= nil then
      table.insert(currentTasData, FrameGo[#FrameGo])
      FrameGo[#FrameGo] = nil
      updatePlayer(currentTasData[#currentTasData])
      setTimer()
      updateWater()
    end
  end
  local function fastFrameDebounce(frameFunc)
    frameFunc()

    ToggleFastFrame = true
    local thisToggleTime = os.clock()
    currentFastFrameTime = thisToggleTime

    task.wait(fastFrameCooldown)
    if currentFastFrameTime == thisToggleTime then -- debounce
      while ToggleFastFrame == true do -- fast frame while holding down key
        frameFunc()
        task.wait(.005)
      end
    end
  end
  local function goToLastSavestate()
    local TargetFrameId = SaveStates[#SaveStates]
    for i=#currentTasData, TargetFrameId + 1, -1 do
      table.remove(currentTasData)
    end

    local savestate = currentTasData[#currentTasData]

    -- fix issue with exiting water while paused
    if AnimationState and (AnimationState[1] == "swim" or AnimationState[1] == "swimidle") then
      local connection = nil
      connection = lp.Character.Animate.ToggleSwim.Event:Connect(function()
        task.wait()
        updatePlayer(savestate)
        connection:Disconnect()
      end)
    end

    updatePlayer(savestate)
    updateTas()
  end

  lp.Character.Animate.Swinging.Event:Connect(function(ziplining)
    ziplineCheck = ziplining
  end)
  lp.Character.Animate.Sliding.Event:Connect(function(ziplining)
    slideCheck = ziplining
  end)

  local exitregion = tasMap:FindFirstChild("NoExit", true)
  table.insert(partcolorwhitelist, exitregion)
  exitregion.Transparency = 0.4
  exitregion.BrickColor = BrickColor.new("Really red")
  local inExit = false
  local function checkIfInExitRegion()
    if exitregion then
      if FE2Library.inPart(hrp.Position, exitregion) then
        if not inExit then
          if buttonCount == totalButtonCount then
            alert("Completed Map!", "rainbow")
            exitregion.BrickColor = BrickColor.new("Pastel light blue")
          else
            alert("You haven't pressed all the buttons!", Color3.new(1, 0, 0))
          end
          inExit = true
        end
      elseif inExit then
        alert("You left the exit region!", Color3.new(1, 0, 0))
        exitregion.BrickColor = BrickColor.new("Really red")
        inExit = false
      end
    end
  end

  local function canChangeColorCheck(part)
    for _,taspart in ipairs(partcolorwhitelist) do
      if part == taspart or taspart:IsAncestorOf(part) then return false end
    end
    return true
  end

  local function enablePartColors()
    for _, part in ipairs(workspace.Multiplayer.Map:GetDescendants()) do
      if part:IsA("BasePart") and canChangeColorCheck(part) then
        local shade = math.random() / 2 + 0.5
        if part:IsA("UnionOperation") then
          part.Color = Color3.new(shade, shade, 0)
        elseif part:IsA("MeshPart") then
          part.Color = Color3.new(0, shade, 0)
        else
          part.Color = Color3.new(shade, shade, shade)
        end
      end
    end
  end

  enablePartColors()

  local function stopViewTas()
    playingtas = false
    getsenv(lp.Character.Animate).playAnimation = recordAnim
    hrp.Anchored = true
    PauseTimeWait = os.clock()
    setTimer()
    ViewRun = false
    keyrelease(87)
  end

  local createTasInputs = UIS.InputBegan:Connect(function(int, gameProcessedEvent)
    if gameProcessedEvent then return end

    if int.KeyCode == Enum.KeyCode[keybinds.Pause.key] then
      if ViewRun == false then
        PauseIt = not PauseIt

        if PauseIt == true then
          hrp.Anchored = true
          recordPos()
          PauseTimeWait = os.clock()
          timer.TextColor3 = Color3.fromRGB(255,255, 0)
          setTimer()
        elseif PauseIt == false then
          hrp.Anchored = false
          TimeSubtractPause = TimeSubtractPause + (os.clock() - PauseTimeWait)
          autosaved = false
          timer.TextColor3 = Color3.fromRGB(255, 255, 255)
          FrameGo = {}
        end
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.AddSavestate.key] then
      if ViewRun == false and currentTasData ~= nil then
        addSavestate()
        FrameGo = {}
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.FrameAdvance.key] then
      if ViewRun == false and PauseIt == true then
        game:GetService("RunService").RenderStepped:Wait()
        hrp.Anchored = false
        TimeSubtractPause = TimeSubtractPause + (os.clock() - PauseTimeWait)
        FrameGo = {}

        game:GetService("RunService").RenderStepped:Wait()

        PauseTimeWait = os.clock()
        hrp.Anchored = true
        recordPos()
        setTimer()
        updateWater()
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.RemoveSavestate.key] then
      if ViewRun == false and #SaveStates >= 2 then
        table.remove(SaveStates)
        savestatesGui.Text = "Savestates: " .. #SaveStates - 1
        textColorAnim("SavestatesCount", Color3.fromRGB(255, 0, 0))
        FrameGo = {}

        goToLastSavestate()
      end
    elseif int.KeyCode == Enum.KeyCode[keybinds.GoToSavestate.key] then
      if ViewRun == false then
        goToLastSavestate()
        FrameGo = {}
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.Rewind.key] then
      if ViewRun == false then
        fastFrameDebounce(goBackFrame)
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.Forward.key] then
      if ViewRun == false then
        fastFrameDebounce(goForwardFrame)
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.ViewTAS.key] and PauseIt == true and #SaveStates > 1 then
      if ViewRun == false then
        playingtas = true
        ViewRun = true
        FrameGo = {}
        TimeForGame = os.clock()
        TimeSubtractPause = 0
        getsenv(lp.Character.Animate).playAnimation = function() end
        PausePlayback = false
        PlaybackPauseTimeWait = 0

        keypress(87)  --fix swimming animations by simulating humanoid.movedirection (hacky)

        local timeStart = os.clock()
        for i = 2, #currentTasData - 1 do
          local data = currentTasData[i]
          local prevData = currentTasData[i - 1]

          -- pause tas
          if PausePlayback then
            repeat task.wait() until not PausePlayback
            TimeSubtractPause += os.clock() - PlaybackPauseTime
          end

          -- fix fps dependency (and implement playback pausing)
          if os.clock() - timeStart - PlaybackPauseTimeWait < data.time then
            repeat task.wait() until os.clock() - timeStart - PlaybackPauseTimeWait > data.time
          end

          if playingtas == false then
            alert("Cancelled View Tas!", Color3.new(1, 0, 0), 1)
            break
          end

          hrp.CFrame = data.CFrame
          hrp.Velocity = data.vel
          if LockCamera then workspace.CurrentCamera.CFrame = data.camCFrame end
          hrp.SwimVel.Velocity = Vector3.new(0, data.swimVel, 0)

          updateWater()
          setTimer()

          -- animation stuff
          if data.anim and prevData.anim and data.animChanged > prevData.animChanged then
            if FE2Anims[data.anim] == "walk" then
              setAnimSpeed(0.76)
            end
            playAnim(FE2Anims[data.anim], data.animTransSpeed, hum)
          end
        end

        stopViewTas()
      else
        stopViewTas()
        updatePlayer(currentTasData[#currentTasData])
        updateWater()
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.CollideToggle.key] then
      toggleCanCollideOnClick = true

    elseif int.KeyCode == Enum.KeyCode[keybinds.WaterToggle.key] then
      if not canUpdateWater then return end
      watertoggle = not watertoggle

      if watertoggle == false then
        alert("Disabled Water!", Color3.new(1, 0, 0))
        for _,water in pairs(waterParts) do
          water.Position = Vector3.new(10000, 10000, 10000)
        end
      else
        alert("Enabled Water!", Color3.new(0.25, 1, 0))
        updateWater()
      end

    elseif int.KeyCode == Enum.KeyCode[keybinds.PartsColors.key] then
      if partcolors == false then
        enablePartColors()
        partcolors = true
      else
        for _,v in pairs(MapPartsData) do
          if canChangeColorCheck(v.part) then
            v.part.Color = v.color
          end
        end
        partcolors = false
      end
    end
  end)
  UIS.InputEnded:Connect(function(int)
    if int.KeyCode == Enum.KeyCode[keybinds.Rewind.key] or int.KeyCode == Enum.KeyCode[keybinds.Forward.key] then
      ToggleFastFrame = false

    elseif int.KeyCode == Enum.KeyCode[keybinds.CollideToggle.key] then
        toggleCanCollideOnClick = false
    end
  end)

  -- cancollide toggle
  local Mouse = lp:GetMouse()
  Mouse.Button1Down:Connect(function()
    if Mouse.Target and toggleCanCollideOnClick then
      if Mouse.Target.CanCollide == true then
        Mouse.Target.CanCollide = false
        Mouse.Target.Transparency = 0.7
      else
        Mouse.Target.CanCollide = true
        Mouse.Target.Transparency = 0
      end
    end
  end)

  local function saveTas(filename)
    local binarydata = table.create(3 + #currentTasData*9 + #SaveStates)

    table.insert(binarydata, string.pack(">f", scriptVersion))
    table.insert(binarydata, string.pack(">I4", #currentTasData))
    table.insert(binarydata, string.pack(">I4", #SaveStates))

    for i, frame in ipairs(currentTasData) do
      table.insert(binarydata, string.pack(">ffffff", cframeTuple(start:ToObjectSpace(frame.CFrame))))
      table.insert(binarydata, string.pack(">ffffff", cframeTuple(start:ToObjectSpace(frame.camCFrame))))
      table.insert(binarydata, string.pack(">fff", vectorTuple(frame.vel)))
      table.insert(binarydata, string.pack(">i1", frame.swimVel))
      table.insert(binarydata, string.pack(">I1", frame.anim))
      table.insert(binarydata, string.pack(">f", frame.animTransSpeed))
      table.insert(binarydata, string.pack(">I" .. bytesLen(i), frame.animChanged))
      table.insert(binarydata, string.pack(">I1", frame.humState))
      table.insert(binarydata, string.pack(">f", frame.time))
    end
    local savestateByteLen = bytesLen(#currentTasData)
    for _, savestate in ipairs(SaveStates) do
      table.insert(binarydata, string.pack(">I" .. savestateByteLen, savestate))
    end

    local saveTasDir = getFileLocation(filename)
    -- compress: binarycompressor.Zlib.Compress()
    writefile(saveTasDir, table.concat(binarydata))
    alert("TAS saved to " ..saveTasDir, "rainbow")
  end
  local function autosave()
    autosaved = true
    if not isfolder(tasFolder.."/autosave") then
      makefolder(tasFolder.."/autosave")
    end

    alert("Autosaving...", Color3.new(1, 0.4, 0))
    saveTas("autosave/" ..mapname)
  end

  NewConfirm.MouseButton1Click:Connect(function()
    if savetasframe.CodeBox.TextBox.Text ~= nil then
      saveTas(TextBox.TextBox.Text)
    else
      alert("You have to enter a TAS name!", Color3.fromRGB(255,100,100),2)
    end
  end)
  NewConfirmTwo.MouseButton1Click:Connect(function()
    saveTas(mapname)
  end)
  DeleteSandboxButton.MouseButton1Click:Connect(function()
    SaveStates = {}
    currentTasData = {}
    savetasframe1:Destroy()
    game:GetService("RunService"):UnbindFromRenderStep("createtas")
    createTasInputs:Disconnect()
    labelFolder:Destroy()
    for _,v in ipairs(lp.PlayerGui.GameGui.MenuFrame.Content:GetDescendants()) do
      if v:IsA("TextLabel") and v.Text == "Save TAS" then
        v.Parent:Destroy()
        break
      end
    end

    pcall(function() lp.Character.Head:Destroy() end)
    task.wait(.5)
    settings():GetService("NetworkSettings").IncomingReplicationLag = 0

    tasGui.Size = UDim2.new(0.7, 0, 1, 0)
    tasGui.Position = UDim2.new(0.3, 0, 0, 0)
    tasGui.Parent.MenuButtons.Position = UDim2.new(0, 0, 0, 0)

    task.wait(1)
    pcall(function() lp.Character.Head:Destroy() end)
  end)


  if editingTas then
    savestatesGui.Text = "Savestates: " .. #SaveStates - 1
    goToLastSavestate()
  else
    hrp.CFrame = start
    hrp.Velocity = Vector3.new()
    SaveStates = {}
    currentTasData = {}
    AnimationState = { "idle", 0.1 }
    recordPos()
    addSavestate()
  end

  updateButtons()

  local fps = 0
  game:GetService("RunService"):BindToRenderStep("createtas", 300, function()
    if ViewRun == false then
      if PauseIt == false then
        recordPos()
        setTimer()
        updateWater()
      elseif os.clock() - PauseTimeWait > 300 and not autosaved then
        autosave() -- if player hasnt unpaused in 5 minutes, autosave
      end

      checkIfInExitRegion()
    end

    hVelGui.Text = "Horizontal Velocity: " .. roundStr((hrp.Velocity * Vector3.new(1, 0, 1)).Magnitude, 3)
    vVelGui.Text = "Vertical Velocity: " .. roundStr(hrp.Velocity.Y, 3)

    fpsGui.Text = "FPS: " .. fps
    fps += 1
    task.wait(1)
    fps -= 1
  end)


  alert("Successfully Loaded TAS Sandbox!", Color3.fromRGB(100,255,100))
end



local function playTas()
    hrp.CFrame = start

    -- increase button hitbox slightly to ensure tas works
    for _, v in ipairs(tasMap:GetDescendants()) do
      if v.Name == "ButtonIcon" then
        for _,j in pairs(v.Parent.Parent:GetChildren()) do
          if j.ClassName == "Part" then
            j.Size = j.Size * 3
          end
        end
      end
    end

    repeat task.wait(0.1) until hum.WalkSpeed ~= 0

    alert("Playing TAS: " .. TASselected, "rainbow")
    playingtas = true
    tasButtonSelected.TextColor3 = Color3.fromRGB(255,255,255)
    tasButtonSelected = nil
    TASselected = nil
    PausePlayback = false
    PlaybackPauseTimeWait = 0

    getsenv(lp.Character.Animate).playAnimation = function() end
    keypress(87)  --fix swimming animations by simulating humanoid.movedirection (hacky)

    local timeStart = os.clock()
    for i = 2, #currentTasData - 1 do
      local data = currentTasData[i]
      local prevData = currentTasData[i - 1]

      -- fix fps dependency (and implement playback pausing)
      if os.clock() - timeStart - PlaybackPauseTimeWait < data.time or PausePlayback then
        repeat task.wait() until os.clock() - timeStart - PlaybackPauseTimeWait > data.time and not PausePlayback
      end

      if hum.Health == 0 then
        alert("Player died during TAS!", Color3.new(0.5, 0, 0))
        break
      end

      hrp.CFrame = start:ToWorldSpace(data.CFrame)
      hrp.Velocity = data.vel
      if LockCamera then workspace.CurrentCamera.CFrame = start:ToWorldSpace(data.camCFrame) end
      hrp.SwimVel.Velocity = Vector3.new(0, data.swimVel, 0)

      -- animation stuff
      if data.anim and prevData.anim and data.animChanged > prevData.animChanged then
        if FE2Anims[data.anim] == "walk" then
          setAnimSpeed(0.76)
        end
        playAnim(FE2Anims[data.anim], data.animTransSpeed, hum)

        -- detect jp
        if FE2Anims[data.anim] == "jump" then
          local maxBjVel = 65 + ((prevData.vel * Vector3.new(1, 0, 1)).Magnitude / 2)
          if data.vel.Y > maxBjVel then
            alert("Backjump Power Used!", Color3.new(1, 0, 0))
          end
        end
      end
    end

    playingtas = false

    if lp.Character.Animate then
      getsenv(lp.Character.Animate).playAnimation = playAnim
    end
    keyrelease(87)

    alert("Made By ianIG, AltLexon", Color3.fromRGB(175, 255, 100), 2)
    alert("TAS Run Finished!", "rainbow", 4)
end


-- MAIN GUI (choose tas)
tasmainGui.Name = "TAS"
tasmainGui.IconID.Value = 4078197699
tasmainGui.ListName.Value = "TAS"
tasmainGui.Parent = lp.PlayerGui.MenuGui

tasmainGui.Content:ClearAllChildren()

local TASes = Instance.new("Frame")
local NoFiles = Instance.new("TextLabel")
local TASFilesList = Instance.new("ScrollingFrame")
local UIGridLayout = Instance.new("UIGridLayout")
local Fade = Instance.new("ImageLabel")
local Title = Instance.new("Frame")
local Info = Instance.new("TextLabel")
local Subtle_Shading = Instance.new("ImageLabel")
local Fade_2 = Instance.new("ImageLabel")
local DropShadow = Instance.new("ImageLabel")

TASes.Name = "TASes"
TASes.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TASes.BackgroundTransparency = 1.000
TASes.Position = UDim2.new(0, 0, 0, 0)
TASes.Size = UDim2.new(1, 0, 0.89, 0)
TASes.Parent = tasmainGui.Content

NoFiles.Name = "NoFiles"
NoFiles.Parent = TASes
NoFiles.AnchorPoint = Vector2.new(0.5, 0.5)
NoFiles.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
NoFiles.BackgroundTransparency = 1.000
NoFiles.BorderSizePixel = 0
NoFiles.Position = UDim2.new(0.5, 0, 0.6, 0)
NoFiles.Size = UDim2.new(0.95, 0, 0.109, 0)
NoFiles.Font = Enum.Font.Ubuntu
NoFiles.Text = "There aren't files!"
NoFiles.TextColor3 = Color3.fromRGB(255, 255, 255)
NoFiles.TextScaled = true
NoFiles.TextSize = 14.000
NoFiles.TextStrokeTransparency = 0.650
NoFiles.TextWrapped = true

TASFilesList.Name = "TASFilesList"
TASFilesList.Parent = TASes
TASFilesList.Active = true
TASFilesList.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TASFilesList.BackgroundTransparency = 1.000
TASFilesList.Position = UDim2.new(0, 0, 0.125, 0)
TASFilesList.Size = UDim2.new(1, 0, 1, 0)
TASFilesList.CanvasSize = UDim2.new(0, 0, 0, 0)
TASFilesList.ScrollBarThickness = 15
TASFilesList.AutomaticCanvasSize = Enum.AutomaticSize.Y

UIGridLayout.Parent = TASFilesList
UIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIGridLayout.CellPadding = UDim2.new(0, 0, 0, 0)
UIGridLayout.CellSize = UDim2.new(1, 0, 0, 64)

Fade.Name = "Fade"
Fade.Parent = TASes
Fade.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Fade.BackgroundTransparency = 1.000
Fade.Position = UDim2.new(-0.001, 0, -0.002, 0)
Fade.Size = UDim2.new(0.025, 0, 1.15, 0)
Fade.ZIndex = 2
Fade.Image = "rbxassetid://1463504275"
Fade.ImageColor3 = Color3.fromRGB(0, 0, 0)
Fade.ImageTransparency = 0.500

Title.Name = "Title"
Title.Parent = TASes
Title.BackgroundColor3 = Color3.fromRGB(44, 62, 80)
Title.BorderSizePixel = 0
Title.ClipsDescendants = true
Title.Size = UDim2.new(1, 0, 0.125, 0)

Info.Name = "Info"
Info.Parent = Title
Info.BackgroundColor3 = Color3.fromRGB(44, 62, 80)
Info.BackgroundTransparency = 1.000
Info.BorderSizePixel = 0
Info.ClipsDescendants = true
Info.Size = UDim2.new(1, 0, 1, 0)
Info.ZIndex = 2
Info.Font = Enum.Font.Ubuntu
Info.Text = "TAS Files"
Info.TextColor3 = Color3.fromRGB(255, 255, 255)
Info.TextScaled = true
Info.TextSize = 14.000
Info.TextStrokeTransparency = 0.650
Info.TextWrapped = true

Subtle_Shading.Name = "Subtle_Shading"
Subtle_Shading.Parent = Title
Subtle_Shading.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Subtle_Shading.BackgroundTransparency = 1.000
Subtle_Shading.BorderSizePixel = 0
Subtle_Shading.Size = UDim2.new(1, 1, 1, 1)
Subtle_Shading.Image = "rbxassetid://156579757"
Subtle_Shading.ImageTransparency = 0.650

Fade_2.Name = "Fade"
Fade_2.Parent = TASes
Fade_2.AnchorPoint = Vector2.new(1, 0)
Fade_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Fade_2.BackgroundTransparency = 1.000
Fade_2.Position = UDim2.new(1, 0, 0, 0)
Fade_2.Rotation = 180.000
Fade_2.Size = UDim2.new(0.025, 0, 1.14999998, 0)
Fade_2.Image = "rbxassetid://1463504275"
Fade_2.ImageColor3 = Color3.fromRGB(0, 0, 0)
Fade_2.ImageTransparency = 0.500

DropShadow.Name = "DropShadow"
DropShadow.Parent = tasmainGui.Content
DropShadow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
DropShadow.BackgroundTransparency = 1.000
DropShadow.Position = UDim2.new(0, 0, 1, 0)
DropShadow.Size = UDim2.new(1, 0, -0.025, 0)
DropShadow.ZIndex = 2
DropShadow.Image = "rbxassetid://156579757"
DropShadow.ImageTransparency = 0.500

local ButtonsFolder = Instance.new("Folder", tasmainGui)
ButtonsFolder.Name = "ButtonsFolder"

tasmainGui.Title:Destroy()

tasmainGui.Close.Size = UDim2.new(0.205, 0, 0.098, 0)
tasmainGui.Close.MouseButton1Click:Connect(function()
  if TASoptionSelected == "None" then
      alert("TAS Tools Disabled!", Color3.new(0, 0.65, 1))
  elseif TASoptionSelected == "Create" then
      alert("Play Map To Create TAS!", Color3.new(0, 0.65, 1))
  elseif TASselected == nil then
    alert("No TAS File Selected!", Color3.new(1, 0.5, 0))
  else
    -- prevent getting xp using tas
    if #game.Players:GetPlayers() >= 4 and TASoptionSelected == "Play" then
      alert("Please play a TAS in a server with less than 4 players", Color3.new(1 ,0 ,0))
      resetTasButtonSelected()
      return
    end

    if prevTASselected ~= TASselected then
      parseBinaryFile()
      prevTASselected = TASselected
    end

    if TASoptionSelected == "Play" then
      alert("Loaded " .. TASselected .. "!", Color3.new(0, 0.65, 1))
    elseif TASoptionSelected == "Edit" then
      alert("Editing " .. TASselected .. "!", Color3.new(0, 0.65, 1))
    end
  end
end)


local buttonsAction = {
  "Create",
  "Play",
  "Edit",
  "None"
}

for i,btn in ipairs(buttonsAction) do
  local button = Instance.new("TextButton")
  button.Name = btn
  if btn == TASoptionSelected then
    button.BackgroundColor3 = Color3.fromRGB(88, 98, 98)
    ButtonSelected = button
  else
    button.BackgroundColor3 = Color3.fromRGB(127, 140, 141)
  end
  button.BorderSizePixel = 0
  button.ClipsDescendants = true
  button.Position = UDim2.new(0.2 * i, 0, 0.9, 0)
  button.Size = UDim2.new(0.2, 0, 0.097, 1)
  button.ZIndex = 2
  button.AutoButtonColor = false
  button.Font = Enum.Font.Ubuntu
  button.Text = btn
  button.TextColor3 = Color3.fromRGB(255, 255, 255)
  button.TextScaled = true
  button.TextSize = 14
  button.TextStrokeTransparency = 0.65
  button.TextWrapped = true
  button.Parent = ButtonsFolder

  button.MouseButton1Click:Connect(function()
    ButtonSelected.BackgroundColor3 = Color3.fromRGB(127, 140, 141)
    button.BackgroundColor3 = Color3.fromRGB(88, 98, 98)
    ButtonSelected = button
    TASoptionSelected = btn
	end)
end

local function createButton(proname)
	local proLabel = Instance.new("TextButton", TASFilesList)
  proLabel.Name = proname
	proLabel.Text = proname
	proLabel.Font = "Ubuntu"
	proLabel.TextColor3 = Color3.fromRGB(255,255,255)
	proLabel.TextScaled = true
	proLabel.BorderSizePixel = 0
	proLabel.TextStrokeTransparency = 0.65

	proLabel.MouseButton1Click:Connect(function()
    if tasButtonSelected ~= nil then
        tasButtonSelected.TextColor3 = Color3.fromRGB(255,255,255)
    end
    if tasButtonSelected ~= proLabel then
      tasButtonSelected = proLabel
      proLabel.TextColor3 = Color3.fromRGB(0, 255, 34)
      TASselected = proname
    else
      tasButtonSelected = nil
      TASselected = nil
    end
	end)

	NoFiles.Visible = false
end

-- auto refresh tas list
local currentTasFiles = {}
task.spawn(function()
  while true do
    local newFiles = {}
    local changedList = false
    for _, file in ipairs(listfiles(tasFolder)) do
      local filesplit = file:split("\\")[2]:split(".")
      if filesplit[2] == tasFileExt then
        table.insert(newFiles, filesplit[1]) -- remove useless parts of filename
      end
    end

    for i = #currentTasFiles, 1, -1 do
      local oldFile = currentTasFiles[i]

      if not table.find(newFiles, oldFile) then
        TASFilesList[oldFile]:Destroy() -- delete from list if not in files anymore
        table.remove(currentTasFiles, i)
        changedList = true

        if oldFile == TASselected then
          tasButtonSelected = nil
          TASselected = nil
        end
      end
    end

    for _, newFile in ipairs(newFiles) do
      if not table.find(currentTasFiles, newFile) then
        createButton(newFile) -- add to list if not in list already
        table.insert(currentTasFiles, newFile)
        changedList = true
      end
    end

    if changedList then -- sort gui
      local alternateColorId = 0
      table.sort(currentTasFiles, function(a, b) -- sort in alphabetical order
        return string.lower(a) < string.lower(b)
      end)

      for order, file in ipairs(currentTasFiles) do
        local rowgui = TASFilesList[file]
        if rowgui:IsA("TextButton") then
          rowgui.LayoutOrder = order

          alternateColorId += 1
          if alternateColorId % 2 == 0 then rowgui.BackgroundColor3 = Color3.fromRGB(127, 140, 141)  -- alternating colors
          else                              rowgui.BackgroundColor3 = Color3.fromRGB(88, 98, 98) end
        end
      end
    end

    task.wait(2)
  end
end)

--------------
-- CHANGE KEYBINDS IN OPTIONS GUI
--------------

local rowHeight = 0.0855
local keybindButtonDeselectWait = 5 -- wait to deselect keybind button if no keys pressed
local ButtonsPath = lp.PlayerGui.MenuGui.Options.Categories.Content

local TAS = Instance.new("ScrollingFrame", ButtonsPath.Parent.Parent.Pages)
TAS.Name = "TAS"
TAS.BackgroundTransparency = 1
TAS.Size = UDim2.new(1, 0, 1, 0)
TAS.CanvasSize = UDim2.new(0, 0, 1.05, 0)
TAS.Visible = false
TAS.ScrollBarThickness = 15
TAS.AutomaticCanvasSize = Enum.AutomaticSize.Y

local rowTemplate = Instance.new("TextButton")
rowTemplate.BackgroundTransparency = 1
rowTemplate.Size = UDim2.new(1, 0, rowHeight, 0)
rowTemplate.ZIndex = 10
rowTemplate.AutoButtonColor = false
rowTemplate.Font = Enum.Font.Ubuntu
rowTemplate.Text = ""
rowTemplate.TextSize = 14

local textTemplate = Instance.new("TextLabel")
textTemplate.Name = "OptionName"
textTemplate.AnchorPoint = Vector2.new(0, 0.5)
textTemplate.BackgroundTransparency = 1
textTemplate.Position = UDim2.new(0.025, 0, 0.5, 0)
textTemplate.Size = UDim2.new(0.45, 0, 0.85, 0)
textTemplate.Font = Enum.Font.Ubuntu
textTemplate.TextColor3 = Color3.fromRGB(255, 255, 255)
textTemplate.TextScaled = true
textTemplate.TextSize = 14
textTemplate.TextStrokeTransparency = 0.65
textTemplate.TextWrapped = true
textTemplate.TextXAlignment = Enum.TextXAlignment.Left

local buttonTemplate = Instance.new("TextLabel")
buttonTemplate.Name = "Status"
buttonTemplate.BackgroundColor3 = Color3.fromRGB(41, 128, 185)
buttonTemplate.BorderSizePixel = 0
buttonTemplate.Position = UDim2.new(0.525, 0, 0.125, 0)
buttonTemplate.Size = UDim2.new(0.45, 0, 0.75, 0)
buttonTemplate.Font = Enum.Font.Ubuntu
buttonTemplate.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonTemplate.TextScaled = true
buttonTemplate.TextSize = 14
buttonTemplate.TextStrokeTransparency = 0.65
buttonTemplate.TextWrapped = true

local shadingTemplate = Instance.new("ImageLabel")
shadingTemplate.Name = "Subtle_Shading"
shadingTemplate.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shadingTemplate.BackgroundTransparency = 1.000
shadingTemplate.BorderSizePixel = 0
shadingTemplate.Size = UDim2.new(1, 0, 1, 0)
shadingTemplate.ZIndex = 2
shadingTemplate.Image = "rbxassetid://156579757"
shadingTemplate.ImageTransparency = 0.750


local rowCount = 0
local selectedBtn = nil
local lastKeybindButtonPress = nil

local function keybindCorrections(keybind, key)
  if keybind == "CollideToggle" then
    key = key .. " + LeftClick"
  end
  return key
end

for _, name in pairs(keybindGuiOrder) do
  local keybind = keybinds[name]

	local row = rowTemplate:Clone()
	row.Name = keybind.text
	row.Position = UDim2.new(0, 0, rowHeight * rowCount, 0)
	row.Parent = TAS

	local text = textTemplate:Clone()
	text.Text = keybind.text
	text.Parent = row

	local button = buttonTemplate:Clone()
	button.Text = keybindCorrections(name, keybind.key)
	button.Parent = row

	local shading = shadingTemplate:Clone()
	shading.Parent = button

	rowCount += 1

	row.MouseButton1Click:Connect(function()
		if selectedBtn ~= nil then
      if name == selectedBtn.keybind then return end -- dont do anything if button is already selected
			TAS[selectedBtn.gui.text].Status.Text = selectedBtn.gui.key -- visually deselect button
		end

		button.Text = "..."
		selectedBtn = { name = name, gui = keybind }

    lastKeybindButtonPress = os.clock()
    local thisButtonPress = lastKeybindButtonPress

    task.wait(keybindButtonDeselectWait)

    if lastKeybindButtonPress == thisButtonPress then
      TAS[selectedBtn.gui.text].Status.Text = selectedBtn.gui.key
      selectedBtn = nil
    end

	end)
end

UIS.InputBegan:Connect(function(e, processed)
  if processed then return end

  if e.UserInputType == Enum.UserInputType.Keyboard and selectedBtn ~= nil then
    local key = e.KeyCode.Name
    local keyVisual = keybindCorrections(selectedBtn.name, key)

    alert("Set " .. selectedBtn.name .. " to " .. keyVisual, Color3.new(0.35, 0.9, 0), 0.5)
    TAS[selectedBtn.gui.text].Status.Text = keyVisual
    keybinds[selectedBtn.name].key = key
    saveSettings()
    selectedBtn = nil
  end
end)

ButtonsPath.Main.Size = UDim2.new(0.334, 0,1, 0)
ButtonsPath.Keybinds.Size = UDim2.new(0.334, 0,1, 0)
ButtonsPath.Keybinds.Position = UDim2.new(0.334, 0,0, 0)

local TASKeybinds = ButtonsPath.Main:Clone()
TASKeybinds.Text = "TAS"
TASKeybinds.Name = "TASKeybinds"
TASKeybinds.Parent = ButtonsPath
TASKeybinds.Position = UDim2.new(0.668,0,0,0)

TASKeybinds.MouseButton1Click:Connect(function()
  ButtonsPath.Parent.Parent.Pages.TAS.Visible = true
  ButtonsPath.Parent.Parent.Pages.Main.Visible = false
  ButtonsPath.Parent.Parent.Pages.Keybinds.Visible = false
  ButtonsPath.TASKeybinds.BackgroundColor3 = Color3.fromRGB(127, 140, 141)
  ButtonsPath.Keybinds.BackgroundColor3 = Color3.fromRGB(64, 70, 70)
  ButtonsPath.Main.BackgroundColor3 = Color3.fromRGB(64, 70, 70)
end)



saveSettings = function()
  local settings = { keybinds = {} }

  for key,val in pairs(keybinds) do
    settings.keybinds[key] = val.key
  end

  writefile(tasFolder .. "/settings.json", Http:JSONEncode(settings))
end

alert("Lexian TAS Tools Loaded!", "rainbow", 3)

while true do
  -- WAIT FOR PLAYER TO BE INGAME
  repeat task.wait(.1) until game:GetService("ReplicatedStorage").Remote.UpdateGameState.OnClientEvent:Wait() == "ingame"

  tasMap = workspace.Multiplayer.Map
  start = tasMap:FindFirstChild("Spawn", true).CFrame * CFrame.new(0,3,0)

  if TASoptionSelected == "Play" then
    playTas()
  end

  repeat task.wait() until hum.WalkSpeed ~= 0

  if TASoptionSelected == "Create" then
    createTas()
  elseif TASoptionSelected == "Edit" then
    prevTASselected = nil -- not a great solution but fixes repeating the fix position function
    for i,v in ipairs(currentTasData) do
      for key, val in pairs(v) do
        if key == "CFrame" or key == "camCFrame" then
          currentTasData[i][key] = start:ToWorldSpace(val) -- fix positions
        end
      end
    end

    createTas(true)
  end

  resetTasButtonSelected()
end
