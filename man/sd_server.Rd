% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/server.R
\name{sd_server}
\alias{sd_server}
\title{Server Logic for a surveydown survey}
\usage{
sd_server(
  db = NULL,
  use_html = FALSE,
  required_questions = NULL,
  all_questions_required = FALSE,
  start_page = NULL,
  admin_page = FALSE,
  auto_scroll = TRUE,
  rate_survey = FALSE
)
}
\arguments{
\item{db}{A list containing database connection information created using
\code{\link{sd_database}} function. Defaults to \code{NULL}.}

\item{use_html}{Logical. By default, the \code{"survey.qmd"} file will be
rendered when the app launches, which can be slow. Users can render it
first into a html file and set \code{use_html = TRUE} to use the pre-rendered
file, which is faster when the app loads. Defaults to \code{FALSE}.}

\item{required_questions}{Vector of character strings. The IDs of questions that must be answered. Defaults to NULL.}

\item{all_questions_required}{Logical. If TRUE, all questions in the survey will be required. Defaults to FALSE.}

\item{start_page}{Character string. The ID of the page to start on. Defaults to NULL.}

\item{admin_page}{Logical. Whether to include an admin page for viewing and downloading survey data. Defaults to \code{FALSE}.}

\item{auto_scroll}{Logical. Whether to enable auto-scrolling to the next question after answering. Defaults to TRUE.}

\item{rate_survey}{Logical. If TRUE, shows a rating question when exiting the survey. If FALSE, shows a simple confirmation dialog. Defaults to FALSE.}
}
\value{
This function does not return a value; it sets up the server-side logic for the Shiny application.
}
\description{
This function defines the server-side logic for a Shiny application used in surveydown.
It handles various operations such as conditional display, progress tracking,
page navigation, database updates for survey responses, and exit survey functionality.
}
\details{
The function performs the following tasks:
\itemize{
\item Initializes variables and reactive values.
\item Implements conditional display logic for questions.
\item Tracks answered questions and updates the progress bar.
\item Handles page navigation and skip logic.
\item Manages required questions.
\item Performs database operations or saves to a local CSV file in preview mode.
\item Sets up admin functionality if enabled in the configuration.
\item Controls auto-scrolling behavior based on the \code{auto_scroll} parameter.
\item Uses sweetalert for warning messages when required questions are not answered.
\item Handles the exit survey process based on the \code{rate_survey} parameter.
}
}
\section{Progress Bar}{

The progress bar is updated based on the last answered question. It will jump to the
percentage corresponding to the last answered question and will never decrease,
even if earlier questions are answered later. The progress is calculated as the ratio
of the last answered question's index to the total number of questions.
}

\section{Database Operations}{

If \code{db} is provided, the function will update the database with survey responses.
If \code{db} is \code{NULL} (ignore mode), responses will be saved to a local CSV file.
}

\section{Auto-Scrolling}{

When \code{auto_scroll} is TRUE, the survey will automatically scroll to the next question
after the current question is answered. This behavior can be disabled by setting
\code{auto_scroll} to FALSE.
}

\section{Exit Survey}{

When \code{rate_survey} is TRUE, the function will show a rating question when the user attempts to exit the survey.
When FALSE, it will show a simple confirmation dialog. The rating, if provided, is saved with the survey data.
}

\examples{
\dontrun{
  library(surveydown)
  library(shinyWidgets)
  db <- sd_database()

  shinyApp(
    ui = sd_ui(),
    server = function(input, output, session) {
      sd_server(db = db, auto_scroll = TRUE, rate_survey = TRUE)
    }
  )
}

}
\seealso{
\code{\link{sd_database}}, \code{\link{sd_ui}}
}
