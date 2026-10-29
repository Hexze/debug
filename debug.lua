plugin = {
    name = "debug",
    displayName = "Debug Menu",
    prefix = "§7DB",
    version = "0.1.1",
    description = "Debug tool for testing overlay rendering, keyboard and mouse input capture, and input blocking",
}

-- Constants

local TITLE_SIZE, BODY_SIZE, SMALL_SIZE = 24, 16, 8

local PANEL_W = 380
local PAD = 24
local CONTENT_W = PANEL_W - PAD * 2
local ACCENT_STRIP_H = 3
local HEADER_H = 82
local SECTION_GAP = 22
local LABEL_GAP = 12
local BUTTON_W, BUTTON_H = 150, 36
local STAT_COL_W, STAT_COL_GAP = 60, 10
local FIELD_H = 34
local FIELD_INSET = 12
local ROW_H = 22
local CARET_BLINK_TICKS = 30

local COLOR = {
    panel = { r = 15, g = 17, b = 23, a = 242 },
    border = { r = 56, g = 62, b = 76, a = 255 },
    divider = { r = 38, g = 42, b = 52, a = 255 },
    accent = { r = 96, g = 165, b = 250, a = 255 },
    title = { r = 240, g = 243, b = 248, a = 255 },
    text = { r = 222, g = 227, b = 236, a = 255 },
    muted = { r = 140, g = 148, b = 164, a = 255 },
    faint = { r = 96, g = 104, b = 120, a = 255 },
    good = { r = 74, g = 222, b = 128, a = 255 },
    buttonIdle = { r = 36, g = 42, b = 54, a = 255 },
    buttonHover = { r = 47, g = 73, b = 116, a = 255 },
    fieldIdle = { r = 22, g = 25, b = 32, a = 255 },
    fieldFocused = { r = 26, g = 32, b = 46, a = 255 },
    selection = { r = 96, g = 165, b = 250, a = 80 },
}

local CENTER = starfish.overlay.Anchor.CENTER
local TOP_LEFT = starfish.overlay.Anchor.TOP_LEFT

-- Panel layout

local layout = {}
local PANEL_H
do
    local y = HEADER_H
    local function section(name, contentHeight)
        layout[name .. "Divider"] = y
        layout[name .. "Label"] = y + SECTION_GAP
        layout[name] = y + SECTION_GAP + SMALL_SIZE + LABEL_GAP
        y = layout[name] + contentHeight + SECTION_GAP
    end
    section("hitTest", BUTTON_H)
    section("textInput", FIELD_H)
    section("status", ROW_H + BODY_SIZE)
    PANEL_H = y
end

-- Menu state

local menu = { open = false, mouseSession = nil }
local hitTest = { clicks = 0, scroll = 0, hovered = false }
local search = { session = nil, text = "", cursor = 0, selection = nil, dragging = false }
local caret = { visible = true, ticks = 0 }

local function resetCaretBlink()
    caret.visible = true
    caret.ticks = 0
end

local function releaseSearchField()
    search.session = nil
    search.selection = nil
    search.dragging = false
    starfish.overlay.invalidate()
end

-- Panel drawing

local function at(localX, localY)
    return -PANEL_W / 2 + localX, -PANEL_H / 2 + localY
end

local function absoluteAt(localX, localY)
    local vw, vh = starfish.overlay.getViewport()
    local offsetX, offsetY = at(localX, localY)
    return vw / 2 + offsetX, vh / 2 + offsetY
end

local function panelRect(localX, localY, w, h, color)
    local x, y = at(localX, localY)
    starfish.overlay.rect({ anchor = CENTER, x = x, y = y, w = w, h = h, color = color })
end

local function panelOutline(localX, localY, w, h, color)
    local x, y = at(localX, localY)
    starfish.overlay.rectOutline({ anchor = CENTER, x = x, y = y, w = w, h = h, color = color })
end

local function panelText(localX, localY, str, size, color)
    local x, y = at(localX, localY)
    starfish.overlay.text({ anchor = CENTER, x = x, y = y, text = str, size = size, color = color })
end

local function panelTextCentered(localX, localY, width, str, size, color)
    local x, y = at(localX, localY)
    starfish.overlay.text({ anchor = CENTER, x = x, y = y, text = str, size = size, color = color, align = "center", alignWidth = width })
end

local function panelTextRight(localX, localY, width, str, size, color)
    local x, y = at(localX, localY)
    starfish.overlay.text({ anchor = CENTER, x = x, y = y, text = str, size = size, color = color, align = "right", alignWidth = width })
end

local function panelClip(localX, localY, w, h)
    local x, y = at(localX, localY)
    starfish.overlay.pushClip({ anchor = CENTER, x = x, y = y, w = w, h = h })
end

local function panelHitRect(id, localX, localY, w, h, cursor, scrollable)
    local x, y = at(localX, localY)
    starfish.overlay.hitRect({ anchor = CENTER, id = id, x = x, y = y, w = w, h = h, cursor = cursor, scrollable = scrollable })
end

-- Menu lifecycle

local function closeMenu()
    if not menu.open then return end
    if search.session then
        search.session:stop()
        releaseSearchField()
    end
    if menu.mouseSession then
        menu.mouseSession:stop()
    end
    menu.mouseSession = nil
    menu.open = false
    starfish.overlay.invalidate()
end

local function openMenu()
    if menu.open then return end
    menu.open = true
    menu.mouseSession = starfish.input.captureMouse({
        onCancel = function()
            menu.mouseSession = nil
            menu.open = false
            starfish.overlay.invalidate()
        end,
    })
    starfish.overlay.invalidate()
end

local function toggleMenu()
    if menu.open then closeMenu() else openMenu() end
end

-- Hit test

local function drawStat(rightEdge, value, label, valueColor)
    local x = rightEdge - STAT_COL_W
    panelTextRight(x, layout.hitTest + 3, STAT_COL_W, value, BODY_SIZE, valueColor)
    panelTextRight(x, layout.hitTest + 21, STAT_COL_W, label, SMALL_SIZE, COLOR.muted)
end

local function drawHitTestSection()
    panelText(PAD, layout.hitTestLabel, "HIT TEST", SMALL_SIZE, COLOR.muted)

    local y = layout.hitTest
    panelRect(PAD, y, BUTTON_W, BUTTON_H, hitTest.hovered and COLOR.buttonHover or COLOR.buttonIdle)
    panelOutline(PAD, y, BUTTON_W, BUTTON_H, hitTest.hovered and COLOR.accent or COLOR.border)
    panelTextCentered(PAD, y + 11, BUTTON_W, "Click / Scroll", BODY_SIZE, COLOR.text)
    panelHitRect("hitTestButton", PAD, y, BUTTON_W, BUTTON_H, "hand", true)

    drawStat(PANEL_W - PAD - STAT_COL_W - STAT_COL_GAP, string.format("%d", hitTest.clicks), "CLICKS", COLOR.good)
    drawStat(PANEL_W - PAD, string.format("%.0f", hitTest.scroll), "SCROLL", COLOR.accent)
end

-- Text input

local function focusSearchField(clickX)
    if not search.session then
        search.text = ""
        search.cursor = 0
        search.selection = nil
        search.session = starfish.input.captureText({
            onChange = function(s)
                search.text = s.text
                search.cursor = s.cursor
                search.selection = s.selection
                resetCaretBlink()
                starfish.overlay.invalidate()
            end,
            onSubmit = releaseSearchField,
            onCancel = releaseSearchField,
        })
    end

    search.dragging = true
    local fieldTextX = absoluteAt(PAD + FIELD_INSET, 0)
    search.session:cursorFromX(clickX - fieldTextX, BODY_SIZE, false)
    resetCaretBlink()
    starfish.overlay.invalidate()
end

local function drawFieldContent(fieldY)
    local textX = PAD + FIELD_INSET

    if search.selection then
        local before = search.text:sub(1, search.selection.start)
        local selected = search.text:sub(search.selection.start + 1, search.selection.finish)
        local beforeWidth = starfish.overlay.measureText(before, BODY_SIZE)
        local selectedWidth = starfish.overlay.measureText(selected, BODY_SIZE)
        panelRect(textX + beforeWidth, fieldY + 7, selectedWidth, 20, COLOR.selection)
    end

    panelText(textX, fieldY + 10, search.text, BODY_SIZE, COLOR.text)

    if caret.visible then
        local caretX = textX + starfish.overlay.measureText(search.text:sub(1, search.cursor), BODY_SIZE)
        panelRect(caretX, fieldY + 7, 2, 20, COLOR.accent)
    end
end

local function drawTextInputSection()
    panelText(PAD, layout.textInputLabel, "TEXT INPUT", SMALL_SIZE, COLOR.muted)

    local y = layout.textInput
    local focused = search.session ~= nil
    panelRect(PAD, y, CONTENT_W, FIELD_H, focused and COLOR.fieldFocused or COLOR.fieldIdle)
    panelOutline(PAD, y, CONTENT_W, FIELD_H, focused and COLOR.accent or COLOR.border)

    panelClip(PAD, y, CONTENT_W, FIELD_H)
    if focused then
        drawFieldContent(y)
    else
        panelText(PAD + FIELD_INSET, y + 10, "Click to type...", BODY_SIZE, COLOR.faint)
    end
    starfish.overlay.popClip()

    panelHitRect("textField", PAD, y, CONTENT_W, FIELD_H, "text")
end

-- Status

local function statusRow(index, key, value)
    local y = layout.status + (index - 1) * ROW_H
    panelText(PAD, y + 2, key, SMALL_SIZE, COLOR.muted)
    panelTextRight(PAD, y, CONTENT_W, value, BODY_SIZE, COLOR.text)
end

local function drawStatusSection()
    local vw, vh = starfish.overlay.getViewport()
    local mx, my = starfish.input.getCursor()

    panelText(PAD, layout.statusLabel, "STATUS", SMALL_SIZE, COLOR.muted)
    statusRow(1, "viewport", string.format("%.0f x %.0f", vw, vh))
    statusRow(2, "cursor", string.format("%.0f, %.0f", mx, my))
end

-- Menu rendering

local function drawHeader()
    panelRect(0, 0, PANEL_W, ACCENT_STRIP_H, COLOR.accent)
    panelText(PAD, 24, "Starfish Debug", TITLE_SIZE, COLOR.title)
    panelText(PAD, 52, "M or Esc to close", SMALL_SIZE, COLOR.muted)
end

local function drawDividers()
    for _, name in ipairs({ "hitTest", "textInput", "status" }) do
        panelRect(PAD, layout[name .. "Divider"], CONTENT_W, 1, COLOR.divider)
    end
end

local function drawClosedHint()
    local message = "Press M for the debug menu"
    local width = starfish.overlay.measureText(message, BODY_SIZE)
    starfish.overlay.rect({ anchor = TOP_LEFT, x = 8, y = 8, w = width + 27, h = 32, color = COLOR.panel })
    starfish.overlay.rect({ anchor = TOP_LEFT, x = 8, y = 8, w = 3, h = 32, color = COLOR.accent })
    starfish.overlay.text({ anchor = TOP_LEFT, x = 23, y = 16, text = message, size = BODY_SIZE, color = COLOR.text, shadow = true })
end

local function draw()
    if not menu.open then
        drawClosedHint()
        return
    end

    panelRect(0, 0, PANEL_W, PANEL_H, COLOR.panel)
    panelOutline(0, 0, PANEL_W, PANEL_H, COLOR.border)
    drawDividers()
    drawHeader()
    drawHitTestSection()
    drawTextInputSection()
    drawStatusSection()
end

-- Event wiring

starfish.input.bind("M", { onPress = toggleMenu })

starfish.overlay.onRender(draw)

starfish.overlay.onHit(function(event)
    if event.id == "textField" then
        if event.type == "click" and event.button == "left" then
            focusSearchField(event.x)
        elseif event.type == "release" then
            search.dragging = false
        end
        return
    end

    if event.id ~= "hitTestButton" then return end

    if event.type == "click" then
        hitTest.clicks = hitTest.clicks + 1
    elseif event.type == "scroll" then
        hitTest.scroll = hitTest.scroll + event.dy
    elseif event.type == "enter" then
        hitTest.hovered = true
    elseif event.type == "leave" then
        hitTest.hovered = false
    end

    starfish.overlay.invalidate()
end)

starfish.timers.interval(16, function()
    if not menu.open then return end

    if search.dragging and search.session then
        local mx = starfish.input.getCursor()
        local fieldTextX = absoluteAt(PAD + FIELD_INSET, 0)
        search.session:cursorFromX(mx - fieldTextX, BODY_SIZE, true)
    end

    caret.ticks = caret.ticks + 1
    if caret.ticks >= CARET_BLINK_TICKS then
        caret.ticks = 0
        caret.visible = not caret.visible
    end

    starfish.overlay.invalidate()
end)
