local warn = require("r").warn
local send = require("r.send")
local utils = require("r.utils")
local job = require("r.job")
local config = require("r.config").get_config()
local check_latexcmd = true

local check_latex_cmd = function()
    check_latexcmd = false
    if config.latexcmd[1] == "default" then
        if vim.fn.executable("xelatex") == 0 then
            if vim.fn.executable("pdflatex") == 1 then
                config.latexcmd = {
                    "latexmk",
                    "-pdf",
                    '-pdflatex="pdflatex %O -file-line-error -interaction=nonstopmode -synctex=1 %S"',
                }
            else
                warn("You should install 'xelatex' to be able to compile pdf documents.")
            end
        end
    end
    if
        (config.latexcmd[1] == "default" or config.latexcmd[1] == "latexmk")
        and vim.fn.executable("latexmk") == 0
    then
        if vim.fn.executable("xelatex") == 1 then
            config.latexcmd = {
                "xelatex",
                "-file-line-error",
                "-interaction=nonstopmode",
                "-synctex=1",
            }
        elseif vim.fn.executable("pdflatex") == 1 then
            config.latexcmd = {
                "pdflatex",
                "-file-line-error",
                "-interaction=nonstopmode",
                "-synctex=1",
            }
        else
            warn(
                "You should install both 'xelatex' and 'latexmk' to be able to compile pdf documents."
            )
        end
    end
end

-- See http://www.stats.uwo.ca/faculty/murdoch/9864/Sweave.pdf page 25
local SyncTeX_readconc = function(basenm)
    local texidx = 1
    local ntexln = #vim.fn.readfile(basenm .. ".tex")
    local lstexln = vim.fn.range(1, ntexln)
    local lsrnwl = vim.fn.range(1, ntexln)
    local lsrnwf = {}
    local conc = vim.fn.readfile(basenm .. "-concordance.tex")
    local idx = 1
    local maxidx = #conc + 1

    for _, _ in pairs(lstexln) do
        table.insert(lsrnwf, "")
    end

    while idx < maxidx and texidx < ntexln and conc[idx]:find("Sconcordance") do
        local rnwf = conc[idx]:gsub(".Sconcordance.concordance:.*:(.*):.*", "%1")
        idx = idx + 1
        local concnum = ""
        while idx < maxidx and not conc[idx]:find("Sconcordance") do
            concnum = concnum .. conc[idx]
            idx = idx + 1
        end
        concnum = concnum:gsub("%%", "")
        concnum = concnum:gsub("%}", "")
        local concl = vim.split(concnum, " ")
        local i = 1
        local max_i = #concl - 1
        local rnwl = tonumber(concl[1])
        lsrnwl[texidx] = rnwl
        lsrnwf[texidx] = rnwf
        texidx = texidx + 1
        while i < max_i and texidx < ntexln do
            i = i + 1
            local lnrange = vim.fn.range(1, concl[i])
            i = i + 1
            for _, _ in ipairs(lnrange) do
                if texidx > ntexln then break end
                rnwl = rnwl + concl[i]
                lsrnwl[texidx] = rnwl
                lsrnwf[texidx] = rnwf
                texidx = texidx + 1
            end
        end
    end
    return { texlnum = lstexln, rnwfile = lsrnwf, rnwline = lsrnwl }
end

local go_to_buf = function(rnwbn, rnwf, basedir, rnwln)
    if vim.fn.expand("%:t") ~= rnwbn then
        if vim.fn.bufloaded(basedir .. "/" .. rnwf) == 1 then
            local savesb = vim.o.switchbuf
            vim.o.switchbuf = "useopen,usetab"
            vim.cmd.sb(string.gsub(basedir .. "/" .. rnwf, " ", "\\ "))
            vim.cmd.sb(string.gsub(basedir .. "/" .. rnwf, " ", "\\ "))
            vim.o.switchbuf = savesb
        elseif vim.fn.bufloaded(rnwf) > 0 then
            local savesb = vim.o.switchbuf
            vim.o.switchbuf = "useopen,usetab"
            vim.cmd.sb(rnwf:gsub(" ", "\\ "))
            vim.o.switchbuf = savesb
        else
            if vim.fn.filereadable(basedir .. "/" .. rnwf) == 1 then
                vim.cmd("tabnew " .. string.gsub(basedir .. "/" .. rnwf, " ", "\\ "))
            elseif vim.fn.filereadable(rnwf) > 0 then
                vim.cmd("tabnew " .. rnwf:gsub(" ", "\\ "))
            else
                warn(
                    'Could not find either "'
                        .. rnwbn
                        .. ' or "'
                        .. rnwf
                        .. '" in "'
                        .. basedir
                        .. '".'
                )
                return 0
            end
        end
    end
    vim.cmd(tostring(rnwln))
    return 1
end

local M = {}

M.write_chunk = function()
    if vim.fn.getline(vim.fn.line(".")) ~= "" and not M.is_in_R_code(false) then
        vim.fn.feedkeys("<", "n")
    else
        local curline = vim.fn.line(".")
        vim.api.nvim_buf_set_lines(
            0,
            curline - 1,
            curline - 1,
            true,
            { "<<>>=", "@", "" }
        )
        vim.api.nvim_win_set_cursor(0, { curline, 2 })
    end
end

--- Check if cursor is within a R block of code
---@param vrb boolean
---@return boolean
M.is_in_R_code = function(vrb)
    local chunkline = vim.fn.search("^<<", "bncW")
    local docline = vim.fn.search("^@", "bncW")
    if chunkline ~= vim.fn.line(".") and chunkline > docline then
        return true
    else
        if vrb then warn("Not inside an R code chunk.") end
        return false
    end
end

M.previous_chunk = function()
    local curline = vim.fn.line(".")
    if M.is_in_R_code(false) then
        local i = vim.fn.search("^<<.*$", "bnW")
        if i ~= 0 then vim.fn.cursor(i - 1, 1) end
    end
    local i = vim.fn.search("^<<.*$", "bnW")
    if i == 0 then
        vim.fn.cursor(curline, 1)
        warn("There is no previous R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1)
    end
end

M.next_chunk = function()
    local i = vim.fn.search("^<<.*$", "nW")
    if i == 0 then
        warn("There is no next R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1)
    end
end

-- Because this function delete files, it will not be documented.
-- If you want to try it, put in your config:
--
-- let rm_knit_cache = true
--
-- If don't want to answer the question about deleting files, and
-- if you trust this code more than I do, put in your vimrc:
--
-- ask_rm_knitr_cache = false
--
-- Note that if you have the string "cache.path=" in more than one place only
-- the first one above the cursor position will be found. The path must be
-- surrounded by quotes; if it's an R object, it will not be recognized.
M.rm_knit_cache = function()
    local lnum = vim.fn.search("\\<cache\\.path\\>\\s*=", "bnwc")
    local cpdir
    if lnum == 0 then
        cpdir = "cache/"
    else
        cpdir = vim.fn.getline(lnum):gsub(".*<cache%.path>%s*=%s*[\"'](.-)[\"'].*", "%1")
        if not cpdir:find("/$") then cpdir = cpdir .. "/" end
    end

    local cleandir
    vim.fn.inputsave()
    local answer = vim.fn.input('Delete all files from "' .. cpdir .. '"? [y/n]: ')
    vim.fn.inputrestore()
    if answer == "y" then
        cleandir = true
    else
        cleandir = false
    end

    if cleandir then
        send.cmd('rm(list=ls(all.names=TRUE)); unlink("' .. cpdir .. '*")')
    end
end

M.weave = function(bibtex, knit, pdf)
    if check_latexcmd then check_latex_cmd() end

    vim.cmd("update")

    local rnwdir = vim.fn.expand("%:p:h")
    if config.is_windows then rnwdir = utils.normalize_windows_path(rnwdir) end

    local pdfcmd = 'nvim.interlace.rnoweb("'
        .. vim.fn.expand("%:t")
        .. '", rnwdir = "'
        .. rnwdir
        .. '"'

    if not knit then pdfcmd = pdfcmd .. ", knit = FALSE" end

    if not pdf then pdfcmd = pdfcmd .. ", buildpdf = FALSE" end

    if config.latexcmd[1] ~= "default" then
        pdfcmd = pdfcmd .. ', latexcmd = "' .. config.latexcmd[1] .. '"'
        if #config.latexcmd == 1 then
            pdfcmd = pdfcmd .. ", latexargs = character()"
        else
            pdfcmd = pdfcmd
                .. ', latexargs = c("'
                .. table.concat(config.latexcmd, '", "')
                .. '")'
        end
    end

    if config.synctex == false then pdfcmd = pdfcmd .. ", synctex = FALSE" end

    if bibtex == "bibtex" then pdfcmd = pdfcmd .. ", bibtex = TRUE" end

    if not pdf or config.open_pdf == 0 then pdfcmd = pdfcmd .. ", view = FALSE" end

    if config.latex_build_dir then
        pdfcmd = pdfcmd .. ', builddir="' .. config.latex_build_dir .. '"'
    end

    if not knit and config.sweaveargs then
        pdfcmd = pdfcmd .. ", " .. config.sweaveargs
    end

    pdfcmd = pdfcmd .. ")"
    send.cmd(pdfcmd)
end

-- Send Sweave chunk to R
M.send_chunk = function(m)
    if vim.fn.getline(vim.fn.line(".")):find("^<<") then
        vim.api.nvim_win_set_cursor(0, { vim.fn.line(".") + 1, 1 })
    elseif not M.is_in_R_code(false) then
        return
    end

    local chunkline = vim.fn.search("^<<", "bncW") + 1
    local docline = vim.fn.search("^@", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true)
    local ok = send.source_lines(lines, "chunk")
    if ok == 0 then return end

    if m == true then M.next_chunk() end
end

M.SyncTeX_get_master = function()
    if vim.fn.filereadable(vim.fn.expand("%:p:r") .. "-concordance.tex") == 1 then
        if config.is_windows then
            return utils.normalize_windows_path(vim.fn.expand("%:p:r"))
        else
            return vim.fn.expand("%:p:r")
        end
    end

    local ischild = vim.fn.search("% *!Rnw *root *=", "bwn")
    if ischild > 0 then
        local basenm
        local mdir
        local mfile = vim.fn.getline(ischild):gsub(".*%% *!Rnw *root *= *(.*) *", "%1")
        if vim.fn.match(mfile, "/") > 0 then
            mdir = mfile:gsub("(.*)/.*", "%1")
            basenm = mfile:gsub(".*/", "")
            if mdir == ".." then mdir = vim.fn.expand("%:p:h:h") end
        else
            mdir = vim.fn.expand("%:p:h")
            basenm = mfile:gsub(".*/", "")
        end

        if config.is_windows then
            return utils.normalize_windows_path(mdir) .. "/" .. basenm
        else
            return mdir .. "/" .. basenm
        end
    end

    if config.is_windows then
        return utils.normalize_windows_path(vim.fn.expand("%:p:r"))
    else
        return vim.fn.expand("%:p:r")
    end
end

M.SyncTeX_backward = function(fname, ln)
    local flnm = fname:gsub("/%./", "/") -- Okular
    local basenm = flnm:gsub("%....$", "") -- Delete extension
    local rnwf
    local rnwln
    local basedir
    if basenm:match("/") then
        basedir = basenm:gsub("(.*)/.*", "%1")
    else
        basedir = "."
    end

    if vim.fn.filereadable(basenm .. "-concordance.tex") == 1 then
        if vim.fn.filereadable(basenm .. ".tex") == 0 then
            warn('SyncTeX: "' .. basenm .. '.tex" not found.')
            return
        end
        local concdata = SyncTeX_readconc(basenm)
        local texlnum = concdata.texlnum
        local rnwfile = concdata.rnwfile
        local rnwline = concdata.rnwline
        rnwln = 0
        for k, v in ipairs(texlnum) do
            if v >= ln then
                rnwf = rnwfile[k]
                rnwln = rnwline[k]
                break
            end
        end
        if rnwln == 0 then
            warn("Could not find Rnoweb source line.")
            return
        end
    else
        if
            vim.fn.filereadable(basenm .. ".Rnw") == 1
            or vim.fn.filereadable(basenm .. ".rnw") == 1
        then
            warn('SyncTeX: "' .. basenm .. '-concordance.tex" not found.')
            return
        elseif vim.fn.filereadable(flnm) > 0 then
            rnwf = flnm
            rnwln = ln
        else
            warn('Could not find "' .. basenm .. '.Rnw".')
            return
        end
    end

    local rnwbn = rnwf:gsub(".*/", "")
    rnwf = rnwf:gsub("^%.\\/", "")

    if go_to_buf(rnwbn, rnwf, basedir, rnwln) > 0 then
        require("r.pdf").focus_window(config.term_title, config.term_pid)
    end
end

M.SyncTeX_forward = function(gotobuf)
    local basenm = vim.fn.expand("%:t:r")
    local lnum = 0
    local rnwf = vim.fn.expand("%:t")
    local basedir

    if vim.fn.filereadable(vim.fn.expand("%:p:r") .. "-concordance.tex") == 1 then
        lnum = vim.fn.line(".")
    else
        local ischild = vim.fn.search("% *!Rnw *root *=", "bwn")
        if ischild > 0 then
            local mfile =
                vim.fn.getline(ischild):gsub(".*%% *!Rnw *root *= *(.*) *", "%1")
            local mlines = vim.fn.readfile(vim.fn.expand("%:p:h") .. "/" .. mfile)
            for k, v in ipairs(mlines) do
                if v:match("SweaveInput.*" .. vim.fn.expand("%:t")) then
                    lnum = vim.fn.line(".")
                    break
                elseif
                    v:match("<<.*child *=.*" .. vim.fn.expand("%:t") .. '["' .. "']")
                then
                    lnum = k
                    rnwf = vim.fn.expand("%:p:h") .. "/" .. mfile
                    break
                end
            end
            if lnum == 0 then
                warn(
                    'Could not find "child='
                        .. vim.fn.expand("%:t")
                        .. '" in '
                        .. vim.fn.expand("%:p:h")
                        .. "/"
                        .. mfile
                        .. "."
                )
                return
            end
        else
            warn('SyncTeX: "' .. basenm .. '-concordance.tex" not found.')
            return
        end
    end

    if vim.fn.filereadable(vim.fn.expand("%:p:h") .. "/" .. basenm .. ".tex") == 0 then
        warn('"' .. vim.fn.expand("%:p:h") .. "/" .. basenm .. '.tex" not found.')
        return
    end
    local concdata = SyncTeX_readconc(vim.fn.expand("%:p:h") .. "/" .. basenm)
    rnwf = rnwf:gsub(".*/", "")
    local texlnum = concdata.texlnum
    local rnwfile = concdata.rnwfile
    local rnwline = concdata.rnwline
    local texln = 0
    for k, v in pairs(texlnum) do
        if rnwfile[k] == rnwf and rnwline[k] >= lnum then
            texln = v
            break
        end
    end

    if texln == 0 then
        warn("Error: did not find LaTeX line.")
        return
    end
    if basenm:match("/") then
        basedir = basenm:gsub("(.*)/.*", "%1")
        basenm = basenm:gsub(".*/", "")
        vim.cmd("cd " .. basedir:gsub(" ", "\\ "))
    else
        basedir = ""
    end

    if gotobuf then
        go_to_buf(basenm .. ".tex", basenm .. ".tex", basedir, texln)
        return
    end

    if not vim.b.rplugin_pdfdir then M.set_pdf_dir() end

    if vim.fn.filereadable(vim.b.rplugin_pdfdir .. "/" .. basenm .. ".pdf") == 0 then
        warn(
            'SyncTeX forward cannot be done because the file "'
                .. vim.b.rplugin_pdfdir
                .. "/"
                .. basenm
                .. '.pdf" is missing.'
        )
        return
    end
    if
        vim.fn.filereadable(vim.b.rplugin_pdfdir .. "/" .. basenm .. ".synctex.gz") == 0
    then
        warn(
            'SyncTeX forward cannot be done because the file "'
                .. vim.b.rplugin_pdfdir
                .. "/"
                .. basenm
                .. '.synctex.gz" is missing.'
        )
        if config.latexcmd[1] ~= "default" and config.latexcmd ~= "synctex" then
            warn(
                'Note: The string "-synctex=1" is not in your R_latexcmd. Please check your vimrc.'
            )
        end
        return
    end

    local ppath = vim.b.rplugin_pdfdir .. "/" .. basenm .. ".pdf"
    -- FIXME: this should not be necessary:
    ppath = ppath:gsub("//", "/")

    if not job.is_running(ppath) then
        require("r.pdf").open(ppath)
        -- Wait up to five seconds
        vim.wait(500)
        local i = 0
        while i < 45 do
            if job.is_running(ppath) then break end
            vim.wait(100)
            i = i + 1
        end
        if not job.is_running(ppath) then return end
    end

    require("r.pdf").SyncTeX_forward(M.SyncTeX_get_master() .. ".tex", ppath, texln)
end

M.set_pdf_dir = function()
    local master = M.SyncTeX_get_master()
    local mdir = master:match("(.*/).*")
    vim.b.rplugin_pdfdir = "."

    -- Latexmk has an option to create the PDF in a directory other than '.'
    if config.latexcmd and (vim.fn.glob("~/.latexmkrc") ~= "") == 1 then
        local ltxmk = vim.fn.readfile(vim.fn.expand("~/.latexmkrc"))
        for _, line in ipairs(ltxmk) do
            if
                line:match('out_dir%s*=%s*"(.*)"') or line:match("out_dir%s*=%s*'(.*)'")
            then
                vim.b.rplugin_pdfdir = line:match('out_dir%s*=%s*"(.*)"')
                    or line:match("out_dir%s*=%s*'(.*)'")
            end
        end
    end

    local latexcmd_str = table.concat(config.latexcmd, " ")
    if latexcmd_str:find("-outdir") or latexcmd_str:find("-output-directory") then
        vim.b.rplugin_pdfdir =
            latexcmd_str:match(".*(-outdir|-output-directory)%s*=%s*([%w/_.]+)")
        if not vim.b.rplugin_pdfdir then
            vim.b.rplugin_pdfdir =
                latexcmd_str:match(".*(-outdir|-output-directory)%s*=%s*'([%w/_.]+)'")
        end
    end

    if vim.b.rplugin_pdfdir == "." then
        vim.b.rplugin_pdfdir = mdir
    elseif not vim.b.rplugin_pdfdir:find("^/") then
        vim.b.rplugin_pdfdir = mdir .. "/" .. vim.b.rplugin_pdfdir
        if vim.fn.isdirectory(vim.b.rplugin_pdfdir) == 0 then
            vim.b.rplugin_pdfdir = "."
        end
    end
end

return M
