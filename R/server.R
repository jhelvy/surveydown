#' Server Logic for a surveydown survey
#'
#' @description
#' This function defines the server-side logic for a Shiny application used in surveydown.
#' It handles various operations such as conditional display, progress tracking,
#' page navigation, database updates for survey responses, and exit survey functionality.
#'
#' @param db A list containing database connection information created using
#' \code{\link{sd_database}} function. Defaults to \code{NULL}.
#' @param use_html Logical. By default, the `"survey.qmd"` file will be
#' rendered when the app launches, which can be slow. Users can render it
#' first into a html file and set `use_html = TRUE` to use the pre-rendered
#' file, which is faster when the app loads. Defaults to `FALSE`.
#' @param required_questions Vector of character strings. The IDs of questions that must be answered. Defaults to NULL.
#' @param all_questions_required Logical. If TRUE, all questions in the survey will be required. Defaults to FALSE.
#' @param start_page Character string. The ID of the page to start on. Defaults to NULL.
#' @param admin_page Logical. Whether to include an admin page for viewing and downloading survey data. Defaults to `FALSE`.
#' @param auto_scroll Logical. Whether to enable auto-scrolling to the next question after answering. Defaults to TRUE.
#' @param rate_survey Logical. If TRUE, shows a rating question when exiting the survey. If FALSE, shows a simple confirmation dialog. Defaults to FALSE.
#'
#' @import shiny
#' @import shinyWidgets
#' @importFrom stats setNames
#' @importFrom shiny reactiveValuesToList observeEvent renderText
#'
#' @details
#'
#' The function performs the following tasks:
#' \itemize{
#'   \item Initializes variables and reactive values.
#'   \item Implements conditional display logic for questions.
#'   \item Tracks answered questions and updates the progress bar.
#'   \item Handles page navigation and skip logic.
#'   \item Manages required questions.
#'   \item Performs database operations or saves to a local CSV file in preview mode.
#'   \item Sets up admin functionality if enabled in the configuration.
#'   \item Controls auto-scrolling behavior based on the `auto_scroll` parameter.
#'   \item Uses sweetalert for warning messages when required questions are not answered.
#'   \item Handles the exit survey process based on the `rate_survey` parameter.
#' }
#'
#' @section Progress Bar:
#' The progress bar is updated based on the last answered question. It will jump to the
#' percentage corresponding to the last answered question and will never decrease,
#' even if earlier questions are answered later. The progress is calculated as the ratio
#' of the last answered question's index to the total number of questions.
#'
#' @section Database Operations:
#' If \code{db} is provided, the function will update the database with survey responses.
#' If \code{db} is \code{NULL} (ignore mode), responses will be saved to a local CSV file.
#'
#' @section Auto-Scrolling:
#' When `auto_scroll` is TRUE, the survey will automatically scroll to the next question
#' after the current question is answered. This behavior can be disabled by setting
#' `auto_scroll` to FALSE.
#'
#' @section Exit Survey:
#' When `rate_survey` is TRUE, the function will show a rating question when the user attempts to exit the survey.
#' When FALSE, it will show a simple confirmation dialog. The rating, if provided, is saved with the survey data.
#'
#' @return
#' This function does not return a value; it sets up the server-side logic for the Shiny application.
#'
#' @examples
#' \dontrun{
#'   library(surveydown)
#'   library(shinyWidgets)
#'   db <- sd_database()
#'
#'   shinyApp(
#'     ui = sd_ui(),
#'     server = function(input, output, session) {
#'       sd_server(db = db, auto_scroll = TRUE, rate_survey = TRUE)
#'     }
#'   )
#' }
#'
#' @seealso
#' \code{\link{sd_database}}, \code{\link{sd_ui}}
#'
#' @export
sd_server <- function(
    db = NULL,
    use_html = FALSE,
    required_questions = NULL,
    all_questions_required = FALSE,
    start_page = NULL,
    admin_page = FALSE,
    auto_scroll = TRUE,
    rate_survey = FALSE
) {

    # Get input, output, and session from the parent environment
    parent_env <- parent.frame()
    input <- get("input", envir = parent_env)
    output <- get("output", envir = parent_env)
    session <- get("session", envir = parent_env)

    # Tag start time and unique session_id
    time_start <- get_utc_timestamp()
    session_id <- session$token

    # Get any skip or show conditions
    show_if <- shiny::getDefaultReactiveDomain()$userData$show_if
    skip_if <- shiny::getDefaultReactiveDomain()$userData$skip_if

    # Auto scroll
    session$sendCustomMessage("updateSurveydownConfig", list(autoScrollEnabled = auto_scroll))

    # Run the configuration settings
    config <- run_config(
        use_html,
        required_questions,
        all_questions_required,
        start_page,
        admin_page,
        skip_if,
        show_if
    )

    # Initialize local variables ----

    # Check if db is NULL (either blank or specified with ignore = TRUE)
    ignore_mode <- is.null(db)

    # Create local objects from config file
    pages        <- config$pages
    head_content <- config$head_content
    page_ids     <- config$page_ids
    question_ids <- config$question_ids
    start_page   <- config$start_page
    admin_page   <- config$admin_page
    question_required <- config$question_required
    page_id_to_index <- setNames(seq_along(page_ids), page_ids)

    # Pre-compute timestamp IDs
    page_ts_ids     <- paste0("time_p_", page_ids)
    question_ts_ids <- paste0("time_q_", question_ids)
    start_page_ts_id <- page_ts_ids[which(page_ids == start_page)]
    all_ids <- c('time_end', question_ids, question_ts_ids, page_ts_ids)

    # show_if conditions ----

    # Reactive to store visibility status of all questions
    question_visibility <- shiny::reactiveVal(
      setNames(rep(TRUE, length(question_ids)), question_ids)
    )

    # Observer to apply show_if conditions and update question_visibility
    shiny::observe({
      shiny::reactiveValuesToList(input)
      show_if_results <- set_show_if_conditions(show_if)()
      current_visibility <- question_visibility()
      for (target in names(show_if_results)) {
          current_visibility[target] <- show_if_results[[target]]
          if (show_if_results[[target]]) {
              shinyjs::show(paste0('container-', target))
          } else {
              shinyjs::hide(paste0('container-', target))
          }
      }
      question_visibility(current_visibility)
    })

    # Initialize local functions ----

    # Function to update progress bar
    update_progress_bar <- function(index) {
        if (index > last_answered_question()) {
            last_answered_question(index)
            current_progress <- index / length(question_ids)
            max_progress(max(max_progress(), current_progress))
            session$sendCustomMessage("updateProgressBar", max_progress() * 100)
        }
    }

    update_data <- function(data_list, changed_fields = NULL, time_last = FALSE) {
        if (length(changed_fields) == 0) {
            changed_fields = names(data_list)
        }
        if (time_last) {
            data_list[['time_end']] <- get_utc_timestamp()
        }
        if (ignore_mode) {
            if (file.access('.', 2) == 0) {  # Check if current directory is writable
                tryCatch({
                    utils::write.csv(
                        as.data.frame(data_list, stringsAsFactors = FALSE),
                        "data.csv",
                        row.names = FALSE
                    )
                }, error = function(e) {
                    warning("Unable to write to data.csv")
                    message("Error details: ", e$message)
                })
            } else {
                message("Running in a non-writable environment.")
            }
        } else {
            database_uploading(data_list, db$db, db$table, changed_fields)
        }
        # Reset changed_fields after updating the data
        changed_fields(character(0))
    }

    # Initial settings ----

    # Keep-alive observer - this will be triggered every 60 seconds
    shiny::observeEvent(input$keepAlive, {
      cat("Session keep-alive at", format(Sys.time(), "%m/%d/%Y %H:%M:%S"), "\n")
    })

    # Create admin page if admin_page is TRUE
    if (isTRUE(config$admin_page)) admin_enable(input, output, session, db)

    # Initialize values for progressbar
    load_js_file("update_progress.js")
    max_progress <- shiny::reactiveVal(0)
    last_answered_question <- shiny::reactiveVal(0)

    # Data tracking ----

    # Initialize the all_data reactive values
    initial_data <- get_initial_data(
        session, session_id, time_start, all_ids, start_page_ts_id
    )
    all_data <- do.call(shiny::reactiveValues, initial_data)

    # Initialize database table
    if (!ignore_mode) {
        table_exists <- pool::poolWithTransaction(db$db, function(conn) {
            DBI::dbExistsTable(conn, db$table)
        })
        if (!table_exists) {
            create_table(initial_data, db$db, db$table)
        }
    }

    # Reactive expression that returns a list of the latest data
    latest_data <- shiny::reactive({
        # Convert reactiveValues to a regular list
        data <- reactiveValuesToList(all_data)

        # Ensure all elements are of length 1, use "" for empty or NULL values
        data <- lapply(data, function(x) {
            if (length(x) == 0 || is.null(x) || (is.na(x) && !is.character(x))) "" else as.character(x)[1]
        })

        data[names(data) != ""]
    })

    # Observer to update the data upon any change in the data
    observe({
        data <- latest_data()
        update_data(data, changed_fields())
    })

    # Reactive value to track which fields have changed
    changed_fields <- shiny::reactiveVal(character(0))

    # Main question observers ----
    # (one created for each question)

    lapply(seq_along(question_ids), function(index) {
        local_id <- question_ids[index]
        local_ts_id <- question_ts_ids[index]

        observeEvent(input[[local_id]], {
            # Tag event time
            timestamp <- get_utc_timestamp()

            # Update question value
            formatted_value <- format_question_value(input[[local_id]])
            all_data[[local_id]] <- formatted_value

            # Update timestamp and progress if interacted
            changed <- local_id
            if (!is.null(input[[paste0(local_id, "_interacted")]])) {
                all_data[[local_ts_id]] <- timestamp
                changed <- c(changed, local_ts_id)
                update_progress_bar(index)
            }

            # Update tracker of which fields changed
            changed_fields(c(changed_fields(), changed))

            # Make value accessible in the UI
            output[[paste0(local_id, "_value")]] <- renderText({ formatted_value })
        }, ignoreNULL = FALSE, ignoreInit = TRUE)
    })

    # Page rendering ----

    # Create reactive values for the start page ID
    # (defaults to first page if NULL...see run_config() function)
    current_page_id <- shiny::reactiveVal(start_page)

    get_current_page <- reactive({
        pages[[which(sapply(pages, function(p) p$id == current_page_id()))]]
    })

    # Render main page content when current page changes
    output$main <- shiny::renderUI({
        current_page <- get_current_page()
        shiny::tagList(
            shiny::tags$head(shiny::HTML(head_content)),
            shiny::tags$div(
                class = "content",
                shiny::tags$div(
                    class = "page-columns page-rows-contents page-layout-article",
                    shiny::tags$div(
                        id = "quarto-content",
                        role = "main",
                        shiny::HTML(current_page$content)
                    )
                )
            )
        )
    })

    # Page navigation ----

    check_required <- function(page) {
      required_questions <- page$required_questions
      is_visible <- question_visibility()[required_questions]
      all(vapply(required_questions, function(q) {
        !is_visible[q] || check_answer(q, input)
      }, logical(1)))
    }

    # Determine which page is next, then update current_page_id() to it
    observe({
      lapply(pages, function(page) {
        observeEvent(input[[page$next_button_id]], {
          shiny::isolate({
            # Grab the time stamp of the page turn
            timestamp <- get_utc_timestamp()

            # Figure out page ids
            current_page_id <- page$id
            next_page_id <- get_default_next_page(page, page_ids, page_id_to_index)
            next_page_id <- handle_skip_logic(input, skip_if, current_page_id, next_page_id)
            if (!is.null(next_page_id) && check_required(page)) {
              # Set the current page as the next page
              current_page_id(next_page_id)

              # Update the page time stamp
              next_ts_id <- page_ts_ids[which(page_ids == next_page_id)]
              all_data[[next_ts_id]] <- timestamp

              # Update tracker of which fields changed
              changed_fields(c(changed_fields(), next_ts_id))
            } else if (!is.null(next_page_id)) {
              shinyWidgets::sendSweetAlert(
                session = session,
                title = "Warning",
                text = "Please answer all required questions before proceeding.",
                type = "warning"
              )
            }
          })
        })
      })
    })

    # Observer to max out the progress bar when we reach the last page
    shiny::observe({
        page <- get_current_page()
        if (is.null(page$next_page_id)) {
            update_progress_bar(length(question_ids))
        }
    })

    # Survey rating ----
    # Observer for the exit survey modal
    observeEvent(input$show_exit_modal, {
      if (rate_survey) {
        showModal(modalDialog(
          title = "Before you go...",
          sd_question(
            type   = 'mc_buttons',
            id     = 'survey_rating',
            label  = "Rate your survey experience:<br><small>(from 1-poor to 5-excellent)</small>",
            option = c(
              "1" = "1",
              "2" = "2",
              "3" = "3",
              "4" = "4",
              "5" = "5"
            )
          ),
          footer = tagList(
            modalButton("Cancel"),
            actionButton("submit_rating", "Submit and Exit")
          )
        ))
      } else {
        showModal(modalDialog(
          title = "Confirm Exit",
          "Are you sure you want to exit the survey?",
          footer = tagList(
            modalButton("Cancel"),
            actionButton("confirm_exit", "Exit")
          )
        ))
      }
    })

    # Observer to handle the rating submission or exit confirmation
    observeEvent(input$submit_rating, {
      # Save the rating
      rating <- input$survey_rating
      all_data[['exit_survey_rating']] <- rating
      changed_fields(c(changed_fields(), 'exit_survey_rating'))
      # Update data immediately
      isolate({
        update_data(latest_data(), time_last = TRUE)
      })
      # Close the modal and the window
      removeModal()
      session$sendCustomMessage("closeWindow", list())
    })

    observeEvent(input$confirm_exit, {
      # Close the modal and the window
      removeModal()
      session$sendCustomMessage("closeWindow", list())
    })

    # Ensure final update on session end
    shiny::onSessionEnded(function() {
        shiny::isolate({
            update_data(latest_data(), time_last = TRUE)
        })
    })

}

#' Define skip conditions for survey pages
#'
#' @description
#' This function is used to define conditions under which certain pages in the survey should be skipped.
#' It takes one or more formulas where the left-hand side is the condition and the right-hand side is the target page ID.
#'
#' @param ... One or more formulas defining skip conditions.
#'   The left-hand side of each formula should be a condition based on input values,
#'   and the right-hand side should be the ID of the page to skip to if the condition is met.
#'
#' @return A list of parsed conditions, where each element contains the condition and the target page ID.
#'
#' @examples
#' \dontrun{
#' sd_skip_if(
#'   as.numeric(input$age < 18) ~ "underage_page",
#'   input$country != "USA" ~ "international_page"
#' )
#'}
#' @seealso \code{\link{sd_show_if}}
#'
#' @export
sd_skip_if <- function(...) {
    conditions <- parse_conditions(...)

    # Create a list in userData to store the skip_if targets
    shiny::isolate({
        session <- shiny::getDefaultReactiveDomain()
        if (is.null(session)) {
            stop("sd_skip_if must be called within a Shiny reactive context")
        }
        if (is.null(session$userData$skip_if)) {
            session$userData$skip_if <- list()
        }
        session$userData$skip_if$conditions <- conditions
        session$userData$skip_if$targets <- get_unique_targets(conditions)
    })
}

#' Define show conditions for survey questions
#'
#' @description
#' This function is used to define conditions under which certain questions in the survey should be shown.
#' It takes one or more formulas where the left-hand side is the condition and the right-hand side is the target question ID.
#' If called with no arguments, it will return NULL and set no conditions.
#'
#' @param ... One or more formulas defining show conditions.
#'   The left-hand side of each formula should be a condition based on input values,
#'   and the right-hand side should be the ID of the question to show if the condition is met.
#'
#' @return A list of parsed conditions, where each element contains the condition and the target question ID.
#'   Returns NULL if no conditions are provided.
#'
#' @examples
#' \dontrun{
#' sd_show_if(
#'   input$has_pets == "yes" ~ "pet_details",
#'   input$employment == "employed" ~ "job_questions"
#' )
#' }
#'
#' @seealso \code{\link{sd_skip_if}}
#'
#' @export
sd_show_if <- function(...) {
  conditions <- parse_conditions(...)
  # Create a list in userData to store the show_if targets
  shiny::isolate({
    session <- shiny::getDefaultReactiveDomain()
    if (is.null(session)) {
      stop("sd_show_if must be called within a Shiny reactive context")
    }
    if (is.null(session$userData$show_if)) {
      session$userData$show_if <- list()
    }
    session$userData$show_if$conditions <- conditions
    session$userData$show_if$targets <- get_unique_targets(conditions)
  })
}

set_show_if_conditions <- function(show_if) {
    if (is.null(show_if) || length(show_if$conditions) == 0) {
        return(shiny::reactive(list()))
    }
    shiny::reactive({
        results <- lapply(show_if$conditions, function(rule) {
            result <- tryCatch({
                evaluate_condition(rule)
            }, error = function(e) {
                warning(sprintf(
                    "Error in show_if condition for target '%s', condition '%s': %s",
                    rule$target,
                    deparse(rule$condition),
                    conditionMessage(e)
                ))
                FALSE
            })
            setNames(list(result), rule$target)
        })
        do.call(c, results)
    })
}

get_unique_targets <- function(a) {
    return(unique(sapply(a, function(x) x$target)))
}

parse_conditions <- function(...) {
    conditions <- list(...)
    lapply(conditions, function(cond) {
        if (!inherits(cond, "formula")) {
            stop("Each condition must be a formula (condition ~ target)")
        }
        list(
            condition = cond[[2]],  # Left-hand side of the formula
            target = eval(cond[[3]])  # Right-hand side of the formula
        )
    })
}

evaluate_condition <- function(rule) {
    isTRUE(eval(
        rule$condition,
        envir = list(input = shiny::getDefaultReactiveDomain()$input)
    ))
}

# Function to get all stored values
get_stored_vals <- function(session) {
    shiny::isolate({
        if (is.null(session)) {
            stop("get_stored_vals must be called from within a Shiny reactive context")
        }
        stored_vals <- session$userData$stored_values
        if (is.null(stored_vals)) { return(NULL) }

        # Format stored values as a list
        formatted_vals <- lapply(stored_vals, function(val) {
            if (is.null(val)) "" else val
        })

        return(formatted_vals)
    })
}

# Get Current UTC Timestamp
get_utc_timestamp <- function() {
    return(format(Sys.time(), tz = "UTC", usetz = TRUE))
}

get_initial_data <- function(
    session, session_id, time_start, all_ids, start_page_ts_id
) {
    # Initialize with static data
    data <- c(
        list(session_id = session_id, time_start = time_start),
        get_stored_vals(session)
    )

    # Initialize question & timestamp values
    for (id in all_ids) { data[[id]] <- "" }
    data[['time_start']] <- time_start
    data[[start_page_ts_id]] <- time_start
    data[['time_end']] <- ""

    return(data)
}

# Helper function to format a single question value
format_question_value <- function(val) {
    if (is.null(val) || identical(val, NA) || identical(val, "NA")) {
        return("")
    } else if (length(val) > 1) {
        return(paste(val, collapse = ", "))
    } else {
        return(as.character(val))
    }
}

get_default_next_page <- function(page, page_ids, page_id_to_index) {
    if (is.null(page$next_page_id)) return(NULL)
    next_page_id <- page$next_page_id
    if (next_page_id == "") {
        index <- page_id_to_index[page$id] + 1
        if (index <= length(page_ids)) {
            return(page_ids[index])
        } else {
            return(NULL)
        }
    }
    return(next_page_id)
}

handle_skip_logic <- function(input, skip_if, current_page_id, next_page_id) {
    if (is.null(next_page_id) | is.null(skip_if)) { return(next_page_id) }

    # Loop through each skip logic condition
    conditions <- skip_if$conditions
    for (i in seq_along(conditions)) {
        rule <- conditions[[i]]

        # Evaluate the condition
        condition_result <- tryCatch({
            evaluate_condition(rule)
        }, error = function(e) {
            warning(sprintf(
                "Error in skip_if condition for target '%s': %s",
                rule$target, conditionMessage(e))
            )
            FALSE
        })

        # Check if the condition is met
        if (condition_result & (current_page_id != rule$target)) {
            return(rule$target)
        }
    }
    return(next_page_id)
}

# Check if a single question is answered
check_answer <- function(q, input) {
    answer <- input[[q]]
    if (is.null(answer)) return(FALSE)
    if (is.character(answer)) return(any(nzchar(answer)))
    if (is.numeric(answer)) return(any(!is.na(answer)))
    if (inherits(answer, "Date")) return(any(!is.na(answer)))
    if (is.list(answer)) return(any(!sapply(answer, is.null)))
    return(TRUE)  # Default to true for unknown types
}

admin_enable <- function(input, output, session, db) {
    #not fun to figure out, do not render the admin page at the start if you are
    #using an outright hide_pages js file
    show_admin_section <- function() {
        shinyjs::hide("quarto-content")
        shiny::insertUI(
            selector = "body",
            where = "beforeEnd",
            ui = htmltools::div(
                id = "admin-section",
                class = "admin-section",
                htmltools::div(
                    id = "login-page",
                    htmltools::h2("Admin Login"),
                    shiny::passwordInput("adminpw", "Password"),
                    shiny::actionButton("submitPw", "Log in"),
                    htmltools::br(),
                    htmltools::br(),
                    shiny::actionButton("back_to_survey_login", "Back to Survey")
                ),
                shinyjs::hidden(
                    htmltools::div(
                        id = "admin-content",
                        htmltools::h2("Admin Page"),
                        shiny::actionButton("pause_survey", "Pause Survey"),
                        shiny::actionButton("pause_db", "Pause DB"),
                        shiny::downloadButton("download_data", "Download Data"),
                        shiny::actionButton("back_to_survey_admin", "Back to Survey"),
                        htmltools::hr(),
                        htmltools::h3("Survey Data"),
                        DT::DTOutput("survey_data_table")
                    )
                )
            )
        )
    }

    # Observe for URL change
    url_reactive <- reactive({
        session$clientData$url_search
    })

    # Observe changes to the URL
    shiny::observe({
        url <- url_reactive()
        query <- parseQueryString(url)
        admin_param <- query[['admin']]
        if(!is.null(admin_param)) {
            show_admin_section()
        }
    })

    # Password check and admin content reveal
    shiny::observeEvent(input$submitPw, {
        if (input$adminpw == Sys.getenv("SURVEYDOWN_PASSWORD")) {
            session$userData$isAdmin <- TRUE
            shinyjs::hide("login-page")
            shinyjs::show("admin-content")

            output$survey_data_table <- DT::renderDT({
                data <- DBI::dbReadTable(db$db, db$table)
                DT::datatable(data, options = list(scrollX = TRUE))
            })
        } else {
            shiny::showNotification("Incorrect password", type = "error")
        }
    })

    # Function to return to survey
    return_to_survey <- function() {
        session$userData$isAdmin <- NULL
        shinyjs::hide("admin-section")
        shinyjs::show("quarto-content")
        shinyjs::runjs("showFirstPage();")
        shiny::updateQueryString("?", mode = "replace")
    }

    # Back to survey button on login page
    shiny::observeEvent(input$back_to_survey_login, {
        return_to_survey()
    })

    # Back to survey button on admin content page
    shiny::observeEvent(input$back_to_survey_admin, {
        return_to_survey()
    })

    #Pause Survey - Pause DB Section

    shiny::observeEvent(input$pause_survey, {
        #Code here that write to the table to change row value from 0 -> 1 and back if it happens
        data <- DBI::dbReadTable(db$db, paste0(db$table, "_admin_table"))
        #Read table value in, change it from true to false


        #Add in sd_server if(survey_paused == TRUE)
        #Create and display a blank page that says the survey is pause


    })

    # Download Data button functionality
    output$download_data <- shiny::downloadHandler(
        filename = function() {
            paste0(db$table, "_", Sys.Date(), ".csv")
        },
        content = function(file) {
            data <- DBI::dbReadTable(db$db, db$table)
            utils::write.csv(data, file, row.names = FALSE)
        }
    )
}

#' Set Password
#'
#' This function sets the supabase password in the .Renviron file and adds .Renviron to .gitignore.
#'
#' @param password Character string. The password to be set for Supabase connection.
#'
#' @details The function performs the following actions:
#'   1. Creates a .Renviron file in the root directory if it doesn't exist.
#'   2. Adds or updates the SURVEYDOWN_PASSWORD entry in the .Renviron file.
#'   3. Adds .Renviron to .gitignore if it's not already there.
#'
#' @return None. The function is called for its side effects.
#'
#' @examples
#' \dontrun{
#'   sd_set_password("your_SURVEYDOWN_PASSWORD")
#' }
#'
#' @export
sd_set_password <- function(password) {
    # Define the path to .Renviron file
    renviron_path <- file.path(getwd(), ".Renviron")

    # Check if .Renviron file exists, if not create it
    if (!file.exists(renviron_path)) {
        file.create(renviron_path)
    }

    # Read existing content
    existing_content <- readLines(renviron_path)

    # Check if SURVEYDOWN_PASSWORD is already defined
    password_line_index <- grep("^SURVEYDOWN_PASSWORD=", existing_content)

    # Prepare the new password line
    new_password_line <- paste0("SURVEYDOWN_PASSWORD=", password)

    # If SURVEYDOWN_PASSWORD is already defined, replace it; otherwise, append it
    if (length(password_line_index) > 0) {
        existing_content[password_line_index] <- new_password_line
    } else {
        existing_content <- c(existing_content, new_password_line)
    }

    # Write the updated content back to .Renviron
    writeLines(existing_content, renviron_path)

    # Add .Renviron to .gitignore if not already there
    gitignore_path <- file.path(getwd(), ".gitignore")
    if (file.exists(gitignore_path)) {
        gitignore_content <- readLines(gitignore_path)
        if (!".Renviron" %in% gitignore_content) {
            # Remove any trailing empty lines
            while (length(gitignore_content) > 0 && gitignore_content[length(gitignore_content)] == "") {
                gitignore_content <- gitignore_content[-length(gitignore_content)]
            }
            # Add .Renviron to the end without an extra newline
            gitignore_content <- c(gitignore_content, ".Renviron")
            writeLines(gitignore_content, gitignore_path)
        }
    } else {
        writeLines(".Renviron", gitignore_path)
    }

    message("Password set successfully and .Renviron added to .gitignore.")
}

#' Show the Saved Survey Password
#'
#' This function displays the password saved in the .Renviron file under the
#' SURVEYDOWN_PASSWORD variable. It includes a confirmation step to ensure
#' the user wants to display the password in the console. If no password is found,
#' it suggests using the sd_set_password() function to define a password.
#'
#' @return A character string containing the password if found and confirmed,
#'         or a message if no password is saved along with a suggestion to set one.
#'
#' @importFrom usethis ui_yeah ui_info ui_oops ui_todo
#'
#' @examples
#' \dontrun{
#'   sd_show_password()
#' }
#'
#' @export
sd_show_password <- function() {
  # Define the path to .Renviron file
  renviron_path <- file.path(getwd(), ".Renviron")

  # Check if .Renviron file exists
  if (!file.exists(renviron_path)) {
    usethis::ui_oops("No .Renviron file found. No password is saved.")
    usethis::ui_todo("Use sd_set_password() to define a password.")
    return(invisible(NULL))
  }

  # Read the content of .Renviron
  env_content <- readLines(renviron_path)

  # Find the line with SURVEYDOWN_PASSWORD
  password_line <- grep("^SURVEYDOWN_PASSWORD=", env_content, value = TRUE)

  if (length(password_line) == 0) {
    usethis::ui_oops("No password found in .Renviron file.")
    usethis::ui_todo("Use sd_set_password() to define a password.")
    return(invisible(NULL))
  }

  # Extract the password
  password <- sub("^SURVEYDOWN_PASSWORD=", "", password_line)

  # Confirm with the user
  if (usethis::ui_yeah("Are you sure you want to display your password in the console?")) {
    usethis::ui_info("Your saved password is: {password}")
  } else {
    usethis::ui_info("Password display cancelled.")
  }
}

#' Store a value
#'
#' This function allows storing additional values to be included in the survey data,
#' such as respondent IDs or other data.
#'
#' @param value The raid value to be stored.
#' @param id (Optional) The id (name) of the value in the data.
#'             If not provided, the id of the `value` variable will be used.
#'
#' @return NULL (invisibly)
#'
#' @examples
#' \dontrun{
#'   sd_store_value(respondentID)
#'   sd_store_value(respondentID, "respID")
#' }
#'
#' @export
sd_store_value <- function(value, id = NULL) {
    if (is.null(id)) {
        id <- deparse(substitute(value))
    }

    shiny::isolate({
        session <- shiny::getDefaultReactiveDomain()
        if (is.null(session)) {
            stop("sd_store_value must be called from within a Shiny reactive context")
        }
        if (is.null(session$userData$stored_values)) {
            session$userData$stored_values <- list()
        }
        formatted_value <- format_question_value(value)
        session$userData$stored_values[[id]] <- formatted_value

        # Make value accessible in the UI
        output <- shiny::getDefaultReactiveDomain()$output
        output[[paste0(id, "_value")]] <- renderText({ formatted_value })
    })

    invisible(NULL)
}

#' Create a copy of an input value
#'
#' This function creates a copy of an input value and makes it available as a new output.
#' The new output can then be displayed using sd_display_value().
#'
#' @param id The ID of the input value to copy
#' @param id_copy The ID for the new copy (must be different from id)
#'
#' @return NULL invisibly. This function is called for its side effects.
#'
#' @examples
#' \dontrun{
#' sd_copy_value(id = "respondent_name", id_copy = "resp_name2")
#'
#' # Then in UI:
#' # sd_display_value("resp_name2")
#' }
#'
#' @export
sd_copy_value <- function(id, id_copy) {
    if (id == id_copy) {
        stop("The 'id_copy' must be different from the 'id'")
    }
    shiny::isolate({
        output <- shiny::getDefaultReactiveDomain()$output
        input <- shiny::getDefaultReactiveDomain()$input
        output_id <- paste0(id_copy, "_value")
        if (!is.null(output)) {
            output[[output_id]] <- shiny::renderText({ input[[id]] })
        } else {
            warning("sd_copy_value was not called within a Shiny reactive context")
        }
    })
    invisible(NULL)
}
