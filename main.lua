-- Daily Challenge: the date is the seed. Everyone who starts a new game today gets the same shuffled chests
-- (the Solo Randomizer's fill.lua and data, bundled here) and the same two rules. Finishing gives a result code.

local S, P, G = cleria.settings, cleria.player, cleria.game
local fill = require("fill")

local enabled = S.get("Enabled", true)         -- a new game is today's challenge
local day_override = S.get("Day", "")          -- "2026-10-13" to replay a past day; empty = today (UTC)

local RULES = {   -- key, name, text
    {"glass", "Glass Cannon", "Double ATK, half max HP."},
    {"brutal", "Brutal", "Monsters and bosses hit 50% harder."},
    {"vampire", "Vampire", "Recovery Drops heal nothing; each kill heals 3% of your max HP."},
    {"midas", "Midas", "Every drop turns to gold."},
    {"famine", "Famine", "Monsters drop nothing."},
    {"scholar", "Scholar", "50% more EXP."},
}
local RULE = {}
for _, r in ipairs(RULES) do RULE[r[1]] = r end
local CHARS = {"yunica", "hugo", "toal"}
local NAMES = {"Yunica", "Hugo", "Toal"}

local function hash(text)                      -- FNV-1a, 32 bits
    local h = 2166136261
    for i = 1, #text do h = ((h ~ text:byte(i)) * 16777619) & 0xFFFFFFFF end
    return h
end
local function today() return day_override ~= "" and day_override or os.date("!%Y-%m-%d", math.floor(cleria.unix_time())) end
local function rules_of(day)                   -- two different rules; Midas and Famine never together
    local h = hash("rules " .. day)
    local a = h % #RULES + 1
    local b = (h >> 8) % (#RULES - 1) + 1
    if b >= a then b = b + 1 end
    local ka, kb = RULES[a][1], RULES[b][1]
    if (ka == "midas" and kb == "famine") or (ka == "famine" and kb == "midas") then kb = "scholar" end
    return {ka, kb}
end

-- This game's challenge, kept with the save: {day, rules = {k, k}, layout = {chest = {old, new}}, deaths, ticks, done}
local run, pending = nil, nil
local function has(key) return run ~= nil and (run.rules[1] == key or run.rules[2] == key) end
local function keep() if run and cleria.save.ready() then cleria.save.set("daily", run) end end
local function apply_stats()
    if not G.in_game() then return end
    P.set_modifier("atk", 0, has("glass") and 2 or 1)
    P.set_modifier("max_hp", 0, has("glass") and 0.5 or 1)
end

local data_cache = {}
local function data_for(char)
    if not data_cache[char] then data_cache[char] = cleria.json.decode(cleria.read("data/" .. char .. ".json")) end
    return data_cache[char]
end

local carry, carry_ticks = nil, 0              -- a death count carried over the continue's reload (see the README)
cleria.events.on("new_game", function()
    run, carry = nil, nil
    apply_stats()
    if not enabled then return end
    local day = today()
    pending = {day = day, data = data_for(CHARS[G.character()] or "hugo"), attempt = 0}
end)
cleria.events.on("load", function()
    pending = nil
    local t = cleria.save.get("daily")
    local saved = type(t) == "table" and type(t.rules) == "table" and type(t.layout) == "table" and t or nil
    -- A continue after a death reloads the save's storage as it was at the last snapshot: in the first room that
    -- is before the challenge was made. This session's challenge is then the one to keep.
    if carry and run and (not saved or saved.day == run.day) then
        run.deaths = math.max(run.deaths or 0, carry)
        keep()
    else
        run = saved
    end
    carry = nil
    apply_stats()
end)
cleria.events.on("death", function()
    if not run then return end
    run.deaths = (run.deaths or 0) + 1
    carry, carry_ticks = run.deaths, 0
    keep()
end)

local function clock(ticks)
    local s = ticks // 60
    return string.format("%d:%02d:%02d", s // 3600, s // 60 % 60, s % 60)
end
local function result_code()
    local who = NAMES[G.character()] or "?"
    local body = string.format("%s %s %s %dd", run.day, who, clock(run.ticks), run.deaths)
    return "YSO-DAILY " .. body .. string.format(" #%04X", hash("ys origin daily " .. body) & 0xFFFF)
end

cleria.events.on("tick", function()
    if pending and cleria.save.ready() then                          -- one layout try per tick
        local p = pending
        p.attempt = p.attempt + 1
        local placed = fill.try(p.data, "daily-" .. p.day, p.attempt)
        if placed or p.attempt >= 200 then
            pending = nil
            local layout = {}
            for i, it in pairs(placed or {}) do layout[p.data.locs[i].chest] = {old = p.data.locs[i].id, new = it.id} end
            run = {day = p.day, rules = rules_of(p.day), layout = layout, deaths = 0, ticks = 0}
            keep()
            apply_stats()
            local text = p.day .. ": " .. RULE[run.rules[1]][2] .. " + " .. RULE[run.rules[2]][2]
            cleria.notice(text .. ". Finish the game for your result code.", "Daily Challenge")
            cleria.log("challenge " .. text)
        end
    end
    if not run or not G.in_game() then return end
    if not G.frozen() and not run.done then run.ticks = run.ticks + 1 end
    if run.ticks % 60 == 0 then keep() end
    if carry and P.hp() > 0 then
        carry_ticks = carry_ticks + 1
        if carry_ticks > 120 then carry = nil end
    end
end)

cleria.events.on("boss_defeated", function(e)
    if not run or run.done then return end
    if not ((e.flag == 226 and G.character() ~= 3) or e.flag == 227) then return end
    run.done = true
    run.code = result_code()
    keep()
    cleria.data.write("results.txt", (cleria.data.read("results.txt") or "") .. run.code .. "\n")
    cleria.notice(run.code, "Daily Challenge complete")
    cleria.log("result " .. run.code)
end)

-- ---- the rules ---------------------------------------------------------------------------------------------------
cleria.combat.add_filter("damage", function(q)
    if has("brutal") and q.dir == "taken" and q.value > 0 then return math.floor(q.value * 1.5 + 0.5) end
end)
cleria.combat.add_filter("exp", function(q) if has("scholar") then return q.value * 1.5 end end)
cleria.combat.add_filter("pickup", function(q) if has("vampire") and q.what == "hp" then return "suppress" end end)
cleria.combat.add_filter("drop", function(q)
    if has("famine") then return "suppress" end
    if has("midas") then return {action = "replace", item = 0x78, value = 5 * math.max(q.level or 1, 1)} end
end)
cleria.events.on("enemy_killed", function()
    if not has("vampire") then return end
    local hp, max = P.hp(), P.max_hp()
    if hp > 0 and hp < max then P.set_hp(math.min(max, hp + math.max(1, math.floor(max * 0.03 + 0.5)))) end
end)

-- ---- the chests (as in the Solo Randomizer) ------------------------------------------------------------------------
cleria.content.add_filter(function(q)
    if not run or q.script == "" then return nil end
    local c = run.layout[q.room .. "/" .. q.script:upper()]
    if not c or c.new == c.old or q.index ~= c.old then return nil end
    if q.kind == "store" then
        if q.value <= math.max(q.old, 0) then return nil end
        cleria.content.give(c.new, 1, "daily")
        return "suppress"
    end
    if q.kind == "icon" then return {action = "replace", index = c.new} end
    if q.kind == "window" then
        return {action = "replace", index = c.new, text = cleria.content.treasure_text(q.text, G.item_name(c.new), 1)}
    end
end)

-- ---- what you see --------------------------------------------------------------------------------------------------
cleria.hud.layer("daily", function(d)
    if not run or not G.in_game() then return end
    local s = d.scale
    local text = "Daily " .. run.day .. "  -  " .. RULE[run.rules[1]][2] .. "  -  " .. RULE[run.rules[2]][2] ..
                 "  -  " .. clock(run.ticks) .. "  -  " .. run.deaths .. (run.deaths == 1 and " death" or " deaths")
    local w = d:text_size(text, {size = 18 * s, font = "cond_medium"})
    d:rect(14 * s, 14 * s, w + 24 * s, 32 * s, {color = 0x100F0B, alpha = 0.7, rounding = 4 * s})
    d:text(26 * s, 20 * s, text, {size = 18 * s, color = run.done and "good" or "gold", font = "cond_medium"})
end)

cleria.ui.page("Daily Challenge", function(p)
    local day = today()
    local r = rules_of(day)
    p:section("Today")
    p:info("Challenge", day, "The date in UTC. It changes at midnight UTC for everyone.")
    p:info(RULE[r[1]][2], "", RULE[r[1]][3])
    p:info(RULE[r[2]][2], "", RULE[r[2]][3])
    p:info("Chests", "shuffled", "The same layout for everyone who plays the same character today. Always beatable.")
    local v, ch = p:toggle("New games are the challenge", enabled, "Off: a new game is an ordinary one.")
    if ch then enabled = v S.set("Enabled", v) end
    v, ch = p:text_field("Another day", day_override, {desc = "A date like 2026-10-13 to play that day's challenge. Empty = today.", empty = "(today)"})
    if ch then day_override = v S.set("Day", v) end
    p:section("This game")
    if run then
        p:info("Day", run.day, RULE[run.rules[1]][2] .. " + " .. RULE[run.rules[2]][2])
        p:info("Time", clock(run.ticks), "Cutscenes and text boxes do not count.")
        p:info("Deaths", tostring(run.deaths))
        p:info("Result", run.code or "not finished", {color = run.done and "good" or "muted", desc = "Share this line. It is also in modsdata/4rtefakt.daily/results.txt."})
    else
        p:info("Not a challenge", "", "Start a new game to play today's.")
    end
end)

cleria.speedrun.modification(function() return "Daily Challenge" .. (run and (" " .. run.day) or "") end)
cleria.command("daily", function(a)
    if a == "rules" then for _, d in ipairs({"2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"}) do cleria.log(d .. " " .. table.concat(rules_of(d), "+")) end return end
    local n = 0
    for _ in pairs(run and run.layout or {}) do n = n + 1 end
    local st = P.stats()
    cleria.log(string.format("day %s rules %s chests %d deaths %d atk %g hp %.0f/%.0f code %s", run and run.day or "-",
                             run and table.concat(run.rules, "+") or "-", n, run and run.deaths or 0, st.atk, st.hp, st.max_hp, run and run.code or "-"))
end)
cleria.log("Daily Challenge loaded: " .. today())
