-- Lua filter for surveydown package
-- Handles both resource inclusion and shorthand page syntax conversion

-- ============================================================================
-- RESOURCE INCLUSION FUNCTIONS
-- ============================================================================

-- Function to get file paths using system.file from R
function get_package_file(file, type)
    local cmd = string.format('Rscript -e "cat(system.file(\'%s/%s\', package = \'surveydown\'))"', type, file)
    local handle = io.popen(cmd)
    local path = handle:read("*a")
    handle:close()
    return path
end

function Meta(meta)
    -- Define standard resources
    local js_files = {
        "auto_scroll.js",
        "clipboard.js",
        "cookies.js",
        "countdown.js",
        "highlighting.js",
        "interaction.js",
        "keep_alive.js",
        "option_attr.js",
        "progressbar.js",
        "ranking.js"
    }

    local css_files = {
        "surveydown.css"
    }

    -- Add default theme if not explicitly disabled
    if meta.default_theme ~= false then
        table.insert(css_files, "default_theme.css")
    end

    -- Initialize header-includes if it doesn't exist
    meta['header-includes'] = meta['header-includes'] or pandoc.MetaList{}

    -- Add Font Awesome from cdnjs
    meta['header-includes'][#meta['header-includes'] + 1] =
        pandoc.RawBlock('html', '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">')
    meta['header-includes'][#meta['header-includes'] + 1] =
        pandoc.RawBlock('html', '<script src="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/js/all.min.js"></script>')

    -- Add JavaScript files
    for _, file in ipairs(js_files) do
        local path = get_package_file(file, "js")
        if path ~= "" then
            meta['header-includes'][#meta['header-includes'] + 1] =
                pandoc.RawBlock('html', string.format('<script src="%s"></script>', path))
        end
    end

    -- Add CSS files
    for _, file in ipairs(css_files) do
        local path = get_package_file(file, "css")
        if path ~= "" then
            meta['header-includes'][#meta['header-includes'] + 1] =
                pandoc.RawBlock('html', string.format('<link rel="stylesheet" href="%s">', path))
        end
    end

    return meta
end

-- ============================================================================
-- SHORTHAND PAGE SYNTAX CONVERSION FUNCTIONS
-- ============================================================================

local has_old_syntax = false
local has_new_syntax = false

-- Function to check if a line contains the old fence syntax
local function is_old_syntax(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.classes then
      for _, class in ipairs(block.classes) do
        if class == "sd_page" or class == "sd-page" then
          return true
        end
      end
    end
  end
  return false
end

-- Function to check if a Para block is a page delimiter (em-dash + pageid)
-- Pandoc converts "--- pageid" to Para containing: em-dash (—) + Space + "pageid"
local function is_page_delimiter(block)
  if block.t ~= "Para" then
    return false, nil
  end

  local content = block.content
  if #content >= 2 and content[1].t == "Str" then
    -- Check if first element is an em-dash (Unicode U+2014 = "—")
    local first_char = content[1].text
    if first_char == "—" or first_char == "\u{2014}" then
      -- Second element should be Space, third should be the page ID
      if content[2].t == "Space" and #content >= 3 and content[3].t == "Str" then
        return true, content[3].text
      end
    end
  end

  return false, nil
end

-- Function to count page delimiters
local function count_page_delimiters(blocks)
  local count = 0
  for _, block in ipairs(blocks) do
    local is_delim, _ = is_page_delimiter(block)
    if is_delim then
      count = count + 1
    end
  end
  return count
end

-- Function to process blocks and detect page syntax
function Pandoc(doc)
  -- First pass: detect which syntax is being used
  has_old_syntax = is_old_syntax(doc.blocks)

  local page_delim_count = count_page_delimiters(doc.blocks)

  -- If we have page delimiters, we're using shorthand syntax
  if page_delim_count > 0 then
    has_new_syntax = true
  end

  -- Error if both syntaxes are detected
  if has_old_syntax and has_new_syntax then
    error("Mixed use of old fence syntax (::: {.sd_page}) and new shorthand syntax (--- pageid). Please use only one style throughout your survey.qmd file.")
  end

  -- If old syntax is used, do nothing (let existing system handle it)
  if has_old_syntax then
    return doc
  end

  -- If new syntax is used, convert to old syntax
  if has_new_syntax then
    local new_blocks = pandoc.List()
    local current_page = nil
    local current_page_content = pandoc.List()

    for i, block in ipairs(doc.blocks) do
      local is_delim, page_id = is_page_delimiter(block)

      if is_delim then
        -- If we have a current page, close it
        if current_page then
          local page_div = pandoc.Div(current_page_content, {id = current_page, class = "sd_page"})
          new_blocks:insert(page_div)
          current_page_content = pandoc.List()
        end

        -- Start new page
        current_page = page_id
      else
        -- Regular content
        if current_page then
          -- Collect content for the page
          current_page_content:insert(block)
        else
          -- Content before first page marker - pass through
          new_blocks:insert(block)
        end
      end
    end

    -- Close the last page if it exists
    if current_page then
      local page_div = pandoc.Div(current_page_content, {id = current_page, class = "sd_page"})
      new_blocks:insert(page_div)
    end

    doc.blocks = new_blocks
  end

  return doc
end
