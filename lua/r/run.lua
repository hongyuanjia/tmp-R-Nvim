local M = {}
local config = require("r.config").get_config()
local job = require("r.job")
local edit = require("r.edit")
local warn = require("r").warn
local utils = require("r.utils")
local send = require("r.send")
local cursor = require("r.cursor")
local what_R = "R"
local R_pid = 0
local r_args
local nseconds

local start_R2
start_R2 = function()
    if vim.g.R_Nvim_status == 4 then
        vim.fn.timer_start(30, start_R2)
        return
    end

    if what_R:find("custom") then
        r_args = vim.fn.split(vim.fn.input("Enter parameters for R: "))
    else
        r_args = config.R_args
    end

    vim.fn.writefile({}, config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    vim.fn.writefile({}, config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)

    edit.add_for_deletion(config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    edit.add_for_deletion(config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)

    if vim.o.encoding == "utf-8" then
        edit.add_for_deletion(config.tmpdir .. "/start_options_utf8.R")
    else
        edit.add_for_deletion(config.tmpdir .. "/start_options.R")
    end

    -- Required to make R load nvimcom without the need for the user to include
    -- library(nvimcom) in his or her ~/.Rprofile.
    local rdp
    if vim.env.R_DEFAULT_PACKAGES then
        rdp = vim.env.R_DEFAULT_PACKAGES
        if not rdp:find(",nvimcom") then rdp = rdp .. ",nvimcom" end
    else
        rdp = "datasets,utils,grDevices,graphics,stats,methods,nvimcom"
    end
    vim.env.R_DEFAULT_PACKAGES = rdp
    local start_options = {
        'Sys.setenv("R_DEFAULT_PACKAGES" = "' .. rdp .. '")',
    }

    if config.objbr_allnames then
        table.insert(start_options, "options(nvimcom.allnames = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.allnames = FALSE)")
    end
    if config.texerr then
        table.insert(start_options, "options(nvimcom.texerrs = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.texerrs = FALSE)")
    end
    if config.update_glbenv then
        table.insert(start_options, "options(nvimcom.autoglbenv = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.autoglbenv = FALSE)")
    end
    if config.setwidth and config.setwidth == 2 then
        table.insert(start_options, "options(nvimcom.setwidth = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.setwidth = FALSE)")
    end
    if config.nvimpager == "no" then
        table.insert(start_options, "options(nvimcom.nvimpager = FALSE)")
    else
        table.insert(start_options, "options(nvimcom.nvimpager = TRUE)")
    end
    if
        type(config.external_term) == "boolean"
        and not config.external_term
        and config.esc_term
    then
        table.insert(start_options, "options(editor = nvimcom:::nvim.edit)")
    end
    if
        (type(config.external_term) == "boolean" and config.external_term == true)
        or type(config.external_term) == "string"
    then
        table.insert(
            start_options,
            "reg.finalizer(.GlobalEnv, nvimcom:::final_msg, onexit = TRUE)"
        )
    end
    if config.csv_delim and (config.csv_delim == "," or config.csv_delim == ";") then
        table.insert(
            start_options,
            'options(nvimcom.delim = "' .. config.csv_delim .. '")'
        )
    else
        table.insert(start_options, 'options(nvimcom.delim = "\t")')
    end

    table.insert(
        start_options,
        'options(nvimcom.source.path = "' .. config.source_read .. '")'
    )

    local rwd = ""
    if config.nvim_wd == 0 then
        rwd = M.get_buf_dir()
    elseif config.nvim_wd == 1 then
        rwd = vim.fn.getcwd()
    end
    if rwd ~= "" and not config.remote_compldir then
        if config.is_windows then rwd = rwd:gsub("\\", "/") end

        -- `rwd` will not be a real directory if editing a file on the internet
        -- with netrw plugin
        if vim.fn.isdirectory(rwd) == 1 then
            table.insert(start_options, 'setwd("' .. rwd .. '")')
        end
    end

    if vim.o.encoding == "utf-8" then
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options_utf8.R")
    else
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options.R")
    end

    if config.RStudio_cmd ~= "" then
        vim.env.R_DEFAULT_PACKAGES = rdp .. ",rstudioapi"
        require("r.rstudio").start_RStudio()
        return
    end

    if type(config.external_term) == "boolean" and config.external_term == false then
        require("r.term").start_term()
        return
    end

    if config.applescript then
        require("r.osx").start_Rapp()
        return
    end

    if config.is_windows then
        require("r.windows").start_Rgui()
        return
    end

    local args_str = table.concat(r_args, " ")
    local rcmd = config.R_app .. " " .. args_str

    require("r.external_term").start_extern_term(rcmd)
end

M.auto_start_R = function()
    if vim.g.R_Nvim_status > 3 then return end
    if vim.v.vim_did_enter == 0 or vim.g.R_Nvim_status < 3 then
        vim.fn.timer_start(100, M.auto_start_R)
        return
    end
    M.start_R("R")
end

M.set_nrs_port = function(p)
    vim.g.R_Nvim_status = 5
    vim.env.RNVIM_PORT = p
end

M.start_R = function(whatr)
    -- R started and nvimcom loaded
    if vim.g.R_Nvim_status == 7 then
        if type(config.external_term) == "boolean" and config.external_term == false then
            require("r.term").reopen_win()
        end
        return
    end

    -- R already started
    if vim.g.R_Nvim_status == 6 then return end

    if vim.g.R_Nvim_status == 4 then
        warn("Cannot start R: TCP server not ready yet.")
        return
    end
    if vim.g.R_Nvim_status == 5 then
        warn("R is already starting...")
        return
    end
    if vim.g.R_Nvim_status == 2 then
        warn("Cannot start R: rnvimserver not ready yet.")
        return
    end

    if vim.g.R_Nvim_status == 1 then
        warn("Cannot start R: rnvimserver not started yet.")
        return
    end

    if vim.g.R_Nvim_status == 3 then
        vim.g.R_Nvim_status = 4
        require("r.send").set_send_cmd_fun()
        job.stdin("Server", "1\n") -- Start the TCP server
        what_R = whatr
        vim.fn.timer_start(30, start_R2)
        return
    end
end

-- Send SIGINT to R
M.signal_to_R = function(signal)
    if R_pid ~= 0 then utils.system({ "kill", "-s", tostring(signal), tostring(R_pid) }) end
end

M.check_nvimcom_running = function()
    nseconds = nseconds - 1
    if R_pid == 0 then
        if nseconds > 0 then
            vim.fn.timer_start(1000, M.check_nvimcom_running)
        else
            local msg =
                "The package nvimcom wasn't loaded yet. Please, quit R and try again."
            warn(msg)
        end
    end
end

M.wait_nvimcom_start = function()
    local args_str = table.concat(r_args, " ")
    if string.find(args_str, "vanilla") then return 0 end

    if config.wait < 2 then config.wait = 2 end

    nseconds = config.wait
    vim.fn.timer_start(1000, M.check_nvimcom_running)
end

M.set_nvimcom_info = function(nvimcomversion, rpid, wid, r_info)
    local r_home_description =
        vim.fn.readfile(config.rnvim_home .. "/nvimcom/DESCRIPTION")
    local current
    for _, v in pairs(r_home_description) do
        if v:find("Version: ") then current = v:sub(10) end
    end
    if nvimcomversion ~= current then
        warn(
            "Mismatch in nvimcom versions: R ("
                .. nvimcomversion
                .. ") and Vim ("
                .. current
                .. ")"
        )
        vim.wait(1000)
    end

    R_pid = rpid
    vim.env.RCONSOLE = wid

    -- R_version = r_info[1]
    config.OutDec = r_info.OutDec
    config.R_prompt_str = r_info.prompt:gsub(" $", "")
    config.R_continue_str = r_info.continue:gsub(" $", "")

    if not r_info.has_color and config.hl_term then require("r.term").highlight_term() end

    if job.is_running("Server") then
        if config.is_windows then
            if vim.env.RCONSOLE == "0" then warn("nvimcom did not save R window ID") end
        end
    else
        warn("nvimcom is not running")
    end

    if config.RStudio_cmd ~= "" then
        if
            config.is_windows
            and config.arrange_windows
            and vim.fn.filereadable(config.compldir .. "/win_pos") == 1
        then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    elseif config.is_windows then
        if
            config.arrange_windows
            and vim.fn.filereadable(config.compldir .. "/win_pos") == 1
        then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    elseif config.applescript then
        vim.fn.foreground()
        vim.wait(200)
    else
        vim.fn.delete(
            config.tmpdir .. "/initterm_" .. vim.fn.string(vim.env.RNVIM_ID) .. ".sh"
        )
        vim.fn.delete(config.tmpdir .. "/openR")
    end

    if config.objbr_auto_start then
        if config.is_windows then
            -- Give R some time to be ready
            vim.fn.timer_start(1010, require("r.browser").start)
        else
            vim.schedule(require("r.browser").start)
        end
    end

    vim.g.R_Nvim_status = 7
    if config.hook.after_R_start then config.hook.after_R_start() end
    send.set_send_cmd_fun()
end

M.clear_R_info = function()
    vim.fn.delete(config.tmpdir .. "/globenv_" .. vim.fn.string(vim.env.RNVIM_ID))
    vim.fn.delete(config.localtmpdir .. "/liblist_" .. vim.fn.string(vim.env.RNVIM_ID))
    R_pid = 0
    if type(config.external_term) == "boolean" and config.external_term == false then
        require("r.term").close_term()
    end
    if job.is_running("Server") then
        vim.g.R_Nvim_status = 3
        job.stdin("Server", "43\n")
    else
        vim.g.R_Nvim_status = 1
    end
    send.set_send_cmd_fun()
end

-- Background communication with R

-- Send a message to rnvimserver job which will send the message to nvimcom
-- through a TCP connection.
M.send_to_nvimcom = function(code, attch)
    if vim.g.R_Nvim_status < 6 then
        warn("R is not running")
        return
    end

    if vim.g.R_Nvim_status < 7 then
        warn("R is not ready yet")
        return
    end

    if not job.is_running("Server") then
        warn("Server not running.")
        return
    end
    job.stdin("Server", "2" .. code .. vim.env.RNVIM_ID .. attch .. "\n")
end

M.quit_R = function(how)
    local qcmd
    if how == "save" then
        qcmd = 'quit(save = "yes")'
    else
        qcmd = 'quit(save = "no")'
    end

    if config.is_windows then
        if type(config.external_term) == "boolean" and config.external_term then
            -- SaveWinPos
            job.stdin(
                "Server",
                "84" .. vim.fn.escape(vim.env.RNVIM_COMPLDIR, "\\") .. "\n"
            )
        end
        job.stdin("Server", "2QuitNow\n")
    end

    if vim.fn.bufloaded("Object_Browser") == 1 then
        vim.cmd("bunload! Object_Browser")
        vim.wait(30)
    end

    require("r.send").cmd(qcmd)
end

M.formart_code = function(tbl)
    if vim.g.R_Nvim_status < 7 then return end

    local wco = vim.o.textwidth
    if wco == 0 then
        wco = 78
    elseif wco < 20 then
        wco = 20
    elseif wco > 180 then
        wco = 180
    end

    local lns = vim.api.nvim_buf_get_lines(0, tbl.line1 - 1, tbl.line2, true)
    local txt = table.concat(lns, "\020")
    txt = txt:gsub("\\", "\\\\"):gsub("'", "\019")
    M.send_to_nvimcom(
        "E",
        "nvimcom:::nvim_format("
            .. tbl.line1
            .. ", "
            .. tbl.line2
            .. ", "
            .. wco
            .. ", "
            .. vim.o.shiftwidth
            .. ", '"
            .. txt
            .. "')"
    )
end

M.insert = function(cmd, type)
    if vim.g.R_Nvim_status < 7 then return end
    M.send_to_nvimcom("E", "nvimcom:::nvim_insert(" .. cmd .. ', "' .. type .. '")')
end

M.insert_commented = function()
    local lin = vim.fn.getline(vim.fn.line("."))
    local cleanl = lin:gsub('".-"', "")
    if cleanl:find(";") then
        warn("`print(line)` works only if `line` is a single command")
    end
    cleanl = string.gsub(lin, "%s*#.*", "")
    M.insert("print(" .. cleanl .. ")", "comment")
end

-- Get the word either under or after the cursor.
-- Works for word(| where | is the cursor position.
M.get_keyword = function()
    local line = vim.fn.getline(vim.fn.line("."))
    local llen = #line
    if llen == 0 then return "" end

    local i = vim.fn.col(".")

    -- Skip opening braces
    local char
    while i > 1 do
        char = line:sub(i, i)
        if char == "[" or char == "(" or char == "{" then
            i = i - 1
        else
            break
        end
    end

    -- Go to the beginning of the word
    while
        i > 1
        and (
            line:sub(i - 1, i - 1):match("[%w@:$:_%.]")
            or (line:byte(i - 1) > 0x80 and line:byte(i - 1) < 0xf5)
        )
    do
        i = i - 1
    end
    -- Go to the end of the word
    local j = i
    local b
    while j <= llen do
        b = line:byte(j + 1)
        if
            b and ((b > 0x80 and b < 0xf5) or line:sub(j + 1, j + 1):match("[%w@$:_%.]"))
        then
            j = j + 1
        else
            break
        end
    end
    return line:sub(i, j)
end

-- Call R functions for the word under cursor
M.action = function(rcmd, mode, args)
    local rkeyword

    if vim.o.syntax == "rdoc" then
        rkeyword = vim.fn.expand("<cword>")
    elseif vim.o.syntax == "rbrowser" then
        local lnum = vim.fn.line(".")
        local line = vim.fn.getline(lnum)
        rkeyword = require("r.browser").get_name(lnum, line)
    elseif mode and mode == "v" and vim.fn.line("'<") == vim.fn.line("'>") then
        rkeyword = vim.fn.strpart(
            vim.fn.getline(vim.fn.line("'>")),
            vim.fn.col("'<") - 1,
            vim.fn.col("'>") - vim.fn.col("'<") + 1
        )
    else
        rkeyword = M.get_keyword()
    end

    if #rkeyword == 0 then return end

    if rcmd == "help" then
        local rhelppkg, rhelptopic
        if rkeyword:find("::") then
            local rhelplist = vim.fn.split(rkeyword, "::")
            rhelppkg = rhelplist[1]
            rhelptopic = rhelplist[2]
        else
            rhelppkg = ""
            rhelptopic = rkeyword
        end
        if config.nvimpager == "no" then
            send.cmd("help(" .. rkeyword .. ")")
        else
            if vim.fn.bufname("%") == "Object_Browser" then
                if require("r.browser").get_curview() == "libraries" then
                    rhelppkg = require("r.browser").get_pkg_name()
                end
            end
            require("r.doc").ask_R_doc(rhelptopic, rhelppkg, true)
        end
        return
    end

    if rcmd == "print" then
        M.print_object(rkeyword)
        return
    end

    local rfun = rcmd

    if rcmd == "args" then
        if config.listmethods and not rkeyword:find("::") then
            send.cmd('nvim.list.args("' .. rkeyword .. '")')
        else
            send.cmd("args(" .. rkeyword .. ")")
        end

        return
    end

    if rcmd == "plot" and config.specialplot then rfun = "nvim.plot" end

    if rcmd == "plotsumm" then
        local raction

        if config.specialplot then
            raction = "nvim.plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
        else
            raction = "plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
        end

        send.cmd(raction)
        return
    end

    if config.open_example and rcmd == "example" then
        M.send_to_nvimcom("E", 'nvimcom:::nvim.example("' .. rkeyword .. '")')
        return
    end

    local argmnts = args or ""

    if rcmd == "viewobj" then
        if config.df_viewer then
            argmnts = argmnts .. ', R_df_viewer = "' .. config.df_viewer .. '"'
        end
        if rkeyword:find("::") then
            M.send_to_nvimcom(
                "E",
                "nvimcom:::nvim_viewobj(" .. rkeyword .. argmnts .. ")"
            )
        else
            local fenc = config.is_windows
                    and vim.o.encoding == "utf-8"
                    and ', fenc="UTF-8"'
                or ""
            M.send_to_nvimcom(
                "E",
                'nvimcom:::nvim_viewobj("' .. rkeyword .. '"' .. argmnts .. fenc .. ")"
            )
        end
        return
    elseif rcmd == "dputtab" then
        M.send_to_nvimcom(
            "E",
            'nvimcom:::nvim_dput("' .. rkeyword .. '"' .. argmnts .. ")"
        )
        return
    end
    local raction = rfun .. "(" .. rkeyword .. argmnts .. ")"
    send.cmd(raction)
end

M.print_object = function(rkeyword)
    local firstobj

    if vim.fn.bufname("%") == "Object_Browser" then
        firstobj = ""
    else
        firstobj = cursor.get_first_obj()
    end

    if firstobj == "" then
        send.cmd("print(" .. rkeyword .. ")")
    else
        send.cmd('nvim.print("' .. rkeyword .. '", "' .. firstobj .. '")')
    end
end

-- knit the current buffer content
M.knit = function()
    vim.cmd("update")
    send.cmd(
        "require(knitr); .nvim_oldwd <- getwd(); setwd('"
            .. M.get_buf_dir()
            .. "'); knit('"
            .. vim.fn.expand("%:t")
            .. "'); setwd(.nvim_oldwd); rm(.nvim_oldwd)"
    )
end

-- Set working directory to the path of current buffer
M.setwd = function() send.cmd('setwd("' .. M.get_buf_dir() .. '")') end

M.show_obj = function(howto, bname, ftype, txt)
    local bfnm = bname:gsub("[^%w]", "_")
    edit.add_for_deletion(config.tmpdir .. "/" .. bfnm)
    vim.cmd({ cmd = howto, args = { config.tmpdir .. "/" .. bfnm } })
    vim.o.filetype = ftype
    local lines = vim.split(txt:gsub("\019", "'"), "\020")
    vim.api.nvim_buf_set_lines(0, 0, 0, true, lines)
    vim.api.nvim_buf_set_var(0, "modified", false)
end

-- Clear the console screen
M.clear_console = function()
    if config.clear_console == false then return end

    if
        config.is_windows
        and type(config.external_term) == "boolean"
        and config.external_term
    then
        job.stdin("Server", "86\n")
        vim.wait(50)
        job.stdin("Server", "87\n")
    else
        send.cmd("\012")
    end
end

M.clear_all = function()
    if config.rmhidden then
        M.send.cmd("rm(list=ls(all.names = TRUE))")
    else
        send.cmd("rm(list = ls())")
    end
    vim.wait(30)
    M.clear_console()
end

M.get_buf_dir = function()
    local rwd = vim.api.nvim_buf_get_name(0)
    if config.is_windows then
        rwd = rwd:gsub("\\", "/")
        rwd = utils.normalize_windows_path(rwd)
    end
    rwd = rwd:gsub("(.*)/.*", "%1")
    return rwd
end

M.source_dir = function(dir)
    if config.is_windows then dir = utils.normalize_windows_path(dir) end
    if dir == "" then
        send.cmd("nvim.srcdir()")
    else
        send.cmd("nvim.srcdir('" .. dir .. "')")
    end
end

return M
