NvimcomEnv <- new.env()
NvimcomEnv$pkgdescr <- list()

#' Function called by R when nvimcom is being loaded.
#' R.nvim creates environment variables and the start_options.R file to set
#' nvimcom options.
.onLoad <- function(libname, pkgname) {
    if (Sys.getenv("RNVIM_TMPDIR") == "")
        return(invisible(NULL))
    library.dynam("nvimcom", pkgname, libname, local = FALSE)

    if (is.null(getOption("nvimcom.verbose")))
        options(nvimcom.verbose = 0)

    # The remaining options are set by Neovim. Don't try to set them in your
    # ~/.Rprofile because they will be overridden here:
    if (file.exists(paste0(Sys.getenv("RNVIM_TMPDIR"), "/start_options_utf8.R"))) {
        source(paste0(Sys.getenv("RNVIM_TMPDIR"), "/start_options_utf8.R"), encoding = "UTF-8")
    } else if (file.exists(paste0(Sys.getenv("RNVIM_TMPDIR"), "/start_options.R"))) {
        source(paste0(Sys.getenv("RNVIM_TMPDIR"), "/start_options.R"))
    } else {
        options(nvimcom.allnames = FALSE)
        options(nvimcom.texerrs = TRUE)
        options(nvimcom.setwidth = TRUE)
        options(nvimcom.autoglbenv = FALSE)
        options(nvimcom.nvimpager = TRUE)
        options(nvimcom.delim = "\t")
    }
    if (getOption("nvimcom.nvimpager"))
        options(pager = nvim.hmsg)
}

#' Function called by R right after loading nvimcom to establish the TCP
#' connection with the rnvimserver
.onAttach <- function(libname, pkgname) {
    if (Sys.getenv("RNVIM_TMPDIR") == "")
        return(invisible(NULL))
    if (version$os == "mingw32") {
        termenv <- "MinGW"
    } else {
        termenv <- Sys.getenv("TERM")
    }

    set_running_info()

    if (interactive() && termenv != "" && termenv != "dumb" && Sys.getenv("RNVIM_COMPLDIR") != "") {
        dir.create(Sys.getenv("RNVIM_COMPLDIR"), showWarnings = FALSE)
        .C("nvimcom_Start",
           as.integer(getOption("nvimcom.verbose")),
           as.integer(getOption("nvimcom.allnames")),
           as.integer(getOption("nvimcom.setwidth")),
           as.integer(getOption("nvimcom.autoglbenv")),
           NvimcomEnv$info[1],
           NvimcomEnv$info[2],
           PACKAGE = "nvimcom")
    }
    if (!is.na(utils::localeToCharset()[1]) &&
        utils::localeToCharset()[1] == "UTF-8" && version$os != "cygwin") {
        NvimcomEnv$isAscii <- FALSE
    } else {
        NvimcomEnv$isAscii <- TRUE
    }
}


#' Stop the connection with rnvimserver and unload the nvimcom library
#' This function is called by the command:
#' detach("package:nvimcom", unload = TRUE)
.onUnload <- function(libpath) {
    if (is.loaded("nvimcom_Stop", PACKAGE = "nvimcom")) {
        .C("nvimcom_Stop", PACKAGE = "nvimcom")
        if (Sys.getenv("RNVIM_TMPDIR") != "" && .Platform$OS.type == "windows") {
                unlink(paste0(Sys.getenv("RNVIM_TMPDIR"), "/rconsole_hwnd_",
                              Sys.getenv("RNVIM_SECRET")))
        }
        Sys.sleep(0.2)
        library.dynam.unload("nvimcom", libpath)
    }
}

set_running_info <- function() {
    pd <- utils::packageDescription("nvimcom")
    hascolor <- FALSE
    if (length(find.package("colorout", quiet = TRUE, verbose = FALSE)) > 0)
        hascolor <- colorout::isColorOut()
    info <- paste0("{Rversion = '", sub("R ([^;]*).*", "\\1", pd$Built),
                  "', OutDec = '", getOption("OutDec"),
                  "', prompt = '", gsub("\n", "#N#", getOption("prompt")),
                  "', continue = '", getOption("continue"),
                  "', has_color = ", ifelse(hascolor, "true", "false"), "}")
    NvimcomEnv$info <- c(pd$Version, info)
    return(invisible(NULL))
}

# On Unix, this function is called when R is ready to execute top-level
# commands. This feature is not implementable on Windows.
send_nvimcom_info <- function(Rpid) {
    winID <- Sys.getenv("WINDOWID")
    if (winID == "")
        winID = "0"
    msg <- paste0("lua require('r.run').set_nvimcom_info('", NvimcomEnv$info[1],
                  "', ", Rpid, ", '", winID, "', ", NvimcomEnv$info[2], ")")
    .C("nvimcom_msg_to_nvim", msg, PACKAGE = "nvimcom")
}

# registered by reg.finalizer() to be called when R is quitting. Only
# necessary if running in a external terminal emulator.
final_msg <- function(e) {
    .C("nvimcom_msg_to_nvim",
       "lua require('r.job').end_of_R_session()",
       PACKAGE = "nvimcom")
    return(invisible(NULL))
}
