--  RetroSubs - Subtitles for retro games.
--  Copyright (C) 2025 - eadmaster
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


-- script for quick retrosubs creation

-- user settings:
--local SCREENSHOT_HOTKEY = "S"
local SCREENSHOT_BASE_PATH = "/tmp/r/"
local OCR_CMD="easyocr --lang ja --detail 0 --paragraph 1 --file "
--local OCR_CMD="tesseract "shot.png" stdout -l jpn_vert+jpn+eng --psm 5 --oem 1"


function get_memory_hash(region, start, len)
    if not start or not len or start < 0 or len <= 0 then
        print("invalid memory region", start, len)
        return ""
    end
    -- else

    -- bizhawk/retroarch
    -- TODO: catch exceptions
    local hash = memory.hash_region(start, len, region)
    return hash
end


local filename = "RetroSubs/" .. gameinfo.getromname() .. ".retrosub"

-- read all lines
local lines = {}
for line in io.lines(filename) do
    -- skip empty lines, code blocks, and comments
    if line ~= "" and line:find("#") ~= 1 and not line:find(";") ~= 1 and not line:find("`") ~= 1 then
        table.insert(lines, line)
    end
end

-- get last line
local lastLine = lines[#lines]
if not lastLine then
    print("File is empty!")
    return
end

-- split by "|"
local fields = {}
for field in lastLine:gmatch("([^|]+)") do
    table.insert(fields, field:match("^%s*(.-)%s*$")) -- trim spaces
end


local curr_hash = ""
local CPU_SAVER_INTERVAL = 100
local last_update = emu.framecount()

local field_names = { "region", "start", "len", "hash", "x_pos", "y_pos", "width_box", "height_box", "font_size", "fg_color", "bg_color", "text", "jap_text" }
local textboxes = {}

function gui_update_from_model()
        for i, fname in ipairs(field_names) do
            local tb = textboxes[i]
            forms.settext(tb, fields[i])
        end
end

function gui_write_to_model()
        for i, fname in ipairs(field_names) do
            local tb = textboxes[i]
            fields[i] = forms.gettext(tb)
        end
end

function gui_destroyall()
        forms.destroyall()
end


function gui_init()
        local xform, yform, delta_x, delta_y = 0, 4, 120, 20
        -- forms.newform([int? width = nil], [int? height = nil], [string title = nil], [nluafunc onclose = nil])
        local main_window = forms.newform(400, 700, "RetroSubs Maker", destroyall)

        label = forms.label(main_window, "editing ".. filename, xform, yform)
        forms.setproperty(label, "AutoSize", true)
        yform = yform + delta_y
        -- forms.textbox(long formhandle, [string caption = nil], [int? width = nil], [int? height = nil], [string boxtype = nil], [int? x = nil], [int? y = nil], [bool multiline = False], [bool fixedwidth = False], [string scrollbars = nil])
        --textbox = forms.textbox(main_window, "text translation", nil, nil, nil, xform, yform, True)
        --forms.setproperty(textbox, "AutoSize", true)
        --yform = yform + delta_y

        -- Loop through field_names and create label + textbox for each
        for i, fname in ipairs(field_names) do
            -- Label
            local lbl = forms.label(main_window, fname, xform, yform)
            forms.setproperty(lbl, "AutoSize", true)
            yform = yform + delta_y

            -- Textbox initialized from fields[i]
            local multiline = (fname == "text" or fname == "jap_text")
            local tb = forms.textbox(main_window, fields[i] or "", 200, multiline and 40 or 20, nil, xform, yform, multiline, false)
            textboxes[i] = tb
            yform = yform + delta_y
            if multiline then
                yform = yform + delta_y
            end
        end

        btn = forms.button(main_window, "Clear overlay", clear_overlay, xform, yform)
        forms.setproperty(btn, "AutoSize", true)
        yform = yform + delta_y
        
        btn = forms.button(main_window, "Draw overlay", draw_overlay, xform, yform)
        forms.setproperty(btn, "AutoSize", true)
        yform = yform + delta_y
        
        --btn = forms.button(main_window, "Try OCR", try_ocr, xform, yform)
        --forms.setproperty(btn, "AutoSize", true)
        --yform = yform + delta_y
        
        btn = forms.button(main_window, "Copy to clipboard", copy_table_line, xform, yform)
        forms.setproperty(btn, "AutoSize", true)
        yform = yform + delta_y
        
        btn = forms.button(main_window, "Append to file", add_table_line, xform, yform)
        forms.setproperty(btn, "AutoSize", true)
        
end


function clear_overlay()
        gui.clearGraphics()
end


function draw_overlay()
    gui_write_to_model()
        
    local x_pos = tonumber(fields[5])
    local y_pos = tonumber(fields[6])
    local width_box = tonumber(fields[7])
    local height_box = tonumber(fields[8])
    local font_size = tonumber(fields[9])
    local fg_color = fields[10]
    local bg_color = fields[11]
    local text = fields[12]
    local font_face = "Arial" -- optional
    
    if (height_box and width_box and height_box > 0 and width_box > 0) then
        -- gui.drawRectangle(int x, int y, int width, int height, [luacolor line = nil], [luacolor background = nil], [string surfacename = nil])
        gui.drawRectangle(x_pos, y_pos, width_box, height_box, bg_color, bg_color);
    end
    
    -- Split text into lines using <br>
    local line_count = 0
    for line in (text .. "<br>"):gmatch("([^<]+)<br>") do
        --console.log(line)
        
        if line then
            -- bizhawk
            -- gui.drawString(int x, int y, string message, [luacolor forecolor = nil], [luacolor backcolor = nil], [int? fontsize = nil], [string fontfamily = nil], [string fontstyle = nil], [string horizalign = nil], [string vertalign = nil], [string surfacename = nil])
            local curr_y_pos = y_pos + line_count*12
            if (height_box and width_box and height_box > 0 and width_box > 0) then
                gui.drawString(x_pos, curr_y_pos, line, fg_color , nil, font_size, font_face)
            else
                gui.drawString(x_pos, curr_y_pos, line, fg_color, bg_color, font_size, font_face)
            end
            --gui.text(x_pos + 10, curr_y_pos + 10, line, nil, "topleft" )
        end
        
        line_count = line_count + 1
    end
end


function try_ocr()
        gui.addmessage("ocring...")

        last_update = emu.framecount()
        
        -- save a screenshot
        last_shot_path = SCREENSHOT_BASE_PATH .. last_update .. ".png"
        client.screenshot(last_shot_path)
        -- TODO: ocr and translate
        -- run tesseract OCR on shot.png and get output
        
        local handle = io.popen(OCR_CMD .. last_shot_path)
        local ocr_result = handle:read("*a")
        handle:close()

        -- remove trailing newline if needed
        --ocr_result = ocr_result:gsub("%s+$", "")
        -- replace all remaining newlines with <br>
        ocr_result = ocr_result:gsub("\n", "<br>")

        -- change last column with jap text
        fields[#fields] = ocr_result
        
        gui_update_from_model()
        
        -- TODO: translate
        --fields[#fields-1] = forms.gettext(textbox)
        --fields[#fields-1] = " ... " 
        --fields[#fields-1] = "New English text here<br>Another line?" 
end


function get_new_table_line()
        gui_write_to_model()
        
        if not fields[1] or not fields[2] or not fields[3] then
                print("invalid last table entry. Update and reload the script manually")
                gui.addmessage("invalid last table entry. Update and reload the script manually")
                return ""
        end
        
        region = fields[1]
        start = tonumber(fields[2], 16)
        len = tonumber(fields[3], 16)
        
        -- check empty fields
        if region == "" or start == nil or len == nil then
            --msg_dialog("memory region field empty")
            gui.addmessage("ERROR: empty memory region field")
            return ""
        end

        curr_hash = get_memory_hash(region, start, len)

        if not curr_hash then
                print("invalid last table entry. Update and reload the script manually")
                gui.addmessage("invalid last table entry. Update and reload the script manually")
                return ""
        end
       
        -- add new hash
        fields[4] = curr_hash
        print(curr_hash)

        -- reconstruct the row
        local newLine = "|"
        for i, f in ipairs(fields) do
            newLine = newLine .. f .. "|"
        end

        --print("new row:")
        --print(newLine)

        -- clean current text
        fields[12] = ""  -- text
        fields[13] = ""  -- jap_text
        
        gui_update_from_model()

        return newLine
end


function copy_table_line()
    newLine = get_new_table_line()

    -- copy to clipboard
    if newLine then
        io.popen('pbcopy','w'):write(newLine):close()
    end
end

function add_table_line()
    newLine = get_new_table_line()
    
    -- append to file
    local file = io.open(filename, "a")
    file:write("\n" .. newLine)
    file:close()
end


-- main loop
gui_init()

while true do
    
    -- check precond
    if not CURRENT_EMU == "bizhawk" then
        print("Unsupported emulator: " .. CURRENT_EMU)
        break
    end
    if not fields then
        -- retry to load
        -- parsed_markdown = parse_csv("RetroSubs/" .. gameinfo.getromname() .. ".retrosub")
        -- exit script
        break
    end
    
    -- CPU SAVER
	--if (emu.framecount() - last_update) > CPU_SAVER_INTERVAL  then
    --local pressed_keys = input.get()
    --if pressed_keys[SCREENSHOT_HOTKEY] then  -- TODO: debounce?
    --    copy_table_line()
    --end
    
	emu.frameadvance();
end  -- while

