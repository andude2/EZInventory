local M = {}

function M.extractCharacterName(name)
    if not name or name == "" then return name end
    local charName = name
    if name:find("_") then
        local parts = {}
        for part in name:gmatch("[^_]+") do
            table.insert(parts, part)
        end
        charName = parts[#parts] or name
    end
    charName = charName:gsub("%s*[%`’']s [Cc]orpse%d*$", "")
    if charName and #charName > 0 then
        return charName:sub(1, 1):upper() .. charName:sub(2):lower()
    end
    return charName
end

function M.normalizeChar(name)
    return (name and name ~= "") and (name:sub(1, 1):upper() .. name:sub(2):lower()) or name
end

return M
