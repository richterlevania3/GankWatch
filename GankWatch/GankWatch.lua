-- GankWatch -- friend-login alerts + Horde-in-your-zone /who scanner.
--
-- Two independent features:
--  1) Friend watch: alerts when any friends-list player logs on (cross-faction).
--  2) Zone scan: every 30s runs /who on your CURRENT zone, filtered by Horde
--     race, and warns about any enemy players present. On this server /who is
--     cross-faction, but a bare zone query may only return your own side, so we
--     query one Horde race at a time (which is confirmed to return Horde) and
--     rotate through all four each cycle.

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

-- Repeat offenders from the HC death feed (>=2 confirmed PvP kills).  /gankwatch seed
local SEED = {
  "Greenmachine", "Noxus", "Matthew", "Aranor", "Baddecisions", "Agoodzug",
  "Onvacation", "Negligence", "Indulgence", "Mosqueito", "Bortyjoe", "Imprudence",
  "Babykittins", "Eveningkillr", "Manaenjoyer", "Bigkobold", "Vwvwvvwwv",
  "Happybritt", "Smoggle", "Abominatiion",
}

-- Races counted as Horde (lowercase). Edit if your server has custom races.
local HORDE_RACES = { orc = true, troll = true, tauren = true, undead = true }
-- The race filters sent to /who each cycle (proper case, as /who expects).
local RACE_QUEUE = { "Orc", "Troll", "Tauren", "Undead" }

local FRIEND_POLL_EVERY = 60   -- re-request the friends list this often (s)
local WHO_EVERY         = 90   -- full zone scan interval (s) -- raised from 30 to cut /who stutter
local STEP_GAP          = 1.5  -- min delay between the per-race /who sends (s)
local STEP_TIMEOUT      = 3    -- give up waiting on one race's result after this (s)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local online = {}          -- friend watch: [lowercase name] = true when last online
local initialized = false  -- suppress friend alerts for whoever is already on at login
local friendPoll = 0

local whoEnabled = true
local cycleAccum = 0       -- toward WHO_EVERY
local scanning   = false
local waitingWho = false
local stepIndex  = 0
local stepSentAt = 0
local stepDoneAt = 0
local currentZone = ""
local present   = {}       -- horde found this scan: [name] = {level,class,race}
local seenHorde = {}       -- horde present last completed scan (for diffing)
local inCombat  = false    -- pause /who + friend polling in combat (stutter guard)

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

local function Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[GankWatch]|r " .. text)
end

local function FriendAlert(name, level, class, area)
  local detail = ""
  if level and level ~= 0 then detail = "Lvl " .. level end
  if class and class ~= "" then
    if detail ~= "" then detail = detail .. " " end
    detail = detail .. class
  end
  if area and area ~= "" then
    if detail ~= "" then detail = detail .. " - " end
    detail = detail .. area
  end

  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, "!! " .. name .. " HAS LOGGED ON !!", ChatTypeInfo["RAID_WARNING"])
  end
  UIErrorsFrame:AddMessage(name .. " has logged on!", 1.0, 0.1, 0.1, 1.0)
  Print("|cffffff00" .. name .. " has logged on!|r " .. detail)
  PlaySound("RaidWarning")
  PlaySound("igQuestFailed")
end

-- ---------------------------------------------------------------------------
-- Friend watch
-- ---------------------------------------------------------------------------

local function FriendScan()
  local n = GetNumFriends()
  local i = 1
  while i <= n do
    local name, level, class, area, connected = GetFriendInfo(i)
    if name then
      local key = string.lower(name)
      if connected then
        if initialized and not online[key] then
          FriendAlert(name, level, class, area)
        end
        online[key] = true
      else
        online[key] = false
      end
    end
    i = i + 1
  end
  initialized = true
end

-- ---------------------------------------------------------------------------
-- Zone /who scanner
-- ---------------------------------------------------------------------------

local function WhoAlert(names)
  local count = table.getn(names)
  local banner = "HORDE IN " .. string.upper(currentZone) .. "!  (" .. count .. ")"
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, banner, ChatTypeInfo["RAID_WARNING"])
  end
  UIErrorsFrame:AddMessage("Horde in " .. currentZone .. "!", 1.0, 0.1, 0.1, 1.0)
  local i = 1
  while i <= count do
    local nm = names[i]
    local info = present[nm]
    local d = ""
    if info then
      d = " (Lvl " .. (info.level or "?") .. " " .. (info.race or "") .. " " .. (info.class or "") .. ")"
    end
    Print("|cffff2020HORDE|r " .. nm .. d .. " - " .. currentZone)
    i = i + 1
  end
  PlaySound("RaidWarning")
  PlaySound("igQuestFailed")
end

local function AbortScan()
  scanning = false
  waitingWho = false
end

local function FinishScan()
  scanning = false
  local me = UnitName("player")
  local newcomers = {}
  for name in pairs(present) do
    if name ~= me and not seenHorde[name] then
      table.insert(newcomers, name)
    end
  end
  seenHorde = present
  if table.getn(newcomers) > 0 then WhoAlert(newcomers) end
end

local function SendNextRace()
  stepIndex = stepIndex + 1
  if stepIndex > table.getn(RACE_QUEUE) then
    FinishScan()
    return
  end
  waitingWho = true
  stepSentAt = GetTime()
  SendWho('z-"' .. currentZone .. '" r-"' .. RACE_QUEUE[stepIndex] .. '"')
end

local function StartScan()
  local zone = GetRealZoneText()
  if not zone or zone == "" then return false end -- not ready; retry next tick
  currentZone = zone
  present = {}
  stepIndex = 0
  scanning = true
  waitingWho = false
  stepDoneAt = 0
  -- NOTE: do NOT call SetWhoToUI(1) -- that routes results to the Who UI and
  -- pops the window open. A bare SendWho() delivers results to the API silently.
  SendNextRace()
  return true
end

local function WhoResult()
  if not scanning or not waitingWho then return end
  local num = GetNumWhoResults()
  local i = 1
  while i <= num do
    local name, guild, level, race, class = GetWhoInfo(i)
    if name and race and HORDE_RACES[string.lower(race)] then
      present[name] = { level = level, class = class, race = race }
    end
    i = i + 1
  end
  waitingWho = false
  stepDoneAt = GetTime()
end

local function ResetZone()
  if scanning then AbortScan() end
  seenHorde = {}
  present = {}
  cycleAccum = WHO_EVERY - 4 -- scan ~4s after the zone settles
end

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

local f = CreateFrame("Frame", "GankWatchFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("WHO_LIST_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entering combat
f:RegisterEvent("PLAYER_REGEN_ENABLED")    -- leaving combat

f:SetScript("OnEvent", function()
  if event == "FRIENDLIST_UPDATE" then
    FriendScan()
  elseif event == "WHO_LIST_UPDATE" then
    WhoResult()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    ResetZone()
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    if scanning then AbortScan() end       -- stop any scan the moment combat starts
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
  else -- PLAYER_LOGIN / PLAYER_ENTERING_WORLD
    ShowFriends()
    ResetZone()
  end
end)

f:SetScript("OnUpdate", function()
  -- pause all periodic network churn while in combat (micro-stutter guard).
  -- Friend-login alerts still fire via FRIENDLIST_UPDATE server pushes in OnEvent.
  if inCombat then return end

  -- friend list poll
  friendPoll = friendPoll + arg1
  if friendPoll >= FRIEND_POLL_EVERY then
    friendPoll = 0
    ShowFriends()
  end

  -- zone /who scanner
  if not whoEnabled then return end
  if not scanning then
    cycleAccum = cycleAccum + arg1
    if cycleAccum >= WHO_EVERY then
      if StartScan() then cycleAccum = 0 end
    end
  else
    if waitingWho then
      if GetTime() >= stepSentAt + STEP_TIMEOUT then
        waitingWho = false
        stepDoneAt = GetTime()
      end
    elseif GetTime() >= stepDoneAt + STEP_GAP then
      SendNextRace()
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_GANKWATCH1 = "/gankwatch"
SLASH_GANKWATCH2 = "/gkw"
SlashCmdList["GANKWATCH"] = function(text)
  local _, _, cmd, rest = string.find(text, "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")

  if cmd == "seed" then
    local c = 0
    local i = 1
    while i <= table.getn(SEED) do
      AddFriend(SEED[i]); c = c + 1; i = i + 1
    end
    Print("Added " .. c .. " known gankers to your friends list.")
    ShowFriends()

  elseif cmd == "add" and rest ~= "" then
    AddFriend(rest)
    Print("Watching " .. rest .. " (added to friends).")

  elseif cmd == "remove" and rest ~= "" then
    RemoveFriend(rest)
    online[string.lower(rest)] = nil
    Print("Stopped watching " .. rest .. " (removed from friends).")

  elseif cmd == "list" then
    ShowFriends()
    local n = GetNumFriends()
    Print(n .. " on friend-watch:")
    local i = 1
    while i <= n do
      local name, level, class, area, connected = GetFriendInfo(i)
      if name then
        Print((connected and "|cff20ff20[ON]|r " or "|cff808080[off]|r ") .. name)
      end
      i = i + 1
    end

  elseif cmd == "who" then
    whoEnabled = not whoEnabled
    if not whoEnabled and scanning then AbortScan() end
    Print("Zone Horde scan " .. (whoEnabled and "|cff20ff20ON|r" or "|cffff2020OFF|r") .. ".")

  elseif cmd == "scan" then
    if not whoEnabled then Print("Zone scan is off (/gankwatch who to enable)."); return end
    if scanning then Print("Already scanning."); return end
    seenHorde = {} -- force alerts for everyone found on a manual scan
    if StartScan() then Print("Scanning " .. currentZone .. " for Horde...") else Print("Zone not ready, try again.") end

  elseif cmd == "test" then
    FriendAlert("Testdummy", 27, "Rogue", "Durotar")

  else
    Print("Usage: /gankwatch seed | add <name> | remove <name> | list | who (toggle zone scan) | scan (now) | test")
  end
end

Print("loaded. Friend-watch + Horde zone scan (every " .. WHO_EVERY .. "s) active. /gankwatch for commands.")
