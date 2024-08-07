% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/templates.R
\name{sd_create_survey}
\alias{sd_create_survey}
\title{Create a Survey Template}
\usage{
sd_create_survey(path = getwd(), template = "simple")
}
\arguments{
\item{path}{A character string specifying the directory in which to create
the survey template. Defaults to the current working directory.}

\item{template}{A character string specifying the survey template to use.
Defaults to \code{"simple"}.}
}
\value{
A message indicating the successful creation of the survey template.
}
\description{
This function creates a survey template in a specified directory. It can use
different templates, with \code{"simple"} being the default. The function prompts
the user to confirm the use of the current working directory if no path is
specified.
}
\examples{
\dontrun{
sd_create_survey()
sd_create_survey(path = "path/to/package", template = "simple")
}
}
