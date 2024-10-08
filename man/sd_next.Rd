% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ui.R
\name{sd_next}
\alias{sd_next}
\title{Create a 'Next' Button for Page Navigation}
\usage{
sd_next(next_page = NULL, label = "Next")
}
\arguments{
\item{next_page}{Character string. The ID of the next page to navigate to. This parameter is required.}

\item{label}{Character string. The label of the 'Next' button. Defaults to "Next".}
}
\value{
A Shiny tagList containing the 'Next' button UI element.
}
\description{
This function creates a 'Next' button for navigating to the specified next page in a Surveydown survey.
The button can be activated by clicking or by pressing the Enter key when visible.
}
\details{
The function generates a Shiny action button that, when clicked or when the Enter key is pressed,
sets the input value to the specified next page ID, facilitating page navigation within the Shiny application.
The button is styled to appear centered on the page and includes a class for Enter key functionality.
}
\examples{
sd_next("page2", "Continue to Next Section")

}
