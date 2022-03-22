
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local CheckButton = require("ui/widget/checkbutton")
local OverlapGroup = require("ui/widget/overlapgroup")

local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextViewer = require("ui/widget/textviewer")
local Button = require("ui/widget/button")
local CloseButton = require("ui/widget/closebutton")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local ButtonTable = require("ui/widget/buttontable")

local ColorTextBoxWidget = require("widget/colortextboxwidget")

local _ = require("gettext")
local T = require("ffi/util").template
local Device = require("device")
local Screen = Device.screen
local Input = Device.input
local Size = require("ui/size")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")

local logger = require("logger")
local dump = require("dump")
--logger:setLevel(1)

local TextSelector = InputContainer:new {
    text = "text text",
    checked = false,
    content_face = Font:getFace("cfont", G_reader_settings:readSetting("dict_font_size") or 20)
}

function TextSelector:init()
    if not self.width then
        self.width = Screen:getWidth()
    end

    self:initCheck(self.checked)

    self.text_box_widget = ColorTextBoxWidget:new {
        face = self.content_face,
        text = self.text,
        fgcolor = self.fgcolor,
        bgcolor = self.bgcolor,
        width = self.width
    }
    self.dimen = self.text_box_widget.dimen
    self[1] = self.text_box_widget

    if Device:isTouchDevice() then
        self.ges_events = {
            TapText = {
                GestureRange:new{
                    ges = "tap",
                    range = self.text_box_widget.dimen,
                },
                doc = "Tap Text",
            }
        }
    end
end

function TextSelector:onTapText()
    self.callback()
end

function TextSelector:initCheck(checked)
    self.checked = checked
    if self.checked then
        self.bgcolor = Blitbuffer.COLOR_BLACK
        self.fgcolor = Blitbuffer.COLOR_WHITE
    else
        self.bgcolor = Blitbuffer.COLOR_WHITE
        self.fgcolor = Blitbuffer.COLOR_BLACK
    end
end

function TextSelector:toggleCheck()
    self.checked = not self.checked
    self:init()
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
    end)
    return self.checked
end

local VocabularyLookup = InputContainer:new {
    title = "Vocabulary Lookup title",
    word = "Vocabulary Lookup content text",
    results = nil,
}

function VocabularyLookup:init()
    self.width = Screen:getWidth() - Screen:scaleBySize(80)
    self.inner_width = self.width - Size.border.window * 2
    self.content_height = Screen:scaleBySize(400)
    if Device:hasKeys() then
        self.key_events = {
            ReadPrevResult = {{Input.group.PgBack}, doc = "read prev result"},
            ReadNextResult = {{Input.group.PgFwd}, doc = "read next result"},
            Close = { {"Back"}, doc = "close quick lookup" }
        }
    end

    self.definition_widget = VerticalGroup:new {}
    self:changeDictionary(1, true)
    self:buildDefinitionWidget()

    local close_button = CloseButton:new {window = self, padding_top = Size.margin.title}
    self.dict_title_text = TextWidget:new{
        text = self.dictionary,
        face = Font:getFace("x_smalltfont"),
        bold = true,
        max_width = self.inner_width - close_button:getSize().w + close_button.padding_left
    }

    local title_bar = OverlapGroup:new{
        dimen = {
            w = self.inner_width,
            --h = self.dict_title_text:getSize().h
        },
        self.dict_title_text,
        close_button,
    }
    local title_sep = LineWidget:new{
        dimen = Geom:new{
            w = self.inner_width,
            h = Size.line.thick,
        }
    }

    self.displaynb_text = TextWidget:new{
        text = self.displaynb,
        face = Font:getFace("cfont", 22),
        padding = 0,
    }
    self.lookup_word_text = TextWidget:new{
        text = self.lookup_word,
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = self.inner_width - self.displaynb_text:getSize().w,
        padding = 0, -- to be aligned with lookup_word_nb
    }
    local lookup_word_nb = FrameContainer:new{
        margin = 0,
        bordersize = 0,
        padding = 0,
        padding_left = Size.padding.small,
        overlap_align = "right",
        self.displaynb_text,
    }
    local lookup_word = OverlapGroup:new{
        dimen = {
            w = self.inner_width,
        },
        self.lookup_word_text,
        lookup_word_nb, -- last, as this might be nil
    }

    local vertical_widget = VerticalGroup:new{
        title_bar,
        title_sep,
        lookup_word,
    }

    self.scroll = ScrollableContainer:new{
        ignore_events = {
            -- ignore event to handle ges_events of VocabularyLookup, see onSwipe
            "swipe", "hold", "hold_release", "hold_pan", "touch", "pan", "pan_release",
        },
        dimen = Geom:new{
            w = self.inner_width,
            h = self.content_height,
        },
        show_parent = self,
        self.definition_widget,
    }

    local prev_dict_text = "◁◁"
    local next_dict_text = "▷▷"
    local buttons = {
        {
            {
                id = "prev_dict",
                text = prev_dict_text,
                vsync = true,
                enabled = self:isPrevDictAvailable(),
                callback = function()
                    self:changeToPrevDict()
                end,
                hold_callback = function()
                    self:changeToFirstDict()
                end,
            },
            {
                id = "add_to_learning",
                text = _("Add To Learning"),
                enabled = not self:isNoResult(),
                callback = function()
                    local definition = ""
                    for i, v in pairs(self.definition_widget) do
                        if v.checked then
                            if definition == "" then
                                definition = definition .. v.text
                            else
                                definition = definition .. "\n" .. v.text
                            end
                        end
                    end
                    if self.add_learning_callback ~= nil then
                        self.add_learning_callback(self.lookup_word, definition, self.results[self.dict_index].definition)
                    end
                end,
            },
            {
                id = "next_dict",
                text = next_dict_text,
                vsync = true,
                enabled = self:isNextDictAvailable(),
                callback = function()
                    self:changeToNextDict()
                end,
                hold_callback = function()
                    self:changeToLastDict()
                end,
            },
        },
        {
            {
                id = "close",
                text = _("Close"),
                callback = function()
                    self:onClose()
                end,
            },
        },
    }
    local buttons_padding = Size.padding.default
    local buttons_width = self.inner_width - 2*buttons_padding
    self.button_table = ButtonTable:new{
        width = buttons_width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    table.insert(vertical_widget, self.scroll)
    table.insert(vertical_widget, self.button_table)

    self.frame = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        vertical_widget
    }

    self.dimen = self.frame:getSize()

    self.movable = MovableContainer:new {
        ignore_events = {
            -- ignore event to handle ges_events of VocabularyLookup, see onSwipe
            "swipe", "hold", "hold_release", "hold_pan", "touch", "pan", "pan_release",
        },
        self.frame
    }

    self.container = CenterContainer:new {
        dimen = Screen:getSize(),
        self.movable,
    }

    self[1] = self.container

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = Screen:getSize(),
            },
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = Screen:getSize(),
            },
        },
    }
end

function VocabularyLookup:update()
    self[1]:free()

    self.dict_title_text:setText(self.dictionary)
    self.displaynb_text:setText(self.displaynb)
    self.lookup_word_text:setText(self.lookup_word)

    self:buildDefinitionWidget()
    self.scroll:initState()

    if not self.is_wiki_fullpage then
        local prev_dict_btn = self.button_table:getButtonById("prev_dict")
        if prev_dict_btn then
            prev_dict_btn:enableDisable(self:isPrevDictAvailable())
        end
        local next_dict_btn = self.button_table:getButtonById("next_dict")
        if next_dict_btn then
            next_dict_btn:enableDisable(self:isNextDictAvailable())
        end
    end

    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
end

function VocabularyLookup:isNoResult()
    return self.results[self.dict_index].no_result
end

function VocabularyLookup:isPrevDictAvailable()
    return self.dict_index > 1
end

function VocabularyLookup:isNextDictAvailable()
    return self.dict_index < #self.results
end

function VocabularyLookup:changeToNextDict()
    if self:isNextDictAvailable() then
        self:changeDictionary(self.dict_index + 1)
    elseif #self.results > 1 then -- restart at first if end reached
        self:changeDictionary(1)
    end
end

function VocabularyLookup:changeToFirstDict()
    if self:isPrevDictAvailable() then
        self:changeDictionary(1)
    end
end

function VocabularyLookup:changeToPrevDict()
    if self:isPrevDictAvailable() then
        self:changeDictionary(self.dict_index - 1)
    elseif #self.results > 1 then -- restart at end if first reached
        self:changeDictionary(#self.results)
    end
end

function VocabularyLookup:changeToLastDict()
    if self:isNextDictAvailable() then
        self:changeDictionary(#self.results)
    end
end

function VocabularyLookup:onTap(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        UIManager.close(self)
        self:onClose()
        return true
    end
    return true
end

function VocabularyLookup:onSwipe(arg, ges)
    local direction = ges.direction
    if ges.pos:intersectWith(self.scroll.dimen) then
        if direction == "east" then
            self:changeToPrevDict()
        elseif direction == "west" then
            self:changeToNextDict()
        else
            return self.scroll:onScrollableSwipe(arg, ges)
        end
        return true
    end
    return self.movable:onMovableSwipe(arg, ges)
end

function VocabularyLookup:onReadPrevResult()
    self:changeToPrevDict()
    return true
end

function VocabularyLookup:onReadNextResult()
    self:changeToNextDict()
    return true
end

function VocabularyLookup:onClose()
    UIManager:close(self, "partial")
    return true
end

function VocabularyLookup:changeDictionary(index, skip_update)

    if not self.results[index] or index == self.dict_index then return end
    for k, v in pairs(self.results[index]) do
        logger.info(k, " - ", v)
    end


    self.dict_index = index
    self.dictionary = self.results[index].dict
    self.lookup_word = self.results[index].word
    self.definition = self:breakLineDefinition(self.results[index].definition)
    self.displaynb = T("%1 / %2", index, #self.results)

    if not skip_update then
        self:update()
    end
end

function VocabularyLookup:buildDefinitionWidget()
    -- clear child widget to add new
    self.definition_widget:clear()
    --No result - No available search
    --{
    --     ["word"] = "abcdejjajfkkfjsvsiendkdbs",
    --     ["lookup_cancelled"] = false,
    --     ["dict"] = "Not available",
    --     ["definition"] = "No results.",
    --     ["no_result"] = true,
    --}
    if self:isNoResult() then
        table.insert(self.definition_widget, ColorTextBoxWidget:new {
            face = Font:getFace("cfont", G_reader_settings:readSetting("dict_font_size") or 20),
            text = self.results[self.dict_index].definition,
            width = self.inner_width - ScrollableContainer:getScrollbarWidth(),
        })
        return
    end
    for i, v in pairs(self.definition) do
        local text_selector = TextSelector:new {
            text = v,
            width = self.inner_width - ScrollableContainer:getScrollbarWidth(),
            parent = self
        }
        text_selector.callback = function()
            text_selector:toggleCheck()
        end
        table.insert(self.definition_widget, text_selector)
    end
end

function VocabularyLookup:breakLineDefinition(definition)
    local lines = {}
    if not definition then
        return lines
    end
    for s in definition:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

return VocabularyLookup