% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/server.R
\name{sd_server}
\alias{sd_server}
\title{Server Logic for a surveydown survey}
\usage{
sd_server(input, session, config, db = NULL)
}
\arguments{
\item{input}{The Shiny input object.}

\item{session}{The Shiny session object.}

\item{config}{A list containing configuration settings for the application. Expected
elements include \code{page_structure}, \code{page_ids}, \code{question_ids}, \code{show_if}, \code{skip_if},
\code{skip_if_custom}, \code{show_if_custom}, \code{preview}, and \code{start_page}.}

\item{db}{A list containing database connection information created using
sd_database() function. Expected elements include \code{db} and \code{table_name}.
Defaults to \code{NULL}.}
}
\description{
This function defines the server-side logic for a Shiny application, handling various
operations such as conditional display, progress tracking, page navigation, and database
updates.
}
\details{
The function performs the following tasks:
\itemize{
\item Initializes local variables based on the provided configuration.
\item Sets up reactive values to track timestamps and progress.
\item Implements conditional display logic for UI elements based on \code{show_if} and \code{show_if_custom} conditions.
\item Tracks the progress of answered questions and updates the progress bar accordingly.
\item Handles page navigation within the Shiny application, including basic and custom skip logic.
\item Performs database operations to store responses, either to a specified database or a local CSV file if in preview mode.
}
}
\examples{
\dontrun{
  server <- function(input, output, session) {
    config <- list(
      page_structure = list(),
      page_ids = c("page1", "page2"),
      question_ids = c("q1", "q2"),
      show_if = NULL,
      skip_if = NULL,
      skip_if_custom = NULL,
      show_if_custom = NULL,
      preview = FALSE,
      start_page = "page1"
    )
    sd_server(input, session, config)
  }
  shinyApp(ui = ui, server = server)
}

}
