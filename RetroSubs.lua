--  RetroSubs - Subtitles for retro games.
--  Copyright (C) 2025-2026 - eadmaster
--  https://github.com/eadmaster/RetroSubs/
-- 
--  RetroSubs is free software: you can redistribute it and/or modify it under the terms
--  of the GNU General Public License as published by the Free Software Found-
--  ation, either version 3 of the License, or (at your option) any later version.
--
--  RetroSubs is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
--  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
--  PURPOSE.  See the GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License along with RetroSubs.
--  If not, see <http://www.gnu.org/licenses/>.


DEBUG_RETROSUB = false
DEBUG_MAX_LINE_LEN=37

function detect_emu()
    if gameinfo and type(gameinfo.getrompath) == "function" then  -- TODO: better detection
        return "retroarch"
    elseif client and type(client.getversion) == "userdata" then
        return "bizhawk"
    elseif fba then
        return "fba"
    --TODO: fceu
    --elseif emu and type(emu.app_name) == "function" and emu.app_name() == "mame" then
    --    return "mame"
    else
        return nil
    end
end

function detect_content()
    if CURRENT_EMU == "bizhawk" or CURRENT_EMU == "retroarch"  then
        return gameinfo.getromname()
    elseif CURRENT_EMU == "fba" then
        --CURRENT_CONTENT = fba.romname()) -- internal name: e.g. "pce_momoktsg"
        return fba.gamename() -- extended name: e.g. "Momotarou Katsugeki (Japan)"
    end
    return ""
end

function message(msg)
    if CURRENT_EMU == "bizhawk" or CURRENT_EMU == "retroarch"  then
        gui.addmessage(msg)
    elseif CURRENT_EMU == "fba" then
        fba.message(msg)
    end
end


-- Helper to safely convert the C-table to a Lua string in 5.1
local function bytes_to_string(byte_table)
    local unpack_func = unpack or table.unpack
    -- Lua has a limit on the number of arguments (stack size).
    -- If the memory region is large, we must use a loop.
    if #byte_table < 2000 then
        return string.char(unpack_func(byte_table))
    else
        local parts = {}
        for i = 1, #byte_table do
            parts[i] = string.char(byte_table[i])
        end
        return table.concat(parts)
    end
end


function hash_region(start, len, region)
    if CURRENT_EMU == "bizhawk" or CURRENT_EMU == "retroarch"  then
        return memory.hash_region(start, len, region)
    else
        -- compute sha256 using external lib
        
        local byte_table = memory.readbyterange(start, len)
        local binary_data = bytes_to_string(byte_table)
        local sha2 = require("sha2")
        h = sha2.sha256(binary_data)
        --print(h)
        return(h:upper())
        --return sha2.sha256(binary_data)
    end
end


CURRENT_EMU = detect_emu()
CURRENT_CONTENT = detect_content()


local function trim(s)
    --if CURRENT_EMU == "bizhawk" or CURRENT_EMU == "retroarch"  then
    --    s = bizstring.trim(s)
    --    if not s then s="" end
    --    return s
    --else
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Safely split markdown row into columns, even if it lacks final pipe or has empty columns
local function split_markdown_row(line)
    local cols = {}
    for col in line:gmatch("|?([^|]*)") do
        if col ~= "" or #cols > 0 then
            table.insert(cols, col)
        end
    end
    return cols
end


function parse_markdown_multi_tables(filename)
    local entries = {}

    local required_cols = { "region", "start", "len", "hash", "text" }
    local optional_cols = { "x_pos", "y_pos", "fg_color", "bg_color", "width_box", "height_box", "font_size", "font_face" }

    local file = io.open(filename, "r")
    if not file then
        --print("not found: ", filename)
        return nil
    else
        print("found: ", filename)
        message("RetroSub loaded")
    end

    local header_map = nil
    local header_found = false

    for line in file:lines() do
        line = trim(line)
        
        repeat
            
            -- Skip empty lines or comments
            if line == "" or line:match("^%s*[#;]") then
                header_found = false
                break
            end

            -- Detect Lua code block start
            if line:match("^%s*```lua") and _VERSION ~= "Lua 5.1" then
                executing_lua = true
                lua_lines = {}
                break
            end
                
            -- If inside a Lua block, collect lines
            if executing_lua then
                if line:match("^%s*```") then
                    -- End of Lua block, execute code
                    local code = table.concat(lua_lines, "\n")
                    local fn, err = load(code)
                    if fn then
                        local ok, result = pcall(fn)
                        if not ok then
                            print("Error executing Lua block:", result)
                        end
                    else
                        print("Error compiling Lua block:", err)
                    end
                    executing_lua = false
                else
                    table.insert(lua_lines, line)
                end
                break
            end
                
            -- Detect header line
            if not header_found and line:match("^|") then
                local raw_cols = split_markdown_row(line)
                local cols = {}
                for _, col in ipairs(raw_cols) do
                    cols[#cols + 1] = trim(col):lower()
                end

                -- Check if required columns exist
                local map = {}
                for i, c in ipairs(cols) do
                    map[c] = i
                end

                local has_all_required = true
                for _, c in ipairs(required_cols) do
                    if not map[c] then
                        has_all_required = false
                        break
                    end
                end

                if has_all_required then
                    header_map = map
                    header_found = true
                    break
                end
            end

            -- Skip separator line under header
            if header_found and line:match("^|%s*[-]+") then
                break
            end

            -- Parse data row when header found
            if header_found then
                if not line:match("^|") then
                    -- End of this table, reset for next table
                    header_found = false
                    header_map = nil
                    break
                end

                local cols = split_markdown_row(line)
                for i, col in ipairs(cols) do
                    --cols[i] = trim(col)
                    cols[i] = col
                end

                -- Skip row if fewer columns than header
                if #cols < #header_map then
                    print("Warning: skipping malformed row: " .. line)
                    break
                end

                -- Extract required fields
                local function getcol(name)
                    return cols[header_map[name]]
                end
                
                local region = getcol("region")
                local start  = getcol("start")
                local len    = getcol("len")
                local hash   = getcol("hash")
                local text   = getcol("text")

                if not (region and start and len and hash and text and tonumber(start, 16) and tonumber(len, 16)) then
                    console.log("Warning: skipping incomplete row: " .. line)
                    break
                end
                
                -- check valid region
                if not memory.usememorydomain(region) then
                    console.log("warning: memory domain not available in current core (skipped): " .. region)
                    break
                end
                
                local curr_entry = {
                    region = region,
                    start  = start,
                    len    = len,
                    hash   = hash,
                    text   = text,
                }
                
                --if DEBUG_RETROSUB then
                --    check_long_line(text) 
                --end

                for _, name in ipairs(optional_cols) do
                    if header_map[name] then
                        local val = getcol(name) or nil
                        if name == "x_pos" or name == "y_pos" or name == "width_box" or name == "height_box" or name == "font_size" then
                            val = tonumber(val) -- returns nil if not valid
                        end
                        curr_entry[name] = val
                    end
                end
                
                local key1 = region .. ":" .. start .. ":" .. len
                entries[key1] = entries[key1] or {}
                
                -- check if duplicate
                if DEBUG_RETROSUB and entries[key1][hash] ~= nil then
                    console.log("warning: duplicate hash found (prev line overwritten): " .. hash)
                end
                
                entries[key1][hash] = curr_entry
            end

        until true
    end

    file:close()
    return entries
end


function get_memory_hash(region, start, len)
    if not start or not len or start < 0 or len <= 0 then
        console.log("invalid memory region", start, len)
        return ""
    end
    -- else

    -- bizhawk/retroarch
    -- TODO: catch exceptions
    local hash = hash_region(start, len, region)
    return hash
end


function clear_text()
    if CURRENT_EMU == "bizhawk" or CURRENT_EMU == "retroarch"  then
        gui.cleartext()
        gui.clearGraphics()
    elseif CURRENT_EMU == "fba" then
        gui.clearuncommitted()
    end
end


function check_long_line(text)
    for line in (text .. "<br>"):gmatch("([^<]+)<br>") do
        if line then
            if (line:len() >= DEBUG_MAX_LINE_LEN) then
                console.log("long line: ", line)
            end
        end
    end
end

function show_text(entry)
    --print(entry.text)
    
    --local height = client.bufferheight()
    --local width = client.bufferwidth()  -- TODO: center by default
    local x_pos = entry.x_pos or 10  -- default: upper-left corner
    local y_pos = entry.y_pos or 10  -- default: upper-left corner
    local bg_color = entry.bg_color or "black"  -- default: black (0xAARRGGBB)
    local fg_color = entry.fg_color or "white"  -- default: white
    local height_box = entry.height_box -- optional
    local width_box = entry.width_box -- optional
    local font_size = entry.font_size or 12  -- optional  -- client.getconfig().FontSize 
    local font_face = entry.font_face or "Arial" -- optional
    local TEXTBOX_PADDING = 2
    local LINE_SPACING = font_size
    
    -- different defaults for retroarch
    if CURRENT_EMU == "retroarch" then
        font_size = 32 + (font_size - 12)  -- * scaling_factor
        font_face = ""
        -- inverted color defaults
        bg_color = entry.bg_color or "white"
        fg_color = entry.fg_color or "black"
        clear_text()
    end
    
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
    
    -- Split text into lines using <br>
    local line_count = 0
    for line in (entry.text .. "<br>"):gmatch("([^<]+)<br>") do
        --console.log(line)
    
        --line_with_tags = line
        --line = line:gsub("<[^>]*>", "")
        --console.log(line)
        
        if line then
        
            -- check more tags
            if (line:find("clear>") ~= nil) then
                clear_text()
                if DEBUG_RETROSUB then
                    console.log("debug: <clear> triggered")
                end
                return
            --if (line:find("clear-on-input>") ~= nil) then
            --    while true do
            --        if input.get() then
            --            break
            --        end
            --        emu.frameadvance();
            --    end
            --    clear_text()
            --    return
            --elseif line:match("^sleep(=%d+)?%>$") then
            --    duration = tonumber(line:match("^sleep=(%d+)>")) or 60
            elseif (line == "sleep>") then
                duration = 60  -- 1 sec
                timer_start = emu.framecount()
                if DEBUG_RETROSUB then
                    console.log("debug: <sleep> triggered")
                end
                while (emu.framecount() - timer_start < duration) do
                    --console.log(emu.framecount() - timer_start)
                    emu.frameadvance();
                end
            elseif (line:find("lua>") ~= nil) then
                code = line:match("lua>(.*)")
                --code = line:match("^lua>(.*)$")
                if code then
                    if DEBUG_RETROSUB then
                        console.log("inline lua code: " .. code)
                    end
                    local fn, err = load(code, "inline_lua")
                    if not fn then
                        console.log("Lua error: " .. err)
                    else
                        pcall(fn)
                    end
                end
            else
                -- draw current line
                -- gui.drawString(int x, int y, string message, [luacolor forecolor = nil], [luacolor backcolor = nil], [int? fontsize = nil], [string fontfamily = nil], [string fontstyle = nil], [string horizalign = nil], [string vertalign = nil], [string surfacename = nil])
                local curr_y_pos = y_pos + line_count * LINE_SPACING
                if (height_box and width_box and height_box > 0 and width_box > 0) then
                    gui.drawString(x_pos + TEXTBOX_PADDING, curr_y_pos, line, fg_color , nil, font_size, font_face)
                else
                    gui.drawString(x_pos + TEXTBOX_PADDING, curr_y_pos, line, fg_color, bg_color, font_size, font_face)
                end
                --gui.text(x_pos + 10, curr_y_pos + 10, line, nil, "topleft" )
            end
        end
        
        line_count = line_count + 1
    end
end



-- main
local parsed_markdown = parse_markdown_multi_tables("RetroSubs/" .. CURRENT_CONTENT .. ".retrosub")
if parsed_markdown == nil then
    -- try to load from content dir
    local curr_rom_path = ""
    
    if gameinfo and type(gameinfo.getrompath) == "function" then 
        curr_rom_path = gameinfo.getrompath()  -- retroarch-only
    end
    
    if client then
        local config = client.getconfig()    -- bizhawk-only
        if config.RecentRoms and config.RecentRoms[0] then
            curr_rom_path = config.RecentRoms[0]
            curr_rom_path = curr_rom_path:gsub("%*OpenRom%*", "")
        end
    end
    
    if curr_rom_path then
        curr_rom_path = curr_rom_path:gsub("%.[^%.]+$", ".retrosub") -- Replace the extension
        parsed_markdown = parse_markdown_multi_tables(curr_rom_path)
    end
    
    if parsed_markdown == nil then
        console.log("parsing failed or retrosub file not found: " .. curr_rom_path)
        return
    end
end

local curr_hash = ""
local CPU_SAVER_INTERVAL = 50
local curr_visible_text_list = {}
local prev_visible_text_list = {}
local last_update = emu.framecount()
local no_match = true

while true do
    
    -- check precond
    --if not CURRENT_EMU == "bizhawk" then
    --    print("Unsupported emulator")
    --    break
    --end
    if not parsed_markdown then
        -- retry to load
        -- parsed_markdown = parse_csv("RetroSubs/" .. gameinfo.getromname() .. ".retrosub")
        -- exit script
        break
    end
    
    -- CPU SAVER
	if (emu.framecount() - last_update) > CPU_SAVER_INTERVAL  then

        last_update = emu.framecount()
        no_match = true
        curr_visible_text_list = {} -- new empty table

        -- iterate over the memory regions to check
        for key, group in pairs(parsed_markdown) do
            --print("Group:", key)
            
            -- compute the hash
            local region, start, len = key:match("^(.-):([^:]+):([^:]+)$")
            -- convert strings->int
            start = tonumber(start, 16)
            len = tonumber(len, 16)
            curr_hash = get_memory_hash(region, start, len)
            if curr_hash ~= "" then
                -- print("hashed ", key, "= ", curr_hash)
                
                -- check if the hash is in any table
                if group[curr_hash] ~= nil then
                    
                    local entry = group[curr_hash]
                    curr_visible_text_list[entry.text] = true
                    no_match = false
                    
                    -- avoid redrawing the same text multiple times
                    if not prev_visible_text_list[entry.text] then
                    
                        --print("drawn:")
                        --    print("  Hash:", curr_hash)
                        --    print("    Text:", entry.text)
                        --    print("    Pos:", entry.x_pos or "nil", entry.y_pos or "nil")
                        --    print("    Colors:", entry.fg_color or "nil", entry.bg_color or "nil")

                        show_text(entry)
                    end
                end
            end
        end  -- end for

        prev_visible_text_list = curr_visible_text_list
        
        if no_match then
            --print("clear all")
            prev_visible_text_list = {}
            clear_text()
        end
    end

	emu.frameadvance();
end
