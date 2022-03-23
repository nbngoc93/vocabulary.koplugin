
local UIManager = require("ui/uimanager")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
ScrollTextWidget.height = nil
local GestureRange = require("ui/gesturerange")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")

local VocabularyRepository = require("widget/vocabularyrepository")

local _ = require("gettext")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")

local Button = require("ui/widget/button")

function Button:incorrect()
    if self.text then
        self.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
    else
        self.label_widget.dim = true
    end
    self.background = Blitbuffer.COLOR_GRAY
    self.enabled = false
    self:init()
end

function Button:correct()
    self.enabled = false
end

function Button:normal()
    if self.text then
        self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
    else
        self.label_widget.dim = false
    end
    self.background = Blitbuffer.COLOR_WHITE
    self.enabled = true
    self:init()
end

local logger = require("logger")
local dump = require("dump")

local Learn = InputContainer:new {

}

function Learn:init()
    if #self.items < 4 then
        self[1] = CenterContainer:new {
            dimen = Geom:new{
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
            FrameContainer:new {
                bordersize = 1,
                padding = Size.padding.large,
                background = Blitbuffer.COLOR_WHITE,
                radius = Size.radius.window,
                TextBoxWidget:new {
                    text = _("Need at least 4 words to start play learning game!!!"),
                    face = Font:getFace("infofont"),
                    width = math.floor(Screen:getWidth() * 2/3)
                }
            }
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    },
                },
                doc = "Tap Item",
            }
        }
        return
    end

    local padding_top_container = WidgetContainer:new {
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:scaleBySize(10),
        }
    }

    self.item_index = 1

    self.question_text = VerticalGroup:new {}
    local question_center_container = CenterContainer:new {
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() * 1/3
        },
        self.question_text
    }
    self:buildQuestionText()

    self.buttonA = Button:new {
        text = "Button A",
        text_font_size = 30,
        width = Screen:getWidth() * 4/5,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:checkAnswer(self.buttonA)
        end,
        hold_callback = function()
        end
    }

    self.buttonB = Button:new {
        text = "Button B",
        text_font_size = 30,
        width = Screen:getWidth() * 4/5,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:checkAnswer(self.buttonB)
        end,
        hold_callback = function()
        end
    }

    self.buttonC = Button:new {
        text = "Button C",
        text_font_size = 30,
        width = Screen:getWidth() * 4/5,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:checkAnswer(self.buttonC)
        end,
        hold_callback = function()
        end
    }

    self.buttonD = Button:new {
        text = "Button D",
        text_font_size = 30,
        width = Screen:getWidth() * 4/5,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:checkAnswer(self.buttonD)
        end,
        hold_callback = function()
        end
    }
    self.buttons = {
        self.buttonA,
        self.buttonB,
        self.buttonC,
        self.buttonD,
    }

    self:buildAnswerButton()

    local margin_button = WidgetContainer:new {
        dimen = Geom:new {
            w = 1,
            h = Size.margin.default
        }
    }
    local button_vertical_group = VerticalGroup:new {
        self.buttonA,
        margin_button,
        self.buttonB,
        margin_button,
        self.buttonC,
        margin_button,
        self.buttonD,
    }

    local button_close = Button:new {
        text = _("Close"),
        text_font_size = 30,
        width = Screen:getWidth() - 2,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:onClose()
        end,
    }

    self.button_next = Button:new {
        text = _("Next"),
        text_font_size = 36,
        bordersize = 0,
        margin = 0,
        padding = Size.padding.default,
        callback = function()
            self:next()
        end,
    }

    self.result_text = TextWidget:new {
        text = "",
        face = Font:getFace("cfont", 30),
        bold = true,
        padding = Size.padding.small,
    }

    local result_center_container = CenterContainer:new {
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = (Screen:getHeight() - padding_top_container:getSize().h - question_center_container:getSize().h - button_vertical_group:getSize().h - button_close:getSize().h)/2
        },
        self.result_text
    }

    self.button_next_container = VerticalGroup:new{}

    local next_center_container = CenterContainer:new {
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = (Screen:getHeight() - padding_top_container:getSize().h - question_center_container:getSize().h - button_vertical_group:getSize().h - button_close:getSize().h)/2
        },
        self.button_next_container
    }

    self.frame = FrameContainer:new {
        bordersize = 1,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            padding_top_container,
            question_center_container,
            button_vertical_group,
            result_center_container,
            next_center_container,
            button_close
        }
    }
    self[1] = self.frame

end

function Learn:update()
    self[1]:free()

    self:buildQuestionText()

    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
end

function Learn:onTapClose(_, ges)
    self:onClose()
    return true
end

function Learn:onClose()
    UIManager:close(self, "partial")
    return true
end

local function contains(table, item)
    for _, v in pairs(table) do
        if v == item then
            return true
        end
    end
    return false
end

local function shuffle(table)
    for i = #table, 2, -1 do
        local j = math.random(i)
        table[i], table[j] = table[j], table[i]
    end
end

function Learn:buildQuestionText()
    self.question_text:clear()
    local scroll_text_question = ScrollTextWidget:new {
        text = self.items[self.item_index].definition,
        face = Font:getFace("cfont", 26),
        alignment = "center",
        width = Screen:getWidth() - 2 * Screen:scaleBySize(10),
        height = nil,
        dialog = self
    }
    if scroll_text_question.dimen.h > (Screen:getHeight() * 1/3) then
        scroll_text_question.height = Screen:getHeight() * 1/3
        scroll_text_question:init()
    end
    table.insert(self.question_text, scroll_text_question)
end

function Learn:buildAnswerButton()
    local answers = {}
    table.insert(answers, self.items[self.item_index].word)
    repeat
        local word = self:pickRandomWord()
        if not contains(answers, word) then
            table.insert(answers, word)
        end
    until #answers >= 4
    shuffle(answers)

    for i, button in pairs(self.buttons) do
        button:setText(answers[i], Screen:getWidth() * 4/5)
    end
end

function Learn:checkAnswer(selected_button)
    local correctSelected = false
    for _, button in pairs(self.buttons) do
        local isCorrectButton = false
        if button.text == self.items[self.item_index].word then
            isCorrectButton = true
        end
        if isCorrectButton and selected_button == button then
            correctSelected = true
        end
        if isCorrectButton then
            button:correct()
        else
            button:incorrect()
        end
        button:disable()
    end
    if correctSelected then
        self:correct(self.items[self.item_index])
    else
        self:incorrect(self.items[self.item_index])
    end


    if self.item_index < #self.items then
        self:showNext()
    end
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
end

function Learn:updateCorrect(item)
    local learning = VocabularyRepository:getLearningByWord(item.word)
    learning.total_correct = learning.total_correct + 1
    VocabularyRepository:saveLearning(learning)
end

function Learn:updateIncorrect(item)
    local learning = VocabularyRepository:getLearningByWord(item.word)
    learning.total_incorrect = learning.total_incorrect + 1
    VocabularyRepository:saveLearning(learning)
end

function Learn:pickRandomWord()
    local i = math.random(1, #self.items)
    return self.items[i].word
end

function Learn:next()
    if self.item_index < #self.items then
        self.item_index = self.item_index + 1
    end
    for _, button in pairs(self.buttons) do
        button:normal()
    end
    self:hideResult()
    self:hideNext()
    self:buildAnswerButton()
    self:update()
end

function Learn:correct(item)
    self:showResult(_("Correct!!!"))
    self:updateCorrect(item)
end

function Learn:incorrect(item)
    self:showResult(_("Incorrect!!!"))
    self:updateIncorrect(item)
end

function Learn:showResult(text)
    self.result_text:setText(text)
end

function Learn:hideResult()
    self.result_text:setText("")
end

function Learn:showNext()
    self.button_next_container:clear()
    table.insert(self.button_next_container, self.button_next)
end

function Learn:hideNext()
    self.button_next_container:clear()
end

return Learn