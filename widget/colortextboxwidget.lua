--[[--
extend TextBoxWidget but can change background color
--]]--

local TextBoxWidget = require("ui/widget/textboxwidget")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local RenderText = require("ui/rendertext")

local ColorTextBoxWidget = TextBoxWidget:extend {
    bgcolor = Blitbuffer.COLOR_WHITE
}

function ColorTextBoxWidget:_renderText(start_row_idx, end_row_idx)
    if start_row_idx < 1 then start_row_idx = 1 end
    if end_row_idx > #self.vertical_string_list then end_row_idx = #self.vertical_string_list end
    local row_count = end_row_idx == 0 and 1 or end_row_idx - start_row_idx + 1
    -- We need a bb with the full height (even if we display only a few lines, we
    -- may have to draw an image bigger than these lines)
    local h = self.height or self.line_height_px * row_count
    h = h + self.line_glyph_extra_height
    if self._bb then self._bb:free() end
    local bbtype = nil
    if self.line_num_to_image and self.line_num_to_image[start_row_idx] then
        bbtype = Screen:isColorEnabled() and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
    end
    self._bb = Blitbuffer.new(self.width, h, bbtype)
    self._bb:fill(self.bgcolor)

    local y = self.line_glyph_baseline
    if self.use_xtext then
        for i = start_row_idx, end_row_idx do
            local line = self.vertical_string_list[i]
            if self.line_with_ellipsis and i == self.line_with_ellipsis and not line.ellipsis_added then
                -- Requested to add an ellipsis on this line
                local ellipsis_width = RenderText:getEllipsisWidth(self.face)
                -- no bold: xtext does synthetized bold with normal metrics
                line.width = line.width + ellipsis_width
                if line.width > line.targeted_width then
                    -- The ellipsis would overflow: we need to re-makeLine()
                    -- this line with a smaller targeted_width
                    line = self._xtext:makeLine(line.offset, line.targeted_width - ellipsis_width, false, self._tabstop_width)
                    self.vertical_string_list[i] = line -- replace the former one
                end
                if line.end_offset and line.end_offset < #self._xtext then
                    -- We'll have shapeLine add the ellipsis to the returned glyphs
                    line.end_offset = line.end_offset + 1
                    line.idx_to_substitute_with_ellipsis = line.end_offset
                end
                line.ellipsis_added = true -- No need to redo it next time
            end
            self:_shapeLine(line)
            if line.xglyphs then -- non-empty line
                for __, xglyph in ipairs(line.xglyphs) do
                    if not xglyph.no_drawing then
                        local face = self.face.getFallbackFont(xglyph.font_num) -- callback (not a method)
                        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
                        local color = self.fgcolor
                        if self._alt_color_for_rtl then
                            color = xglyph.is_rtl and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
                        end
                        self._bb:colorblitFrom(glyph.bb,
                                xglyph.x0 + glyph.l + xglyph.x_offset,
                                y - glyph.t - xglyph.y_offset,
                                0, 0, glyph.bb:getWidth(), glyph.bb:getHeight(), color)
                    end
                end
            end
            y = y + self.line_height_px
        end
        -- Render image if any
        self:_renderImage(start_row_idx)
        return
    end

    -- Only when not self.use_xtext:

    for i = start_row_idx, end_row_idx do
        local line = self.vertical_string_list[i]
        local pen_x = 0 -- when alignment == "left"
        if self.alignment == "center" then
            pen_x = (self.width - line.width)/2 or 0
        elseif self.alignment == "right" then
            pen_x = (self.width - line.width)
        end
        -- Note: we use kerning=true in all RenderText calls
        -- (But kerning should probably not be used with monospaced fonts.)
        local line_text = self:_getLineText(line)
        if self.line_with_ellipsis and i == self.line_with_ellipsis then
            -- Requested to add an ellipsis on this line
            local ellipsis_width = RenderText:getEllipsisWidth(self.face, self.bold)
            if line.width + ellipsis_width > self.width then
                -- We could try to find the last break point (space, CJK) to
                -- truncate there and add the ellipsis, but well...
                line_text = RenderText:truncateTextByWidth(line_text, self.face, self.width, true, self.bold)
            else
                line_text = line_text .. "…"
            end
        end
        RenderText:renderUtf8Text(self._bb, pen_x, y, self.face, line_text, true, self.bold, self.fgcolor, nil, self:_getLinePads(line))
        y = y + self.line_height_px
    end

    -- Render image if any
    self:_renderImage(start_row_idx)
end

return ColorTextBoxWidget