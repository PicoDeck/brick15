-- loader.lua — multi-file module loading (require/dofile are blocked on PicoDeck)

local fs = picocalc.fs

local function load_module(name)
    local path = APP_DIR .. "/" .. name .. ".lua"
    local handle = fs.open(path, "r")
    if not handle then
        error("Cannot open module: " .. path)
    end
    local chunks = {}
    while true do
        local chunk = fs.read(handle, 4096)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    fs.close(handle)
    return load(table.concat(chunks), "@" .. name .. ".lua")()
end

return load_module
