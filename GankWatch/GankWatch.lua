-- GankWatch -- alert when any friend logs on.
-- Detection is 100% friends-list based (works cross-faction on this server),
-- so it is localization-proof: no chat-string parsing, just online-state diffing.

-- Repeat offenders from the HC death feed (>=2 confirmed PvP kills).
-- Add them all with:  /gankwatch seed
local SEED = {
  "Greenmachine", "Noxus", "Matthew", "Aranor", "Baddecisions", "Agoodzug",
  "Onvacation", "Negligence", "Indulgence", "Mosqueito", "Bortyjoe", "Imprudence",
  "Babykittins", "Eveningkillr", "Manaenjoyer", "Bigkobold", "Vwvwvvwwv",
  "Happybritt", "Smoggle", "Abominatiion",
}

local online = {}          -- [lowercase name] = true when last seen online
local initialized = false  -- suppress alerts for whoever is already online at login
local poll = 0             -- OnUpdate accumulator (seconds)
local POLL_EVERY = 30      -- re-request the friends list this often (safety net)

local function Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[GankWatch]|r " .. text)
end

local function Alert(name, level, class, area)
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

  local banner = "!! " .. name .. " HAS LOGGED ON !!"
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, banner, ChatTypeInfo["RAID_WARNING"])
  end
  UIErrorsFrame:AddMessage(name .. " has logged on!", 1.0, 0.1, 0.1, 1.0)
  Print("|cffffff00" .. name .. " has logged on!|r " .. detail)

  PlaySound("RaidWarning")
  PlaySound("igQuestFailed")
end

local function Scan()
  local n = GetNumFriends()
  local i = 1
  while i <= n do
    local name, level, class, area, connected = GetFriendInfo(i)
    if name then
      local key = string.lower(name)
      if connected then
        if initialized and not online[key] then
          Alert(name, level, class, area)
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

local f = CreateFrame("Frame", "GankWatchFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("FRIENDLIST_UPDATE")

f:SetScript("OnEvent", function()
  if event == "FRIENDLIST_UPDATE" then
    Scan()
  else -- PLAYER_LOGIN / PLAYER_ENTERING_WORLD
    ShowFriends() -- asks the server for a fresh list -> fires FRIENDLIST_UPDATE
  end
end)

f:SetScript("OnUpdate", function()
  poll = poll + arg1
  if poll >= POLL_EVERY then
    poll = 0
    ShowFriends()
  end
end)

SLASH_GANKWATCH1 = "/gankwatch"
SLASH_GANKWATCH2 = "/gkw"
SlashCmdList["GANKWATCH"] = function(text)
  local _, _, cmd, rest = string.find(text, "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")

  if cmd == "seed" then
    local c = 0
    local i = 1
    while i <= table.getn(SEED) do
      AddFriend(SEED[i])
      c = c + 1
      i = i + 1
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
    Print(n .. " on watch:")
    local i = 1
    while i <= n do
      local name, level, class, area, connected = GetFriendInfo(i)
      if name then
        Print((connected and "|cff20ff20[ON]|r " or "|cff808080[off]|r ") .. name)
      end
      i = i + 1
    end

  elseif cmd == "test" then
    Alert("Testdummy", 27, "Rogue", "Durotar")

  else
    Print("Usage: /gankwatch seed | add <name> | remove <name> | list | test")
  end
end

Print("loaded. /gankwatch seed to add the known gankers, /gankwatch test to preview an alert.")
