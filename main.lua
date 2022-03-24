
local _ = require("gettext")
local logger = require("logger")
local dump = require("dump")
local Dispatcher = require("dispatcher")  -- luacheck:ignore

local Blitbuffer = require("ffi/blitbuffer")
local ffiUtil  = require("ffi/util")
local T = ffiUtil.template
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local util  = require("util")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local KeyValuePage = require("ui/widget/keyvaluepage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local InfoMessage = require("ui/widget/infomessage")

local VocabularyTable = require("widget/vocabularytable")
local VocabularyLookup = require("widget/vocabularylookup")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
function ReaderDictionary:look(word)
    return self:startSdcv(word, self.enabled_dict_names, not self.disable_fuzzy_search)
end

local DataStorage = require("datastorage")
local LuaData = require("luadata")
local VocabularyRepository = require("widget/vocabularyrepository")

local lookup_history = LuaData:open(DataStorage:getSettingsDir() .. "/lookup_history.lua", { name = "LookupHistory" })
local lookup_history_table = {}

local VocabularyBuilder = WidgetContainer:new {
    name = "vocabulary builder"
}

--function VocabularyBuilder:onDispatcherRegisterActions()
--    Dispatcher:registerAction("vocabulary_action", {category="none", event="VocabularyBuilder", title=_("Vocabulary Builder"), general=true,})
--end

VocabularyRepository:init()

function VocabularyBuilder:init()
    --self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.dict = ReaderDictionary:new({ui = self.ui})
end

function VocabularyBuilder:addToMainMenu(menu_items)
    menu_items.vocabulary_builder = {
        text = _("Vocabulary Builder"),
        -- in which menu this should be appended
        sorting_hint = "search",
        -- a callback when tapping
        callback = function()
            self:onShowMenu();
        end,
    }
end

function VocabularyBuilder:onShowMenu()
    local items_per_page = nil
    local items_font_size = 24
    local items_with_dots = false
    self.menu = Menu:new{
        title = _("Vocabulary Builder"),
        item_table = self:buildMenuItems(),
        state_size = nil,
        ui = self.ui,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("x_smallinfofont"),
        single_line = true,
        align_baselines = true,
        with_dots = items_with_dots,
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        items_padding = nil,
        line_color = Blitbuffer.COLOR_WHITE,
    }
    UIManager:show(self.menu)
end

function VocabularyBuilder:buildMenuItems()
    lookup_history = LuaData:open(DataStorage:getSettingsDir() .. "/lookup_history.lua", { name = "LookupHistory" })
    if lookup_history:has("lookup_history") then
        lookup_history_table = lookup_history:readSetting("lookup_history")
    else
        lookup_history_table = {}
    end
    local item_table = {}
    if #lookup_history_table > 0 then
        table.insert(item_table, {
            text = _("Lookup History " .. "(" .. #lookup_history_table .. ")"),
            callback = function()
                self:onShowLookupHistory()
            end,
        })
    end
    local count_learning = VocabularyRepository:countLearning()
    table.insert(item_table, {
        text = _("Learning") .. string.format(" (%d)", count_learning),
        callback = function()
            self.learning = VocabularyTable:new{
                title = _("Learning Word")
            }
            self.learning.onClose = function()
                self:updateMenuItems()
                UIManager:close(self.learning)
            end
            UIManager:show(self.learning, "partial")
        end,
    })
    local count_learned = VocabularyRepository:countLearned()
    table.insert(item_table, {
        text = _("Mastered") .. string.format(" (%d)", count_learned),
        callback = function()
            self.learned = VocabularyTable:new{
                title = _("Mastered"),
                table_type = "learned",
            }
            self.learned.onClose = function()
                self:updateMenuItems()
                UIManager:close(self.learned)
            end
            UIManager:show(self.learned, "partial")
        end,
    })
    return item_table
end

function VocabularyBuilder:updateMenuItems()
    self.menu.item_table = self:buildMenuItems()
    self.menu:updateItems()
end

local function tidyMarkup(results)
    local cdata_tag = "<!%[CDATA%[(.-)%]%]>"
    local format_escape = "&[29Ib%+]{(.-)}"
    for _, result in ipairs(results) do
            local def = result.definition
            -- preserve the <br> tag for line break
            def = def:gsub("<[bB][rR] ?/?>", "\n")
            -- parse CDATA text in XML
            if def:find(cdata_tag) then
                def = def:gsub(cdata_tag, "%1")
                -- ignore format strings
                while def:find(format_escape) do
                    def = def:gsub(format_escape, "%1")
                end
            end
            -- convert any htmlentities (&gt;, &quot;...)
            def = util.htmlEntitiesToUtf8(def)
            -- ignore all markup tags
            def = def:gsub("%b<>", "")
            -- strip all leading empty lines/spaces
            def = def:gsub("^%s+", "")
            result.definition = def
    end
    return results
end

function VocabularyBuilder:onShowLookupHistory()
    local kv_pairs = {}
    local previous_title
    for i = #lookup_history_table, 1, -1 do
        local value = lookup_history_table[i]
        if value.book_title ~= previous_title then
            table.insert(kv_pairs, { value.book_title..":", "" })
        end
        previous_title = value.book_title
        table.insert(kv_pairs, {
            os.date("%Y-%m-%d %H:%M:%S", value.time),
            value.word,
            callback = function()
                self:onLookupWord(value.word)
            end
        })
    end
    local key_value_page = KeyValuePage:new{
        title = _("Dictionary lookup history"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
    }
    key_value_page.onClose = function()
        self:updateMenuItems()
        UIManager:close(key_value_page)
    end
    UIManager:show(key_value_page)
end

function VocabularyBuilder:showDict(word)
    self.dict:showLookupInfo(word, 0.5)
    local results = self.dict:look(word)
    self.vlookup = VocabularyLookup:new {
        word = word,
        results = tidyMarkup(results),
        add_learning_callback = function(w, definition, full_definition)
            if definition ~= "" and definition ~= nil then
                VocabularyRepository:saveLearning({
                    word = w,
                    definition = definition,
                    full_definition = full_definition
                })
                UIManager:show(InfoMessage:new {
                    text = _("Added to learning!") .. string.format("\nWord: %s\n%s", w, definition),
                })
            else
                UIManager:show(InfoMessage:new {
                    text = _("You need select the definition you want to learn (Just tap on it)"),
                })
            end

        end
    }
    self.dict:dismissLookupInfo()
    UIManager:show(self.vlookup, "partial")
end

function VocabularyBuilder:onLookupWord(word)
    Trapper:wrap(function()
        self:showDict(word)
    end)
end

return VocabularyBuilder