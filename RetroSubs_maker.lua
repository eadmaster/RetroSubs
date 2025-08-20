
-- RetroSubs maker lua script by eadmaster
-- https://github.com/eadmaster/RetroSubs/

-- script for quick retrosubs creation
-- press this hotkey
local SCREENSHOT_HOTKEY = "S"
-- to capture a screenshot in this dir:
local SCREENSHOT_BASE_PATH = "/tmp/r/"
-- then perform OCR and add a new table entry
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
    table.insert(lines, line)
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

-- create UI
local xform, yform, delta_x, delta_y = 0, 4, 120, 20
-- forms.newform([int? width = nil], [int? height = nil], [string title = nil], [nluafunc onclose = nil])
local main_window = forms.newform()
label = forms.label(main_window, "editing ".. filename, xform, yform)
forms.setproperty(label, "AutoSize", true)
yform = yform + delta_y
-- forms.textbox(long formhandle, [string caption = nil], [int? width = nil], [int? height = nil], [string boxtype = nil], [int? x = nil], [int? y = nil], [bool multiline = False], [bool fixedwidth = False], [string scrollbars = nil])
textbox = forms.textbox(main_window, "text translation", nil, nil, nil, xform, yform, True)
forms.setproperty(textbox, "AutoSize", true)
yform = yform + delta_y
btn = forms.button(main_window, "Add line", add_table_line, xform, yform)
forms.setproperty(btn, "AutoSize", true)


function add_table_line()
        
        last_update = emu.framecount()
        
        if not fields[1] or not fields[2] or not fields[3] then
                print("invalid last table entry. Update and reload the script manually")
                return
        end
        
        region = fields[1]
        start = tonumber(fields[2], 16)
        len = tonumber(fields[3], 16)
        curr_hash = get_memory_hash(region, start, len)

        if not curr_hash then
                print("invalid last table entry. Update and reload the script manually")
                return
        end
        
        print("ocring...")
        
        -- add new hash
        fields[4] = curr_hash
        print(curr_hash)

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
        
        -- TODO: translate
        fields[#fields-1] = forms.gettext(textbox)
        --fields[#fields-1] = " ... " 
        --fields[#fields-1] = "New English text here<br>Another line?" 

        -- reconstruct the row
        local newLine = "|"
        for i, f in ipairs(fields) do
            newLine = newLine .. f .. "|"
        end

        -- append to file
        local file = io.open(filename, "a")
        file:write("\n" .. newLine)
        file:close()

        print("Added new row:")
        print(newLine)
end


-- main loop
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
    local pressed_keys = input.get()
    if pressed_keys["S"] then  -- TODO: debounce?
        add_table_line()
    end
    
	emu.frameadvance();
end  -- while

