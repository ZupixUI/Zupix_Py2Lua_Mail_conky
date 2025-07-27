--[[
Zupix_Py2Lua_Mail_conky
Copyright © 2025 Zupix

License: GPL v3+
]]

--#####################################################
--#         CONFIGURATION – ONLY HERE                #
--#####################################################

local script_path = debug.getinfo(1, "S").source:match("@(.*/)")
package.path = package.path .. ";" .. script_path .. "?.lua"

-- Debugging and global flags
SHOW_PNG_ERROR_LABEL = true   -- show error label on widget if PNG is unavailable
SHOW_LOGIN_ERRORS = true      -- show login error messages (true/false)
SHOW_DEBUG_BORDER = false     -- debug border (red border around conky)
SHOW_WAV_ERROR_LABEL = true   -- show error label on widget if WAV is unavailable

ACCOUNT_DEFAULT_COLOR = {1, 1, 1}  -- default account color (RGB 0-1)
ACCOUNT_COLORS = {                 -- custom account colors (mapped by account from JSON)
    ["name_1"] = {0.2, 0.5, 1},
    ["name_2"] = {1, 0.8, 0.3},
    ["name_3"] = {0, 1, 0},
}

local ACCOUNT_NAMES = {  -- Full account names to display in header
    "All accounts",
    "name_1@gmail.com",
    "name_2@gmail.com",
    "name_3@gmail.com"
}
-- Animation if scrolling reaches max.
local shake_anim_time = 0
local SHAKE_DURATION = 0.015 -- seconds (animation duration)
local prev_mail_scroll_offset = 0

local shake_sound_played = false


-- Mail block layout and directions (NEW NAMES)
local MAILS_DIRECTION = "down_right"   -- one of: up, down, up_left, up_right, down_left, down_right
local RIGHT_LAYOUT_REVERSED = false

-- Scroll mail list on demand
local MAIL_SCROLL_FILE = "/tmp/conky_mail_scroll_offset"
local SCROLL_TIMEOUT = 3.0  -- seconds before returning to position 0 after last scroll

-- Mail block parameters (positions, margins, widths)
local MAILS_MARGIN      = 24           -- general margin of mail block
local MAILS_WIDTH       = 600          -- mail block width (pixels)
local MAILS_HEIGHT      = 0            -- (for future improvements)
local MAILS_TOP_MARGIN  = 0            -- (for future improvements)
local MAILS_BOTTOM_MARGIN = 0          -- (for future improvements)
local SEPARATOR_MARGIN  = 0            -- (for future improvements)

-- Sender/preview display control
local SHOW_SENDER_EMAIL = false     -- true: show sender email, false: only name/surname
local SHOW_MAIL_PREVIEW = true      -- whether to show mail preview (2nd line)

-- Paths to image and sound files
local SHAKE_SOUND = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-eng_v1.0.0-beta1/sound/shake_2.wav"
local NEW_MAIL_SOUND = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-eng_v1.0.0-beta1/sound/nowy_mail.wav"
local ENVELOPE_IMAGE = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-eng_v1.0.0-beta1/icons/mail.png"
local ATTACHMENT_ICON_IMAGE = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-eng_v1.0.0-beta1/icons/spinacz1.png"
local MAIL_SOUND_PLAYED_FILE = "/tmp/mail_sound_played"

local ATTACHMENT_ICON_ENABLE = true      -- whether to show paperclip icon (attachment)
local ATTACHMENT_ICON_SIZE = { w = 18, h = 18 } -- paperclip size
local ATTACHMENT_ICON_OFFSET = { dx = -26, dy = -6 }  -- paperclip offset (relative to line start)
local ATTACHMENT_ICON_ANGLE = 0

-- Envelope and badge settings (icon and unread count)
local ENVELOPE_IMAGE_ANGLE = 0
local ENVELOPE_SIZE = { w = 74, h = 74 }
local BADGE_RADIUS = 12
local BADGE_POS = { dx = 41, dy = 7 }
local PREVIEW_INDENT = false -- whether preview should be indented (optional, default no)

-- Scrolling/marquee for mail preview
local ENABLE_PREVIEW_SCROLL = true
local MAX_MAIL_LINE_PIXELS = 600  -- width of scrolling area
local preview_scroll_speed = 200  -- scroll speed (higher = faster)

local PREVIEW_EXTRA_SPACE = -3    -- extra space/align at the end for *_right mirrored mode

-- Fonts and colors – global
local FROM_FONT_NAME      = "Arial"
local FROM_FONT_SIZE      = 12
local FROM_FONT_BOLD      = true
local FROM_COLOR_TYPE     = "custom"
local FROM_COLOR_CUSTOM   = {0.98, 0.145, 0.196}

local SUBJECT_FONT_NAME    = "Arial"
local SUBJECT_FONT_SIZE    = 12
local SUBJECT_FONT_BOLD    = true
local SUBJECT_COLOR_TYPE   = "white"
local SUBJECT_COLOR_CUSTOM = {0.424, 1, 0}

local PREVIEW_FONT_NAME      = "Arial"
local PREVIEW_FONT_SIZE      = 11
local PREVIEW_FONT_BOLD      = true
local PREVIEW_COLOR_TYPE     = "custom"
local PREVIEW_COLOR_CUSTOM   = {22, 217, 197}

local BADGE_COLOR_TYPE    = "red"
local BADGE_COLOR_CUSTOM  = {22, 217, 197}
local BADGE_TEXT_COLOR_TYPE   = "white"
local BADGE_TEXT_COLOR_CUSTOM = {255, 255, 0}
local BADGE_BORDER_COLOR_TYPE   = "white"
local BADGE_BORDER_COLOR_CUSTOM = {0, 255, 0}

-- Header and separator – styles and lengths
local HEADER_FONT = "Arial"
local HEADER_SIZE = 12
local HEADER_BOLD = true
local HEADER_COLOR = {1, 0, 0}
local HEADER_LINE_COLOR = {1, 1, 1}
local HEADER_LINE_WIDTH = 1.8
local HEADER_LINE_LENGTH = 450

-- Mail line heights (with/without preview)
local MAIL_LINE_HEIGHT_PREVIEW    = 40  -- height of single mail with preview
local MAIL_LINE_HEIGHT_NO_PREVIEW = 28  -- without preview

-- Variables needed for various functions. Don't change unless you know what you're doing!
local previous_mail_json_ok = true
local first_run_mail_sound = true
local first_mail_sound_played = false

--## Mail "glow" (highlight) padding/corrections ##--
MAIL_BG_PADDING_LEFT    = 10    -- left padding (affects "milk" width)
MAIL_BG_PADDING_RIGHT   = 5     -- right padding
MAIL_BG_PADDING_TOP     = 0     -- top
MAIL_BG_PADDING_BOTTOM  = 2     -- bottom
MAIL_BG_RADIUS          = 11    -- border radius for glow
MAIL_BG_ALPHA           = 0.18  -- transparency (0-1)
MAIL_BG_COLOR           = {1, 1, 1} -- glow color (white, RGB 0-1)



------------------------------------------------------------------
-- MAIN CODE & UTILITY FUNCTIONS
------------------------------------------------------------------

require 'cairo'
local json = require("dkjson")
pcall(require, 'cairo_xlib')
--------------------------------------------------------
-- Function: draw rectangle with rounded corners
--------------------------------------------------------
local function draw_rounded_rect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3*math.pi/2)
    cairo_close_path(cr)
end

--------------------------------------------------------
-- Function: Play new mail sound only at startup and on every new mail. 
--------------------------------------------------------
local function has_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function set_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "w")
    if f then
        f:write("1")
        f:close()
    end
end
--------------------------------------------------------
-- Function: smooth color blending (interpolation)
--------------------------------------------------------
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_color(color1, color2, t)
    -- color1, color2 = {r,g,b} (0-1)
    return {
        lerp(color1[1], color2[1], t),
        lerp(color1[2], color2[2], t),
        lerp(color1[3], color2[3], t)
    }
end
--------------------------------------------------------
-- Function: draw red debug border around Conky window
--------------------------------------------------------
local function draw_debug_border(cr, color, thickness)
    if not conky_window then return end
    local w = conky_window.width
    local h = conky_window.height
    color = color or {1, 0, 0}
    thickness = thickness or 2
    cairo_save(cr)
    cairo_set_line_width(cr, thickness)
    cairo_set_source_rgb(cr, color[1], color[2], color[3])
    cairo_rectangle(cr, thickness/2, thickness/2, w-thickness, h-thickness)
    cairo_stroke(cr)
    cairo_restore(cr)
end

--------------------------------------------------------
-- Utility: store previous data
--------------------------------------------------------
local previous_unread_count = nil
local last_good_mails = {}
local last_mail_json_ok = false

local MAX_MAILS = 6

--------------------------------------------------------
-- Function: get_max_mails_from_file()
--------------------------------------------------------
local function get_max_mails_from_file()
    local path = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-eng_v1.0.0-beta1/config/mail_conky_max"
    local f = io.open(path, "r")
    if f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local v = tonumber(value or "0")
        if v then return v end
    end
    return MAX_MAILS
end

--------------------------------------------------------
-- Function: get_selected_account_idx()
--------------------------------------------------------
local function get_selected_account_idx()
    local f = io.open("/tmp/conky_mail_account", "r")
    if f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local idx = tonumber(value or "0")
        if idx then return idx end
    end
    return 0
end

--------------------------------------------------------
-- Function: extract_sender_name(from)
--------------------------------------------------------
local function extract_sender_name(from)
    local name = from and from:match('^"?([^"<]+)"?%s*<[^>]+>$')
    if name then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        return name
    else
        return from or "(no sender)"
    end
end

--------------------------------------------------------
-- Function: decode_html_entities(text)
--------------------------------------------------------
local function decode_html_entities(text)
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end)
    text = text:gsub("&#x(%x+);", function(n) return utf8.char(tonumber(n, 16)) end)
    text = text:gsub("&apos;", "'")
    return text
end

--------------------------------------------------------
-- Function: clean_preview(text, line_mode)
--------------------------------------------------------
local function clean_preview(text, line_mode)
    if not text then return "" end
    text = decode_html_entities(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if
            line ~= "" and
            not line:match("^[=]{8,}$") and
            not line:match("^Wyświetl inn") and
            not line:match("^Ta wiadomość została") and
            not line:match("facebook%.com") and
            not line:match("Meta Platforms") and
            not line:match("unsubscribe") and
            not line:match("zrezygnować z subskrypcji")
        then
            table.insert(lines, line)
        end
    end
    if line_mode == "auto" or tonumber(line_mode or "0") == 0 then
        preview_lines = lines
    else
        local max_lines = tonumber(line_mode or "2") or 2
        preview_lines = {}
        for i = 1, math.min(#lines, max_lines) do
            table.insert(preview_lines, lines[i])
        end
    end
    local out = table.concat(preview_lines, " ")
    if #out > 240 then out = out:sub(1, 240) .. "..." end
    return out
end

--------------------------------------------------------
-- Function: fetch_mails_from_python()
--------------------------------------------------------
local function fetch_mails_from_python()
    local CACHE_FILE = "/tmp/mail_cache.json"
    local f = io.open(CACHE_FILE, "r")
    if not f then
        last_mail_json_ok = false
        return 0, {}
    end
    local result = f:read("*a")
    f:close()
    local data, pos, err = json.decode(result, 1, nil)
    if not data or type(data) ~= "table" then
        last_mail_json_ok = false
        return 0, {}
    end
    last_mail_json_ok = true
    return data.unread or 0, data.mails or {}
end

--------------------------------------------------------
-- Function: read_error_messages()
--------------------------------------------------------
local function read_error_messages()
    local ERR_FILE = "/tmp/mail_cache.err"
    local msgs = {}
    local f = io.open(ERR_FILE, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("%s+$", "")
            local acc = line:match("%[Account error ([^%]]+)%]")
            if acc then
                table.insert(msgs, "[Account error " .. acc .. "] Invalid login data")
            end
        end
        f:close()
    end
    return msgs
end

-- Scrolling of messages in mail block
local mail_scroll_offset = 0
local last_scroll_time = 0

local function read_mail_scroll_offset()
    local f = io.open(MAIL_SCROLL_FILE, "r")
    if f then
        local value = tonumber((f:read("*a") or "0"):match("%-?%d+")) or 0
        f:close()
        return value
    end
    return 0
end

local function write_mail_scroll_offset(offset)
    local f = io.open(MAIL_SCROLL_FILE, "w")
    if f then
        f:write(tostring(offset))
        f:close()
    end
end

local function update_mail_scroll_timeout()
    local stat = io.popen("stat -c %Y " .. MAIL_SCROLL_FILE .. " 2>/dev/null")
    local mtime = stat and tonumber(stat:read("*a"))
    stat:close()
    return mtime or 0
end


-- Simple cache of PNG surfaces (icons)
local png_surface_cache = {}

-- Function to clear cache (e.g. for manual use, not needed to call)
local function clear_png_surface_cache()
    for path, surf in pairs(png_surface_cache) do
        if type(surf) == "userdata" then
            cairo_surface_destroy(surf)
        end
    end
    png_surface_cache = {}
end

--------------------------------------------------------
-- Function: set_color(cr, type, custom)
--------------------------------------------------------
local function set_color(cr, typ, custom)
    if typ == "white" then
        cairo_set_source_rgb(cr, 1, 1, 1)
    elseif typ == "black" then
        cairo_set_source_rgb(cr, 0, 0, 0)
    elseif typ == "red" then
        cairo_set_source_rgb(cr, 1, 0, 0)
    elseif typ == "orange" then
        cairo_set_source_rgb(cr, 1, 0.55, 0)
    elseif typ == "custom" and custom then
        local r, g, b = custom[1], custom[2], custom[3]
        if r > 1 or g > 1 or b > 1 then
            r = r / 255
            g = g / 255
            b = b / 255
        end
        cairo_set_source_rgb(cr, r, g, b)
    else
        cairo_set_source_rgb(cr, 1, 1, 1)
    end
end
-------------------------------------------------------
-- Function: set_font(cr, font_name, font_size, bold)
--------------------------------------------------------
local function set_font(cr, font_name, font_size, bold)
    cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)
end
--------------------------------------------------------
-- Function: safe PNG drawing (won't crash the widget)
--------------------------------------------------------
local function draw_png_rotated_safe(cr, x, y, w, h, path, angle_deg, label)
    label = label or "PNG"
    local image = png_surface_cache[path]

    -- TRY TO LOAD to cache if not present!
    if image == nil or image == false then
        local file = io.open(path, "rb")
        if file then
            file:close()
            local ok, loaded_image = pcall(cairo_image_surface_create_from_png, path)
            if ok and loaded_image and cairo_image_surface_get_width(loaded_image) > 0 then
                if image and type(image) == "userdata" then
                    cairo_surface_destroy(image)
                end
                png_surface_cache[path] = loaded_image
                image = loaded_image
            else
                if loaded_image and type(loaded_image) == "userdata" then
                    cairo_surface_destroy(loaded_image)
                end
                png_surface_cache[path] = false
                image = false
            end
        else
            png_surface_cache[path] = false
            image = false
        end
    end

    
    if not image or image == false then
        if SHOW_PNG_ERROR_LABEL then
            local time_s = os.time()
            if (time_s % 2 == 0) then
                set_color(cr, "red")
                local font_size = (label == "spinacz" and 11 or 13)
                set_font(cr, "Arial", font_size, true)
                local dx, dy = 0, 0
                if label == "spinacz" then
                    dx, dy = -25, 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, "ERROR")
                    set_font(cr, "Arial", font_size, true)
                    cairo_move_to(cr, x + dx, y + dy + h/2 + 11)
                    cairo_show_text(cr, label)
                else
                    dx, dy = 0, 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, "ERROR")
                    set_font(cr, "Arial", font_size, true)
                    cairo_move_to(cr, x + dx, y + dy + h/2 + 14)
                    cairo_show_text(cr, label)
		-- separator under "ENVELOPE" text
		if label == "ENVELOPE" then
    	set_font(cr, "Arial", 10, false)  -- smaller, not bold
    	set_color(cr, "red")              -- you can change color if you want
    	cairo_move_to(cr, x + dx, y + dy + h/2 + 22)  -- +32px from top of envelope
    	cairo_show_text(cr, "-------------------------")
		end

                end
            end
        end
        return
    end

    -- Surface is OK: draw PNG
    local img_w = cairo_image_surface_get_width(image)
    local img_h = cairo_image_surface_get_height(image)
    cairo_save(cr)
    cairo_translate(cr, x + w/2, y + h/2)
    cairo_rotate(cr, math.rad(angle_deg or 0))
    cairo_translate(cr, -w/2, -h/2)
    cairo_scale(cr, w / img_w, h / img_h)
    cairo_set_source_surface(cr, image, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
end

--------------------------------------------------------
-- Functions: utf8_sub(s, i, j) and utf8_len(s)
--------------------------------------------------------
local function utf8_sub(s, i, j)
    local pos = 1
    local bytes = #s
    local start, end_ = nil, nil
    local k = 0
    while pos <= bytes do
        k = k + 1
        if k == i then start = pos end
        if k == (j and j + 1 or nil) then end_ = pos - 1 break end
        local c = s:byte(pos)
        if c < 0x80 then pos = pos + 1
        elseif c < 0xE0 then pos = pos + 2
        elseif c < 0xF0 then pos = pos + 3
        else pos = pos + 4 end
    end
    if start then return s:sub(start, end_ or bytes) end
    return ""
end

local function utf8_len(s)
    local _, count = s:gsub("[^\128-\193]", "")
    return count
end

--------------------------------------------------------
-- Function: trim_line_to_width()
--------------------------------------------------------
local function trim_line_to_width(cr, text, max_width)
    local ellipsis = "..."
    local trimmed = text
    while true do
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, trimmed, ext)
        if ext.width <= max_width or utf8_len(trimmed) <= #ellipsis then
            break
        end
        trimmed = utf8_sub(trimmed, 1, utf8_len(trimmed) - 1)
    end
    if trimmed ~= text then
        trimmed = utf8_sub(trimmed, 1, utf8_len(trimmed) - #ellipsis - 1) .. ellipsis
    end
    return trimmed
end


--------------------------------------------------------
-- Function: split_emoji(text)
--------------------------------------------------------
local function split_emoji(text)
    local res = {}
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c and c >= 0xF0 then
            local emoji = text:sub(i, i+3)
            table.insert(res, {emoji=true, txt=emoji})
            i = i + 4
        else
            local j = i
            while j <= len do
                local cj = text:byte(j)
                if cj and cj >= 0xF0 then break end
                j = j + 1
            end
            if j > i then
                table.insert(res, {emoji=false, txt=text:sub(i, j-1)})
            end
            i = j
        end
    end
    return res
end

--------------------------------------------------------
-- Function: get_chunks_width(cr, chunks, font_name, font_size, font_bold)
--------------------------------------------------------
local function get_chunks_width(cr, chunks, font_name, font_size, font_bold)
    local width = 0
    for _, chunk in ipairs(chunks) do
        if chunk.emoji then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, chunk.txt, ext)
        width = width + ext.x_advance
    end
    return width
end

--------------------------------------------------------
-- Function: trim_line_to_width_emoji(cr, text, max_width, ...)
--------------------------------------------------------
local function trim_line_to_width_emoji(cr, text, max_width, font_name, font_size, font_bold)
    local chunks = split_emoji(text)
    local out_chunks = {}
    local width = 0
    for i, chunk in ipairs(chunks) do
        if chunk.emoji then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, chunk.txt, ext)
        if width + ext.x_advance > max_width then
            break
        end
        table.insert(out_chunks, chunk)
        width = width + ext.x_advance
    end
    if #out_chunks < #chunks then
        table.insert(out_chunks, {emoji=false, txt="..."})
    end
    return out_chunks
end

function conky_draw_mail_indicator()
    -- Without a Conky window, we draw nothing!
    if conky_window == nil then return end

    -- Blinking for "warning/error" effect
    local time_s = os.time()
    local blink = (time_s % 2 == 0)  -- alternating true/false every second

    -- Read selected account (index)
    local selected_account_idx = get_selected_account_idx()

    -- Dynamic number of mails displayed (can be changed by file)
    local MAX_MAILS = get_max_mails_from_file()

    -- Read possible login errors (for messages)
    local error_msgs = read_error_messages()

    -- Get current mailbox state (number of unread + list of mails)
    local unread, mails = fetch_mails_from_python()

    -- Prepare an empty list (every refresh)
    last_good_mails = {}

    -- Convert each mail to a unified format
    for i, mail in ipairs(mails) do
        local from
        if SHOW_SENDER_EMAIL then
            from = mail.from or "(no sender)"
        else
            from = mail.from_name or mail.from or "(no sender)"
            from = extract_sender_name(from)
        end
        local subject = mail.subject or "(no subject)"
        local preview = mail.preview or "(no preview)"
        table.insert(last_good_mails, {
            from=from,
            subject=subject,
            preview=preview,
            has_attachment=mail.has_attachment,
            account=mail.account,
            account_idx=mail.account_idx
        })
    end

    -- --- Scroll handling for mail list (offset + timeout) ---
    local mail_scroll_offset = read_mail_scroll_offset()
    local last_offset_time = update_mail_scroll_timeout()
    local now = os.time()
    if mail_scroll_offset ~= 0 and (now - last_offset_time > SCROLL_TIMEOUT) then
        mail_scroll_offset = 0
        write_mail_scroll_offset(0)
    end

-- Play sound in two situations:
-- 1) First start of Conky with unread mail(s).
-- 2) New mail arrived.

if not has_played_start_sound() and unread > 0 then
    -- First start of Conky with unread mail(s)
    local f = io.open(NEW_MAIL_SOUND, "rb")
    if f then
        f:close()
        os.execute('paplay "' .. NEW_MAIL_SOUND .. '" &')
        set_played_start_sound()
        wav_missing_persistent = false
    else
        wav_missing_persistent = true
    end
elseif previous_mail_json_ok and last_mail_json_ok and previous_unread_count ~= nil and unread > previous_unread_count then
    -- New mail (unread count increased)
    local f = io.open(NEW_MAIL_SOUND, "rb")
    if f then
        f:close()
        os.execute('paplay "' .. NEW_MAIL_SOUND .. '" &')
        wav_missing_persistent = false
    else
        wav_missing_persistent = true
    end
end

-- State counter updates
previous_mail_json_ok = last_mail_json_ok
previous_unread_count = unread

    -- Create Cairo graphic context for Conky window
    local cs = cairo_xlib_surface_create(conky_window.display,
                                         conky_window.drawable,
                                         conky_window.visual,
                                         conky_window.width,
                                         conky_window.height)
    local cr = cairo_create(cs)

    -- Calculate height of single mail line
    local mail_line_h = SHOW_MAIL_PREVIEW and MAIL_LINE_HEIGHT_PREVIEW or MAIL_LINE_HEIGHT_NO_PREVIEW
    local mail_block_h = MAX_MAILS * mail_line_h

    -------------------------------------------------
    -- Calculate base layout positions (block starts)
    -------------------------------------------------
    local koperta_x, koperta_y, mails_x, mails_y, header_x, header_y
    local margin_x, margin_y = 16, 16
    local gap_x, gap_y = 10, 8

    -- Widget layout modes
    if MAILS_DIRECTION == "up" then
        local layout_extra_x = 50
        local koperta_extra_x = -20
        local koperta_extra_y = -30
        local header_gap = HEADER_SIZE + 10
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = margin_y + header_gap
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
        header_x = mails_x - 10
        header_y = mails_y - HEADER_SIZE - 8

    elseif MAILS_DIRECTION == "down" then
        local layout_extra_x = 55
        local extra_block_down = 32
        local extra_header_up = -16
        local extra_koperta_up = -40
        local koperta_extra_left = -22
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - 10 + extra_block_down
        header_x = mails_x - 10
        header_y = mails_y + mail_block_h + HEADER_SIZE + 4 + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up

    elseif MAILS_DIRECTION == "up_left" then
        local mails_extra_x, mails_extra_y = 15, 25
        local koperta_extra_x, koperta_extra_y = 0, -25
        local header_extra_x, header_extra_y = -2, 2
        header_x = margin_x + header_extra_x
        header_y = margin_y + header_extra_y
        mails_x = margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_left" then
        local mails_extra_x, mails_extra_y = 10, 15
        local koperta_extra_x, koperta_extra_y = 10, 13
        local header_extra_x, header_extra_y = 0, -23
        mails_x = margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = margin_x + header_extra_x
        header_y = mails_y + mail_block_h + HEADER_SIZE + 4 + header_extra_y

    elseif MAILS_DIRECTION == "up_right" then
        local mails_extra_x, mails_extra_y = 0, 20
        local koperta_extra_x, koperta_extra_y = -25, -25
        local header_extra_x, header_extra_y = 0, 0
        header_x = conky_window.width - MAILS_WIDTH - margin_x + header_extra_x - 7
        header_y = margin_y + header_extra_y
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_right" then
        local mails_extra_x, mails_extra_y = 0, 16
        local koperta_extra_x, koperta_extra_y = -23, 13
        local header_extra_x, header_extra_y = 0, -23
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = mails_x + header_extra_x - 5
        header_y = mails_y + mail_block_h + HEADER_SIZE + 4 + header_extra_y
    end

-- SHAKE ANIMATION if the condition is met
local shake_offset = 0
local shake_color_mix = 0
if shake_anim_time > 0 then
    local elapsed = os.clock() - shake_anim_time
    if elapsed < SHAKE_DURATION then
        shake_offset = math.sin(elapsed * 800) * 3
        shake_color_mix = math.abs(math.sin(elapsed * math.pi / SHAKE_DURATION))
        -- SOUND only once at the start of the animation
        if not shake_sound_played then
			os.execute('paplay "' .. SHAKE_SOUND .. '" &')
            shake_sound_played = true
        end
    else
        shake_anim_time = 0
        shake_color_mix = 0
        shake_sound_played = false
    end
end
mails_x = mails_x + shake_offset
koperta_x = koperta_x + shake_offset
header_x = header_x + shake_offset
    -------------------------------------------------
    -- Display login error messages
    -------------------------------------------------
    if SHOW_LOGIN_ERRORS and blink and #error_msgs > 0 then
        set_color(cr, "red")
        set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE + 2, true)
        local win_w, win_h = conky_window.width, conky_window.height

        -- Helper for error position (with RIGHT_LAYOUT_REVERSED support)
        local function get_error_pos(text_w)
            local x, y
            if MAILS_DIRECTION == "up" then
                x = (win_w - text_w) / 2 + 125
                y = 15
            elseif MAILS_DIRECTION == "down" then
                x = (win_w - text_w) / 2 + 125
                y = win_h - 8
            elseif MAILS_DIRECTION == "up_left" then
                x = 265
                y = 15
            elseif MAILS_DIRECTION == "down_left" then
                x = 265
                y = win_h - 8
            elseif MAILS_DIRECTION == "up_right" then
                if RIGHT_LAYOUT_REVERSED then
                    x = header_x
                    y = 10
                else
                    x = win_w - text_w - 15
                    y = 10
                end
            elseif MAILS_DIRECTION == "down_right" then
                if RIGHT_LAYOUT_REVERSED then
                    x = header_x
                    y = win_h - 10
                else
                    x = win_w - text_w - 15
                    y = win_h - 10
                end
            else
                x = (win_w - text_w) / 2
                y = 18
            end
            return x, y
        end

        if selected_account_idx == 0 then
            -- "all accounts" mode: show all errors as a single line
            local accounts_with_error = {}
            for i, msg in ipairs(error_msgs) do
                local account = msg:match("%[Account error ([^%]]+)%]")
                if account then
                    table.insert(accounts_with_error, account)
                end
            end
            if #accounts_with_error > 0 then
                local error_str = "Login error for account: [" .. table.concat(accounts_with_error, "], [") .. "]"
                local text_ext = cairo_text_extents_t:create()
                cairo_text_extents(cr, error_str, text_ext)
                local text_w = text_ext.width
                local error_msg_x, error_msg_y = get_error_pos(text_w)
                cairo_move_to(cr, error_msg_x, error_msg_y)
                cairo_show_text(cr, error_str)
            end

        else
            -- Single account mode: only error for this account (if present)
            local account_name = ACCOUNT_NAMES[selected_account_idx + 1]:match("([^@]+)")
            for i, msg in ipairs(error_msgs) do
                if msg:lower():find(account_name:lower()) then
                    local text_ext = cairo_text_extents_t:create()
                    cairo_text_extents(cr, msg, text_ext)
                    local text_w = text_ext.width
                    local error_msg_x, error_msg_y = get_error_pos(text_w)
                    cairo_move_to(cr, error_msg_x, error_msg_y)
                    cairo_show_text(cr, msg)
                end
            end
        end
    end

    -- DRAWING THE ENVELOPE (PNG)
	draw_png_rotated_safe(cr, koperta_x, koperta_y, ENVELOPE_SIZE.w, ENVELOPE_SIZE.h, ENVELOPE_IMAGE, ENVELOPE_IMAGE_ANGLE, "ENVELOPE")

    cairo_new_path(cr)

    -------------------------------------------------
    -- DRAWING HEADER + SEPARATOR (dynamic!)
    -------------------------------------------------
    print("DEBUG Header: MAILS_DIRECTION=" .. tostring(MAILS_DIRECTION) .. " | RIGHT_LAYOUT_REVERSED=" .. tostring(RIGHT_LAYOUT_REVERSED))
    local header_account_text
    if selected_account_idx == 0 then
        header_account_text = ACCOUNT_NAMES[1]  -- "All accounts"
    else
        header_account_text = ACCOUNT_NAMES[selected_account_idx + 1] or ("account no " .. tostring(selected_account_idx))
    end

    if MAILS_DIRECTION:find("right") and RIGHT_LAYOUT_REVERSED then
        -- Mirror mode: separator left, header right, dynamic separator
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        local min_sep_length = 64
        local sep_margin = 8
        local window_right = conky_window.width - 18
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = "E-MAIL: " .. header_account_text
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local sep_start_x = header_x
        local sep_end_x = window_right - ext.x_advance - sep_margin
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
           dynamic_sep_length = min_sep_length
        end
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)
        -- Header after separator
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        cairo_move_to(cr, sep_start_x + dynamic_sep_length + sep_margin, header_y)
        cairo_show_text(cr, header_final)

    elseif MAILS_DIRECTION:find("right") and not RIGHT_LAYOUT_REVERSED then
        -- Classic mode: header left, separator right, dynamic separator
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = "E-MAIL: " .. header_account_text
        cairo_move_to(cr, header_x, header_y)
        cairo_show_text(cr, header_final)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local min_sep_length = 64
        local sep_margin = 12
        local window_right = conky_window.width - 12
        local sep_start_x = header_x + ext.x_advance + sep_margin
        local sep_end_x = window_right
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
            dynamic_sep_length = min_sep_length
        end
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)

    else
        -- Other modes (up, down, up_left, down_left) – separator ends at end of mail block
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = "E-MAIL: " .. header_account_text
        cairo_move_to(cr, header_x, header_y)
        cairo_show_text(cr, header_final)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local min_sep_length = 64
        local sep_margin = 12
        -- separator ends at the end of the mail block (MAILS_WIDTH + padding)
        local window_right = header_x + MAILS_WIDTH + MAIL_BG_PADDING_RIGHT + 10
        local sep_start_x = header_x + ext.x_advance + sep_margin
        local sep_end_x = window_right
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
            dynamic_sep_length = min_sep_length
        end
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)
    end

    -- DRAWING BADGE (red circle with unread count)
    cairo_new_path(cr)
    if unread > 0 then
        local badge_x = koperta_x + ENVELOPE_SIZE.w - BADGE_RADIUS + 2
        local badge_y = koperta_y + BADGE_RADIUS + 2

        -- Circle (badge)
        cairo_arc(cr, badge_x, badge_y, BADGE_RADIUS, 0, 2*math.pi)
        set_color(cr, BADGE_COLOR_TYPE, BADGE_COLOR_CUSTOM)
        cairo_fill_preserve(cr)  -- fill badge with color

        -- Ring (border)
        set_color(cr, BADGE_BORDER_COLOR_TYPE, BADGE_BORDER_COLOR_CUSTOM)
        cairo_set_line_width(cr, 2.2)
        cairo_stroke(cr)
        cairo_new_path(cr)  -- <-- clear path after border

        -- Number inside badge
        set_color(cr, BADGE_TEXT_COLOR_TYPE, BADGE_TEXT_COLOR_CUSTOM)
        set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE + 3, true)
        local txt = tostring(unread)
        local ext2 = cairo_text_extents_t:create()
        cairo_text_extents(cr, txt, ext2)
        cairo_move_to(cr, badge_x - ext2.width/2 - ext2.x_bearing, badge_y + ext2.height/2)
        cairo_show_text(cr, txt)
    end

-- Message about missing WAV file (next to envelope, blinking every second)
if SHOW_WAV_ERROR_LABEL then
    local f = io.open(NEW_MAIL_SOUND, "rb")
    if not f then
        local blink = (os.time() % 2 == 0)
        if blink then
            set_color(cr, "red")
            set_font(cr, "Arial", 12, true)
            -- Move if you want below envelope: koperta_x, koperta_y + ENVELOPE_SIZE.h + 8
            cairo_move_to(cr, koperta_x, koperta_y + 70)
            cairo_show_text(cr, "ERROR WAV")
        end
    else
        f:close()
    end
end
    -------------------------------------------------
    -- FILTERING MAILS – pick for given account
    -------------------------------------------------
    local filtered_mails = {}
    for _, mail in ipairs(last_good_mails) do
        -- Show only for selected account (or all if "All accounts")
        if selected_account_idx == 0 or mail.account_idx == (selected_account_idx - 1) then
            table.insert(filtered_mails, mail)
        end
    end
local N = #filtered_mails
local max_offset = math.max(N - MAX_MAILS, 0)

if mail_scroll_offset > max_offset then
    if prev_mail_scroll_offset <= max_offset then
        shake_anim_time = os.clock()  -- shake when scrolling up to the end of the list
    end
    mail_scroll_offset = max_offset
    write_mail_scroll_offset(mail_scroll_offset)
elseif mail_scroll_offset < 0 then
    if prev_mail_scroll_offset >= 0 then
        shake_anim_time = os.clock()  -- shake when scrolling down to the start of the list
    end
    mail_scroll_offset = 0
    write_mail_scroll_offset(0)
end

prev_mail_scroll_offset = mail_scroll_offset

    -- Prepare drawing list with scroll offset support!
    local mails_to_draw = {}
    local N = #filtered_mails
    local first = 1 + mail_scroll_offset
    local last = math.min(N, first + MAX_MAILS - 1)

    if first < 1 then first = 1 end
    if last > N then last = N end

    for i = first, last do
        table.insert(mails_to_draw, filtered_mails[i])
    end

    -- In "down" mode, reverse order (bottom to top)
    if MAILS_DIRECTION:find("down") then
        local reversed = {}
        for i = #mails_to_draw, 1, -1 do
            table.insert(reversed, mails_to_draw[i])
        end
        mails_to_draw = reversed
    end

    -- Calculate separator position – for mail preview (scroll/stick)
    local separator_start_x = header_x
    local separator_end_x = header_x + HEADER_LINE_LENGTH

    -- =======================================
    -- DRAWING INDIVIDUAL MAILS (BLOCKS)
    -- =======================================
    for i, mail in ipairs(mails_to_draw) do
        -- Calculate vertical position of mail on the list
        local mail_y
        if MAILS_DIRECTION:find("down") then
            -- In "down" mode: draw from bottom to top (reverse order)
            mail_y = mails_y + mail_block_h - i * mail_line_h
        else
            -- Standard: draw from top to bottom
            mail_y = mails_y + (i-1) * mail_line_h
        end
        local mail_x = mails_x

        -- 1. DRAWING THE GLOW (background with rounded corners under each mail)
        local rect_x = mail_x - MAIL_BG_PADDING_LEFT
        local rect_y = mail_y - 16 - MAIL_BG_PADDING_TOP
        local rect_w = MAILS_WIDTH + MAIL_BG_PADDING_LEFT + MAIL_BG_PADDING_RIGHT
        local rect_h = (SHOW_MAIL_PREVIEW and 32 or 24) + MAIL_BG_PADDING_TOP + MAIL_BG_PADDING_BOTTOM
        local rect_radius = MAIL_BG_RADIUS
        cairo_save(cr)
        draw_rounded_rect(cr, rect_x, rect_y, rect_w, rect_h, rect_radius)
	    local milk_base_color = MAIL_BG_COLOR
	    if shake_color_mix and shake_color_mix > 0 then
            milk_base_color = lerp_color(MAIL_BG_COLOR, {1, 0, 0}, shake_color_mix)
	    end
	    cairo_set_source_rgba(
            cr,
            milk_base_color[1], milk_base_color[2], milk_base_color[3],
            MAIL_BG_ALPHA
        )
        cairo_fill(cr)
        cairo_restore(cr)

        -- 2. ATTACHMENT ICON (if mail has attachment)
        if ATTACHMENT_ICON_ENABLE and mail.has_attachment then
            local icon_x = mail_x + (ATTACHMENT_ICON_OFFSET.dx or -24)
            local icon_y = mail_y + (ATTACHMENT_ICON_OFFSET.dy or 0)
			draw_png_rotated_safe(cr, icon_x, icon_y, ATTACHMENT_ICON_SIZE.w, ATTACHMENT_ICON_SIZE.h, ATTACHMENT_ICON_IMAGE, ATTACHMENT_ICON_ANGLE, "clip")
        end

        -- 3. LAYOUT MODE: reverse or classic?
        local right_layout = (MAILS_DIRECTION:find("_right") ~= nil) and RIGHT_LAYOUT_REVERSED

        if right_layout then
            -- ======== REVERSE MODE (header on the right) ========
            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local ext_acc = cairo_text_extents_t:create()
            cairo_text_extents(cr, account_label, ext_acc)
            local base_right_x = mails_x + MAILS_WIDTH
            local x_cursor = base_right_x - ext_acc.x_advance
            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then
                set_color(cr, "custom", ACCOUNT_COLORS[mail.account])
            else
                set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR)
            end
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, account_label)
            local konta_end_x = x_cursor + ext_acc.x_advance

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = ": " .. mail.from:gsub(":*$", "")
            local max_from_width = 225 - (ext_acc.x_advance or 0)
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, max_from_width)
            local ext_from = cairo_text_extents_t:create()
            cairo_text_extents(cr, from_txt_trimmed, ext_from)
            x_cursor = x_cursor - ext_from.x_advance - 8
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, from_txt_trimmed)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = x_cursor - mails_x - 12
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local subject_width = get_chunks_width(cr, subject_chunks, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local emoji_end_count = 0
            for i = #subject_chunks, 1, -1 do
                if subject_chunks[i].emoji then emoji_end_count = emoji_end_count + 1 else break end
            end
            local text_part, emoji_part = {}, {}
            local cut_index = #subject_chunks - emoji_end_count
            if cut_index < 0 then cut_index = 0 end
            for i = 1, cut_index do table.insert(text_part, subject_chunks[i].txt) end
            for i = cut_index + 1, #subject_chunks do table.insert(emoji_part, subject_chunks[i].txt) end
            local emoji_width = 0
            for _, emoji in ipairs(emoji_part) do
                cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                local ext = cairo_text_extents_t:create()
                cairo_text_extents(cr, emoji, ext)
                emoji_width = emoji_width + ext.x_advance
            end
            local SUBJECT_FROM_MARGIN = 5
            x_cursor = x_cursor - subject_width - SUBJECT_FROM_MARGIN
            local emoji_x = x_cursor
            local cursor_x = emoji_x
            local chunks = split_emoji(table.concat(text_part))
            for _, chunk in ipairs(chunks) do
                if chunk.emoji then
                    cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else
                    cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                end
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_move_to(cr, cursor_x, mail_y)
                cairo_show_text(cr, chunk.txt)
                local ext = cairo_text_extents_t:create()
                cairo_text_extents(cr, chunk.txt, ext)
                cursor_x = cursor_x + ext.x_advance
            end
            for _, emoji in ipairs(emoji_part) do
                cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_move_to(cr, cursor_x, mail_y)
                cairo_show_text(cr, emoji)
                local ext = cairo_text_extents_t:create()
                cairo_text_extents(cr, emoji, ext)
                cursor_x = cursor_x + ext.x_advance
            end

            -- d) Preview – scrolling/static support
            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + 2
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
                local preview_start_x = separator_start_x + 5
                local preview_end_x_stat = konta_end_x + PREVIEW_EXTRA_SPACE
                local preview_end_x_scroll = konta_end_x + PREVIEW_EXTRA_SPACE - 4
                local scroll_area_stat = preview_end_x_stat - preview_start_x
                local scroll_area_scroll = preview_end_x_scroll - preview_start_x
                cairo_save(cr)
                local preview_chunks_full = split_emoji(preview_txt)
                local preview_chunks_width = get_chunks_width(
                    cr, preview_chunks_full, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD
                )
                local emoji_end_count_full = 0
                for i = #preview_chunks_full, 1, -1 do
                    if preview_chunks_full[i] and preview_chunks_full[i].emoji then
                        emoji_end_count_full = emoji_end_count_full + 1
                    else break end
                end
                local emoji_pad = emoji_end_count_full * PREVIEW_FONT_SIZE * 1.05
                local emoji_clip_pad = 4
                if ENABLE_PREVIEW_SCROLL and preview_chunks_width > scroll_area_scroll then
                    cairo_rectangle(
                        cr,
                        preview_start_x - emoji_clip_pad,
                        preview_y - PREVIEW_FONT_SIZE,
                        scroll_area_scroll + emoji_clip_pad * 2,
                        PREVIEW_FONT_SIZE + 8
                    )
                    cairo_clip(cr)
                    local t = os.clock()
                    local preview_marquee_str = ""
                    for _, chunk in ipairs(preview_chunks_full) do
                        preview_marquee_str = preview_marquee_str .. chunk.txt
                    end
                    local preview_marquee_chunks = split_emoji(preview_marquee_str)
                    local preview_marquee_width = get_chunks_width(
                        cr, preview_marquee_chunks, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD
                    )
                    local gap = 48
                    local scrollable = preview_marquee_width + gap
                    local scroll_offset = (t * preview_scroll_speed) % scrollable
                    local preview_x_start = preview_end_x_scroll - preview_marquee_width - scroll_offset
                    for loop=1,2 do
                        local cursor_x = preview_x_start + (loop - 1) * (preview_marquee_width + gap)
                        for _, chunk in ipairs(preview_marquee_chunks) do
                            if chunk.emoji then
                                cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else
                                cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            end
                            cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                            cairo_move_to(cr, cursor_x, preview_y)
                            cairo_show_text(cr, chunk.txt)
                            local ext = cairo_text_extents_t:create()
                            cairo_text_extents(cr, chunk.txt, ext)
                            cursor_x = cursor_x + ext.x_advance
                        end
                    end
                else
                    cairo_rectangle(
                        cr,
                        preview_start_x - emoji_clip_pad,
                        preview_y - PREVIEW_FONT_SIZE,
                        scroll_area_stat + emoji_clip_pad * 2 + emoji_pad,
                        PREVIEW_FONT_SIZE + 8
                    )
                    cairo_clip(cr)
                    local preview_chunks = trim_line_to_width_emoji(
                        cr, preview_txt, scroll_area_stat, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD
                    )
                    local preview_x = preview_end_x_stat - get_chunks_width(cr, preview_chunks, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                    if preview_x < preview_start_x then preview_x = preview_start_x end
                    local cursor_x = preview_x
                    for _, chunk in ipairs(preview_chunks) do
                        if chunk.emoji then
                            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else
                            cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        end
                        cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        cairo_move_to(cr, cursor_x, preview_y)
                        cairo_show_text(cr, chunk.txt)
                        local ext = cairo_text_extents_t:create()
                        cairo_text_extents(cr, chunk.txt, ext)
                        cursor_x = cursor_x + ext.x_advance
                    end
                end
                cairo_restore(cr)
            end
        -- ======== END OF REVERSE MODE ========
        else
            -- ======== LEFT MODE (classic) ========
            -- (dalsza część rysowania klasycznego)
            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then
                set_color(cr, "custom", ACCOUNT_COLORS[mail.account])
            else
                set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR)
            end
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            cairo_move_to(cr, mail_x, mail_y)
            cairo_show_text(cr, account_label)

            local ext_acc = cairo_text_extents_t:create()
            cairo_text_extents(cr, account_label, ext_acc)

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = (mail.from:gsub(":*$", "") .. ":")
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, 225 - (ext_acc.x_advance or 0))
            cairo_move_to(cr, mail_x + ext_acc.x_advance, mail_y)
            cairo_show_text(cr, from_txt_trimmed)

            local ext3 = cairo_text_extents_t:create()
            cairo_text_extents(cr, from_txt_trimmed, ext3)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = MAX_MAIL_LINE_PIXELS - ext_acc.x_advance - ext3.width - 12
            local function trim_line_to_width_emoji(cr, text, max_width, font_name, font_size, font_bold)
                local chunks = split_emoji(text)
                local out_chunks = {}
                local width = 0
                cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                cairo_set_font_size(cr, font_size)
                local ext_dots = cairo_text_extents_t:create()
                cairo_text_extents(cr, "...", ext_dots)
                local ellipsis_width = ext_dots.x_advance

                for i, chunk in ipairs(chunks) do
                    local this_face = chunk.emoji and "Noto Color Emoji" or font_name
                    cairo_select_font_face(cr, this_face, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                    cairo_set_font_size(cr, font_size)
                    local ext = cairo_text_extents_t:create()
                    cairo_text_extents(cr, chunk.txt, ext)
                    local next_will_overflow = (width + ext.x_advance + ellipsis_width) > max_width
                    if next_will_overflow then
                        break
                    end
                    table.insert(out_chunks, chunk)
                    width = width + ext.x_advance
                end
                if #out_chunks < #chunks then
                    table.insert(out_chunks, {emoji=false, txt="..."})
                end
                return out_chunks
            end
            local subject_chunks = trim_line_to_width_emoji(
                cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD
            )
            local cursor = mail_x + ext_acc.x_advance + ext3.x_advance + 8
            for _, chunk in ipairs(subject_chunks) do
                cairo_move_to(cr, cursor, mail_y)
                if chunk.emoji then
                    cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else
                    cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                end
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_show_text(cr, chunk.txt)
                local ext4 = cairo_text_extents_t:create()
                cairo_text_extents(cr, chunk.txt, ext4)
                cursor = cursor + ext4.x_advance
            end

            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + 2
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
                local preview_chunks_full = split_emoji(preview_txt)
                local preview_chunks_width = get_chunks_width(cr, preview_chunks_full, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local scroll_area = MAX_MAIL_LINE_PIXELS - 12
                local preview_x = PREVIEW_INDENT and (mail_x + 18) or mail_x
                cairo_save(cr)
                cairo_rectangle(cr, preview_x, preview_y - PREVIEW_FONT_SIZE, scroll_area, PREVIEW_FONT_SIZE + 8)
                cairo_clip(cr)
                if ENABLE_PREVIEW_SCROLL and preview_chunks_width > scroll_area then
                    local t = os.clock()
                    local preview_marquee_str = ""
                    for _, chunk in ipairs(preview_chunks_full) do
                        preview_marquee_str = preview_marquee_str .. chunk.txt
                    end
                    local preview_marquee_chunks = split_emoji(preview_marquee_str)
                    local preview_marquee_width = get_chunks_width(
                        cr, preview_marquee_chunks, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD
                    )
                    local gap = 48
                    local scrollable = preview_marquee_width + gap
                    local scroll_offset = (t * preview_scroll_speed) % scrollable
                    local preview_x_start = preview_x - scroll_offset

                    for loop=1,2 do
                        local cursor_x = preview_x_start + (loop - 1) * (preview_marquee_width + gap)
                        for _, chunk in ipairs(preview_marquee_chunks) do
                            if chunk.emoji then
                                cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else
                                cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            end
                            cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                            cairo_move_to(cr, cursor_x, preview_y)
                            cairo_show_text(cr, chunk.txt)
                            local ext = cairo_text_extents_t:create()
                            cairo_text_extents(cr, chunk.txt, ext)
                            cursor_x = cursor_x + ext.x_advance
                        end
                    end
                else
                    local trimmed_preview = trim_line_to_width(cr, preview_txt, scroll_area)
                    local preview_chunks = split_emoji(trimmed_preview)
                    cairo_move_to(cr, preview_x, preview_y)
                    for _, chunk in ipairs(preview_chunks) do
                        if chunk.emoji then
                            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else
                            cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        end
                        cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        cairo_show_text(cr, chunk.txt)
                    end
                end
                cairo_restore(cr)
            end
        end -- end if right_layout / else
    end -- end for loop over mails

    -- DEBUG BORDER – draw window border (if active)
    if SHOW_DEBUG_BORDER then
        draw_debug_border(cr)
    end

    -- Cairo resource cleanup
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

