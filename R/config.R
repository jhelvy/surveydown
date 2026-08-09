# MC type names that support option randomization
MC_TYPE_NAMES <- c("mc", "mc_buttons", "mc_multiple", "mc_multiple_buttons")

# Parse a single index specification (e.g., "1-5" or 3)
# Returns an integer vector of indices
parse_single_index_spec <- function(spec) {
  if (is.numeric(spec)) {
    return(as.integer(spec))
  }
  spec <- as.character(spec)
  # Check if it's a range like "1-5"
  if (grepl("^\\d+-\\d+$", spec)) {
    parts <- strsplit(spec, "-")[[1]]
    start <- as.integer(parts[1])
    end <- as.integer(parts[2])
    return(seq(start, end))
  }
  # Otherwise try to parse as integer
  as.integer(spec)
}

# Parse shuffle indices from YAML value
# Input can be: NULL, integer, string "1-5", vector [1,2,4], or mixed ["1-5", 8]
# Returns: integer vector of 1-based indices, or NULL (meaning shuffle all)
parse_shuffle_indices <- function(value) {
  if (is.null(value)) {
    return(NULL) # NULL means shuffle all
  }

  # Handle single values
  if (length(value) == 1 && !is.list(value)) {
    return(parse_single_index_spec(value))
  }

  # Handle vectors/lists
  indices <- unlist(lapply(value, parse_single_index_spec))
  sort(unique(indices))
}

# Parse the shuffled YAML structure into a named list
# Input formats supported:
#   - question_id (no indices = shuffle all)
#   - question_id: 1-5 (range)
#   - question_id: [1, 2, 4] (specific indices)
#   - question_id: [1-5, 8-10] (mixed ranges)
# Returns: named list where names are question IDs and values are index vectors or NULL
parse_shuffled_yaml <- function(shuffled_raw) {
  if (is.null(shuffled_raw)) {
    return(NULL)
  }

  result <- list()

  for (item in shuffled_raw) {
    if (is.list(item) && length(item) == 1) {
      # Format: - question_id: indices
      q_id <- names(item)[1]
      indices <- parse_shuffle_indices(item[[1]])
      result[[q_id]] <- indices
    } else if (is.character(item) && length(item) == 1) {
      # Format: - question_id (no indices, shuffle all)
      # Use list(NULL) to actually store NULL (direct assignment removes the element)
      result[item] <- list(NULL)
    }
  }

  result
}

# Check if a question is an MC-type question (supports option randomization)
is_mc_type_question <- function(question) {
  type <- question$type
  if (is.null(type) || length(type) == 0) {
    return(FALSE)
  }
  if (isTRUE(question$is_matrix)) {
    return(FALSE)
  }

  # Check for simple type names or CSS class patterns
  type %in%
    MC_TYPE_NAMES ||
    grepl("radio", type, ignore.case = TRUE) ||
    grepl("checkbox", type, ignore.case = TRUE)
}

# Get IDs of all MC-type questions from question structure
get_mc_question_ids <- function(question_structure) {
  names(which(sapply(question_structure, is_mc_type_question)))
}

# Load shuffled settings from YAML if not provided
load_shuffled_settings <- function(shuffled, all_shuffled) {
  if (!is.null(shuffled) || all_shuffled) {
    return(list(
      shuffled = shuffled,
      all_shuffled = all_shuffled
    ))
  }

  settings <- read_settings_yaml()
  list(
    shuffled = settings$`shuffled`,
    all_shuffled = isTRUE(settings$`all-shuffled`)
  )
}

# Get IDs of all matrix-type questions from question structure
get_matrix_question_ids <- function(question_structure) {
  names(which(sapply(question_structure, function(q) isTRUE(q$is_matrix))))
}

# Determine which questions should be shuffled
# For MC-type questions: shuffles options
# For Matrix-type questions: shuffles rows (sub-questions)
# Returns: named list where names are question IDs and values are:
#   - NULL: shuffle all options/rows
#   - integer vector: only shuffle these 1-based indices
determine_shuffled_questions <- function(
  question_structure,
  shuffled,
  all_shuffled,
  warn_invalid = FALSE
) {
  mc_question_ids <- get_mc_question_ids(question_structure)
  matrix_question_ids <- get_matrix_question_ids(question_structure)
  valid_question_ids <- c(mc_question_ids, matrix_question_ids)

  # If all_shuffled, return named list with NULL values (shuffle all) for all valid questions

  if (all_shuffled) {
    result <- stats::setNames(
      replicate(length(valid_question_ids), NULL, simplify = FALSE),
      valid_question_ids
    )
    return(result)
  }

  if (is.null(shuffled) || length(shuffled) == 0) {
    return(list()) # Return empty list instead of character(0)
  }

  # Parse the shuffled YAML structure
  parsed_shuffled <- parse_shuffled_yaml(shuffled)

  if (is.null(parsed_shuffled) || length(parsed_shuffled) == 0) {
    return(list())
  }

  # Get question IDs from the parsed structure
  shuffled_ids <- names(parsed_shuffled)

  # Warn about invalid questions if requested
  if (warn_invalid) {
    invalid <- setdiff(shuffled_ids, valid_question_ids)
    if (length(invalid) > 0) {
      warning(
        "The following questions in shuffled are not MC-type or matrix questions and will be skipped: ",
        paste(invalid, collapse = ", ")
      )
    }
  }

  # Filter to only valid questions
  valid_shuffled_ids <- intersect(shuffled_ids, valid_question_ids)

  # Return named list with only valid questions
  parsed_shuffled[valid_shuffled_ids]
}

run_config <- function() {
  # Get skip_if and show_if from session userData (set before sd_server() is called)
  skip_if <- shiny::getDefaultReactiveDomain()$userData$skip_if
  show_if <- shiny::getDefaultReactiveDomain()$userData$show_if

  # Read all settings from _survey/settings.yml
  settings <- read_settings_yaml()
  required_questions <- settings$`required`
  all_required <- isTRUE(settings$`all-required`)
  start_page <- settings$`start-page`
  rate_survey <- isTRUE(settings$`rate-survey`)
  system_language <- settings$`system-language`
  shuffled <- settings$`shuffled`
  all_shuffled <- isTRUE(settings$`all-shuffled`)

  if (rate_survey) {
    check_sd_close()
  }

  paths <- get_paths()

  if (survey_files_need_updating(paths)) {
    message("Changes detected...re-parsing survey contents...")

    html_content <- rvest::read_html(paths$target_html)
    question_structure <- get_question_structure(paths, html_content)

    # Load shuffled settings from YAML if not provided
    shuffled_settings <- load_shuffled_settings(shuffled, all_shuffled)
    shuffled <- shuffled_settings$shuffled
    all_shuffled <- shuffled_settings$all_shuffled

    # Determine which questions should be shuffled (warn on fresh parse)
    question_shuffled <- determine_shuffled_questions(
      question_structure,
      shuffled,
      all_shuffled,
      warn_invalid = TRUE
    )

    pages <- extract_html_pages(
      paths,
      html_content,
      required_questions,
      all_required,
      show_if,
      question_shuffled,
      question_structure
    )

    message(
      "Survey content saved to:\n",
      "  ",
      paths$target_html,
      "\n",
      "  ",
      paths$target_head,
      "\n",
      "  ",
      paths$target_pages,
      "\n",
      "  ",
      paths$target_questions,
      "\n",
      "  ",
      paths$target_settings
    )
  } else {
    message('No changes detected. Importing contents from "_survey" folder.')

    pages <- readRDS(paths$target_pages)
    question_structure <- load_question_structure_yaml(paths$target_questions)

    # Load shuffled settings from YAML if not provided
    shuffled_settings <- load_shuffled_settings(shuffled, all_shuffled)
    shuffled <- shuffled_settings$shuffled
    all_shuffled <- shuffled_settings$all_shuffled

    # Determine which questions should be shuffled
    question_shuffled <- determine_shuffled_questions(
      question_structure,
      shuffled,
      all_shuffled
    )
  }

  # Get page and question IDs
  page_ids <- sapply(pages, function(p) p$id)
  question_ids <- names(question_structure)

  # Check for duplicate, overlapping, or pre-defined IDs
  check_ids(page_ids, question_ids)

  # Determine required questions, excluding matrix question IDs
  if (all_required) {
    matrix_question_ids <- names(which(sapply(
      question_structure,
      `[[`,
      "is_matrix"
    )))
    question_required <- setdiff(question_ids, matrix_question_ids)
  } else {
    question_required <- required_questions
  }

  # Check that start_page (if used) points to an actual page
  if (!is.null(start_page) && !(start_page %in% page_ids)) {
    stop(
      "The specified start_page does not exist - check that you have not mis-spelled the id"
    )
  }

  # Set the start page
  if (is.null(start_page)) {
    start_page <- page_ids[1]
  }

  # Check skip_if and show_if inputs
  question_values <- unname(unlist(lapply(question_structure, `[[`, "options")))
  check_skip_show(
    question_ids,
    question_values,
    page_ids,
    skip_if,
    show_if
  )

  # Store all config settings
  config <- list(
    pages = pages,
    page_ids = page_ids,
    question_ids = question_ids,
    question_required = question_required,
    start_page = start_page,
    question_structure = question_structure,
    question_shuffled = question_shuffled
  )
  return(config)
}

check_sd_close <- function() {
  # Read the content of survey.qmd
  qmd_content <- readLines('survey.qmd', warn = FALSE)

  # Check for sd_close() call with any parameters
  sd_close_present <- any(grepl("sd_close\\s*\\(.*\\)", qmd_content))

  if (!sd_close_present) {
    warning(
      "\u274C No sd_close() function found in 'survey.qmd' file. You must use sd_close() to trigger the rating question response at the end of the survey. You can also remove this rating question by setting 'rate_survey = FALSE' in sd_server()."
    )
  }
}

get_paths <- function() {
  target_folder <- "_survey"
  if (!fs::dir_exists(target_folder)) {
    fs::dir_create(target_folder)
  }
  paths <- list(
    qmd = "survey.qmd",
    app = "app.R",
    root_html = "survey.html",
    msg = "messages.yml", # User-provided custom messages (root folder)
    target_html = file.path(target_folder, "survey.html"),
    target_pages = file.path(target_folder, "pages.rds"),
    target_head = file.path(target_folder, "head.rds"),
    target_questions = file.path(target_folder, "questions.yml"),
    target_settings = file.path(target_folder, "settings.yml") # Contains merged messages
  )
  return(paths)
}

survey_files_need_updating <- function(paths) {
  # Re-parse if any of the target files are missing
  targets <- c(
    paths$target_pages,
    paths$target_questions,
    paths$target_settings
  )
  if (any(!fs::file_exists(targets))) {
    return(TRUE)
  }

  # Re-parse if the target pages file is out of date with 'survey.qmd', 'app.R',
  # or 'settings.yml' (which contains system-messages used for nav button labels)
  time_qmd <- file.info(paths$qmd)$mtime
  time_app <- file.info(paths$app)$mtime
  time_settings <- file.info(paths$target_settings)$mtime
  time_pages <- file.info(paths$target_pages)$mtime

  if ((time_qmd > time_pages) || (time_app > time_pages) ||
      (time_settings > time_pages)) {
    return(TRUE)
  }

  # Find all YAML files
  # find_all_yaml_files() defined in ui.R
  yaml_files <- find_all_yaml_files()

  # Check if any YAML file is newer than the parsed pages
  for (yaml_file in yaml_files) {
    if (fs::file_exists(yaml_file)) {
      time_yml <- file.info(yaml_file)$mtime
      if (time_yml > time_pages) {
        return(TRUE)
      }
    }
  }

  # Re-parse if the user provided a 'messages.yml' file which is out of date
  if (fs::file_exists(paths$msg)) {
    time_msg <- file.info(paths$msg)$mtime
    if (time_msg > time_pages) {
      return(TRUE)
    }
  }

  return(FALSE)
}

set_messages <- function(paths, language, metadata = NULL) {
  # Load default messages
  messages <- get_messages_default()

  # Check for valid language input (see https://shiny.posit.co/r/reference/shiny/1.7.0/dateinput)
  valid_languages <- get_valid_languages()

  # Fallback to English if not set or not supported (from shiny::dateInput())
  if (is.null(language) || !(language %in% valid_languages)) {
    message(
      "Invalid or unsupported language selected. Falling back to predefined English."
    )
    message(
      "Check https://shiny.posit.co/r/reference/shiny/1.7.0/dateinput for supported languages."
    )
    language <- "en"
  }

  # Include user provided messages if messages.yml file is in root
  if (fs::file_exists(paths$msg)) {
    # Read messages file and select messages for selected language
    tryCatch(
      {
        user_msg <- yaml::read_yaml(paths$msg)
        user_msg <- user_msg[unique(names(user_msg))]
        user_msg <- user_msg[names(user_msg) == language]

        # Check for valid set of messages for selected language
        if (length(user_msg) == 1) {
          message(
            "User provided messages for language '",
            language,
            "' from '",
            paths$msg,
            "' file loaded."
          )

          # Add missing texts from default messages (if not available, use English)
          if (language %in% names(messages)) {
            predef_msg <- messages[[language]]
          } else {
            predef_msg <- messages[["en"]]
          }
          user_msg[[1]] <- c(
            user_msg[[1]],
            predef_msg[!(names(predef_msg) %in% names(user_msg[[1]]))]
          )
        } else {
          user_msg <- NULL
        }
      },
      error = function(e) {
        message(
          "Error reading '",
          paths$msg,
          "' file. Please review and revise the file. Error details: ",
          e$message
        )
        user_msg <- NULL
      }
    )

    # Combine user provided messages with predefined messages
    messages <- c(user_msg, messages) # user provided take precedence
  }

  # Choose messages by chosen language
  if (!language %in% names(messages)) {
    # Fallback to English if no messages found for selected language
    sd_create_messages(language)
    messages <- messages["en"]
  } else {
    messages <- messages[names(messages) == language]
    messages <- messages[1]
  }

  # Restructure messages to use "system_message" as key instead of language code
  # Extract the message values (which are in a list under the language code)
  message_values <- messages[[1]]

  # Check for custom system-messages entries in YAML metadata (highest priority)
  if (!is.null(metadata)) {
    custom_messages <- get_yaml_value(metadata, "system-messages")
    if (!is.null(custom_messages)) {
      # Define valid kebab-case message keys
      valid_message_keys <- c(
        "cancel",
        "confirm-exit",
        "sure-exit",
        "submit-exit",
        "warning",
        "required",
        "rating-title",
        "rating-text",
        "rating-scale",
        "previous",
        "next",
        "exit",
        "close-tab",
        "choose-option",
        "click",
        "redirect",
        "seconds",
        "new-tab",
        "redirect-error"
      )

      # Merge custom messages with default messages (only valid kebab-case keys)
      # Custom entries override defaults
      valid_count <- 0
      for (key in names(custom_messages)) {
        if (key %in% valid_message_keys) {
          message_values[[key]] <- custom_messages[[key]]
          valid_count <- valid_count + 1
        } else {
          warning(
            "Invalid message key '",
            key,
            "' ignored. ",
            "Only kebab-case keys are supported. ",
            "Did you mean '",
            gsub("_", "-", key),
            "'?"
          )
        }
      }
      if (valid_count > 0) {
        message(
          "Custom system-messages entries found in YAML header. ",
          valid_count,
          " custom message(s) applied."
        )
      }
    }
  }

  # Create new structure with "system-messages" as the key (kebab-case)
  messages_restructured <- list(`system-messages` = message_values)

  # Return messages (will be written to settings.yml)
  return(list(
    language = language,
    messages = messages_restructured
  ))
}

# Helper function to clean up YAML apostrophes
# Converts: 'won''t' -> "won't" for better readability
clean_yaml_quotes <- function(yaml_string) {
  # Split into lines for easier processing
  lines <- strsplit(yaml_string, "\n")[[1]]

  # Process each line
  for (i in seq_along(lines)) {
    line <- lines[i]

    # Check if line contains single-quoted string with escaped apostrophes
    if (grepl("'[^']*''[^']*'", line)) {
      # Find all matches
      pattern <- "'([^']*(?:''[^']*)*)'"
      matches <- gregexpr(pattern, line, perl = TRUE)

      if (matches[[1]][1] != -1) {
        # Extract all matched strings
        match_text <- regmatches(line, matches)[[1]]

        # Process each match
        for (match in match_text) {
          # Only process if it contains ''
          if (grepl("''", match)) {
            # Remove outer quotes
            content <- substring(match, 2, nchar(match) - 1)
            # Replace '' with '
            content <- gsub("''", "'", content, fixed = TRUE)
            # Create double-quoted version
            replacement <- paste0('"', content, '"')
            # Replace in line
            line <- sub(match, replacement, line, fixed = TRUE)
          }
        }

        lines[i] <- line
      }
    }
  }

  # Rejoin lines
  return(paste(lines, collapse = "\n"))
}

# Helper function to create sectioned YAML output with organized comments
create_sectioned_yaml <- function(
  settings,
  general_params,
  theme_params,
  survey_params,
  messages = NULL
) {
  # Build YAML string with sections
  yaml_string <- ""

  # General Settings section (may be NULL if not using)
  if (!is.null(general_params) && length(general_params) > 0) {
    yaml_string <- paste0(yaml_string, "# General Settings (Quarto-defined)\n")
    # Build list explicitly to preserve names for NULL values
    general_settings <- list()
    for (param in general_params) {
      general_settings[[param]] <- settings[[param]]
      # Convert NULL to NA_character_ to preserve names in YAML output
      if (is.null(general_settings[[param]])) {
        general_settings[[param]] <- NA_character_
      }
    }
    yaml_string <- paste0(yaml_string, yaml::as.yaml(general_settings))
  }

  # Theme Settings section - nested under theme-settings (kebab-case)
  if (!is.null(theme_params) && length(theme_params) > 0) {
    if (yaml_string != "") {
      yaml_string <- paste0(yaml_string, "\n")
    }
    # Build list explicitly to preserve names for NULL values
    theme_settings <- list()
    for (param in theme_params) {
      theme_settings[[param]] <- settings[[param]]
      # Convert NULL to NA_character_ to preserve names in YAML output
      if (is.null(theme_settings[[param]])) {
        theme_settings[[param]] <- NA_character_
      }
    }
    # Nest under theme-settings key (kebab-case)
    theme_nested <- list(`theme-settings` = theme_settings)
    yaml_string <- paste0(yaml_string, yaml::as.yaml(theme_nested))
  }

  # Survey Settings section - nested under survey-settings (kebab-case)
  if (!is.null(survey_params) && length(survey_params) > 0) {
    if (yaml_string != "") {
      yaml_string <- paste0(yaml_string, "\n")
    }
    # Build list explicitly to preserve names for NULL values
    survey_settings <- list()
    for (param in survey_params) {
      survey_settings[[param]] <- settings[[param]]
      # Convert NULL to NA_character_ to preserve names in YAML output
      if (is.null(survey_settings[[param]])) {
        survey_settings[[param]] <- NA_character_
      }
    }
    # Nest under survey-settings key (kebab-case)
    survey_nested <- list(`survey-settings` = survey_settings)
    yaml_string <- paste0(yaml_string, yaml::as.yaml(survey_nested))
  }

  # System Messages section
  if (!is.null(messages)) {
    if (yaml_string != "") {
      yaml_string <- paste0(yaml_string, "\n")
    }
    yaml_string <- paste0(yaml_string, yaml::as.yaml(messages))
  }

  # Clean up awkward YAML apostrophe escaping (won''t -> "won't")
  yaml_string <- clean_yaml_quotes(yaml_string)

  # Convert .na.character to standard YAML null (~)
  yaml_string <- gsub(": \\.na\\.character", ": ~", yaml_string)

  return(yaml_string)
}

create_settings_yaml <- function(paths, metadata) {
  # Extract server configuration from survey.qmd YAML metadata during UI rendering
  # All settings come from the YAML header only - no sd_server() parameter overrides
  if (file.exists("survey.qmd")) {
    tryCatch(
      {
        # Get system language for messages from YAML header
        system_language <- get_system_language(metadata)
        if (is.null(system_language)) {
          system_language <- "en"
        }

        # Get messages for the selected language (pass metadata for custom overrides)
        msg_result <- set_messages(paths, system_language, metadata)

        # Define parameter categories (kebab-case only)
        # Note: format, echo, warning are now implicit via render_survey_qmd()
        theme_params <- c(
          "theme",
          "barposition",
          "barcolor",
          "footer-left",
          "footer-center",
          "footer-right"
        )
        survey_params <- c(
          "mode",
          "show-previous",
          "use-cookies",
          "auto-scroll",
          "rate-survey",
          "all-required",
          "start-page",
          "system-language",
          "highlight-unanswered",
          "highlight-color",
          "capture-metadata",
          "required",
          "shuffled",
          "all-shuffled"
        )

        # Combine all parameters
        all_params <- c(theme_params, survey_params)

        # Define defaults for all parameters (kebab-case keys)
        default_settings <- list(
          # Theme Settings
          theme = "default",
          barposition = "top",
          barcolor = NULL,
          `footer-left` = "",
          `footer-center` = "",
          `footer-right` = "",
          # Survey Settings
          mode = "database",
          `show-previous` = FALSE,
          `use-cookies` = TRUE,
          `auto-scroll` = FALSE,
          `rate-survey` = FALSE,
          `all-required` = FALSE,
          `start-page` = NULL,
          `system-language` = "en",
          `highlight-unanswered` = TRUE,
          `highlight-color` = "gray",
          `capture-metadata` = TRUE,
          `required` = NULL,
          `shuffled` = NULL,
          `all-shuffled` = FALSE
        )

        # Extract YAML values using helper functions (priority: YAML > defaults)
        settings <- list()
        for (param in all_params) {
          # Use specific extraction functions for parameters that need special handling
          if (param == "theme") {
            value <- get_theme(metadata)
          } else if (param == "barposition") {
            value <- get_barposition(metadata)
          } else if (param == "barcolor") {
            value <- get_barcolor(metadata)
          } else if (param == "footer-left") {
            value <- get_footer_left(metadata)
          } else if (param == "footer-center") {
            value <- get_footer_center(metadata)
          } else if (param == "footer-right") {
            value <- get_footer_right(metadata)
          } else if (param == "use-cookies") {
            value <- get_use_cookies(metadata)
          } else if (param == "auto-scroll") {
            value <- get_auto_scroll(metadata)
          } else if (param == "rate-survey") {
            value <- get_rate_survey(metadata)
          } else if (param == "all-required") {
            value <- get_all_required(metadata)
          } else if (param == "start-page") {
            value <- get_start_page(metadata)
          } else if (param == "system-language") {
            value <- get_system_language(metadata)
          } else if (param == "highlight-unanswered") {
            value <- get_highlight_unanswered(metadata)
          } else if (param == "highlight-color") {
            value <- get_highlight_color(metadata)
          } else if (param == "capture-metadata") {
            value <- get_capture_metadata(metadata)
          } else if (param == "required") {
            value <- get_required_questions(metadata)
          } else if (param == "shuffled") {
            value <- get_shuffled(metadata)
          } else if (param == "all-shuffled") {
            value <- get_all_shuffled(metadata)
          } else if (param == "show-previous") {
            value <- get_show_previous(metadata)
          } else if (param == "mode") {
            value <- get_mode(metadata)
          } else {
            value <- NULL
          }

          if (!is.null(value)) {
            settings[[param]] <- value
          } else {
            # Use default value
            settings[[param]] <- default_settings[[param]]
          }
        }

        # Warn about invalid snake_case keys in YAML (theme-settings, survey-settings)
        yaml_data <- metadata$formats$html$metadata
        if (!is.null(yaml_data)) {
          # Check for snake_case keys in theme-settings
          if (!is.null(yaml_data$`theme-settings`)) {
            for (key in names(yaml_data$`theme-settings`)) {
              if (grepl("_", key)) {
                warning(
                  "Invalid key '",
                  key,
                  "' in theme-settings ignored. ",
                  "Only kebab-case keys are supported. ",
                  "Did you mean '",
                  gsub("_", "-", key),
                  "'?"
                )
              }
            }
          }
          # Check for snake_case keys in survey-settings
          if (!is.null(yaml_data$`survey-settings`)) {
            for (key in names(yaml_data$`survey-settings`)) {
              if (grepl("_", key)) {
                warning(
                  "Invalid key '",
                  key,
                  "' in survey-settings ignored. ",
                  "Only kebab-case keys are supported. ",
                  "Did you mean '",
                  gsub("_", "-", key),
                  "'?"
                )
              }
            }
          }
        }

        # Write settings file with sectioned YAML (includes messages)
        yaml_content <- create_sectioned_yaml(
          settings,
          NULL,
          theme_params,
          survey_params,
          msg_result$messages
        )
        comment_line1 <- "# ! JUST READ - don't change the content of this file\n"
        comment_line2 <- "# All survey configuration settings with final resolved values\n\n"
        full_content <- paste0(comment_line1, comment_line2, yaml_content)
        writeLines(full_content, con = paths$target_settings)
      },
      error = function(e) {
        warning("Could not extract settings from survey.qmd: ", e$message)
        # Create settings file with defaults on error (kebab-case only)
        theme_params <- c(
          "theme",
          "barposition",
          "barcolor",
          "footer-left",
          "footer-center",
          "footer-right"
        )
        survey_params <- c(
          "mode",
          "show-previous",
          "use-cookies",
          "auto-scroll",
          "rate-survey",
          "all-required",
          "start-page",
          "system-language",
          "highlight-unanswered",
          "highlight-color",
          "capture-metadata",
          "required",
          "shuffled",
          "all-shuffled"
        )
        default_settings <- list(
          theme = "default",
          barposition = "top",
          barcolor = NULL,
          `footer-left` = "",
          `footer-center` = "",
          `footer-right` = "",
          mode = "database",
          `show-previous` = FALSE,
          `use-cookies` = TRUE,
          `auto-scroll` = FALSE,
          `rate-survey` = FALSE,
          `all-required` = FALSE,
          `start-page` = NULL,
          `system-language` = "en",
          `highlight-unanswered` = TRUE,
          `highlight-color` = "gray",
          `capture-metadata` = TRUE,
          `required` = NULL,
          `shuffled` = NULL,
          `all-shuffled` = FALSE
        )
        # Get default English messages
        default_msg <- get_messages_default()
        yaml_content <- create_sectioned_yaml(
          default_settings,
          NULL,
          theme_params,
          survey_params,
          default_msg["en"]
        )
        comment_line1 <- "# ! JUST READ - don't change the content of this file\n"
        comment_line2 <- "# All survey configuration settings with defaults (error reading YAML header)\n"
        comment_line3 <- "# Note: format, echo, warning are implicit in render_survey_qmd()\n\n"
        full_content <- paste0(
          comment_line1,
          comment_line2,
          comment_line3,
          yaml_content
        )
        writeLines(full_content, con = paths$target_settings)
      }
    )
  } else {
    # Create settings file with defaults if survey.qmd doesn't exist (kebab-case only)
    theme_params <- c(
      "theme",
      "barposition",
      "barcolor",
      "footer-left",
      "footer-center",
      "footer-right"
    )
    survey_params <- c(
      "show-previous",
      "use-cookies",
      "auto-scroll",
      "rate-survey",
      "all-required",
      "start-page",
      "system-language",
      "highlight-unanswered",
      "highlight-color",
      "capture-metadata",
      "required",
      "shuffled",
      "all-shuffled"
    )
    default_settings <- list(
      theme = "default",
      barposition = "top",
      barcolor = NULL,
      `footer-left` = "",
      `footer-center` = "",
      `footer-right` = "",
      `show-previous` = FALSE,
      `use-cookies` = TRUE,
      `auto-scroll` = FALSE,
      `rate-survey` = FALSE,
      `all-required` = FALSE,
      `start-page` = NULL,
      `system-language` = "en",
      `highlight-unanswered` = TRUE,
      `highlight-color` = "gray",
      `capture-metadata` = TRUE,
      `required` = NULL,
      `shuffled` = NULL,
      `all-shuffled` = FALSE
    )
    # Get default English messages
    default_msg <- get_messages_default()
    yaml_content <- create_sectioned_yaml(
      default_settings,
      NULL,
      theme_params,
      survey_params,
      default_msg["en"]
    )
    comment_line1 <- "# ! JUST READ - don't change the content of this file\n"
    comment_line2 <- "# All survey configuration settings with defaults (no survey.qmd file found)\n"
    comment_line3 <- "# Note: format, echo, warning are implicit in render_survey_qmd()\n\n"
    full_content <- paste0(
      comment_line1,
      comment_line2,
      comment_line3,
      yaml_content
    )
    writeLines(full_content, con = paths$target_settings)
  }
}

# Function to read settings from _survey/settings.yml file (kebab-case only)
read_settings_yaml <- function() {
  paths <- get_paths()

  # Define default settings to return if reading fails (kebab-case)
  defaults <- list(
    # Theme Settings
    theme = "default",
    barposition = "top",
    barcolor = NULL,
    `footer-left` = "",
    `footer-center` = "",
    `footer-right` = "",
    # Survey Settings
    mode = "database",
    `use-cookies` = TRUE,
    `auto-scroll` = FALSE,
    `rate-survey` = FALSE,
    `all-required` = FALSE,
    `start-page` = NULL,
    `system-language` = "en",
    `highlight-unanswered` = TRUE,
    `highlight-color` = "gray",
    `capture-metadata` = TRUE,
    `required` = NULL,
    `shuffled` = NULL,
    `all-shuffled` = FALSE
  )

  # Try multiple possible locations for the settings file
  possible_paths <- c(
    paths$target_settings, # "_survey/settings.yml"
    file.path(getwd(), paths$target_settings), # Full path from current dir
    file.path(".", paths$target_settings), # Explicit relative path
    "settings.yml" # Fallback: just settings.yml in current dir
  )

  settings_raw <- NULL
  successful_path <- NULL

  # Try to read from each path directly (without file.exists check)
  for (path in possible_paths) {
    tryCatch(
      {
        settings_raw <- yaml::read_yaml(path)
        successful_path <- path
        break
      },
      error = function(e) {
        # Continue to next path
      }
    )
  }

  if (is.null(settings_raw)) {
    return(defaults)
  }

  # Flatten hierarchical structure: extract theme-settings and survey-settings (kebab-case)
  settings <- list()

  # Extract theme settings if nested (kebab-case section name)
  if (!is.null(settings_raw$`theme-settings`)) {
    for (key in names(settings_raw$`theme-settings`)) {
      settings[[key]] <- settings_raw$`theme-settings`[[key]]
    }
  }

  # Extract survey settings if nested (kebab-case section name)
  if (!is.null(settings_raw$`survey-settings`)) {
    for (key in names(settings_raw$`survey-settings`)) {
      settings[[key]] <- settings_raw$`survey-settings`[[key]]
    }
  }

  # Also check for flat structure (backward compatibility)
  # If theme-settings and survey-settings don't exist, use flat structure
  if (
    is.null(settings_raw$`theme-settings`) &&
      is.null(settings_raw$`survey-settings`)
  ) {
    settings <- settings_raw
  }

  # Process required if it exists (convert list to character vector)
  if (!is.null(settings$`required`)) {
    if (is.list(settings$`required`)) {
      settings$`required` <- unlist(settings$`required`)
    }
  }

  # Note: shuffled is kept as-is (not flattened) to preserve index specifications
  # It will be parsed by parse_shuffled_yaml() in determine_shuffled_questions()

  return(settings)
}

# Function to update settings.yml with final resolved parameters from sd_server()
# This ONLY updates Survey Settings, preserving Theme Settings from the YAML header
update_settings_yaml <- function(resolved_params) {
  paths <- get_paths()

  # Define parameter categories (kebab-case only)
  # Note: format, echo, warning are now implicit in render_survey_qmd()
  theme_params <- c(
    "theme",
    "barposition",
    "barcolor",
    "footer-left",
    "footer-center",
    "footer-right"
  )
  survey_params <- c(
    "show-previous",
    "use-cookies",
    "auto-scroll",
    "rate-survey",
    "all-required",
    "start-page",
    "system-language",
    "highlight-unanswered",
    "highlight-color",
    "capture-metadata",
    "required",
    "shuffled",
    "all-shuffled"
  )

  # Read existing settings to preserve Theme Settings
  existing_settings <- read_settings_yaml()

  # Define defaults for survey parameters only (kebab-case)
  survey_defaults <- list(
    `show-previous` = FALSE,
    `use-cookies` = TRUE, # Note: this becomes TRUE when NULL is passed to sd_server
    `auto-scroll` = FALSE,
    `rate-survey` = FALSE,
    `all-required` = FALSE,
    `start-page` = NULL,
    `system-language` = "en",
    `highlight-unanswered` = TRUE,
    `highlight-color` = "gray",
    `capture-metadata` = TRUE,
    `required` = NULL,
    `shuffled` = NULL,
    `all-shuffled` = FALSE
  )

  # Filter out language parameter to avoid breaking Quarto
  resolved_params$language <- NULL

  # Build final settings: preserve theme settings, update survey settings
  final_settings <- list()

  # Preserve theme settings from existing settings.yml (set by create_settings_yaml)
  for (param in theme_params) {
    if (!is.null(existing_settings[[param]])) {
      final_settings[[param]] <- existing_settings[[param]]
    }
  }

  # Update survey settings with resolved params
  # Map snake_case from resolved_params to kebab-case for storage
  param_mapping <- list(
    `show-previous` = "show_previous",
    `use-cookies` = "use_cookies",
    `auto-scroll` = "auto_scroll",
    `rate-survey` = "rate_survey",
    `all-required` = "all_required",
    `start-page` = "start_page",
    `system-language` = "system_language",
    `highlight-unanswered` = "highlight_unanswered",
    `highlight-color` = "highlight_color",
    `capture-metadata` = "capture_metadata",
    `required` = "required_questions",
    `shuffled` = "shuffled",
    `all-shuffled` = "all_shuffled"
  )

  for (param in survey_params) {
    # Get the snake_case version of the parameter name for resolved_params lookup
    snake_param <- param_mapping[[param]]

    if (!is.null(snake_param) && !is.null(resolved_params[[snake_param]])) {
      final_settings[[param]] <- resolved_params[[snake_param]]
    } else {
      # Use default if not in resolved_params
      final_settings[[param]] <- survey_defaults[[param]]
    }
  }

  # Handle special case for use-cookies (NULL becomes TRUE)
  if (is.null(final_settings$`use-cookies`)) {
    final_settings$`use-cookies` <- TRUE
  }

  # Read existing messages from settings.yml to preserve them
  existing_msg <- NULL
  if (fs::file_exists(paths$target_settings)) {
    tryCatch(
      {
        full_settings <- yaml::read_yaml(paths$target_settings)
        # Look for the system-messages key (kebab-case) or old keys for backward compatibility
        if (!is.null(full_settings$`system-messages`)) {
          # New structure with system-messages (kebab-case)
          existing_msg <- list(
            `system-messages` = full_settings$`system-messages`
          )
        } else if (!is.null(full_settings$system_messages)) {
          # Old structure with system_messages (snake_case) - convert to kebab
          existing_msg <- list(
            `system-messages` = full_settings$system_messages
          )
        } else if (!is.null(full_settings$system_message)) {
          # Old structure with system_message (singular) - convert to kebab
          existing_msg <- list(`system-messages` = full_settings$system_message)
        } else {
          # Older structure - look for language keys for backward compatibility
          for (lang in c("en", "de", "es", "fr", "it", "zh-CN")) {
            if (!is.null(full_settings[[lang]])) {
              # Convert old structure to new structure
              existing_msg <- list(`system-messages` = full_settings[[lang]])
              break
            }
          }
        }
      },
      error = function(e) {
        # If reading fails, continue without messages
      }
    )
  }

  # If no existing messages found, use default English with system-messages key
  if (is.null(existing_msg)) {
    default_msg <- get_messages_default()["en"]
    existing_msg <- list(`system-messages` = default_msg[[1]])
  }

  # Create YAML content with sections (including messages)
  yaml_content <- create_sectioned_yaml(
    final_settings,
    NULL,
    theme_params,
    survey_params,
    existing_msg
  )
  comment_line1 <- "# ! JUST READ - don't change the content of this file\n"
  comment_line2 <- "# All survey configuration settings with final resolved values\n\n"
  full_content <- paste0(
    comment_line1,
    comment_line2,
    yaml_content
  )

  # Write to file
  writeLines(full_content, con = paths$target_settings)
}

extract_html_pages <- function(
  paths,
  html_content,
  required_questions,
  all_required,
  show_if,
  question_shuffled = list(),
  question_structure = NULL
) {
  # Check for both sd-page and sd_page classes
  pages_dash <- html_content |> rvest::html_elements(".sd-page")
  pages_underscore <- html_content |> rvest::html_elements(".sd_page")

  # Check if mixing of classes exists
  if (length(pages_dash) > 0 && length(pages_underscore) > 0) {
    stop("Mixed use of '.sd-page' and '.sd_page'. Please use only one style.")
  }

  # Use whichever page style is found
  if (length(pages_dash) > 0) {
    pages_elements <- pages_dash
    class_used <- ".sd-page"
  } else if (length(pages_underscore) > 0) {
    pages_elements <- pages_underscore
    class_used <- ".sd_page"
  } else {
    stop(
      "No survey pages found. Add divs with either '.sd-page' or '.sd_page' class."
    )
  }

  # Get total number of pages to identify the last page
  total_pages <- length(pages_elements)

  pages <- lapply(seq_along(pages_elements), function(page_index) {
    x <- pages_elements[[page_index]]
    page_id <- rvest::html_attr(x, "id")
    question_containers <- rvest::html_elements(x, ".question-container")
    question_ids <- character(0)
    required_question_ids <- character(0)
    shuffled_question_ids <- character(0)

    for (i in seq_along(question_containers)) {
      container <- question_containers[[i]]
      question_id <- rvest::html_attr(container, "data-question-id")
      question_ids <- c(question_ids, question_id)

      # Check if it's a matrix question
      is_matrix <- length(rvest::html_elements(container, ".matrix-question")) >
        0

      # Determine if the question is required
      is_required <- if (is_matrix) {
        all_required || question_id %in% required_questions
      } else if (all_required) {
        TRUE
      } else {
        question_id %in% required_questions
      }

      # Track required questions and display asterisk
      if (is_required) {
        if (is_matrix) {
          # Only show asterisks for subquestions, not the main matrix question
          sub_asterisks <- rvest::html_elements(
            container,
            ".matrix-question td .hidden-asterisk"
          )
          for (asterisk in sub_asterisks) {
            xml2::xml_attr(asterisk, "style") <- "display: inline;"
          }
        } else {
          asterisk <- rvest::html_element(container, ".hidden-asterisk")
          xml2::xml_attr(asterisk, "style") <- "display: inline;"
        }
        required_question_ids <- c(required_question_ids, question_id)
      }
      if (!is.null(show_if)) {
        if (question_id %in% show_if$targets) {
          current_style <- xml2::xml_attr(container, "style")
          new_style <- paste(current_style, "display: none;", sep = " ")
          xml2::xml_attr(container, "style") <- new_style
        }
      }

      # Check if this question needs shuffling
      # For MC questions: shuffled options (replace with placeholder)
      # For matrix questions: shuffled rows via JavaScript (keep original HTML)
      if (question_id %in% names(question_shuffled)) {
        if (is_matrix) {
          # For matrix questions, just mark for JS-based row shuffling
          # Keep the original HTML intact to preserve Quarto styling
          xml2::xml_attr(container, "data-shuffled-matrix") <- "true"
          shuffled_question_ids <- c(shuffled_question_ids, question_id)
        } else {
          # For MC questions, add a placeholder for option shuffling
          placeholder_html <- sprintf(
            '<div id="%s_shuffled" class="sd-shuffled-placeholder" data-shuffled-type="mc"></div>',
            question_id
          )

          # Get all children of the container
          children <- xml2::xml_children(container)

          # Remove all children except the hidden-asterisk (if present)
          for (child in children) {
            child_class <- xml2::xml_attr(child, "class")
            if (is.na(child_class) || !grepl("hidden-asterisk", child_class)) {
              xml2::xml_remove(child)
            }
          }

          # Add the uiOutput placeholder as the first child (before any asterisk)
          placeholder_node <- xml2::read_html(placeholder_html) |>
            rvest::html_element("body > div")
          xml2::xml_add_child(container, placeholder_node, .where = 0)

          # Track this as a shuffled question
          shuffled_question_ids <- c(shuffled_question_ids, question_id)
        }
      }

      question_containers[[i]] <- container
    }

    # Update the 'Next' button ID and extract the next_page_id
    next_button_id <- make_next_button_id(page_id)
    next_button <- rvest::html_element(x, "#page_id_next")
    if (is.na(next_button)) {
      # No next button on this page
      next_page_id <- NULL
    } else {
      xml2::xml_attr(next_button, "id") <- next_button_id
      next_page_id <- rvest::html_attr(
        xml2::xml_parent(next_button),
        "data-next-page"
      )
    }

    # Update the 'Previous' button ID (if present)
    prev_button_id <- make_prev_button_id(page_id)
    prev_button <- rvest::html_element(x, "#page_id_prev")
    has_prev_button <- !is.na(prev_button)

    if (has_prev_button) {
      xml2::xml_attr(prev_button, "id") <- prev_button_id
    } else {
      prev_button_id <- NULL
    }

    # AUTO-NAVIGATION: Check if we need to auto-insert sd_nav()
    # Only auto-insert if:
    # 1. This is NOT the last page
    # 2. No explicit sd_nav() or sd_close() button exists
    is_last_page <- (page_index == total_pages)

    # Check for sd_close() button (id="close-survey-button")
    has_close_button <- !is.na(rvest::html_element(x, "#close-survey-button"))

    # Check for sd_nav(show_buttons = FALSE) marker
    has_nav_marker <- !is.na(rvest::html_element(x, "#sd-nav-marker"))

    # Check if explicit navigation already exists
    has_explicit_nav <- !is.na(next_button) ||
      has_close_button ||
      has_nav_marker

    # Auto-insert navigation if conditions are met
    if (!is_last_page && !has_explicit_nav) {
      # Get settings including show_previous and translated messages
      settings_path <- file.path("_survey", "settings.yml")
      show_prev <- FALSE # Default
      messages <- list("previous" = "Previous", "next" = "Next") # Default

      if (file.exists(settings_path)) {
        tryCatch(
          {
            settings_yaml <- yaml::read_yaml(settings_path)

            # Get show-previous setting from survey-settings (kebab-case)
            if (!is.null(settings_yaml$`survey-settings`$`show-previous`)) {
              show_prev <- settings_yaml$`survey-settings`$`show-previous`
            }

            # Get translated messages
            if (!is.null(settings_yaml$`system-messages`)) {
              messages <- settings_yaml$`system-messages`
            }
          },
          error = function(e) {
            # Use defaults on error
          }
        )
      }

      # IMPORTANT: Never show Previous button on the first page or on pages with sd_close()
      is_first_page <- (page_index == 1)
      if (is_first_page || has_close_button) {
        show_prev <- FALSE
      }

      prev_label <- paste0("\u2190 ", messages[['previous']]) # ← Previous
      next_label <- paste0(messages[['next']], " \u2192") # Next →

      # Create auto-generated sd_nav() HTML
      # This matches the exact output from sd_nav() in R/ui.R
      # Include Previous button only if show_previous setting is TRUE AND not first page
      if (show_prev) {
        auto_nav_html <- sprintf(
          '
<div data-next-page="" style="margin-top: 1rem; margin-bottom: 0.5rem;" class="sd-nav-container">
  <button class="btn btn-default action-button sd-nav-button sd-nav-prev" id="page_id_prev" onclick="Shiny.setInputValue(&#39;prev_page&#39;, true, {priority: &#39;event&#39;});" style="float: left;" type="button">%s</button>
  <button class="btn btn-default action-button sd-enter-button sd-nav-button sd-nav-next" id="page_id_next" onclick="Shiny.setInputValue(&#39;next_page&#39;, this.parentElement.getAttribute(&#39;data-next-page&#39;));" style="float: right;" type="button">%s</button>
  <div style="clear: both;"></div>
</div>
        ',
          prev_label,
          next_label
        )
      } else {
        # Only Next button (centered when no Previous button)
        auto_nav_html <- sprintf(
          '
<div data-next-page="" style="margin-top: 1rem; margin-bottom: 0.5rem;" class="sd-nav-container">
  <button class="btn btn-default action-button sd-enter-button sd-nav-button sd-nav-next" id="page_id_next" onclick="Shiny.setInputValue(&#39;next_page&#39;, this.parentElement.getAttribute(&#39;data-next-page&#39;));" style="display: block; margin: auto;" type="button">%s</button>
  <div style="clear: both;"></div>
</div>
        ',
          next_label
        )
      }

      # Parse the HTML and append to page
      auto_nav_node <- xml2::read_html(auto_nav_html) |>
        rvest::html_element("body > div")

      xml2::xml_add_child(x, auto_nav_node)

      # Update the Next button ID (always present)
      next_button_id <- make_next_button_id(page_id)
      next_button <- rvest::html_element(x, "#page_id_next")
      xml2::xml_attr(next_button, "id") <- next_button_id

      # Update the Previous button ID (only if show_prev is TRUE)
      if (show_prev) {
        prev_button_id <- make_prev_button_id(page_id)
        prev_button <- rvest::html_element(x, "#page_id_prev")
        xml2::xml_attr(prev_button, "id") <- prev_button_id
        has_prev_button <- TRUE
      } else {
        prev_button_id <- NULL
        has_prev_button <- FALSE
      }

      next_page_id <- "" # Auto-nav always has empty data-next-page (sequential)
    }

    list(
      id = page_id,
      questions = question_ids,
      required_questions = required_question_ids,
      shuffled_questions = shuffled_question_ids,
      next_button_id = next_button_id,
      next_page_id = next_page_id,
      prev_button_id = prev_button_id,
      content = as.character(x)
    )
  })
  saveRDS(pages, paths$target_pages)
  return(pages)
}

# Get question structure ('smart': load YAML or extract from HTML and save to YAML)
get_question_structure <- function(paths, html_content) {
  question_structure <- extract_question_structure_html(html_content)
  write_question_structure_yaml(question_structure, paths$target_questions)
  return(question_structure)
}

# Extract question structure from HTML
extract_question_structure_html <- function(html_content) {
  question_nodes <- rvest::html_nodes(html_content, "[data-question-id]")
  question_structure <- list()

  # Loop through all question nodes and extract information
  for (question_node in question_nodes) {
    question_id <- rvest::html_attr(question_node, "data-question-id")

    # Enhanced extraction that considers both class and tag name
    target_element <- question_node |>
      rvest::html_nodes(glue::glue("#{question_id}"))

    if (length(target_element) > 0) {
      tag_name <- rvest::html_name(target_element)
      class_attr <- rvest::html_attr(target_element, "class")

      # For textarea elements, ensure we get the right type even if class is incomplete
      if (
        tag_name == "textarea" &&
          (is.na(class_attr) || class_attr == "form-control")
      ) {
        type <- "shiny-input-textarea form-control"
      } else {
        type <- class_attr
      }
    } else {
      type <- question_node |>
        rvest::html_nodes(glue::glue("#{question_id}")) |>
        rvest::html_attr("class")
    }

    # Handle case where type is empty (e.g., for reactive questions)
    if (length(type) == 0 || is.na(type)) {
      type <- "unknown"
    }

    is_matrix <- length(rvest::html_nodes(question_node, ".matrix-question")) >
      0

    if (is_matrix) {
      type <- "matrix"
    }

    # Extract the question text (label) as plain text. This is what most
    # consumers display (e.g. the `<id>_label_question` text output).
    label <- question_node |>
      rvest::html_nodes("p") |>
      rvest::html_text(trim = TRUE)

    # Also capture the label paragraph(s) as inner HTML, preserving inline
    # markdown formatting (e.g. **bold** -> <strong>, italics, links). Option-
    # shuffled mc/mc_multiple questions are re-rendered from this structure on
    # the client, so without this their formatting would be lost (only plain
    # text survives `html_text()` above).
    label_nodes <- rvest::html_nodes(question_node, "p")
    label_html <- if (length(label_nodes) == 0) {
      label
    } else {
      inner_html <- vapply(
        seq_along(label_nodes),
        function(i) {
          paste(
            as.character(xml2::xml_contents(label_nodes[[i]])),
            collapse = ""
          )
        },
        character(1)
      )
      trimws(paste(inner_html, collapse = " "))
    }

    # Detect if this is a button-style question (mc_buttons or mc_multiple_buttons)
    # Button-style questions have .btn-group class in their container
    is_button_style <- length(rvest::html_nodes(question_node, ".btn-group")) >
      0

    # Write main information to the question structure
    question_structure[[question_id]] <- list(
      type = type,
      is_matrix = is_matrix,
      is_button_style = is_button_style,
      label = label,
      label_html = label_html
    )

    # Extract rows for matrix questions (sub-questions that will be shuffled)
    if (is_matrix) {
      # Extract row information from the matrix table
      # Each row is a tr element in the tbody, containing the row label and MC inputs
      matrix_rows <- question_node |>
        rvest::html_nodes(".matrix-question tbody tr")

      if (length(matrix_rows) > 0) {
        rows <- list()
        for (row_node in matrix_rows) {
          # Get the row label (first td)
          row_label <- row_node |>
            rvest::html_node("td:first-child") |>
            rvest::html_text(trim = TRUE)

          # Get the row ID from the input elements (extract sub-question ID)
          # Input IDs are in format: {matrix_id}_{row_id}
          input_node <- row_node |>
            rvest::html_node("input[type='radio'], input[type='checkbox']")
          if (!is.na(input_node)) {
            input_name <- rvest::html_attr(input_node, "name")
            # Extract row_id by removing the matrix_id prefix
            if (
              !is.null(input_name) &&
                grepl(paste0("^", question_id, "_"), input_name)
            ) {
              row_id <- sub(paste0("^", question_id, "_"), "", input_name)
              rows[[row_label]] <- row_id
            }
          }
        }
        question_structure[[question_id]]$row <- rows
      }
    }

    # Extract options for ranking questions. Ranking lists are hand-built markup,
    # so they carry none of the Shiny input classes the option
    # extraction below keys off.
    if(grepl("sd-ranking-list", type, fixed = TRUE)){
      item_nodes <- rvest::html_nodes(question_node, ".sd-ranking-item")
      if(length(item_nodes) > 0){
        options <- rvest::html_atr(item_nodes, "data-value")
        names(options) <- rvest::html_text(item_nodes, trim = TRUE)
        question_structure[[question_id]]$options <- as.list(options)
      }
    }

    # Extract options for the question ( mc, *_multiple, *_buttons, and select)
    if (length(type) > 0 && grepl("radio|checkbox|select|matrix", type)) {
      if (is_matrix) {
        # For matrix questions, extract options from the table header
        # Try multiple selectors to handle different HTML parsing behaviors
        header_cells <- question_node |>
          rvest::html_nodes(".matrix-question th")

        # Fallback: try selecting from thead if present
        if (length(header_cells) == 0) {
          header_cells <- question_node |>
            rvest::html_nodes(".matrix-question thead th")
        }

        # Another fallback: select all th descendants
        if (length(header_cells) == 0) {
          header_cells <- question_node |>
            rvest::html_nodes("table.matrix-question th")
        }

        if (length(header_cells) > 1) {
          # Skip the first th (empty cell for row labels)
          option_headers <- header_cells[-1]
          label_options <- rvest::html_text(option_headers, trim = TRUE)

          # Get option values from any radio inputs in the matrix
          # (all rows have the same options, so just get unique values)
          all_inputs <- question_node |>
            rvest::html_nodes(".matrix-question input[type='radio']")

          # Fallback selector
          if (length(all_inputs) == 0) {
            all_inputs <- question_node |>
              rvest::html_nodes("table.matrix-question input[type='radio']")
          }

          if (length(all_inputs) > 0) {
            all_values <- rvest::html_attr(all_inputs, "value")
            # Get unique values while preserving order
            options <- all_values[!duplicated(all_values)]
            # Make sure we have the same number of labels and options
            if (length(options) == length(label_options)) {
              names(options) <- label_options
            } else {
              # If mismatch, use values as names too
              names(options) <- options
            }
          } else {
            # Fallback: use labels as both names and values
            options <- label_options
            names(options) <- label_options
          }
        } else {
          options <- character(0)
        }
      } else {
        # For non-matrix MC questions
        options <- question_node |>
          rvest::html_nodes(
            "input[type='radio'], input[type='checkbox'], option"
          ) |>
          rvest::html_attr("value")
        label_nodes <- question_node |>
          rvest::html_nodes("label>span, button:not(.sd-attr-btn), option")
        label_options <- vapply(label_nodes, function(node) {
          inner <- rvest::html_nodes(node, ".sd-option-label")
          if (length(inner) > 0) return(rvest::html_text(inner[[1]], trim = TRUE))
          rvest::html_text(node, trim = TRUE)
        }, character(1))
        names(options) <- label_options

        # Handle empty names by setting them to their corresponding values
        empty_name_indices <- which(
          names(options) == "" | is.na(names(options))
        )
        if (length(empty_name_indices) > 0) {
          names(options)[empty_name_indices] <- options[empty_name_indices]
        }
      }

      # Write options to the question structure
      question_structure[[question_id]]$options <- as.list(options)

      # Extract options for the question (slider)
    } else if (grepl("slider", type)) {
      # Check if this is a numeric slider
      is_numeric_slider <- length(rvest::html_nodes(
        question_node,
        ".js-range-slider:not(.sw-slider-text)"
      )) >
        0

      if (is_numeric_slider) {
        # Extract min, max, and step attributes from the numeric slider
        slider_element <- rvest::html_nodes(question_node, ".js-range-slider")

        min_value <- as.numeric(rvest::html_attr(slider_element, "data-min"))
        max_value <- as.numeric(rvest::html_attr(slider_element, "data-max"))
        step_value <- as.numeric(rvest::html_attr(slider_element, "data-step"))

        # Check if this is a range slider (has data-to attribute)
        is_range <- !is.na(rvest::html_attr(slider_element, "data-to"))

        # Get the from and to values for range sliders
        from_value <- as.numeric(rvest::html_attr(slider_element, "data-from"))
        to_value <- as.numeric(rvest::html_attr(slider_element, "data-to"))

        # Default to step=1 if missing or invalid
        if (is.na(step_value) || step_value <= 0) {
          step_value <- 1
        }

        # Generate sequence
        numeric_values <- seq(min_value, max_value, by = step_value)

        # Create a named list with actual numeric values
        # Start with empty list to ensure the types are preserved
        named_options <- list()
        for (val in numeric_values) {
          named_options[[as.character(val)]] <- val
        }

        # Note that this is a range slider in the structure if needed
        if (is_range) {
          question_structure[[question_id]]$is_range <- TRUE
          # Also store the default range values
          question_structure[[question_id]]$default <- c(from_value, to_value)
        } else if (!is.na(from_value)) {
          # For single sliders, store the default value
          question_structure[[question_id]]$default <- from_value
        }

        question_structure[[question_id]]$options <- named_options
      } else {
        # For regular text slider
        options_labels_raw <- question_node |>
          rvest::html_nodes(".js-range-slider") |>
          rvest::html_attr("data-swvalues")

        # Process labels
        options_labels <- gsub("\\[|\\]|\\\"", "", options_labels_raw) |>
          strsplit(",") |>
          unlist()

        # Try to extract actual values from the script tag that sets data-values
        # Pattern: $("#question_id").attr("data-values", ["val1","val2",...]);
        scripts <- question_node |>
          rvest::html_nodes("script") |>
          rvest::html_text()

        options_values <- NULL
        for (script in scripts) {
          # Look for the data-values pattern (both old "#id input" and new "#id" formats)
          pattern <- paste0(
            '\\$\\("#',
            question_id,
            '(?: input)?"\\)\\.attr\\("data-values",\\s*\\[([^\\]]+)\\]\\)'
          )
          match <- regmatches(script, regexpr(pattern, script, perl = TRUE))
          if (length(match) > 0 && nchar(match) > 0) {
            # Extract the array content
            values_match <- regmatches(
              match,
              regexpr("\\[([^\\]]+)\\]", match, perl = TRUE)
            )
            if (length(values_match) > 0) {
              # Parse the JSON array
              options_values <- tryCatch(
                jsonlite::fromJSON(values_match),
                error = function(e) NULL
              )
              break
            }
          }
        }

        # Fallback to snake_case conversion if extraction failed
        if (
          is.null(options_values) ||
            length(options_values) != length(options_labels)
        ) {
          options_values <- sapply(options_labels, function(label) {
            # Convert to lowercase
            value <- tolower(label)
            # Replace spaces and special characters with underscore
            value <- gsub("[^a-z0-9]", "_", value)
            # Replace multiple underscores with a single one
            value <- gsub("_+", "_", value)
            # Remove leading and trailing underscores
            value <- gsub("^_|_$", "", value)
            return(value)
          })
        }

        # Create named options list
        options <- options_values
        names(options) <- options_labels

        question_structure[[question_id]]$options <- as.list(options)
      }
    }
  }
  return(question_structure)
}

# Write question structure to YAML
write_question_structure_yaml <- function(question_structure, file_yaml) {
  # Map question types to extracted html classes
  # Note: Order matters - more specific patterns should come first
  type_replacement <- c(
    'shiny-input-text form-control' = 'text',
    'shiny-input-textarea form-control' = 'textarea',
    'shiny-input-number form-control' = 'numeric',
    'form-group shiny-input-radiogroup shiny-input-container' = 'mc',
    'radio-group-buttons' = 'mc_buttons',
    'form-group shiny-input-checkboxgroup shiny-input-container' = 'mc_multiple',
    'checkbox-group-buttons' = 'mc_multiple_buttons',
    'shiny-input-select' = 'select',
    'js-range-slider sw-slider-text' = 'slider',
    'js-range-slider' = 'slider_numeric',
    'shiny-date-input form-group shiny-input-container' = 'date',
    'shiny-date-range-input form-group shiny-input-container' = 'daterange',
    'sd-ranking-list' = 'ranking',
  )

  # Add index to each question (1-based, for display order tracking)
  # Index is added first, then reordered to appear at the top of each entry
  question_ids <- names(question_structure)
  for (i in seq_along(question_ids)) {
    q <- question_structure[[question_ids[i]]]
    # Create new list with index first, then all other fields
    question_structure[[question_ids[i]]] <- c(list(index = i), q)
  }

  # Loop through question structure and clean/prepare questions
  question_structure <- lapply(question_structure, function(question) {
    # Rename type to function option names using pattern matching
    # This handles cases where HTML classes have additional classes beyond the expected ones
    matched_type <- NULL
    for (pattern in names(type_replacement)) {
      if (grepl(pattern, question$type, fixed = TRUE)) {
        matched_type <- type_replacement[[pattern]]
        break
      }
    }

    if (!is.null(matched_type)) {
      question$type <- matched_type
    } else if (question$is_matrix) {
      question$type <- "matrix"
    } else {
      question$type <- "unknown"
    }

    # Remove indicators (they are restored when loading from YAML based on type)
    question$is_matrix <- NULL
    question$is_button_style <- NULL

    # Remove first option from select type question
    if (question$type == "select") {
      question$options <- question$options[-1]
    }

    # Special handling for numeric slider options to ensure they remain numeric
    if (question$type == "slider_numeric" && !is.null(question$options)) {
      # Include all options
      options_to_include <- seq_along(question$options)

      # Create a new options list with all elements
      if (length(options_to_include) > 0) {
        question$options <- question$options[options_to_include]
      }
    }

    return(question)
  })

  # Remove NULL elements (matrix subquestions)
  question_structure <- Filter(Negate(is.null), question_structure)

  # Write question to YAML (with comment in first lines)
  yaml_content <- yaml::as.yaml(question_structure)
  comment_line1 <- "# ! JUST READ - don't change the content of this file\n"
  comment_line2 <- "# Question structure extracted from survey.html\n"
  full_content <- paste0(comment_line1, comment_line2, yaml_content)
  writeLines(full_content, con = file_yaml)
}

# Load question structure from YAML
load_question_structure_yaml <- function(file_yaml) {
  # Read question structure from YAML file
  question_structure <- yaml::read_yaml(file_yaml)

  # Add indicators to all questions (derived from type)
  question_structure <- lapply(question_structure, function(question) {
    question$is_matrix <- FALSE
    question$is_button_style <- question$type %in%
      c("mc_buttons", "mc_multiple_buttons")
    return(question)
  })

  # Get question types to create subquestions for matrix questions
  question_types <- sapply(question_structure, function(q) q$type)
  matrix_questions_ids <- names(question_types)[question_types == "matrix"]

  # Loop trough matrix questions and add subquestions
  for (matrix_question_id in matrix_questions_ids) {
    # Get matrix question and subquestion (rows option) from question list
    matrix_question <- question_structure[[matrix_question_id]]
    rows <- matrix_question$row
    parent_index <- matrix_question$index

    # Loop over subquestions and add to question structure (with label and options)
    for (row_number in seq_along(rows)) {
      subquestion_id <- paste0(matrix_question_id, "_", rows[[row_number]])
      subquestion_structure <- list(
        type = "mc",
        label = names(rows)[row_number],
        options = matrix_question$options,
        # Subquestion index: parent index + row position (e.g., 5.1, 5.2, 5.3)
        index = parent_index + (row_number - 1) / length(rows),
        parent_index = parent_index,
        row_index = row_number
      )
      question_structure[[subquestion_id]] <- subquestion_structure
    }

    # Add matrix question indicator
    question_structure[[matrix_question_id]]$is_matrix <- TRUE
  }

  # Negate NULL elements in is_matrix (matrix subquestions)
  for (question in names(question_structure)) {
    if (is.null(question_structure[[question]]$is_matrix)) {
      question_structure[[question]]$is_matrix <- FALSE
    }
  }
  return(question_structure)
}

get_output_ids <- function() {
  output <- shiny::getDefaultReactiveDomain()$output
  outs <- shiny::outputOptions(output)
  return(names(outs))
}

check_skip_show <- function(
  question_ids,
  question_values,
  page_ids,
  skip_if,
  show_if
) {
  if (!is.null(skip_if)) {
    invalid_skip_targets <- setdiff(skip_if$targets, page_ids)
    if (length(invalid_skip_targets) > 0) {
      stop(sprintf(
        "Invalid sd_skip_if targets: %s. These must be valid page IDs.",
        paste(invalid_skip_targets, collapse = ", ")
      ))
    }
  }

  if (!is.null(show_if)) {
    # Get any potential question_ids from the output
    # Now also include page_ids as valid targets
    invalid_show_targets <- setdiff(
      show_if$targets,
      c(question_ids, page_ids, get_output_ids())
    )
    if (length(invalid_show_targets) > 0) {
      stop(sprintf(
        "Invalid show_if targets: %s. These must be question IDs or page IDs defined in the survey.qmd file.",
        paste(invalid_show_targets, collapse = ", ")
      ))
    }
  }
  return(TRUE)
}

check_ids <- function(page_ids, question_ids) {
  # Check for duplicated IDs
  all_ids <- c(page_ids, question_ids)
  duplicate_ids <- all_ids[duplicated(all_ids)]
  if (length(duplicate_ids) > 0) {
    stop(
      "Duplicate IDs found: ",
      paste(duplicate_ids, collapse = ", "),
      ". All page IDs and question IDs must be unique."
    )
  }

  # Check for restricted IDs
  restricted_ids <- get_reserved_ids()
  used_restricted_ids <- intersect(restricted_ids, all_ids)
  if (length(used_restricted_ids) > 0) {
    stop(
      "Restricted IDs found: ",
      paste(used_restricted_ids, collapse = ", "),
      ". These IDs are reserved and should not be used for survey pages or questions."
    )
  }
}
