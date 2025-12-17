
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ApiFetcher = WidgetContainer:extend {
    name = "opentgcfetcher",
    is_doc_only = false,
}

local API_DOMAIN = "opentgc.com"

function ApiFetcher:onDispatcherRegisterActions()
    Dispatcher:registerAction("opentgcfetcher_action", {
        category = "none",
        event = "ApiFetcherOpen",
        title = _("OpenTGC"),
        general = true,
    })
end

function ApiFetcher:init()
    self.last_post_id = ""
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function ApiFetcher:addToMainMenu(menu_items)
    menu_items.api_fetcher = {
        sorting_hint = "search",
        text = _("OpenTGC"),
        callback = function()
            self:showInputDialog()
        end,
    }
end

function ApiFetcher:showInputDialog()
    local input_dialog
    input_dialog = InputDialog:new {
        title = _("Search Post"),
        input = self.last_post_id or "ac9432a492700a1e70fd0c6148bfa0b2",
        input_hint = _("Enter the post ID."),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local post_id = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if post_id and post_id ~= "" then
                            self.last_post_id = post_id
                            self:showLoadingMessage(_("Starting search..."))
                            -- Usar scheduleIn para não bloquear a UI
                            UIManager:scheduleIn(0.1, function()
                                self:fetchAndDisplayPost(post_id)
                            end)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ApiFetcher:showLoadingMessage(text)
    self:closeLoadingMessage()
    self.loading_message = InfoMessage:new {
        text = text,
        timeout = 0,
    }
    UIManager:show(self.loading_message)
    UIManager:forceRePaint()
end

function ApiFetcher:updateLoadingMessage(text)
    if self.loading_message then
        UIManager:close(self.loading_message)
    end
    self.loading_message = InfoMessage:new {
        text = text,
        timeout = 0,
    }
    UIManager:show(self.loading_message)
    UIManager:forceRePaint()
end

function ApiFetcher:closeLoadingMessage()
    if self.loading_message then
        UIManager:close(self.loading_message)
        self.loading_message = nil
        UIManager:forceRePaint()
    end
end

function ApiFetcher:fetchAndDisplayPost(post_id)
    if not NetworkMgr:isOnline() then
        self:closeLoadingMessage()
        UIManager:show(InfoMessage:new {
            text = _("No connection!\nConnect to Wi-Fi first."),
            timeout = 3,
        })
        NetworkMgr:promptWifiOn()
        return
    end

    self:updateLoadingMessage(_("Connecting to the server...\n\nPlease wait..."))

    local url = string.format("https://%s/api/posts/%s", API_DOMAIN, post_id)
    logger.info("OpenTGC: Searching for URL:", url)

    local http = require("socket.http")
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local json = require("json")

    local response_body = {}
    local request_fn = url:match("^https://") and https.request or http.request

    local ok, code, headers = pcall(function()
        return request_fn {
            url = url,
            method = "GET",
            sink = ltn12.sink.table(response_body),
            headers = {
                ["User-Agent"] = "KOReader/ApiFetcher 1.0",
            },
        }
    end)

    if not ok or headers ~= 200 then
        logger.err("OpenTGC: Error in request. Code:", headers)
        self:closeLoadingMessage()

        UIManager:show(InfoMessage:new {
            text = T(_("X Error retrieving post.!\n\nCode: %1\n\nTry again."), tostring(headers)),
            timeout = 3,
        })

        UIManager:scheduleIn(3, function()
            self:showInputDialogWithPreviousId()
        end)

        return
    end

    self:updateLoadingMessage(_("Processing response...\n\nDecoding JSON..."))

    local response_text = table.concat(response_body)
    logger.info("OpenTGC: Response received, size:", #response_text)

    local success, post_data = pcall(json.decode, response_text)

    if not success or not post_data then
        logger.err("OpenTGC: Error decoding JSON")
        self:closeLoadingMessage()

        UIManager:show(InfoMessage:new {
            text = _("X Error processing response!\n\nInvalid JSON."),
            timeout = 3,
        })

        UIManager:scheduleIn(3, function()
            self:showInputDialogWithPreviousId()
        end)

        return
    end

    logger.info("OpenTGC: Post received successfully.")
    self:updateLoadingMessage(_("Downloading images...\n\nPlease wait...."))

    UIManager:scheduleIn(0.1, function()
        self:createAndOpenHtml(post_data)
    end)
end

function ApiFetcher:showInputDialogWithPreviousId()
    local input_dialog
    input_dialog = InputDialog:new {
        title = _("Search Post"),
        input = self.last_post_id or "",
        input_hint = _("Enter the post ID."),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local post_id = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if post_id and post_id ~= "" then
                            self.last_post_id = post_id
                            self:showLoadingMessage(_("Starting search..."))
                            UIManager:scheduleIn(0.1, function()
                                self:fetchAndDisplayPost(post_id)
                            end)
                        end
                    end,
                },
            },
        },
    }

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ApiFetcher:downloadImage(url, dir, filename)
    if not url or url == "" then return nil end
    if not filename or filename == "" then return nil end

    local http = require("socket.http")
    local https = require("ssl.https")
    local ltn12 = require("ltn12")

    local response = {}
    local request = url:match("^https://") and https.request or http.request
    local filepath = dir .. "/" .. filename

    logger.info("Downloading image:", url)

    local ok, body, code = pcall(function()
        return request {
            url = url,
            sink = ltn12.sink.table(response),
            headers = {
                ["User-Agent"] = "KOReader/ApiFetcher 1.0",
            },
        }
    end)

    if not ok or code ~= 200 then
        logger.err("OpenTGC: Error downloading image.:", url, "code:", code)
        return nil
    end

    local file = io.open(filepath, "wb")
    if not file then
        logger.err("OpenTGC: Error creating file:", filepath)
        return nil
    end

    file:write(table.concat(response))
    file:close()

    return filename
end

function ApiFetcher:downloadMarkdownImages(markdown, dir)
    local images = {}
    local index = 1
    local total = 0

    for _ in markdown:gmatch("!%[.-%]%((.-)%)") do
        total = total + 1
    end

    if total > 0 then
        self:updateLoadingMessage(T(_("Downloading images...\n\n0 of %1"), total))
    end

    for url in markdown:gmatch("!%[.-%]%((.-)%)") do
        logger.info("Downloading image: " .. url)
        if type(url) == "string"
            and url ~= ""
            and url:match("^https?://")
            and not images[url]
        then
            -- Atualizar progresso
            if total > 0 then
                self:updateLoadingMessage(T(_("Downloading images...\n\n%1 of %2"), index, total))
            end

            local ext = url:match("%.([%w]+)$") or "jpg"
            local filename = string.format("image_%d.%s", index, ext)

            if self:downloadImage(url, dir, filename) then
                images[url] = filename
                index = index + 1
            end
        end
    end

    return images
end

local function escape_lua_pattern(s)
    return s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
end

function ApiFetcher:rewriteMarkdownImages(markdown, images)
    for remote, localname in pairs(images) do
        local escaped = escape_lua_pattern(remote)
        markdown = markdown:gsub(escaped, localname)
    end
    return markdown
end

function ApiFetcher:markdownToHtml(md)
    md = md:gsub("\r\n", "\n")

    md = md:gsub("!%[(.-)%]%((.-)%)", '<img src="%2" alt="%1">')
    md = md:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
    md = md:gsub("%*(.-)%*", "<em>%1</em>")

    md = md:gsub("\n\n+", "</p><p>")
    md = "<p>" .. md .. "</p>"

    return md
end

function ApiFetcher:formatTags(tags)
    if #tags == 0 then return "" end

    local html = '<div class="tags"><strong>Tags:</strong><br>'
    for _, tag in ipairs(tags) do
        html = html .. string.format('<span class="tag">%s</span>', tag)
    end
    html = html .. '</div>'
    return html
end

function ApiFetcher:createAndOpenHtml(post_data)
    local title = post_data.title or "Untitled"
    local text = post_data.text or "No content"
    local author = post_data.author and post_data.author.name or "Anonymous"
    local date = post_data.date or ""
    local tags = post_data.tags or {}
    local post_id = post_data.id or "unknown"

    local formatted_date = date:sub(1, 10)

    self:updateLoadingMessage(_("Creating directories..."))

    local base_dir = DataStorage:getDataDir() .. "/opentgc"
    local post_dir = base_dir .. "/" .. post_id

    local ffi = require("ffi")
    ffi.cdef [[ int mkdir(const char *pathname, unsigned int mode); ]]
    ffi.C.mkdir(base_dir, tonumber("755", 8))
    ffi.C.mkdir(post_dir, tonumber("755", 8))

    local markdown = post_data.text or "No content"

    local images = self:downloadMarkdownImages(markdown, post_dir)

    self:updateLoadingMessage(_("Processing markdown..."))

    markdown = self:rewriteMarkdownImages(markdown, images)

    local html_body = self:markdownToHtml(markdown)

    local cover_img_html = ""
    local img_url = post_data.imgUrl

    if img_url and img_url ~= "" and not post_data.noImg then
        self:updateLoadingMessage(_("Downloading main image..."))

        local ext = img_url:match("%.([%w]+)$") or "jpg"
        local filename = "cover." .. ext

        local saved = self:downloadImage(img_url, post_dir, filename)
        if saved then
            cover_img_html = string.format([[
<figure class="cover">
    <img src="%s"
        loading="lazy"
        decoding="async"
        alt="%s" />
    <figcaption>%s</figcaption>
</figure>
    ]], filename, title, title)
        end
    end

    local html_content = string.format([[
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>

    <style>
        body {
            margin: 0;
            padding: 1em;
            font-family: serif;
        }

        figure.cover {
            margin: 1em auto;
            text-align: center;
        }

        figure.cover img, img {
            display: block;
            max-width: 90%%;
            height: auto;
            margin: 1em auto;
        }

        figure.cover figcaption {
            font-size: 0.9em;
            opacity: 0.7;
            margin-top: 0.5em;
        }
        .meta, .footer {
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        %s
        <div class="meta">
            <h1>%s</h1>
            <strong>Author:</strong> %s<br>
            <strong>Date:</strong> %s<br>
            <strong>ID:</strong> %s
        </div>


        <div class="content">
            %s
        </div>

        
        <div class="tags">
            %s
        </div>
    </div>
</body>
</html>
]],
        title,
        cover_img_html,
        title,
        author,
        formatted_date,
        post_id,
        html_body,
        #tags > 0 and self:formatTags(tags) or ""
    )

    self:updateLoadingMessage(_("Saving file..."))

    -- Salvar arquivo
    local filename = string.format("%s/index.html", post_dir)
    logger.info("OpenTGC: Saving to:", filename)

    local file = io.open(filename, "w")
    if not file then
        logger.err("OpenTGC: Error creating file")
        self:closeLoadingMessage()
        UIManager:show(InfoMessage:new {
            text = _("X Error creating file!"),
            timeout = 3,
        })
        return
    end

    file:write(html_content)
    file:close()

    logger.info("OpenTGC: File saved successfully.")

    self:updateLoadingMessage(_("Completed!\n\nOpening document..."))

    UIManager:scheduleIn(0.5, function()
        self:closeLoadingMessage()

        UIManager:show(InfoMessage:new {
            text = _("Post downloaded successfully.!"),
            timeout = 1,
        })

        UIManager:scheduleIn(0.3, function()
            if self.ui and self.ui.document then
                self.ui:closeDocument()
            end
            require("apps/reader/readerui"):showReader(filename)
        end)
    end)
end

function ApiFetcher:onApiFetcherOpen()
    self:showInputDialog()
end

return ApiFetcher
