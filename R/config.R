#' Configuration Function for surveydown Surveys
#'
#' This function sets up the configuration for a surveydown survey, including
#' page and question structures, conditional display settings, and navigation options.
#'
#' @param skip_if A list of conditions under which certain pages should be skipped. Defaults to NULL.
#' @param skip_if_custom A custom function to handle conditions under which certain pages should be skipped. Defaults to NULL.
#' @param show_if A list of conditions under which certain pages should be shown. Defaults to NULL.
#' @param show_if_custom A custom function to handle conditions under which certain pages should be shown. Defaults to NULL.
#' @param preview Logical. Whether the survey is in preview mode. Defaults to FALSE.
#' @param start_page Character string. The ID of the page to start on. Defaults to NULL.
#' @param show_all_pages Logical. Whether to show all pages initially. Defaults to FALSE.
#'
#' @details The function retrieves the survey metadata, checks the validity of the conditional
#'   display settings, and ensures that the specified start page (if any) exists. It then stores
#'   these settings in a configuration list.
#'
#' @return A list containing the configuration settings for the survey, including page and question
#'   structures, conditional display settings, and navigation options.
#'
#' @examples
#' \dontrun{
#'   config <- sd_config(
#'     skip_if = list(),
#'     skip_if_custom = NULL,
#'     show_if = list(),
#'     show_if_custom = NULL,
#'     preview = FALSE,
#'     start_page = "page1",
#'     show_all_pages = FALSE
#'   )
#' }
#'
#' @export
sd_config <- function(
        skip_if = NULL,
        skip_if_custom = NULL,
        show_if = NULL,
        show_if_custom = NULL,
        preview = FALSE,
        start_page = NULL,
        show_all_pages = FALSE
) {

    # Get survey metadata
    page_structure <- get_page_structure()
    question_structure <- get_question_structure()
    config <- list(
        page_structure     = page_structure,
        question_structure = question_structure,
        page_ids           = names(page_structure),
        question_ids       = names(question_structure),
        question_values    = unname(unlist(lapply(question_structure, `[[`, "options"))),
        question_required  = sapply(question_structure, `[[`, "required")
    )

  # Check skip_if and show_if inputs
  check_skip_show(config, skip_if, skip_if_custom, show_if, show_if_custom)

  # Check that start_page (if used) points to an actual page
  if (!is.null(start_page)) {
    if (! start_page %in% config$page_ids) {
      stop(
        "The specified start_page does not exist - check that you have ",
        "not mis-spelled the id"
      )
    }
  }

  if (show_all_pages) {
    for (page in config$page_ids) {
      shinyjs::show(page)
    }
  }

  # Store remaining config settings
  config$skip_if <- skip_if
  config$skip_if_custom <- skip_if_custom
  config$show_if <- show_if
  config$show_if_custom <- show_if_custom
  config$preview <- preview
  config$start_page <- start_page
  config$show_all_pages <- show_all_pages

  return(config)
}

## Page structure ----

get_page_structure <- function() {

  # Get all page nodes
  page_nodes <- get_page_nodes()
  page_ids <- page_nodes |> rvest::html_attr("id")

  # Initialize a list to hold the results
  page_structure <- list()

  # Iterate over each page node to get the question_ids
  for (i in seq_along(page_nodes)) {
    page_id <- page_ids[i]
    page_node <- page_nodes[i]

    # Extract all question IDs within this page
    question_ids <- page_node |>
      rvest::html_nodes("[data-question-id]") |>
      rvest::html_attr("data-question-id")

    # Store the question IDs for this page
    page_structure[[page_id]] <- question_ids
  }

  return(page_structure)
}

get_page_nodes <- function() {

  # Get the list of .qmd files in the current working directory
  qmd_files <- list.files(pattern = "\\.qmd$", full.names = TRUE)

  # Check if there is exactly one .qmd file
  if (length(qmd_files) == 1) {
    qmd_file_name <- qmd_files[1]
    html_file_name <- sub("\\.qmd$", ".html", qmd_file_name)

    # Use the derived HTML file name to read the document with rvest
    pages <- rvest::read_html(html_file_name) |>
      rvest::html_nodes(".sd-page")
    return(pages)
  }

  stop("Error: {surveydown} requires that only one .qmd file in the directory.")

}

get_question_structure <- function() {
    question_nodes <- get_question_nodes()

    # Initialize a list to hold the results
    question_structure <- list()

    # Iterate over each question node to get the question details
    for (question_node in question_nodes) {
        question_id <- rvest::html_attr(question_node, "data-question-id")

        # Extract the options for the question
        option_nodes <- question_node |>
            rvest::html_nodes("input[type='radio']")

        options <- sapply(option_nodes, function(opt) {
            rvest::html_attr(opt, "value")
        })

        # Get the required status
        is_required <- rvest::html_attr(question_node, "data-required")

        # Store the options and required status for this question
        question_structure[[question_id]] <- list(
            options = options,
            required = as.logical(is_required)
        )
    }

    return(question_structure)
}

get_question_nodes <- function() {

    # Get the list of .qmd files in the current working directory
    qmd_files <- list.files(pattern = "\\.qmd$", full.names = TRUE)

    # Check if there is exactly one .qmd file
    if (length(qmd_files) == 1) {
        qmd_file_name <- qmd_files[1]
        html_file_name <- sub("\\.qmd$", ".html", qmd_file_name)

        # Use the derived HTML file name to read the document with rvest
        questions <- rvest::read_html(html_file_name) |>
            rvest::html_nodes("[data-question-id]")

        return(questions)
    }

    stop("Error: {surveydown} requires that only one .qmd file in the directory.")
}

## Config checks ----

check_skip_show <- function(config, skip_if, skip_if_custom,
                            show_if, show_if_custom) {
    required_names <- c("question_id", "question_value", "target")

    if (!is.null(skip_if)) {
        if (!is.data.frame(skip_if)) {
            stop("skip_if must be a data frame or tibble.")
        }
        if (!all(required_names %in% names(skip_if))) {
            stop("skip_if must contain the columns: question_id, question_value, and target.")
        }
        if (!all(skip_if$question_id %in% config$question_ids)) {
            stop("All question_id values in skip_if must be valid question IDs.")
        }
        if (!all(skip_if$target %in% config$page_ids)) {
            stop("All target values in skip_if must be valid page IDs.")
        }
        if (!all(skip_if$question_value %in% config$question_values)) {
            stop("All question_value values in skip_if must be valid question values.")
        }
    }

    if (!is.null(show_if)) {
        if (!is.data.frame(show_if)) {
            stop("show_if must be a data frame or tibble.")
        }
        if (!all(required_names %in% names(show_if))) {
            stop("show_if must contain the columns: question_id, question_value, and target.")
        }
        if (!all(show_if$question_id %in% config$question_ids)) {
            stop("All question_id values in show_if must be valid question IDs.")
        }
        if (!all(show_if$target %in% config$question_ids)) {
            stop("All target values in show_if must be valid question IDs.")
        }
        if (!all(show_if$question_value %in% config$question_values)) {
            stop("All question_value values in show_if must be valid question values.")
        }
    }

    return(TRUE)
}
