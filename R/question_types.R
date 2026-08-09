# Question type registry
#
# Each supported question type is defined here in one place with:
#   - render(a, ...): builds the question UI. `a` is the list of arguments
#     collected by sd_question() (id, label, option, messages, ...) and
#     `...` carries extra arguments through to the underlying widget.
#   - restore(session, id, value, info): re-applies a stored value to the
#     rendered input when navigating back to a page. `info` carries
#     `is_range` and `options`. NULL for types that need no restoration
#     (e.g. the matrix parent, whose rows are restored individually).
#   - requires_option: whether sd_question() must receive an `option`.
#
# Adding a new question type means adding one entry here (plus docs); the
# render dispatch in sd_question() and the page-restoration dispatch in
# sd_server() pick it up automatically.
#
# NOTE: the render and restore bodies are faithful extractions of the
# previous inline logic in sd_question() (R/ui.R) and the restoration loop
# in sd_server() (R/server.R); behavior is intended to be identical.

# -- Shared helpers ---------------------------------------------------------

# Split a stored multi-value string into its parts. Multi-value answers are
# stored pipe-joined (see format_question_value(), e.g. "red|blue"), so
# restoration splits on the pipe. A value that is already a vector, or a
# single value with no pipe, is returned unchanged.
split_stored_value <- function(value) {
  if (
    is.character(value) &&
      length(value) == 1 &&
      grepl("|", value, fixed = TRUE)
  ) {
    return(strsplit(value, "|", fixed = TRUE)[[1]])
  }
  value
}

# -- Renderers --------------------------------------------------------------

qt_render_select <- function(a, ...) {
  with(a, {
    label_select <- messages[['choose-option']]

    # Add blank option for visible selected option
    option <- c("", option)
    names(option)[1] <- label_select

    shiny::selectInput(
      inputId = id,
      label = label,
      choices = option,
      multiple = FALSE,
      selected = FALSE,
      ...
    )
  })
}

qt_render_mc <- function(a, ...) {
  with(a, {
    choices <- choice_list_html(option, option_attr)
    shiny::radioButtons(
      inputId = id,
      label = label,
      choiceNames = choices$names,
      choiceValues = choices$values,
      selected = FALSE,
      ...
    )
  })
}

qt_render_mc_multiple <- function(a, ...) {
  with(a, {
    choices <- choice_list_html(option, option_attr)
    shiny::checkboxGroupInput(
      inputId = id,
      label = label,
      choiceNames = choices$names,
      choiceValues = choices$values,
      selected = FALSE,
      ...
    )
  })
}

qt_render_mc_buttons <- function(a, ...) {
  with(a, {
    # Value reporting and interaction tracking are handled by delegated
    # handlers in interaction.js (keyed off the .radio-group-buttons class)
    shinyWidgets::radioGroupButtons(
      inputId = id,
      label = label,
      choices = choice_html(option),
      direction = direction,
      selected = character(0),
      ...
    )
  })
}

qt_render_mc_multiple_buttons <- function(a, ...) {
  with(a, {
    # Value reporting and interaction tracking are handled by delegated
    # handlers in interaction.js (keyed off the .checkbox-group-buttons class)
    shinyWidgets::checkboxGroupButtons(
      inputId = id,
      label = label,
      choices = choice_html(option),
      direction = direction,
      individual = individual,
      justified = FALSE,
      selected = character(0),
      ...
    )
  })
}

qt_render_mc_image <- function(a, ...) {
  with(a, {
    choices <- choice_image_html(option, image)
    output <- shiny::radioButtons(
      inputId = id,
      label = label,
      choiceNames = choices$names,
      choiceValues = choices$values,
      selected = FALSE,
      ...
    )
    # Wrapper class drives the card-grid layout (see surveydown.css)
    shiny::div(class = "sd-image-choice", output)
  })
}

qt_render_mc_multiple_image <- function(a, ...) {
  with(a, {
    choices <- choice_image_html(option, image)
    output <- shiny::checkboxGroupInput(
      inputId = id,
      label = label,
      choiceNames = choices$names,
      choiceValues = choices$values,
      selected = FALSE,
      ...
    )
    # Wrapper class drives the card-grid layout (see surveydown.css)
    shiny::div(class = "sd-image-choice", output)
  })
}

qt_render_text <- function(a, ...) {
  with(a, {
    shiny::textInput(
      inputId = id,
      label = label,
      placeholder = option,
      ...
    )
  })
}

qt_render_textarea <- function(a, ...) {
  with(a, {
    shiny::textAreaInput(
      inputId = id,
      label = label,
      height = "100px",
      cols = cols,
      value = NULL,
      rows = "6",
      placeholder = placeholder,
      resize = resize,
      ...
    )
  })
}

qt_render_numeric <- function(a, ...) {
  with(a, {
    output <- shiny::textInput(
      inputId = id,
      label = label,
      value = "",
      ...
    )

    # Mark the input so the delegated handlers in interaction.js apply
    # numeric validation, interaction tracking, and the spinner UI
    htmltools::tagQuery(output)$
      find("input")$
      addClass("sd-numeric")$
      allTags()
  })
}

qt_render_slider <- function(a, ...) {
  with(a, {
    # Extract display labels and values
    display_labels <- names(option)
    values <- unname(option)

    # Value to display mapping (for finding the display label from a selected value)
    value_to_label <- display_labels
    names(value_to_label) <- values

    # Create a choices vector that sliderTextInput will use
    slider_choices <- display_labels

    # Determine the selected display label based on the selected value
    selected_label <- NULL
    if (!is.null(selected) && selected != "") {
      selected_label <- value_to_label[selected]
    }

    # If no valid selection, default to first choice
    if (is.null(selected_label) || is.na(selected_label)) {
      selected_label <- slider_choices[1]
    }

    # Store the mapping for later use in JavaScript
    value_map <- option

    if (!is.null(shiny::getDefaultReactiveDomain())) {
      session <- shiny::getDefaultReactiveDomain()
      session$userData[[paste0(id, "_values")]] <- value_map
    }

    # Create the slider with display labels
    output <- shinyWidgets::sliderTextInput(
      inputId = id,
      label = label,
      choices = slider_choices, # These are the display labels
      selected = selected_label, # Must be a display label, not a value
      force_edges = force_edges,
      grid = grid,
      ...
    )

    # Store the values in a data attribute for extraction
    values_json <- jsonlite::toJSON(values)

    # Add a data-values attribute to the input element for extraction
    # The input element has the id directly, so we use #id not #id input
    js_add_values <- sprintf(
      '
        $(document).ready(function() {
          $("#%s").attr("data-values", %s);
        });
      ',
      id,
      values_json
    )

    output <- shiny::tagAppendChild(
      output,
      shiny::tags$script(htmltools::HTML(js_add_values))
    )

    # JavaScript to map the display label back to the stored value
    # (slider uses display labels but stores internal values)
    js_value_mapping <- sprintf(
      "
      $(document).ready(function() {
        var sliderId = '%s';
        var valueMap = %s;

        // Track value changes and map display label to internal value
        $('#' + sliderId).on('change', function(e) {
          var currentLabel = $(this).val();
          Shiny.setInputValue(sliderId, valueMap[currentLabel]);
        });

        // On page load, ensure the current value is mapped (for cookie restoration)
        // Use a short delay to ensure the slider is fully initialized
        setTimeout(function() {
          var currentLabel = $('#' + sliderId).val();
          if (currentLabel && valueMap[currentLabel]) {
            Shiny.setInputValue(sliderId, valueMap[currentLabel]);
          }
        }, 100);

        // Initialize interaction tracking (from interaction.js)
        initInteractionTracking(sliderId, 'slider');
      });
    ",
      id,
      jsonlite::toJSON(as.list(value_map))
    )

    shiny::tagAppendChild(
      output,
      shiny::tags$script(htmltools::HTML(js_value_mapping))
    )
  })
}

qt_render_slider_numeric <- function(a, ...) {
  with(a, {
    # Extract min, max, and step from option
    slider_min <- min(option)
    slider_max <- max(option)

    # Calculate step from the option sequence
    if (length(option) > 1) {
      slider_step <- option[2] - option[1]
    } else {
      slider_step <- 1
    }

    # Set default value if not provided (use midpoint)
    if (is.null(default)) {
      default <- (slider_min + slider_max) / 2
    }

    # Note: the small minor tick marks between the labeled major ticks are
    # hidden by surveydown's styling (see .irs-grid-pol.small in
    # surveydown.css)
    output <- shiny::sliderInput(
      inputId = id,
      label = label,
      min = slider_min,
      max = slider_max,
      value = default,
      step = slider_step,
      ...
    )

    # Initialize interaction tracking (from interaction.js)
    js_init <- sprintf(
      "$(document).ready(function() { initInteractionTracking('%s', 'slider_numeric'); });",
      id
    )

    shiny::tagAppendChild(
      output,
      shiny::tags$script(htmltools::HTML(js_init))
    )
  })
}

qt_render_date <- function(a, ...) {
  with(a, {
    output <- shiny::dateInput(
      inputId = id,
      label = label,
      value = NULL,
      min = NULL,
      max = NULL,
      format = "yyyy-mm-dd",
      startview = "month",
      weekstart = 0,
      language = language,
      autoclose = TRUE,
      datesdisabled = NULL,
      daysofweekdisabled = NULL,
      ...
    )

    # Initialize interaction tracking (from interaction.js)
    js_init <- sprintf(
      "$(document).ready(function() { initInteractionTracking('%s', 'date'); });",
      id
    )

    shiny::tagAppendChild(
      output,
      shiny::tags$script(htmltools::HTML(js_init))
    )
  })
}

qt_render_daterange <- function(a, ...) {
  with(a, {
    output <- shiny::dateRangeInput(
      inputId = id,
      label = label,
      start = NULL,
      end = NULL,
      min = NULL,
      max = NULL,
      format = "yyyy-mm-dd",
      startview = "month",
      weekstart = 0,
      language = language,
      separator = "-",
      autoclose = TRUE,
      ...
    )

    # Initialize interaction tracking (from interaction.js)
    js_init <- sprintf(
      "$(document).ready(function() { initInteractionTracking('%s', 'daterange'); });",
      id
    )

    shiny::tagAppendChild( 
      output,
      shiny::tags$script(htmltools::HTML(js_init))
    )
  })
}

qt_render_matrix <- function(a, ...) {
  with(a, {
    # Each row is rendered as its own sub-question: radio buttons for
    # "matrix" (single selection) or checkboxes for "matrix_multiple"
    # (multiple selections per row)
    sub_type <- if (type == "matrix_multiple") "mc_multiple" else "mc"

    # Auto-calculate question column width if not provided
    if (is.null(matrix_question_width)) {
      # Find the longest row label by character count
      row_labels <- names(row)
      max_chars <- max(nchar(row_labels))
      # Estimate width: base 20% + 0.5% per character, bounded between 30% and 80%
      estimated_width <- min(80, max(30, 20 + max_chars * 0.5))
      matrix_question_width <- paste0(estimated_width, "%")
    } else {
      # Normalize matrix_question_width to always have "%" suffix
      # Accepts: 40, "40", or "40%" - all become "40%"
      if (is.numeric(matrix_question_width)) {
        matrix_question_width <- paste0(matrix_question_width, "%")
      } else if (!grepl("%$", matrix_question_width)) {
        matrix_question_width <- paste0(matrix_question_width, "%")
      }
    }

    # Calculate option column widths from remaining space after question column
    remaining_width <- 100 - as.numeric(gsub("%", "", matrix_question_width))
    matrix_option_width <- paste0(remaining_width / length(option), "%")

    # Create colgroup element
    colgroup <- shiny::tags$colgroup(
      # First column for questions
      shiny::tags$col(style = paste0("width: ", matrix_question_width, ";")),
      # Remaining columns for options (auto-distributed)
      lapply(seq_along(option), function(i) {
        shiny::tags$col(style = paste0("width: ", matrix_option_width, ";"))
      })
    )
    header <- shiny::tags$tr(
      shiny::tags$th(""),
      lapply(names(option), function(opt) shiny::tags$th(opt))
    )
    rows <- lapply(row, function(q_id) {
      full_id <- paste(id, q_id, sep = "_")
      shiny::tags$tr(
        shiny::tags$td(names(row)[row == q_id]),
        shiny::tags$td(
          colspan = length(option),
          sd_question(
            type = sub_type,
            id = full_id,
            label = "",
            option = option,
            direction = "horizontal",
            ...
          )
        )
      )
    })

    shiny::div(
      class = "matrix-question-container",
      shiny::tags$label(class = "control-label", label),
      shiny::tags$table(
        class = "matrix-question",
        colgroup,
        header,
        shiny::tags$tbody(rows)
      )
    )
  })
}

qt_render_ranking <- function(a, ...){
  with(a, {
    # Hand-built markup rather than a Shiny input widget: the value is
    # reported by ranking.js via Shiny.setInputValue() as the drag order
    # changes (same approach the slider renderer uses its label -> value
    # ramping).
    labels <- names(choice_html(option))
    items <- lapply(seq_along(option), function(i) {
      shiny::tags$li(
        class = "sd-ranking-item",
        `data-value` = unname(option[i]),
        shiny::tags$li(
          class = "sd-ranking-item",
          `data-value` = unname(option[i]),
          shiny::tags$span(
            class = "sd-ranking-label",
            shiny::HTML(labels[i])
          ),
          shiny::tag$span(
            class = "sd-ranking-handle",
            `aria-hidden` = "true",
            "\u2261"
          )
        )
      )
    })

    shiny::div(
      class = "sd-ranking-container",
      shiny::tags$label(class = "control-label", label),
      shiny::tags$ul(id = id, class = "sd-ranking-list", items)
    )

  })
}

# -- Restorers --------------------------------------------------------------

qt_restore_mc <- function(session, id, value, info) {
  shiny::updateRadioButtons(session, id, selected = value)
}

qt_restore_mc_buttons <- function(session, id, value, info) {
  # Use shinyWidgets update function for button-style radio groups
  shinyWidgets::updateRadioGroupButtons(session, id, selected = value)
  # Also send custom message to trigger JavaScript update
  session$sendCustomMessage(
    "restoreButtonValue",
    list(id = id, value = value, type = "radio")
  )
}

qt_restore_mc_multiple <- function(session, id, value, info) {
  values <- split_stored_value(value)
  shiny::updateCheckboxGroupInput(session, id, selected = values)
}

qt_restore_mc_multiple_buttons <- function(session, id, value, info) {
  values <- split_stored_value(value)
  # Use shinyWidgets update function for button-style checkbox groups
  shinyWidgets::updateCheckboxGroupButtons(session, id, selected = values)
  # Also send custom message to trigger JavaScript update
  session$sendCustomMessage(
    "restoreButtonValue",
    list(id = id, value = values, type = "checkbox")
  )
}

qt_restore_select <- function(session, id, value, info) {
  shiny::updateSelectInput(session, id, selected = value)
}

qt_restore_text <- function(session, id, value, info) {
  shiny::updateTextInput(session, id, value = value)
}

qt_restore_textarea <- function(session, id, value, info) {
  shiny::updateTextAreaInput(session, id, value = value)
}

qt_restore_numeric <- function(session, id, value, info) {
  shiny::updateNumericInput(session, id, value = as.numeric(value))
}

qt_restore_slider <- function(session, id, value, info) {
  if (isTRUE(info$is_range)) {
    # For range sliders, stored value is two values joined by a pipe
    values <- as.numeric(split_stored_value(value))
    if (length(values) == 2) {
      shinyWidgets::updateSliderTextInput(session, id, selected = values)
      session$sendCustomMessage(
        "restoreSliderValue",
        list(id = id, selected = values)
      )
    }
    return(invisible())
  }

  # Single value slider: convert the stored value to its display label.
  # Try session userData first, then fall back to the question's options.
  value_map <- session$userData[[paste0(id, "_values")]]
  if (is.null(value_map)) {
    value_map <- info$options
  }
  if (!is.null(value_map)) {
    label_idx <- which(value_map == value)
    if (length(label_idx) > 0) {
      display_label <- names(value_map)[label_idx[1]]
      shinyWidgets::updateSliderTextInput(
        session,
        id,
        selected = display_label
      )
      session$sendCustomMessage(
        "restoreSliderValue",
        list(id = id, selected = display_label)
      )
    }
  } else {
    # Fallback if value map not available
    shinyWidgets::updateSliderTextInput(session, id, selected = value)
    session$sendCustomMessage(
      "restoreSliderValue",
      list(id = id, selected = value)
    )
  }
}

qt_restore_slider_numeric <- function(session, id, value, info) {
  if (isTRUE(info$is_range)) {
    # For range sliders, stored value is two values joined by a pipe
    values <- as.numeric(split_stored_value(value))
    if (length(values) == 2) {
      shiny::updateSliderInput(session, id, value = values)
    }
    return(invisible())
  }
  shiny::updateSliderInput(session, id, value = as.numeric(value))
}

qt_restore_date <- function(session, id, value, info) {
  shiny::updateDateInput(session, id, value = value)
}

qt_restore_daterange <- function(session, id, value, info) {
  # For date range, stored value is two dates joined by a pipe
  dates <- split_stored_value(value)
  if (length(dates) == 2) {
    shiny::updateDateRangeInput(session, id, start = dates[1], end = dates[2])
  }
}

qt_restore_ranking <- function(session, id, value, info){
  # Stored pipe-joined; as.list() keeps it a JSON array even for one item
  order <- split_stored_value(value)
  session$sendCustomMessage(
    "restoreRankingOrder",
    list(id = id, order = as.list(order))
  )
}

# -- Registry ----------------------------------------------------------------

question_type_registry <- list(
  select = list(
    render = qt_render_select,
    restore = qt_restore_select,
    requires_option = TRUE
  ),
  mc = list(
    render = qt_render_mc,
    restore = qt_restore_mc,
    requires_option = TRUE
  ),
  mc_multiple = list(
    render = qt_render_mc_multiple,
    restore = qt_restore_mc_multiple,
    requires_option = TRUE
  ),
  mc_buttons = list(
    render = qt_render_mc_buttons,
    restore = qt_restore_mc_buttons,
    requires_option = TRUE
  ),
  mc_multiple_buttons = list(
    render = qt_render_mc_multiple_buttons,
    restore = qt_restore_mc_multiple_buttons,
    requires_option = TRUE
  ),
  mc_image = list(
    # Renders as a radio group, so it restores like mc
    render = qt_render_mc_image,
    restore = qt_restore_mc,
    requires_option = TRUE
  ),
  mc_multiple_image = list(
    # Renders as a checkbox group, so it restores like mc_multiple
    render = qt_render_mc_multiple_image,
    restore = qt_restore_mc_multiple,
    requires_option = TRUE
  ),
  text = list(
    render = qt_render_text,
    restore = qt_restore_text,
    requires_option = FALSE
  ),
  textarea = list(
    render = qt_render_textarea,
    restore = qt_restore_textarea,
    requires_option = FALSE
  ),
  numeric = list(
    render = qt_render_numeric,
    restore = qt_restore_numeric,
    requires_option = FALSE
  ),
  slider = list(
    render = qt_render_slider,
    restore = qt_restore_slider,
    requires_option = TRUE
  ),
  slider_numeric = list(
    render = qt_render_slider_numeric,
    restore = qt_restore_slider_numeric,
    requires_option = TRUE
  ),
  date = list(
    render = qt_render_date,
    restore = qt_restore_date,
    requires_option = FALSE
  ),
  daterange = list(
    render = qt_render_daterange,
    restore = qt_restore_daterange,
    requires_option = FALSE
  ),
  matrix = list(
    render = qt_render_matrix,
    # The matrix parent has no input of its own; each row is a sub-question
    # restored individually by its own type
    restore = NULL,
    requires_option = TRUE
  ),
  matrix_multiple = list(
    render = qt_render_matrix,
    restore = NULL,
    requires_option = TRUE
  ),
  ranking = list(
    render = qt_render_ranking,
    restore = qt_restore_ranking,
    requires_option = TRUE
  )
)
