
-- RetroSubs lua script by eadmaster
-- https://github.com/eadmaster/RetroSubs/


function detect_emu()
    if client and type(client.getversion) == "userdata" then
        return "bizhawk"
    else
        return nil
    end
end

CURRENT_EMU = detect_emu()

function parse_csv(filename)
    local entries = {}
    local file = io.open(filename, "r")
    if not file then
        print("not found: ", filename)
        return nil
    end
    
    -- Read header
    local header = file:read("*l")
    
    for line in file:lines() do
        -- Skip empty lines and comment lines
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        
        -- Parse current line
        --local region, start, len, hash, text = line:match("^([^,]+),([^,]+),([^,]+),([^,]+),(.+)$")
        local region, start, len, hash,
              x_pos, y_pos, width_box, height_box,
              fg_color, bg_color, text = line:match(
          "^([^,]+),([^,]+),([^,]+),([^,]+)," ..
          "(.-),(.-),(.-),(.-),(.-),(.-)," ..
          "(.+)$"
        )
        
        -- Check required fields
        if not (region and start and len and hash and text) then
            print("Missing required fields in line (skipped): ", line)
            goto continue
        end
        
        table.insert(entries, {
            region     = region,
            start      = tonumber(start, 16),
            len        = tonumber(len, 16),
            hash       = hash,
            text       = text,
            x_pos      = tonumber(x_pos) or nil,
            y_pos      = tonumber(y_pos) or nil,
            height_box = tonumber(height_box) or nil,
            width_box  = tonumber(width_box) or nil,
            fg_color   = fg_color ~= "" and fg_color or nil,
            bg_color   = bg_color ~= "" and bg_color or nil,
        })
        
        ::continue::
    end

    file:close()
    
    print("loaded: ", filename)
    
    return entries
end


function get_memory_hash(region, start, len)
    if start < 0 or len <= 0 then
        print("invalid memory region", start, len)
        return ""
    end
    -- else

    -- bizhawk/retroarch
    -- TODO: catch exceptions
    local hash = memory.hash_region(start, len, region)
    return hash
end


function clear_text()
    -- bizhawk
    gui.cleartext()
    gui.clearGraphics()
end


function show_text(entry)
    --local height = client.bufferheight()
    --local width = client.bufferwidth()  -- TODO: center by default
    local x_pos = entry.x_pos or 10  -- default: upper-left corner
    local y_pos = entry.y_pos or 10  -- default: upper-left corner
    local bg_color = entry.bg_color or 0xFF000000  -- default: black (0xAARRGGBB)
    local fg_color = entry.fg_color or 0xFFFFFFFF  -- default: white
    local height_box = entry.height_box -- optional
    local width_box = entry.width_box -- optional
    
    --print("X:", x_pos)
    --print("Y:", y_pos)
    --print("Height:", height_box)
    --print("Width:", width_box)
    --print("FG:", fg_color)
    --print("BG:", bg_color)
    
    if (height_box and width_box and height_box > 0 and width_box > 0) then
        -- gui.drawRectangle(int x, int y, int width, int height, [luacolor line = nil], [luacolor background = nil], [string surfacename = nil])
        gui.drawRectangle(x_pos, y_pos, width_box, height_box, bg_color, bg_color);
    end
    
    -- Split text into lines using \n
    local line_count = 0
    local text = entry.text:gsub("\\n", "\n")
    for line in text:gmatch("[^\r\n]+") do
        print(line)
        
        -- bizhawk
        -- gui.drawString(int x, int y, string message, [luacolor forecolor = nil], [luacolor backcolor = nil], [int? fontsize = nil], [string fontfamily = nil], [string fontstyle = nil], [string horizalign = nil], [string vertalign = nil], [string surfacename = nil])
        local curr_y_pos = y_pos + line_count*12
        if (height_box and width_box and height_box > 0 and width_box > 0) then
            gui.drawString(x_pos, curr_y_pos, line, fg_color , nil, nil, "Arial")
        else
            gui.drawString(x_pos, curr_y_pos, line, fg_color, bg_color, nil, "Arial")
        end
        --gui.text(x_pos + 10, curr_y_pos + 10, line, nil, "topleft" )
        
        line_count = line_count + 1
    end
end

-- main
local data = parse_csv("RetroSubs/" .. gameinfo.getromname() .. ".csv")
local curr_hash = ""
local CPU_SAVER_INTERVAL = 100
local prev_entry = nil
local prev_hash = nil
local prev_text = nil
local last_update = emu.framecount()
local no_match = true

while true do

    -- check precond
    if not CURRENT_EMU == "bizhawk" then
        print("Unsupported emulator: " .. CURRENT_EMU)
        break
    end
    if not data then
        -- retry to load the CSV
        -- data = parse_csv("RetroSubs/" .. gameinfo.getromname() .. ".csv")
        -- exit script
        break
    end
    
	-- CPU SAVER
	if (emu.framecount() - last_update) > CPU_SAVER_INTERVAL  then
        
        last_update = emu.framecount()
        no_match = true
        prev_entry = nil
        prev_hash = nil
        
        for i, entry in ipairs(data) do
            --print(string.format("Region: %s, Start: 0x%X, Len: 0x%X, Hash: %s, Text: %s", entry.region, entry.start, entry.len, entry.hash, entry.text))
            
            -- skip repeated regions
            if prev_entry and prev_hash and prev_entry.region == entry.region and prev_entry.start == entry.start and prev_entry.len == entry.len then
                -- same memory region, reuse prev_hash
                curr_hash = prev_hash
                --print("reuse hash")
            else
                curr_hash = get_memory_hash(entry.region, entry.start, entry.len)
                print(string.format("hashed %X", entry.start), "= ", curr_hash)
            end
        
            -- copies for the next iteration
            prev_entry = entry
            prev_hash = curr_hash          
            
            -- check current hash
            if curr_hash == entry.hash then
                --if prev_text and entry.text ~= prev_text then
                    clear_text()
                    -- TODO: handle pos_x, pos_y, fg_color, bg_color
                    show_text(entry)
                    no_match = false
                    prev_text = entry.text
                --end
                break
            end
        end
        
        if no_match then
            clear_text()
        end
        
    end

	emu.frameadvance();
end






