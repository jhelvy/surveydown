# surveydown (development version)

- New feature: `sd_db_config()` now accepts a `url` parameter for quick setup from a Supabase (or any PostgreSQL) connection URL, e.g. `sd_db_config(url = "postgresql://user:[YOUR-PASSWORD]@host:6543/postgres")`. The URL is parsed to extract `host`, `port`, `dbname`, and `user` automatically. If the password is a placeholder (e.g. `[YOUR-PASSWORD]`), the user is prompted to enter it. The table name is always prompted (defaulting to `"responses"`). Individual parameters still override URL-parsed values.

# surveydown 1.3.0

- New feature: `mc_image` and `mc_multiple_image` question types — multiple choice where each option is a clickable image card (single selection with `mc_image`, multiple with `mc_multiple_image`). Pass a new `image` argument to `sd_question()`: a vector of image paths or URLs, one per option, in the same order as `option` (paths resolve against the survey's `images`/`www` folder, e.g. `"images/cat.png"`, or use full URLs). Captions are optional and controlled by the `option` names: named options (e.g. `c('Cat' = 'cat')`) show the names as text captions beneath each image, while an unnamed option vector (e.g. `c('cat', 'dog')`) shows the images only with no captions. (This differs from the other multiple-choice types, where an unnamed vector uses the values as visible labels.) Values are stored exactly like `mc`/`mc_multiple` (single value, or pipe-joined for multiple), so storage, restoration, and required-question logic all work the same.
- New feature: `matrix_multiple` question type — a matrix where each row allows multiple selections (checkboxes), complementing the single-selection `matrix` type (radio buttons). Usage is identical to `matrix` (same `row` and `option` parameters); each row becomes a `<question_id>_<row_id>` sub-question stored as its own column, with multiple selections pipe-joined (e.g., `"fast|cheap"`). Row shuffling, required-question handling, and session restoration work the same as for `matrix`.

- Enhancement: Sliders have been restyled. `slider` and `slider_numeric` questions now get a slim, theme-colored track with a clean circular handle and value bubble (previously ionRangeSlider shipped completely unstyled). The dense minor tick marks between positions are hidden; only the labeled major tick marks at the main breaks are shown.
- Enhancement: `sd_reactive()` no longer warns when its expression fails simply because the questions it references are not answered yet (e.g., arithmetic on a blank value at session start). Question references (`input$x`, `all_data$x`, `sd_value()`, `sd_values()`) are extracted from the expression; if any referenced value is still blank when an error occurs, the error is treated as the expected "not answered yet" state and `""` is stored quietly. Genuine errors (all referenced values filled in, or no detectable references) still warn. For this detection to work, call `sd_value()` _inside_ the `sd_reactive()` expression rather than capturing values in local variables beforehand.

- Bug fix: Navigating back to and then forward again past an answered matrix (or `matrix_multiple`) question no longer crashes the survey. The matrix parent question has no input of its own, so its stored value can be `NA`; the restoration guard now handles `NA` safely instead of erroring.
- Bug fix: Multi-value answers (`mc_multiple`, `mc_multiple_buttons`, `daterange`, and range `slider_numeric`) are now correctly restored when a respondent navigates back to a page or refreshes. These answers are stored pipe-joined (e.g. `"red|blue"`), but the restoration logic was splitting on commas, so previously the inputs came back blank. They now split on the pipe to match how the values are stored.
- Bug fix: `mode: preview` (and `mode: local`) now guarantee that the database is never used, even when a valid connection is passed to `sd_server()`. Previously, if `sd_db_connect()` succeeded while `mode: preview` was set, responses were silently written to the database while the banner claimed they were going to `preview_data.csv`. The connection is still created and tested by `sd_db_connect()` (so credentials are verified during preview), but all reads and writes go to the local CSV. When a connection exists but is ignored, the preview banner now reads "Database connected but not used" and a console message explains how to switch to database mode. `sd_db_connect()` no longer claims "Running in database mode" on connection (it cannot know the survey mode); it simply reports that the connection succeeded. `sd_server()` now always prints the operating mode on the console at session start for every mode: preview/local (with or without an ignored connection), database with a working connection, and a warning when mode is `database` but no connection is available (responses not saved). This also applies to `sd_store_value()`, which previously could read session-persistence values from the database in preview mode via the auto-detected `db` object.
- Bug fix: Restoring a cookied session in `preview`/`local` mode crashed the app with `object 'local_csv_file' not found` (a respondent refreshing the page in these modes hit a grey screen and a new session row). The local CSV filename is now set before `handle_sessions()` runs. The bug was introduced with the `mode` setting in v1.2.0 and only affected cookie restoration without a database connection; database mode was unaffected.
- Bug fix: A warm `_survey/` cache is now invalidated when the installed surveydown package is newer than the cached render. Previously, upgrading the package did not trigger a re-render, so surveys kept serving the previous package version's embedded JavaScript and CSS until `survey.qmd` was next edited.

- Efficiency: Consolidated the per-question observers in `sd_server()`. Two of the three observer sets created for every question (`*_manual_range` and `*_autosave_timestamp`) were dead code — the client-side JavaScript that emitted those inputs was removed in earlier refactors — so each question now registers one observer instead of three. The `*_value`, `*_label_option`, and `*_label_question` outputs are registered once per question (reading reactively from `all_data`) instead of being re-registered on every input event; as a side benefit, `sd_output(id, type = "value")` now shows values restored from a resumed session before any new interaction.
- Efficiency: In preview/local mode, the response CSV (`preview_data.csv` / `local_data.csv`) is now held in an in-process cache instead of being re-read from disk on every save and every lookup. Local modes run in a single R process, so all sessions share one copy per file; entries are keyed by absolute path and invalidated if the file changes on disk (external edits or deletion are picked up). Saves still write the complete file to disk every time, so no data is lost on a crash. Also removed a duplicate definition of `get_local_data()` that existed in both `server.R` and `util.R`. Database mode is unaffected.
- Efficiency: App startup with a warm `_survey/` cache no longer runs `quarto::quarto_inspect()` (a 1-3s subprocess) or rewrites `settings.yml`. When nothing changed, `sd_ui()` reads the progress bar and footer settings from the cached `_survey/settings.yml`; previously the unconditional settings rewrite also bumped its mtime, forcing `run_config()` to re-parse all pages and questions on every startup. This mainly speeds up cold starts of deployed apps (new workers, container restarts). The full inspect path still runs whenever `survey.qmd`, any YAML file, or `app.R` changes, or if the cached settings are missing/unreadable.
- Efficiency / bug fix: The per-question inline JavaScript for `mc_buttons`, `mc_multiple_buttons`, and `numeric` questions has been replaced with delegated handlers in `interaction.js`, registered once per page load. Previously each question embedded its own script; for reactive questions (re-rendered via the server), the `mc_buttons`/`mc_multiple_buttons` scripts re-registered a new document-level click handler on every re-render, so handlers accumulated over a session. The numeric input's validation, spinner UI, and paste handling now also live in the shared file (the spinner is injected on Shiny's `shiny:bound` event, so it works for reactive questions too), shrinking the rendered HTML. Surveys with a stale `_survey/` cache keep working (the old inline scripts remain functional alongside the new handlers until the next re-render).
- Efficiency: The cookie-sync observer (which mirrors current-page answers, page history, and shuffle orders into the browser cookie) is now debounced by 500ms. Previously it re-serialized all current-page answers and messaged the client on every input change — including every keystroke in text questions. Now a single cookie update is sent shortly after the respondent pauses.
- Efficiency: Parsed `_survey/settings.yml` content (settings and system messages) is now cached per Shiny session in `session$userData`, so repeated calls (e.g., per reactive question or per `sd_store_value()`) no longer re-read and re-parse the file from disk. Calls made outside a Shiny session (e.g., during Quarto rendering of `survey.qmd`) still read directly from disk.
- Efficiency: The `show_if` observer no longer depends on every input via `reactiveValuesToList(input)`, which re-evaluated all `show_if` conditions on every keystroke of any input. It now depends only on the question values actually referenced in the conditions (extracted statically, plus dependencies registered dynamically during condition evaluation). Since `show_if` target containers are baked into each page's HTML as hidden, the rendered page now signals the server when its DOM is inserted (`sd_page_rendered`) so question visibility is re-applied on every page render.

- Internal: Question types are now defined in a single registry (`R/question_types.R`). Each type provides a `render()` (build the UI) and `restore()` (re-apply a stored value when navigating back) function plus a `requires_option` flag. `sd_question()` and the page-restoration logic in `sd_server()` dispatch through this registry instead of long if/else chains, so adding a new question type touches one place. No change to existing behavior.

- Testing: Added `tests/manual/` with chromote-based headless browser tests covering `sd_show_if()` (all condition styles, including cross-page `input$`/`all_data$` conditions), `sd_skip_if()` (simple and two-question skips, required-question blocking), `sd_stop_if()` (stop messages, priority over required warnings, per-page applicability), data storage in preview mode (every question type verified end-to-end in `preview_data.csv`, including pipe-joined multi-selects, slider label-to-value mapping, matrix sub-columns, `sd_store_value()`, and session metadata), and cookies/session restoration (page refresh restores the current page and answers, sessions resume with the same `session_id` and a single CSV row, and a fresh browser starts a new session). The tests run against bundled apps in `tests/manual/apps/`, so they are self-contained and machine-independent. `tests/manual/run-all.R` runs the whole suite (in parallel when `mirai` is installed). Not run by `devtools::test()` or R CMD check.

# surveydown 1.2.0

- New feature: Survey operating mode is now controlled via a `mode` key under `survey-settings` in `survey.qmd`. Supported values are `"database"` (default), `"preview"` (saves responses to `preview_data.csv`), and `"local"` (saves responses to `local_data.csv`). The `mode` parameter replaces the deprecated `ignore = TRUE` argument in `sd_db_connect()`.
- Breaking change: The `ignore` argument in `sd_db_connect()` is now deprecated. Use `mode: preview` in `survey.qmd` YAML instead. Setting `ignore = TRUE` still works but emits a deprecation warning.
- Enhancement: A visible banner is now displayed at the bottom of the survey when running in `preview` mode (yellow) or when the database is not connected while in `database` mode (red), alerting developers that responses are not being saved to the database.
- Bug fix: Markdown/HTML formatting in `mc` and `mc_multiple` question labels (e.g. `**bold**`) is now preserved when option shuffling is enabled. Previously, shuffled choice questions were re-rendered on the client from a plain-text copy of the label, which stripped bold, italics, and links from the question text. The parsed question structure now carries the label's inline HTML (`label_html`) alongside the existing plain-text `label`.

# surveydown 1.1.3

- New feature: A new `option_attr` parameter for `sd_question()`, limited to the `mc` and `mc_multiple` types. It can be used to define the extra attributes for the designated options with a question mark icon to the right which can be triggered either with hovering or clicking. For example, an `mc` question might have `option = c("option_1, "option_2", "option_3", "option_4")`. Then we can give `option_attr = c("Attribute 1", NA, "Attribute 3")` to define attributes for the 1st and 3rd options.

# surveydown 1.1.2

- Bug fix (#266): Matrix row shuffling now works correctly with Quarto >= 1.7.

# surveydown 1.1.1

- Bug fix (#250): Indexed option shuffling (e.g., `question_id: [1, 2, 3]`) failed silently when all `shuffled` items used indices with no plain question IDs mixed in. Options now shuffle correctly regardless of format.

# surveydown 1.1.0

- Bug fix (#246): Added a helper function that provides a vector of all preserved words that cannot be used as IDs and use it to prevent preserved IDs in `sd_store_value()`.
- New feature (#247): `sd_values()` and `sd_value()` as new approach of accessing question values, replacing the Shiny default `input$`. `sd_values()` and `sd_value()` are able to restore user inputs from db after refreshing the page. They also accept either quoted question IDs or unquoted, so that either `sd_value(fruit)` or `sd_value("fruit")` is fine. They also support multiple parameters, which return into a vector of values. For example, `sd_value(fruit, vegetable)` returns `c("apple", "lettuce")`. sd_value()`is the alias of`sd_values()`, so they function the same.
- New feature (#248): Option shuffling supported for `mc`, `mc_buttons`, `mc_multiple`, and `mc_multiple_buttons`. Subquestion shuffling supported for `matrix`. In YAML of `survey.qmd`, 2 new keys are available: `shuffled` and `all-shuffled`. `shuffled` is used to list the question IDs of these 5 question types to have their options/subquestions randomly shuffled. `all-shuffled` is by default `false` and can be set to `true` to apply shuffling to all questions.
- New feature (#248, continued): Indexed option shuffling. Use indexing to define what positions of options/subquestions you want to shuffle. For example, `question_id: 1-5` means to shuffle the first 5 options of the question, or the first 5 subquestions if it's a matrix question. Other supported syntax: `question_id: [1, 2, 4, 7]`, `question_id: [1-5, 8-10]`. No indexing means to shuffle all options/subquestions.
- Breaking change: The `required-questions` and `all-questions-required` YAML keys are renamed as `required` and `all-required`, respectively.
- Therefore, for YAML keys, we have `required` and `shuffled` both accepting question IDs, and `all-required` and `all-shuffled` both accepting `true` and `false`.
- Breaking change: All survey setting parameters are removed from `sd_server()`, which only supports `db` as its only parameter. To define survey settings, please only use the YAML header in `survey.qmd`.
- Breaking change: The `sd_question()` function no longer has the `matrix_option_width` parameter. Since the matrix question type only has a question column and an option column, we chose to only keep `matrix_question_width` to control the question column width. The option column width is defined automatically according to whatever is left. Also, now `matrix_question_width` is default to `NULL`, in which case the width is auto-defined according to the length of the longest question. Users can overwrite it by defining `matrix_question_width` to a specific value, and we support numeric, string, or string with %. For example, it's valid to define `matrix_question_width = "40%"`, `= "40"`, and `= 40`, all of which result in 40% of width.
- Enhancement (#261, #262): Now the short-hand format of options in `sd_question()`, for example `c("Label 1", "Label 2")`, will be stored as they are. This is for compatibility with special characters.
- Depreciated the `sd_create_messages()` function.

# surveydown 1.0.2

- Bug fix (PR #241): `textarea` questions were being parsed as `"unknown"` type instead of `"textarea"`, preventing proper restoration when navigating between pages.
- Feature add (PR #240): Added `matrix_question_width` and `matrix_option_width` arguments to `sd_question` to modify the width of the question and option columns in the `type = "matrix"` questions.
- Feature add (PR #242): Added support to have a "restart" button added when using `sd_close()` so respondents can submit another response with proper cookie handling.

# surveydown 1.0.1

- Bug fix (#243): Updated all internal templates and roxygen examples to latest UI established in v1.0.0.
- Bug fix (#244): theme assignment with custom scss files in YAML now works properly, e.g. `theme: [united, custom.scss]`.
- Progress bar update: Now users can define `barcolor` under the `theme-settings` YAML section to customize the progress bar color, accepting both text color names (over 140 supported by browser CSS) and hex color codes in 3 or 6 digits, e.g. `#FF5733` or `#F53`. If not defined, it shows `~` as the value in `settings.yml`, indicating it's using the default setting which follows the theme.
- Documentation update: Removed the `inst/examples/` directory. Now all exported functions are documented with simple execution showcases, plus a designated template from one of the supported [templates](https://github.com/surveydown-dev).

# surveydown 1.0.0

- Function update: `sd_nav()` replacing `sd_next()`, which contains both previous and next buttons.
- Function update: `sd_close()` now supports addition of previous button as well.
- Function update: `sd_question()` now supports either `option` or `options`. If both are provided, `option` will be used. When defining `option` or `options`, users can now only provide display labels, and the db values will be auto-converted to snake case. For example, `sd_question(options = c("Option 1", "Option 2"))` will have db values of `option_1` and `option_2`.
- New feature: `surveydown` now supports previous buttons. Under `survey-settings`, users can now define `show-previous` (default to `FALSE`) to enable previous button globally. In `sd_nav()`, users can define `show_previous` being `TRUE` or `FALSE` to override the global setting for that specific page.
- Simplification: No need to define `format`, `echo`, and `warning` in YAML header of `survey.qmd` anymore. The survey can have a clean start and runs fine without the YAML header.
- Simplification: No need to define `sd_nav()` for each page. It's auto-injected unless `sd_nav()` or `sd_close()` is explicitly defined in the page with or without parameters.
- New `settings.yml` content structure with 3 sections: `theme-settings`, `survey-settings`, and `system-messages`. They appear with our without YAML header of `survey.qmd` and are verbose (meaning all keys and values always appear).
- Progress bar update: Now since previous button is supported, the progress bar will update accordingly when user goes back and forth among pages.
- Enter key depreciated for triggering next button: Since `surveydown` now supports both previous and next buttons, we decided to disable the Enter key for triggering next button to avoid confusion.

# surveydown 0.14.0

- New feature: shorthand page syntax supported. Now we recommend using `--- page_id` to start a new page, and there is no need to end the page. The previous syntax of starting a page with `::: {.sd_page id=page_id}` and ending with `:::` still works.

# surveydown 0.13.4

- Bug fix: Now the `"auto"` mode of `sd_db_connect()` will correctly detect if `gssencmode` should be `"prefer"` or `"disable"`, based on the actual connection status.
- Improvement: Now `mc` and `mc_multiple` question types in `sd_question()` will have their options HTML and markdown compatible.

# surveydown 0.13.3

- Enhanced the `numeric` question type input logic.
- Added validation to ensure page closing fences (`:::`) are properly matched in survey.qmd files.
- Added validation to ensure `sd_server()` is called as the last statement in the server function.
- Survey templates are now split into individual repos. For details, see the [surveydown-dev](https://github.com/surveydown-dev) organization site and search for "template" in Repositories.
- The `sd_create_survey()` function now obtains survey templates from these new individual repos. The function syntax remains the same.

# surveydown 0.13.2

- New feature: `sd_stop_if()` function to stop the navigate button if certain conditions cannot be met.
- Deprecated `sd_skip_forward()` function, and reuse `sd_stop_if()`.
- Enhanced: Now for the judging conditions in the 3 condition check functions (`sd_show_if()`, `sd_skip_if()`, and `sd_stop_if()`), these judging questions are auto-assigned as required questions.
- Updated `sd_create_survey()` to update with the latest templates.

# surveydown 0.13.1

- Updated citation to include _PLOS One_ publication

# surveydown 0.13.0

- Enhanced: `sd_store_value()` - Now session-persistent with database integration, compatible with local testing. It also saves the value into the server so it matches the database.
- Enhanced: Now cookie is working for both db mode and local csv.
- New feature: YAML-based server configuration - All `sd_server()` parameters can now be configured in the survey.qmd YAML header (e.g., `use_cookies: yes`, `auto_scroll: no`). Parameters in `sd_server()` take priority over YAML.
- Bug fix: We noticed if question options are generated from HTML, they will have empty labels saved in `questions.yml`. Now it's fixed by auto-assigning the labels from the values. This auto-assignment is already applied in general cases where option labels are empty.
- Depreciated the `sd_dashboard()` function; functionality is now included in the [{sdstudio} package](https://github.com/surveydown-dev/sdstudio/).
- Bug fix: Solved the Shiny Client Error of "shared input/output ID" triggered by `sd_output()` with `type` being `"question"`. Now users can still use `sd_output()` to display reactive questions with same IDs, but the internal HTML IDs will be different by appending a `_question` in the end.

# surveydown 0.12.8

- New argument for `sd_server()`: `capture_metadata` automatically captures and stores browser information and IP address. Defaults to `TRUE`.

# surveydown 0.12.7

- Bug fix: The `sd_redirect()` function used to trigger Shiny Client error of duplicated IDs for input and output. Now it's fixed by adding a unique ID to the button.
- Allow for environment variables to come from system (if available), PR #212

# surveydown 0.12.6

- UI update: Now `"matrix"` question type has better layout.
- Bug fix: `"text"`, `"textarea"` and `"numeric"` types could bypass the "required" question check with mouse clicking on their areas. Now it's fixed.

# surveydown 0.12.5

- New argument: `gssencmode` now has values of `"auto"`, `"prefer"`, and `"disable"`, with `"auto"` being default.
- New feature: Now re-rendering will be triggered by changing of either the `survey.qmd` or `app.R` file.
- Bug fix: `slider`, `slider_numeric`, `date`, and `daterage` questions now will be marked as answered without user interaction if the Next/Close button is pushed, and will have their default value saved.
- Bug fix: `mc_buttons` and `mc_multiple_buttons` now can properly save data.

# surveydown 0.12.4

- In `sd_question()`, `"numeric"` question type will only allow numeric inputs and `+`/`-` signs.
- Progress bar won't force to 100% if the ending page has questions. It is useful for those one-page surveys without any Next button or even finish button. In our previous versions, this case will force the bar to 100% even with unanswered questions.

# surveydown 0.12.3

- New argument for `sd_server()`: `highlight_unanswered` gives color shading for the unanswered questions, default to `TRUE`, can be turned off by changing to `FALSE`.
- New argument for `sd_server()`: `highlight_color` changes the shading color, default to `"gray"` (or `"grey"` as an acceptable spelling), can be changed to `"blue"`, `"orange"`, `"green"`, or `"purple"`.

# surveydown 0.12.2

- `sd_create_survey()` now accepts a new `ask` argument, defaults to `TRUE`. If `ask = FALSE`, the survey creation will proceed without asking.

# surveydown 0.12.1

- Bug fix: In the `0.11.1` version, `sd_show_if()` works for pages as well, but it will make `sd_skip_forward()` totally ignored. Now this is fixed.

# surveydown 0.12.0

- Required question highlighting: Now upon clicking the "Next" button, the unanswered required questions will be highlighted.

# surveydown 0.11.1

- `sd_create_survey()` now accepts `template` as the first argument, and `path` as the second. This follows intuition that we firstly choose a template, and then define the location.
- `sd_show_if()` now works for both questions and pages with the same syntax. Therefore, we also added an ID check for the uniqueness of the `page_id` and `question_id` altogether. If there is a duplicated ID, the survey will stop and show an error.

# surveydown 0.11.0

- Questions can now be defined using an external yml file, defaulting to `"questions.yml"`.
- New `yml` argument in `sd_question()`, defaults to `"questions.yml"`, to allow users which yml file to use for questions. For details, refer to the [Defining Questions](https://surveydown.org/docs/defining-questions) documentation page.
- Update to `sd_create_survey()`: now the the `template` argument is by default `"default"`.
- Update to `sd_create_survey()`: new `template = "questions_yml"` option to create a survey with the `questions_yml` template.

# surveydown 0.10.1

- `sd_create_survey()` now accepts two arguments. The `template` argument is by default `"plain_template"`, which creates a default plain template of surveydown. It also accepts a list of templates. On our [surveydown-dev organization](https://github.com/surveydown-dev) page, there are 14 repos starting with `template_`, each serving as a survey template. The `path` argument is unchanged. It defines the relative path of the template location.

# surveydown 0.10.0

- New feature: gadgets added for creating survey pages and questions. It can be triggered under the "Addins" menu on the top of RStudio window, or by keyboard shortcut. To set up keyboard shortcut, go to "Tools -> Addins -> Browse Addins..."
- Recommended page fence structure changed to: `.sd_page id=page_id`. The previous structure also works.
- Updated template (triggered by `sd_create_survey()`) to match with new recommended page structure.
- Remove `sd_show_password()` function entirely (previously was depreciated)
- Remove the dependency on `usethis` package
- Created internal `yesno()` function to replace `usethis::ui_yeah()`

# surveydown 0.9.1

- `sd_dashboard()` now accepts an argument of `gssencmode`, defaults to `"prefer"`. This is same logic as the `gssencmode` argument in `sd_db_connect()`.
- To further explain this update, both `sd_dashboard()` and `sd_db_connect()` accepts the `gssencmode` argument to embrace the different `gssencmode` situations of the internet connection. It is not embedded into `sd_db_config()` because `gssencmode` is not accessible for all connections (some may have `NULL`). This extra argument for `sd_dashboard()` and `sd_db_connect()` can be considered as a work-around.

# surveydown 0.9.0

- Overhauled how page skipping logic is handled for improved performance and consistency with different skipping conditions users provide.
- The `sd_skip_if()` function is depreciated and replaced with `sd_skip_forward()` for clarity of what the function does.
- Skipping logic is now strictly forward to avoid unintended skipping logic loops.

# surveydown 0.8.4

- Add support for `sd_skip_if()` to be able to use static values and reactive expressions as conditions.
- Add support for `sd_show_if()` to be able to use static values and reactive expressions as conditions.

# surveydown 0.8.3

- Added `sd_reactive()` function to store reactive values in the data, addressing #179.

# surveydown 0.8.2

- Added `"slider_numeric"` type to `sd_question()`, which supports both single and dual numeric sliders.
- Added the `...` argument to all question types in `sd_question()` so that users can pass other input arguments specific to each input type.
- Move the `gssencmode` parameter out of the database settings and made it an argument in `sd_db_connect()` so that users can pass `NULL` if needed to completely ignore it when making connections.

# surveydown 0.8.1

- Updated the template used in `sd_create_survey()` to match the new database configuration introduced in v0.8.0.
- Fixed [Issue 170](https://github.com/surveydown-dev/surveydown/issues/170): Now the matrix question type can have all subquestions defined as required with `sd_server(required_questions = "matrix_question")`.

# surveydown 0.8.0

- New function for setting up the database configuration: `sd_db_config()`. Stores database parameters in a local .env file. Replaces `sd_set_password()` and `sd_show_password()`, which are now depreciated.
- New function for connecting to database: `sd_db_connect`. Replaces older `sd_database()` function, which is now depreciated.
- New `sd_dashboard()` that locally runs an interactive shiny app for monitoring data in database.
- Bug fix: Fixed the slider question type options. They we previously in the opposite order from all other question types (label = value), see #166.

# surveydown 0.7.2

- Bug fix: The `mc_multiple` question type could not resume its UI if multiple options are selected. Now it's solved.
- New feature: a new `sd_question_custom()` function is created for custom question definition. See the [`leaflet-map`](https://github.com/surveydown-dev/template_custom_leaflet_map) and [`plotly`](https://github.com/surveydown-dev/template_custom_plotly_chart) template surveys for more details.

# surveydown 0.7.1

- `custom` type added for `sd_question()`. Now users can create customized question types according to their own needs. A demo of leaflet map is created as well to showcase this ability.

# surveydown 0.7.0

- Heavy revision to how css and us dependencies are loaded. Now the `sd_ui()` function handles the rendering of the `survey.qmd` file and extracting the header contents. All surveydown css and js dependencies are loaded via a simple lua filter when rendering. This simplifies how these dependencies get loaded into the resulting shiny app.

# surveydown 0.6.2

- Update: Now `ignore = TRUE` in `sd_server()` will turn off cookies, regardless of the value of `use_cookies`.

# surveydown 0.6.1

- Cookies now contain not only the `session_id` but a complete JSON object of the current page questions, answers, and latest time stamp.
- Increased checkpoints of data updates. Now they are: upon starting, upon proceeding to the next page, upon submitting rating or clicking the exit button, and finally, upon abruptly quitting the survey.

# surveydown 0.6.0

- Cookies functionality fully working, applied to both local testing and online db.
- Bug fix: The matrix subquestions used to be counted as the last questions in order regardless of their location in the survey. It's now solved.

# surveydown 0.5.2

- Cookies feature fixed and back online.
- Now upon window closure, the data will be immediately uploaded to db. A backup uploading will trigger upon session ends, which is usually after 5-10 secs upon closing the window.

# surveydown 0.5.1

- Revert mostly to v0.4.2 to completely remove the cookies feature added in v0.5.0. Will re-implement a new approach in a later version.
- Fixed typo in error message (`data.csv` -> `preview_data.csv`).

# surveydown 0.5.0

- New cookies feature! Now `sd_server()` accepts a new argument `use_cookies`, defaults to `TRUE`. It enables cookies so that reopening the survey will resume the participant to where the survey was left. The database will trace to the original `session_id` and continuous the data update based on user input. If changed to `FALSE`, the survey will start as brand new session upon reopening.
- Off-line data storage upgrade. Now if ignore mode is on, the data will be stored on the project directory with file name called `preview_data.csv`. This file works exactly the same as online database, and is compatible with cookies functionality.
- Simplified Chinese supported in `sd_server()`. You can trigger it by: `sd_server(language = "zh-CN")`.
- Improvement: default language behavior in UI functions cleaner when separately rendering survey.qmd file.
- Bug fix: There used to be a bug if multiple themes are defined in YAML. Now it's solved.

# surveydown 0.4.2

- New "translations" feature now supported (see PR #138). This allows system messages and date formats to be specified by a language using the `language` argument in `sd_server()`. Custom language messages can be further modified by providing a `translations.yml` file in the root project folder.
- Added new `sd_create_translations()` function to generate a template `translations.yml` file to use to edit the system messages.
- Added Stefan Munnes as contributor in DESCRIPTION file (`ctb`)
- Bug fix: The `is_matrix` metadata was not recorded for matrix sub-questions when exported into the `_survey/questions.yml` file, which caused an error if any matrix question was required. This is now corrected when obtaining the question structure from the stored `_survey/questions.yml` file.

# surveydown 0.4.1

- Modified survey rendering to move all rendered files into "\_survey" folder.
- Export survey question metadata to "\_survey/questions.yml" file (see #132).
- Survey content is now extracted and saved to '\_survey/pages.rds', '\_survey/head.rds', and '\_survey/questions.yml' files for faster loading.
- Survey will load content from stored files if no changes detected in 'survey.qmd' or 'app.R' files.

# surveydown 0.4.0

- All examples updated to include run-able examples (where possible).
- Added example survey.qmd files in inst/examples (for use in function examples).
- All roxygen documentation reviewed for errors / typos.
- Removed `sd_update()` function.
- Removed `sd_deploy()` function.
- Installation instructions updated.

# surveydown 0.3.7

- Updated `sd_output()` to now be able to output the chosen question values, chosen question option label(s), and the question label itself. Addresses feature request #128.
- Enhance: `sd_update()` now directly force update the package without checking for version difference anymore.
- New: `sd_is_answered()` function to check if a question is answered or not and returns `TRUE` or `FALSE` accordingly. For `"matrix"` type, only if all sub-questions are answered will it be marked as `TRUE`.

# surveydown 0.3.6

- Enhance: `sd_add_question()` now has a `chunk` argument, if `TRUE` it will include the outer chunk wrapper. Default is `FALSE`.
- Enhance: The `matrix` question type now will have its root question id shown in the data sheet. This id is essential in other logic, for example it can be used as a handle for the `sd_show_if()` logic. This root id is also removed from the `all_question_required` logic, since it's only a handle and doesn't provide option to answer.
- Enhance: Removed the `use_html` argument in `sd_server()`. Now the survey.qmd file will always be rendered when the app runs only if one of two conditions are met: 1) the survey.html file is not detected, or 2) the survey.html file is outdated. Otherwise, it will use the rendered survey.html file.
- Bug fix: `auto_scroll` now works better and smoother.
- Bug fix: the enter key will not trigger page turn if working on `text`, `textarea`, `numeric`, `select`, `date`, and `daterange`.
- Enhance: the Enter key can now used to trigger the "Submit and Exit" button for the rating pop-up modal.

# surveydown 0.3.5

- Enhance: The database updating is simplified to only write to the database on each page turn and after the survey closes.
- Bug fix: if you added new questions or values to the survey after creating the initial database table, those new values would not have been added to the table. Now they are added.
- Enhance: `auto_scroll` changed to `FALSE` by default.

# surveydown 0.3.4

- Bug fix: reactive questions now work with show_if conditions too
- Bug fix: show_if conditions now work even if the target question is on a different page.
- Bug fix: reactive question ids (those defined in the server) were not being considered in `check_skip_show()` checks, so you'd get an error that the question id was invalid.
- Enhance: `sd_server()` accepts a new parameter called `"rate_survey"`, default to `FALSE`. If `TRUE`, the Exit button will trigger a rating question. If `FALSE`, the Exit button will only trigger a double confirmation to ensure the user really wants to exit.
- Enhance: Now the survey will check if there exists an `sd_close()` function call.
- Enhance: Now the survey will check if the reserved question IDs are used, including `session_id`, `time_start`, `time_end`, and `exit_survey_rating`. There could be more in the future.
- Enhance: Now the `sd_output()` function will take care of the styling setting of reactive questions. For example, `sd_output(id = "some_question_id", type = "question", width = "80%")` will define with of 80% for a reactive question.
- Enhance: Now the `sd_show_if()` can take care of cross-page conditional reactive questions.

# surveydown 0.3.3

- Enhance: `sd_server()` now has a new parameter called `auto_scroll`. It's default to `TRUE`, which enables auto scrolling that tracks the user's input, can be turned off by changing to `FALSE`. Thanks to the contribution from [Zain Hoda](https://github.com/zainhoda1).
- Enhance: `sd_question()` now has the `"matrix"` type.
- Enhance: Asterisk, as an indication of required questions, is now moved to the top right corner of question containers.
- Enhance: Replaced the default shiny alert with `sweetalert`.

# surveydown 0.3.2

- New: Added `sd_completion_code()` function.
- Bug fix: make stored values accessible with `sd_output()` with `type = 'value'` argument. Previously only question values could be displayed in the UI with `sd_output()`.
- New: `sd_add_question()` to instantly create a question template. Defaults to type of `"mc"` but also accepts all other types (`"text"`, `"textarea"`, `"numeric"`, etc.). The function call will delete itself after running.
- New: `sd_add_page()` to instantly create a page template. Make sure to run this function outside any division or code chunk. The function call will delete itself after running.

# surveydown 0.3.1

- Enhance: Improved efficiency in `database_uploading()` so only the changed fields get written, and also the writing happens after checking the `show_if` conditions (addresses #100).
- Enhance: Modified default rendering behavior to not delete the rendered html file.
- Enhance: Modified the `refresh_interval` argument in `sd_get_data()` as defaulting to `NULL`, which means the data will not be reactively fetched, regardless of the context it is used in. The data will only continuously refresh if `sd_get_data()` is called within a reactive context and `refresh_interval > 0`.
- Enhance: Modified messaging from `sd_set_password()` to not print out user's password and provide clearer instructions.
- New: `sd_show_password()` added to show a stored password. The user will be prompted to double confirm that they want to show it. If there is no password, the user will be prompted so, along with a message of using `sd_set_password()` to create the password.

# surveydown 0.3.0

- Introduced `sd_ui()` function to set placeholders for the shiny app ui.
- Heavily revised how `skip_if` and `show_if` works, removing `skip_if_custom` and `show_if_custom`. Now they work similar to the `case_when()` function, where you provide the formula `condition ~ target` for each condition in either function. These are also provided globally inside the `server()` function using `sd_skip_if()` and `sd_show_if()`.
- Require that the survey file be named `"survey.qmd"`.
- Added `sd_include_folder()` function so users can add a folder to the shiny resource path.
- Automatically include the `images`, `js`, `css`, and `www` folders as well as folders to quarto files to the shiny resource path when the package loads.
- Heavily modified how `sd_next()` works to improve page navigation and ensure that each `sd_next()` button has a unique id based on the current page.
- Removed the quarto extension.
- `sd_create_survey()` changed to sourcing template directly from the package. Two parameters are provided. The first parameter is `path`, which defines the relative path of the target. If left blank, the path will be the current working directory. The second parameter is `structure`, which defines which structure of the template the user wants to choose, default as `"single"` and can be changed to `"multi"`.
- `sd_deploy()` as a wrapper function of `rsconnect::deployApp()` to deploy the survey.
- `sd_update()` as a replacement of `sd_update_surveydown()` to update the package.
- `sd_version()` as a replacement of `sd_check_versions()` to check for the current version and the latest version.
- `sd_close()` function to create a close button for the survey.

# surveydown 0.2.4

- No need to use `<br>` above the Next button anymore. The Next buttons can now be in the same chunk as the questions as spacing has been added.
- Modified margins on top and bottom. Solved the large gap created by hidden questions.
- Fixed an issue with `sd_store_value()`. There used to be a problem if a value is a list with multiple entries. Now they are collapsed with commas due to the application of `format_question_value()` on the `value` variable.
- Removed the `reactive` argument for `sd_get_data()`. Now all functions that should be compatible with both reactive (server) and static (ui) conditions will automatically match, without necessity of explicitly specifying them.
- `sd_redirect()` updated with a parameter called `newtab`, defaults to `FALSE`. If `TRUE`, the redirection link will be opened in a new tab. If used together with `delay`, the new tab might be blocked by the browser after count-down, but the user click will not be blocked.
- Improved the `database_uploading()` function to secure it from possible SQL injection attacks.

# surveydown 0.2.3

- Solved the speed problem for database connections: refactored `sd_server()` for efficiency; converted local data storage to lists instead of data frames.
- Assigned `session_id` as the leading column, and removed the `respondent_id` column.

# surveydown 0.2.2

- `sd_redirect()` to create redirection to external links, either by providing a button, a countdown, or both. This function can be called both in the survey body and the server chunk.
- `sd_get_url_pars()` to reactively get the parameters in the URL.
- The above 3 functions work together to retrieve and redirect URL parameters so that surveydown is compatible with survey panels.
- Now `sd_next()` and `sd_redirect()` both support the "Enter" key for a better user experience.
- Add automatic clean up in `sd_database()`.
- `sd_output()` function that replaces the original `sd_display_question()` (by specifying `type = "question"`) and `sd_display_value()` (by specifying `type = "value"`). The original 2 functions are depreciated and will be removed in future updates. If `sd_output()` is only used with `"id"` specified, it works the same as `shiny::uiOutput()`.

# surveydown 0.2.1

- In `sd_database()`, now `db_name` is changed to `dbname`, and `table_name` is changed to `table`, for consistency with Supabase, and simplicity of parameter names.
- Now the error message of `sd_database()` will also prompt "If you have verified all connection details are correct but still cannot access the database, consider setting the `gssencmode` parameter to `"disable"` in the `sd_database()` function." We don't encourage users to disable `gssencmode`, since it's more secure to have it on, but if users encounter with connection error, this will be a possible solution.
- Bug fix: A bug was introduced when restructuring the `sd_server()` function in the last update that affected numeric questions being determined as answered or not, that is now fixed.
- Fixed [issue #80](https://github.com/surveydown-dev/surveydown/issues/80): If `sd_display_value()` was used multiple times on different question IDs, it could only fetch the last user input. Now it's fixed.
- Renamed main lua file in `inst/quarto/filters` from `surveydown.lua` to `sd_main.lua` and updated the extension v0.2.5 to call this via a more robust, cross-platform approach.
- (Extension) Renamed the extension lua filter to `sd_wrapper.lua` to avoid naming conflict. Now the extension is only used as a wrapper. The `sd_main.lua` and related CSS and JS files are all in the R package.

# surveydown 0.2.0

- Moved `sd_store_value()` and `sd_copy_value()` to the server.R file (these are server operations).
- Added `respondent_id` variable that tracks the respondent based on their starting the survey.
- Restructure the server to be more efficient.
- Now the required questions can successfully bypass the hidden required questions of all types.

# surveydown 0.1.2

- Moved the main surveydown.lua file into the package at inst/quarto/filters. The surveydown Quarto extension is now just a wrapper to load this file, so the extension won't likely need to update any further as all updates can be made in the package lua file.
- Changed `jhelvy` to `surveydown-dev` in version control functions.
- Now if there are duplicated `page_id` and `question_id`, the survey will stop and show error.
- Removed roxygen2 documentation from non-exported functions.

# surveydown 0.1.1

- Added `sd_get_data()` with a `reactive` argument to enable reactive data fetching.
- `sd_question()` now has a `reactive` argument to enable reactive questions, and `sd_question_reactive()` was removed.
- Made `sd_admin_enable()` internal, changed to `admin_enable()`.
- Removed `sd_admin_ui()` and `sd_add_admin()` from the package.
- Moved the surveydown.css and page_nav.js files into the R package and out of the Quarto extension.
- Added keep alive functionality to the survey.
- Bug fixes:
  - The admin page password was looking for the `SUPABASE_PASSWORD` environment variable, but it should be `SURVEYDOWN_PASSWORD`.
  - The data fetching was not working to download the data as a CSV file in the admin page, now uses `sd_get_data()` and works.
  - The `show_if_custom` logic was not working for multiple conditions, now it does.
  - The `skip_if_custom` logic could error if a condition was `NULL` (fixed with `isTRUE()`).
  - In `sd_config()`, items were being assigned with the `<-` operator, causing them to be deleted when the thing being assigned was `NULL`. Now changed to `=`.

# surveydown 0.1.0

- Added `sd_display_value()` for displaying a question value based on the question `id`.
- Added `sd_copy_value()` for making a copy of a question value, which may be needed if you need to display something more than once since you can't make more than one object with the same `id`.
- Changed `sd_reactive_output()` to `sd_display_question()`.
- Changed how `sd_store_value()` works to avoid a global environment, and changed the arg name from `name` to `id`.
- Added `sd_add_admin()` function to react to admin_page condition, if set to true an 'Admin' page will be created for survey creators.
- Added `sd_admin_ui()` function to create the UI for the Admin page button.
- (extension) JS files removed from extension to R package. Now the extension only contains the `.lua` file and the css styles.

# surveydown 0.0.9

- Required questions are now moved to `sd_config()` as a separate `required_questions` argument, instead of being defined in `sd_question()`.
- Two new functions for supporting reactive questions: `sd_question_reactive()` and `sd_reactive_output()`.
- `sd_store_value()` function to store variables into the database. For example, `sd_store_value(respondentID, "respID")` will store the value of `respondentID` into a column named `"respID"`. If the name is not provided, the column will be named as its original variable name, in this case, `respondentID`.
- Enhanced robustness for progress bar. Now the progress bar will update based on user's input.
- Added a `timestamp` column in the beginning of the result dataframe.
- Now both Mac and PC will have no problem connecting with supabase.
- Updated all roxygen2 documentation texts.

# surveydown 0.0.8

- `sd_database()` function added with `pause` argument default to `FALSE`. If `pause = FALSE`, database will be properly connected; if `pause = TRUE`, a local CSV will be generated and survey results will be stored there.
- `sd_config()` function has `preview` removed due to `pause` in `sd_database`.
- For `pause = FALSE` (aka default), warning messages will be shown for missing or incorrect password, and will prompt the usage of `sd_set_password()`.
- Initiation of the `admin_page` argument in `config.R`.

# surveydown 0.0.7

- `sd_set_password()` function to set the supabase password as the survey environment variable. This function takes in a string, which should be your supabase password. We recommend you to only run it in the R Console so that your password does not appear in the `.qmd` file.
- (Continue) Upon running `sd_set_password()`, an `.Renviron` file will be created in your survey project root directory. In this file, `SUPABASE_PASSWORD=your_password` will be created, with `your_password` being whatever your input of `sd_set_password()`. Then, `.Renviron` will be added to your `.gitignore` file to avoid being pushed to GitHub.
- (Continue) If there is already an `.Renviron` file, `SUPABASE_PASSWORD=your_password` will be concatenated to the end. If there is already a definition of `SUPABASE_PASSWORD`, it will be overwritten. If there is no `.gitignore` file, it will be created. If there is already an `.Renviron` in `.gitignore`, it won't be duplicated.
- (Continue) All the above explanation means that you simply run `sd_set_password()` once to define supabase password for your survey project. It takes care of the rest of necessary operations, and you can rerun `sd_set_password()` to change the password, with the previous value safely overwritten.

# surveydown 0.0.6

- In `sd_database`, a `gssencmode` argument is added and set to "prefer" by default. In some cases, local deployment may fail due to network environments such as VPN settings. It can be solved by setting `gssencmode = "disable"` in the survey `qmd` file.
- Now the survey can be updated even AFTER its deployment. You may add, delete, or modify a question. The old question column and its time stamp, will stay where they were. The new question column and time stamp will be concatenated in the end of the table.
- (extension) Now the `example.qmd` survey has instructions for supabase configuration and shinyapps deployment.
- (extension) Now the `.gitignore` file has `.Renviron` included. This file will store supabase password and is essential for shinyapps deployment. Eliminating this file from pushing to GitHub will ensure that your password is only saved locally.

# surveydown 0.0.5

- `create_survey()` changed to `sd_create_survey()` for function name consistency.
- `sd_update_extension()` function to update the surveydown Quarto extension.
- `sd_check_versions()` function to check the version of both the R package and the Quarto extension. If any of them don't match with the latest version, there will be a suggestion to run the `sd_update_surveydown()` function.
- `sd_update_surveydown()` function to update both the R package and the Quarto extension.

# surveydown 0.0.4

- (extension) [Raleway Font](https://fonts.google.com/specimen/Raleway) is set as the default font of the survey pages. Can be overwritten in the YAML header with the `theme` command using the [bootswatch themes](https://bootswatch.com) or a custom `scss` file.
- (extension) Default page background is set as "#f2f6f9" (a light blue color). Can be overwritten in the YAML header with the `backgroundcolor`.
- (extension) Questions are now encapsulated in a container that distinguishes from the descriptive texts.
- (extension) Options of `mc_button` and `mu_multiple_buttons` types of questions are now centered.
- Now the `surveydown::create_survey()` function will download the whole extension repo, containing the extension, an example survey, and an RStudio project.

# surveydown 0.0.3

- Now `show_if` can be applied to multiple options of the same question, which allows users to have more than one option in a question that triggers the revealing of a hidden question.
- Now if the "required" question is hidden, it will not trigger the page warning of "not all questions are answered".
- (extension) Now users can have a page with the same name of its ID and its header, regardless of capitalization. For example, users can now have a page ID being "#educational", and its header being "#Educational". This sounds as it should be, but in previous versions, the page hiding logic will show bug if page ID is the same as page header.

# surveydown 0.0.2

- Support added for the `required` argument in `sd_question()`, which allows users to force a question to be required. If not answered, a popup window blocks the user from continuing to the next page.
- The supabase backend is now connected and documentation on how to set up the database is complete.
- Initial setup for tests added

# surveydown 0.0.1

Initial version!
