% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ui.R
\name{sd_output}
\alias{sd_output}
\title{Output Function for Displaying reactive objects and values}
\usage{
sd_output(
  id,
  type = NULL,
  width = "100\%",
  display = "inline",
  wrapper = NULL,
  ...
)
}
\arguments{
\item{id}{Character string. A unique identifier for the output element.}

\item{type}{Character string. Specifies the type of output. Can be "question", "value", or \code{NULL.}
If \code{NULL}, the function behaves like \code{shiny::uiOutput()}.}

\item{width}{Character string. The width of the UI element. Defaults to "100\%".}

\item{display}{Character string. Specifies the display type for "value" outputs.
Can be "inline", "text", "verbatim", or "ui". Only used when \code{type = "value"}.}

\item{wrapper}{Function. A function to wrap the output. Only used when \code{type = "value"}.}

\item{...}{Additional arguments passed to the underlying Shiny functions or the wrapper function.}
}
\value{
A Shiny UI element, the type of which depends on the input parameters.
}
\description{
Output Function for Displaying reactive objects and values
}
\details{
The function behaves differently based on the \code{type} parameter:
\itemize{
\item If \code{type} is \code{NULL}, it acts like \code{shiny::uiOutput()}.
\item If \code{type} is \code{"question"}, it creates a placeholder for a reactive survey question.
\item If \code{type} is \code{"value"}, it creates an output to display the value of a survey question,
with the display style determined by the \code{display} parameter.
}
}
\examples{
\dontrun{
# Create a placeholder for a reactive question
sd_output('cbc1', type = 'question')

# Display the value of a survey question inline
sd_output('cbc1', type = 'value', display = 'inline')

# Use as a simple uiOutput
sd_output('redirect')

# Use with a wrapper function
sd_output('age', type = 'value', display = 'text',
          wrapper = function(x) tags$strong(x))
}

}
