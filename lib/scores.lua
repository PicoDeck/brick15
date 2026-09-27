-- scores.lua — high scores, read from the SD card once at startup and
-- written back only when a record is beaten. Slots are "hi_<game id>".

local Scores = {}
Scores.__index = Scores

-- save: picocalc.game.save (or a stub); games: list of { id = ... }.
function Scores.new(save, games)
    local s = setmetatable({ save = save, cache = {} }, Scores)
    for _, g in ipairs(games) do
        local rec = save.get("hi_" .. g.id)
        local v = type(rec) == "table" and rec.v or nil
        -- 0 means "no record" ("low" games need that); anything that isn't a
        -- positive number is a damaged slot and is treated the same way.
        if type(v) ~= "number" or v <= 0 then v = nil end
        s.cache[g.id] = v
    end
    return s
end

-- The record, or nil if there is none yet.
function Scores:get(id)
    return self.cache[id]
end

-- order: "high" (default, bigger is better) or "low" (fewer is better).
-- Returns true, and saves, only when value beats the record.
function Scores:submit(id, value, order)
    if not value or value <= 0 then return false end
    local best = self.cache[id]
    local better
    if order == "low" then
        better = best == nil or value < best
    else
        better = best == nil or value > best
    end
    if better then
        self.cache[id] = value
        self.save.set("hi_" .. id, { v = value })
    end
    return better
end

return Scores
