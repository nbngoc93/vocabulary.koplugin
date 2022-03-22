
local _ = require("gettext")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local CloseButton = require("ui/widget/closebutton")
local LineWidget = require("ui/widget/linewidget")
local Button = require("ui/widget/button")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")

local VocabularyRepository = require("widget/vocabularyrepository")

local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")
local FFIUtil = require("ffi/util")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Screen = Device.screen
local Geom = require("ui/geometry")
local BD = require("ui/bidi")

local logger = require("logger")
local dump = require("dump")

local FlashCard = InputContainer:new {
    word = "word",
    definition = "definition"
}

function FlashCard:init()
    self.width = Screen:getWidth() - Screen:scaleBySize(80)
    self.height = Screen:getHeight() - Screen:scaleBySize(200)
    if self.height > Screen:getHeight() * 2 / 3 then
        self.height = Screen:getHeight() * 2 / 3
    end

    self.word_text_widget = TextWidget:new {
        text = self.word,
        face = Font:getFace("tfont", 34),
        padding = Size.padding.large
    }
    self.back_container = CenterContainer:new {
        dimen = Geom:new{
            w = self.width,
            h = self.height,
        },
        self.word_text_widget,
    }
    self.back = FrameContainer:new {
        bordersize = Size.border.default,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        margin = 0,
        padding = 0,
        self.back_container
    }

    self.front_word_container = CenterContainer:new {
        dimen = Geom:new{
            w = self.width,
            h = self.word_text_widget:getSize().h,
        },
        self.word_text_widget
    }

    self.front_definition_container = CenterContainer:new {
        dimen = Geom:new{
            w = self.width,
            h = self.height - self.front_word_container:getSize().h - Size.line.thick,
        },
        ScrollTextWidget:new{
            text = self.definition,
            face = Font:getFace("cfont", 26),
            width = self.width - Size.padding.small - 2 * Size.padding.large,
            height = self.height - self.front_word_container:getSize().h - Size.line.thick - Screen:scaleBySize(10),
            dialog = self
        }
    }
    self.front_container = VerticalGroup:new {
        self.front_word_container,
        LineWidget:new {
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{
                w = self.width,
                h = Size.line.thick,
            }
        },
        self.front_definition_container
    }


    self.front = FrameContainer:new {
        bordersize = Size.border.default,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        margin = 0,
        padding = 0,
        self.front_container
    }

    self.center_container = CenterContainer:new {
        dimen = Screen:getSize(),
        self.back
    }
    self.on_top = "back"

    self.dimen = Screen.getSize()

    self[1] = self.center_container

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
            doc = "Tap Item",
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            },
            doc = "Swipe",
        }
    }
end

function FlashCard:onSwipe(_, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "east" then
        self.swipe_east_callback()
        return true
    elseif direction == "west" then
        self.swipe_west_callback()
        return true
    end
end

function FlashCard:onTap(arg, ges)
    if self.on_top == "back" and ges.pos:intersectWith(self.back.dimen) then
        self:flip()
    elseif self.on_top == "front" and ges.pos:intersectWith(self.front.dimen) then
        self:flip()
    else
        self:onClose()
    end
    return true
end

function FlashCard:onClose()
    UIManager:close(self, "partial")
    return true
end

function FlashCard:update()
    self.center_container:clear(true)

    self.word_text_widget:setText(self.word)
    self.front_definition_container:clear()
    table.insert(self.front_definition_container, ScrollTextWidget:new{
        text = self.definition,
        face = Font:getFace("cfont", 26),
        width = self.width - Size.padding.small - 2 * Size.padding.large,
        height = self.height - self.front_word_container:getSize().h - Size.line.thick - Screen:scaleBySize(10),
        dialog = self
    })

    table.insert(self.center_container, self.back)
    self.on_top = "back"

    UIManager:setDirty(self, function()
        return "partial", self.back.dimen
    end)
end

function FlashCard:flip()
    self.center_container:clear(true)
    if self.on_top == "back" then
        table.insert(self.center_container, self.front)
        self.on_top = "front"
        UIManager:setDirty(self, function()
            return "partial", self.front.dimen
        end)
    else
        table.insert(self.center_container, self.back)
        self.on_top = "back"
        UIManager:setDirty(self, function()
            return "partial", self.back.dimen
        end)
    end
end

local VocabularyTableItem = InputContainer:new {
    text = nil,
    face = nil,
    bold = false, -- use bold=true to use a real bold font (or synthetized if not available),
    -- or bold=Font.FORCE_SYNTHETIZED_BOLD to force using synthetized bold,
    -- which, with XText, makes a bold string the same width as it non-bolded.
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = Size.padding.small, -- vertical padding (should it be function of face.size ?)
    -- (no horizontal padding is added)
    max_width = nil,
    truncate_with_ellipsis = true, -- when truncation at max_width needed, add "…"
    truncate_left = false, -- truncate on the right by default

    -- Force a baseline and height to use instead of those obtained from the font used
    -- (mostly only useful for TouchMenu to display font names in their own font, to
    -- ensure they get correctly vertically aligned in the menu)
    forced_baseline = nil,
    forced_height = nil,
    callback = nil,
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
}

function VocabularyTableItem:init()
    self.text_widget = TextWidget:new {
        text = self.text,
        face = self.face,
        bold = self.bold,
        fgcolor = self.fgcolor,
        padding = self.padding,
        max_width = self.max_width,
        truncate_with_ellipsis = self.truncate_with_ellipsis,
        truncate_left = self.truncate_left,
        forced_baseline = self.forced_baseline,
        forced_height = self.forced_height,
        max_width = self.width,
    }

    local text_size = self.text_widget:getSize()
    local center_container_width
    if self.width == nil then
        center_container_width = text_size.w
    else
        center_container_width = self.width
    end

    self.center_container = CenterContainer:new{
        dimen = Geom:new{
            w = center_container_width,
            h = text_size.h,
        },
        self.text_widget,
    }

    self.frame = FrameContainer:new{
        bordersize = self.bordersize,
        color = self.border_color,
        background = self.background,
        margin = 0,
        padding = 0,
        padding_top = self.padding_h,
        padding_bottom = self.padding_h,
        self.center_container,
    }

    self.dimen = self.frame:getSize()

    if self.callback then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Tap Item",
            }
        }
    end

    self[1] = self.frame
end

function VocabularyTableItem:highlight()
    if G_reader_settings:isFalse("flash_ui") then
        return
    else
        local highlight_dimen = self.dimen

        -- Highlight
        --
        self[1].invert = true
        UIManager:widgetInvert(self[1], highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
        UIManager:setDirty(nil, "fast", highlight_dimen)

        UIManager:forceRePaint()
        UIManager:yieldToEPDC()

        -- Unhighlight
        --
        self[1].invert = false
        UIManager:widgetInvert(self[1], highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
        UIManager:setDirty(nil, "ui", highlight_dimen)

        UIManager:forceRePaint()

    end
end

function VocabularyTableItem:onTap()
    self:highlight()
    self.callback()
    return true
end

function VocabularyTableItem:setText(text)
    if text ~= self.text then
        self.text_widget:setText(text)
    end
end

local LEARNING_TABLE = "learning"
local LEARNED_TABLE = "learned"

local VocabularyTable = InputContainer:new {
    title = _("Vocabulary")
}

function VocabularyTable:init()
    if not self.table_type or (self.table_type ~= LEARNING_TABLE and self.table_type ~= LEARNED_TABLE) then
        self.table_type = LEARNING_TABLE
    end

    local temp = self:buildVocabularyTableItem(1,{
        word = "temp",
        definition = "temp"
    })
    self.item_dimen = temp.dimen

    local close_button = CloseButton:new {
        window = self,
        padding_top = Size.margin.title,
    }
    local title_widget = TextWidget:new{
        text = self.title,
        face = Font:getFace("tfont", 26),
        max_width = Screen:getWidth() - (close_button:getSize().w * 2),
        padding = Size.padding.large
    }
    local menu_title_container = FrameContainer:new {
        bordersize = 0,
        margin = 0,
        padding = 0,
        padding_left = close_button:getSize().w,
        CenterContainer:new{
            dimen = Geom:new{
                w = Screen:getWidth() - (close_button:getSize().w * 2),
                h = title_widget:getSize().h,
            },
            title_widget,
        }
    }
    self.title_bar = VerticalGroup:new {
        HorizontalGroup:new {
            menu_title_container,
            close_button
        },
        LineWidget:new{
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Size.line.thick,
            }
        }
    }

    self.widget = VerticalGroup:new {
        self.title_bar,
    }

    self.button_table = VerticalGroup:new {
        LineWidget:new{
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Size.line.thick,
            }
        }
    }

    if self.table_type == LEARNING_TABLE then
        self.button_learn = VocabularyTableItem:new {
            text = _("Learn"),
            face = Font:getFace("cfont"),
            bold = true,
            width = Screen:getWidth(),
            padding = Size.padding.small,
            padding_h = Screen:scaleBySize(10),
            callback = function()
                logger.info("Learn word")
            end
        }
        table.insert(self.button_table, self.button_learn)
        table.insert(self.button_table, LineWidget:new{
            background = Blitbuffer.COLOR_GRAY,
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Size.line.medium,
            }
        })
    end

    local prev_page_text = "◁◁"
    local next_page_text = "▷▷"
    self.button_prev_page = Button:new{
        text = prev_page_text,
        width = (Screen:getWidth() - Size.line.medium * 2)/3,
        bordersize = 0,
        margin = 0,
        padding = 0,
        callback = function()
            self:changeToPrevPage()
        end,
        hold_callback = function()
            self:changeToFirstPage()
        end
    }

    self.page_info_text = VocabularyTableItem:new {
        text = _("Page info"),
        face = Font:getFace("cfont"),
        width = (Screen:getWidth() - Size.line.medium * 2)/3,
        padding = 0,
        padding_h = Screen:scaleBySize(10),
    }

    self.button_next_page = Button:new{
        text = next_page_text,
        width = (Screen:getWidth() - Size.line.medium * 2)/3,
        bordersize = 0,
        margin = 0,
        padding = 0,
        callback = function()
            self:changeToNextPage()
        end,
        hold_callback = function()
            self:changeToLastPage()
        end
    }

    local line_sep = LineWidget:new{
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new{
            w = Size.line.medium,
            h = self.button_prev_page:getSize().h,
        }
    }
    local page_nav = HorizontalGroup:new {
        self.button_prev_page,
        line_sep,
        self.page_info_text,
        line_sep,
        self.button_next_page
    }

    table.insert(self.button_table, page_nav)

    --Calculate items_per_page

    self:changePage(1, true)
    self.items_height = Screen:getHeight() - self.title_bar:getSize().h - self.button_table:getSize().h
    self.items_per_page = 2 * math.floor(self.items_height / self.item_dimen.h)
    if self.table_type == LEARNING_TABLE then
        self.total_items = VocabularyRepository:countLearning()
    else
        self.total_items = VocabularyRepository:countLearned()
    end
    if (self.total_items / self.items_per_page) - math.floor(self.total_items / self.items_per_page) == 0 then
        self.total_pages = math.floor(self.total_items / self.items_per_page)
    else
        self.total_pages = math.floor(self.total_items / self.items_per_page) + 1
    end

    self.button_prev_page:enableDisable(self:isPrevPageAvailable())
    self.button_next_page:enableDisable(self:isNextPageAvailable())
    self:buildItemsContent()

    self.page_info_text:setText(FFIUtil.template(_("Page %1 of %2"), self.page, self.total_pages))

    self.item_frame = WidgetContainer:new {
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = self.items_height,
        },
        self.items_content
    }

    table.insert(self.widget, self.item_frame)
    table.insert(self.widget, self.button_table)

    self.frame = FrameContainer:new {
        bordersize = 0,
        margin = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.widget
    }

    self.dimen = Screen:getSize()

    self.ges_events = {
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            },
        }
    }

    self[1] = self.frame
end

function VocabularyTable:setCard(index)
    if self.card == nil then
        self.card = FlashCard:new {
            word = self.items[index].word,
            definition = self.items[index].definition,
            index = index,
            swipe_east_callback = function()
                self:prevCard()
            end,
            swipe_west_callback = function()
                self:nextCard()
            end
        }
    end
    if index == self.card.index then
        return
    end
    self.card.word = self.items[index].word
    self.card.definition = self.items[index].definition
    self.card.index = index
    self.card:update()
end

function VocabularyTable:nextCard()
    if self.card.index < #self.items then
        self:setCard(self.card.index + 1)
    else
        self:setCard(1)
    end
end

function VocabularyTable:prevCard()
    if self.card.index > 1 then
        self:setCard(self.card.index - 1)
    else
        self:setCard(#self.items)
    end
end

function VocabularyTable:update()
    self[1]:free()

    self:buildItems()
    self.page_info_text:setText(FFIUtil.template(_("Page %1 of %2"), self.page, self.total_pages))
    self.button_prev_page:enableDisable(self:isPrevPageAvailable())
    self.button_next_page:enableDisable(self:isNextPageAvailable())

    UIManager:setDirty(self, function()
        return "partial", self.dimen
    end)
end

function VocabularyTable:isPrevPageAvailable()
    return self.page > 1
end

function VocabularyTable:isNextPageAvailable()
    return self.page < self.total_pages
end

function VocabularyTable:changeToNextPage()
    if self:isNextPageAvailable() then
        self:changePage(self.page + 1)
    elseif self.total_pages > 1 then -- restart at first if end reached
        self:changePage(1)
    end
end

function VocabularyTable:changeToFirstPage()
    if self:isPrevPageAvailable() then
        self:changePage(1)
    end
end

function VocabularyTable:changeToPrevPage()
    if self:isPrevPageAvailable() then
        self:changePage(self.page - 1)
    elseif self.total_pages > 1 then -- restart at end if first reached
        self:changePage(self.total_pages)
    end
end

function VocabularyTable:changeToLastPage()
    if self:isNextPageAvailable() then
        self:changePage(self.total_pages)
    end
end


function VocabularyTable:changePage(page, skip_update)
    if self.page == page then
        return
    end

    self.page = page

    if not skip_update then
        self:update()
    end
end

function VocabularyTable:buildItemsContent()
    if not self.items_content then
        self.items_content = VerticalGroup:new {
            align = "left"
        }
    end

    self.items_content:clear()

    self.items = {}
    if self.table_type == LEARNING_TABLE then
        self.items = VocabularyRepository:findAllLearning()
    else
        self.items = VocabularyRepository:findAllLearned()
    end

    local i = (self.page - 1) * self.items_per_page + 1
    while i <= (self.page * self.items_per_page) and i <= self.total_items do
        local horizontal = HorizontalGroup:new {}
        if self.items[i] == nil then
            return
        end
        table.insert(horizontal, self:buildVocabularyTableItem(i, self.items[i]))
        i = i + 1
        if self.items[i] ~= nil then
            table.insert(horizontal, self:buildVocabularyTableItem(i, self.items[i]))
        end
        table.insert(self.items_content, horizontal)
        i = i + 1
    end
end

function VocabularyTable:buildVocabularyTableItem(item_position, item)
    return VocabularyTableItem:new {
        text = item.word,
        face = Font:getFace("cfont", 30),
        width = Screen:getWidth()/2 - Size.border.thin * 2,
        padding = Size.padding.large,
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_GRAY_E,
        callback = function()
            self:setCard(item_position)
            UIManager:show(self.card, "ui")
        end
    }
end

function VocabularyTable:onSwipe(_, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "south" then
        self:onClose()
        return true
    end
end

function VocabularyTable:onClose()
    UIManager:close(self, "partial")
    return true
end

return VocabularyTable