
local Widget = require("ui/widget/widget")

local logger = require("logger")

local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local SQ3 = require("lua-ljsqlite3/init")

local DB_SCHEMA_VERSION = 20220311

local VOCABULARY_DIR = DataStorage:getDataDir() .. "/vocabulary"
local DB_LOCATION = VOCABULARY_DIR .."/vocabulary.sqlite3"

local VocabularyRepository = Widget:new {}

VocabularyRepository.default_settings = {
    db_created = nil
}

function VocabularyRepository:init()
    self.settings = G_reader_settings:readSetting("vocabulary", self.default_settings)
    self:initDB()
end

function VocabularyRepository:rowexec(command, ...)
    local conn = SQ3.open(DB_LOCATION)
    local stmt = conn:prepare(command)
    local res = stmt:reset():bind(...):_step()
    if stmt:_step() then
        error("ljsqlite3[misuse] multiple records returned, 1 expected\n" .. debug.traceback())
    end
    stmt:close()
    conn:close()
    if res then
        return unpack(res)
    else
        return nil
    end
end

local VOCABULARY_INIT_DB_SQL = [[
    CREATE TABLE IF NOT EXISTS learning
    (
        id integer PRIMARY KEY autoincrement,
        word            TEXT NOT NULL,
        definition      TEXT NOT NULL,
        full_definition TEXT NOT NULL,
        total_correct   integer NOT NULL DEFAULT 0,
        total_incorrect integer NOT NULL DEFAULT 0,
        UNIQUE (word)
    );
    CREATE TABLE IF NOT EXISTS learned
    (
        id integer PRIMARY KEY autoincrement,
        word TEXT NOT NULL,
        definition TEXT NOT NULL,
        full_definition TEXT NOT NULL,
        UNIQUE (word)
    );
]]

function VocabularyRepository:initDB()
    if self.settings.db_created and lfs.attributes(DB_LOCATION, "mode") == "file" then
        return
    end
    if lfs.attributes(VOCABULARY_DIR, "mode") ~= "directory" then
        lfs.mkdir(VOCABULARY_DIR)
    end
    local conn = SQ3.open(DB_LOCATION)
    self:createDB(conn)
    self.settings.db_created = true
end

function VocabularyRepository:createDB(conn)
    -- Make it WAL, if possible
    if Device:canUseWAL() then
        conn:exec("PRAGMA journal_mode=WAL;")
    else
        conn:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    conn:exec(VOCABULARY_INIT_DB_SQL)

    -- DB schema version
    conn:exec(string.format("PRAGMA user_version=%d;", DB_SCHEMA_VERSION))
end

function VocabularyRepository:getLearningByWord(word)
    local id, w, definition, full_definition, total_correct, total_incorrect = self:rowexec("SELECT id, word, definition, full_definition, total_correct, total_incorrect FROM learning WHERE word == ?", word)
    return {
        id = id,
        word = w,
        definition = definition,
        full_definition = full_definition,
        total_correct = total_correct,
        total_incorrect = total_incorrect
    }
end

function VocabularyRepository:saveLearning(learning)
    if learning.word == nil or learning.word == "" or learning.definition == nil or learning.definition == "" then
        return
    end
    if learning.total_correct == nil then
        learning.total_correct = 0
    end
    if learning.total_incorrect == nil then
        learning.total_incorrect = 0
    end
    local conn = SQ3.open(DB_LOCATION)

    local word = self:rowexec("SELECT word FROM learning WHERE word == ?", learning.word)

    local stmt
    if word ~= nil then
        stmt = conn:prepare("UPDATE learning SET definition = ?, full_definition = ?, total_correct = ?, total_incorrect = ? WHERE word = ?")
        stmt:reset():bind(learning.definition, learning.full_definition, learning.total_correct, learning.total_incorrect, learning.word):step()
    else
        stmt = conn:prepare("INSERT INTO learning (definition, full_definition, word) VALUES (?, ?, ?)")
        stmt:reset():bind(learning.definition, learning.full_definition, learning.word):step()
    end
    stmt:close()
    conn:close()
    return learning
end

function VocabularyRepository:findAllLearning(limit, page)
    if page == nil then
        page = 1
    end
    local conn = SQ3.open(DB_LOCATION)
    local findAllSql = "SELECT id, word, definition, full_definition FROM learning"
    if limit ~= nil then
        local offset = (page - 1) * limit
        findAllSql = findAllSql .. string.format(" LIMIT %d OFFSET %d", limit, offset)
    end
    local sqlResults = conn:execsql(findAllSql)
    conn:close()
    return self:mapResultsSql(sqlResults)
end

function VocabularyRepository:countLearning()
    local conn = SQ3.open(DB_LOCATION)
    local count = conn:rowexec("SELECT COUNT(*) FROM learning")
    conn:close()
    return tonumber(count)
end

function VocabularyRepository:findAllLearned(limit, page)
    if page == nil then
        page = 1
    end
    local conn = SQ3.open(DB_LOCATION)
    local findAllSql = "SELECT id, word, definition, full_definition FROM learned"
    if limit ~= nil then
        local offset = (page - 1) * limit
        findAllSql = findAllSql .. string.format(" LIMIT %d OFFSET %d", limit, offset)
    end
    local sqlResults = conn:execsql(findAllSql)
    conn:close()
    return self:mapResultsSql(sqlResults)
end

function VocabularyRepository:countLearned()
    local conn = SQ3.open(DB_LOCATION)
    local count = conn:rowexec("SELECT COUNT(*) FROM learned")
    conn:close()
    return tonumber(count)
end

function VocabularyRepository:mapResultsSql(sqlResults)
    if sqlResults[0] == nil or #sqlResults[0] == 0 then
        return {}
    end
    local results = {}
    for i = 1, #sqlResults[1] do
        local result = {}
        for j = 1, #sqlResults[0] do
            result[sqlResults[0][j]] = sqlResults[sqlResults[0][j]][i]
        end
        table.insert(results, result)
    end
    return results
end

return VocabularyRepository