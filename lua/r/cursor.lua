local M = {}

--- Remove leading spaces and trailing comments from string
---@param line string Line to clean
local clean_current_line = function(line)
    local cleanline = line:gsub("^%s*", "")
    cleanline = cleanline:gsub("#.*", "")
    if vim.o.filetype == "r" then cleanline = M.clean_oxygen_line(cleanline) end
    return cleanline
end

M.clean_oxygen_line = function(line)
    if line:find("^%s*#'") then
        local synID = vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1)
        local synName = vim.fn.synIDattr(synID, "name")
        if synName == "rOExamples" then line = string.gsub(line, "^%s*#'", "") end
    end
    return line
end

-- Returns the line number of the first non-empty line after the current
-- paragraph. If the cursor is on the last paragraph, returns the last line
-- number.
M.find_next_paragraph = function()
    local current_line = vim.fn.line(".")
    local next_empty_line = current_line

    -- Search for the next empty line (paragraph separator)
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) == "" then break end
        next_empty_line = next_empty_line + 1
    end

    -- Move cursor to the first non-empty line after the empty line
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) ~= "" then
            return next_empty_line
        end
        next_empty_line = next_empty_line + 1
    end

    return vim.fn.line("$")
end

-- Moves the cursor to the first non-empty line after the current paragraph.
M.move_next_paragraph = function()
    vim.api.nvim_win_set_cursor(0, { M.find_next_paragraph(), 0 })
end

-- Moe the cursor to the next line
M.move_next_line = function()
    local lnum = vim.fn.line(".")
    if lnum == vim.fn.line("$") then return end

    local filetype = vim.o.filetype
    local has_code = false
    while not has_code do
        lnum = lnum + 1
        local curline = clean_current_line(vim.fn.getline(lnum))
        if filetype == "rnoweb" and string.sub(curline, 1, 1) == "@" then
            require("r.rnw").next_chunk()
            return
        elseif (filetype == "rmd" or filetype == "quarto") and curline:find("^```$") then
            require("r.rmd").next_chunk()
            return
        end
        if #curline > 0 then break end
    end
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
end

M.get_first_obj = function()
    -- FIXME: The algorithm is too simple to correctly get the first object
    -- in complex cases.
    -- FIXME: try to use tree-sitter instead of patterns to find the first object
    -- of a function.

    local firstobj = ""
    local line = vim.fn.getline(vim.fn.line(".")):gsub("#.*", "")
    local begin = vim.fn.col(".")

    local find_po = function(s)
        if s:find("|>") then
            s = s:gsub("(.*)%s*|>.*", "%1")
        elseif s:find("%%>%%") then
            s = s:gsub("(.*)%s*%%>%%.*", "%1")
        elseif s:find("%+") then
            s = s:gsub("(.*)%s*%+.*", "%1")
        end
        local i = #s - 1
        local j = #s - 1
        local op = 0
        while i > 1 do
            if s:sub(i, i):find("[%(%[%{]") then
                op = op + 1
            elseif s:sub(i, i):find("[%)%]%}]") then
                op = op - 1
            end
            if op == 0 and i > 1 and not s:sub(i - 1, i - 1):find('[%w%d%._"%$@%(]') then
                return s:sub(i, j)
            end
            i = i - 1
        end
        return s:sub(i, j)
    end

    -- Check if the first argument is being passed through a pipe operator
    local piece = line:sub(1, begin)
    if piece:find("|>") or piece:find("%%>%%") or piece:find("%+") then
        firstobj = find_po(piece)
        return firstobj
    elseif line:find("^%s+") then
        local pline = vim.fn.getline(vim.fn.line(".") - 1):gsub("#.*", "")
        if pline:find("|>%s*$") or pline:find("%%>%%%s*$") or pline:find("%+%s*$") then
            firstobj = find_po(pline)
            return firstobj
        end
    end

    local find_fo = function(s)
        local i = 1
        local j = 1
        local op = 0
        while j < #s and not s:sub(j, j):find('[%w%d%._"%$@]') do
            j = j + 1
        end
        while j <= #s do
            if s:sub(j, j):find("[%(%[%{]") then
                op = op + 1
            elseif s:sub(j, j):find("[%)%]%}]") then
                op = op - 1
            end
            if
                op == 0
                and (j + 1) <= #s
                and not s:sub(j + 1, j + 1):find('[%w%d%._"%$@%(]')
            then
                return i, j
            end
            j = j + 1
        end
        return 0, 0
    end

    if vim.fn.strlen(line) > begin then
        piece = line:sub(begin)
        if piece:find("^[%w%._][%w%d%._]-%s-%(") then
            piece = piece:gsub("^[%w%d%._]-%s-%(", "")
            local i
            local j
            i, j = find_fo(piece)
            firstobj = piece:sub(i, j)

            -- Skip name of argument and get the actual first argument
            if i > 0 then
                local k = j + 1
                if k < #piece then
                    piece = piece:sub(k)
                    k = 1
                    while k < #piece and piece:sub(k, k) == " " do
                        k = k + 1
                    end
                    if piece:sub(k, k) == "=" then
                        k = k + 1
                        while k < #piece and piece:sub(k, k) == " " do
                            k = k + 1
                        end
                        if k < #piece then
                            piece = piece:sub(k)
                            i, j = find_fo(piece)
                            firstobj = piece:sub(i, j)
                        end
                    end
                end
            end
        end
    end

    if firstobj:sub(1, 1) == '"' or firstobj:sub(1, 1) == "'" then
        firstobj = "#c#"
    elseif firstobj:sub(1, 1) >= "0" and firstobj:sub(1, 1) <= "9" then
        firstobj = "#n#"
    end
    if firstobj:find('"') then firstobj = firstobj:gsub('"', '\\"') end

    return firstobj
end

return M
