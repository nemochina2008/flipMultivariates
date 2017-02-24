#' \code{SupportVectorMachine}
#'
#' SupportVectorMachine
#' @param formula A formula of the form \code{groups ~ x1 + x2 + ...}
#' That is, the response is the grouping factor and the right hand side
#' specifies the (non-factor) discriminators, and any transformations, interactions,
#' or other non-additive operators will be ignored.
#' @param data A \code{\link{data.frame}} from which variables specified
#' in formula are preferentially to be taken.
#' @param subset An optional vector specifying a subset of observations to be
#'   used in the fitting process, or, the name of a variable in \code{data}. It
#'   may not be an expression.
#' @param weights An optional vector of sampling weights, or the
#'   name of a variable in \code{data}. It may not be an expression.
#' @param output One of \code{"Accuracy"}, \code{"Confusion Matrix"} or \code{"Detail"}.
#' @param missing How missing data is to be treated. Options:
#'   \code{"Error if missing data"},
#'   \code{"Exclude cases with missing data"},
#' @param cost A positive number controlling the compromoise between exactly fitting the training data
#' (higher cost) and the ability to generalise to unseen data (lower cost).
#' @param seed The random number seed used in imputation.
#' @param statistical.assumptions A Statistical Assumptions object.
#' @param show.labels Shows the variable labels, as opposed to the labels, in the outputs, where a
#' variables label is an attribute (e.g., attr(foo, "label")).
#' @param ... Other arguments to be supplied to \code{\link{svm}}.
#' @importFrom flipData GetData CleanSubset CleanWeights EstimationData DataFormula
#' @importFrom stats pnorm
#' @importFrom flipFormat Labels
#' @importFrom flipU OutcomeName
#' @importFrom e1071 svm
#' @importFrom flipTransformations AdjustDataToReflectWeights
#' @export
SupportVectorMachine <- function(formula,
                                 data = NULL,
                                 subset = NULL,
                                 weights = NULL,
                                 output = "Accuracy",
                                 missing  = "Exclude cases with missing data",
                                 cost = 1,
                                 seed = 12321,
                                 statistical.assumptions,
                                 show.labels = FALSE,
                                 ...)
{
    ####################################################################
    ##### Reading in the data and doing some basic tidying        ######
    ####################################################################
    cl <- match.call()
    if(!missing(statistical.assumptions))
        stop("'statistical.assumptions' objects are not yet supported.")
    if (cost <= 0)
        stop("cost must be positive")
    input.formula <- formula # To work past scoping issues in car package: https://cran.r-project.org/web/packages/car/vignettes/embedding.pdf.
    subset.description <- try(deparse(substitute(subset)), silent = TRUE) #We don't know whether subset is a variable in the environment or in data.
    subset <- eval(substitute(subset), data, parent.frame())
    if (!is.null(subset))
    {
        if (is.null(subset.description) | (class(subset.description) == "try-error") | !is.null(attr(subset, "name")))
            subset.description <- Labels(subset)
        if (is.null(attr(subset, "name")))
            attr(subset, "name") <- subset.description
    }
    if(!is.null(weights))
        if (is.null(attr(weights, "name")))
            attr(weights, "name") <- deparse(substitute(weights))
    weights <- eval(substitute(weights), data, parent.frame())
    data <- GetData(input.formula, data, auxiliary.data = NULL)
    row.names <- rownames(data)
    outcome.name <- OutcomeName(input.formula)
    outcome.i <- match(outcome.name, names(data))
    outcome.variable <- data[, outcome.i]
    numeric.outcome <- !is.factor(outcome.variable)
    variable.labels <- Labels(data)
    outcome.label <- variable.labels[outcome.i]
    if (outcome.label == "data[, outcome.name]")
        outcome.label <- outcome.name
    if (!is.null(weights) & length(weights) != nrow(data))
        stop("'weights' and 'data' are required to have the same number of observations. They do not.")
    if (!is.null(subset) & length(subset) > 1 & length(subset) != nrow(data))
        stop("'subset' and 'data' are required to have the same number of observations. They do not.")

    # Treatment of missing values.
    processed.data <- EstimationData(input.formula, data, subset, weights, missing, seed = seed)
    unfiltered.weights <- processed.data$unfiltered.weights
    .estimation.data <- processed.data$estimation.data
    n.predictors <- ncol(.estimation.data)
    n <- nrow(.estimation.data)
    if (n < ncol(.estimation.data) + 1)
        stop("The sample size is too small for it to be possible to conduct the analysis.")
    .weights <- processed.data$weights
    .formula <- DataFormula(input.formula)

    # Resampling to generate a weighted sample, if necessary.
    .estimation.data.1 <- if (is.null(weights))
        .estimation.data
    else
        AdjustDataToReflectWeights(.estimation.data, .weights)

    ####################################################################
    ##### Fitting the model. Ideally, this should be a call to     #####
    ##### another function, with the output of that function       #####
    ##### called 'original'.                                       #####
    ####################################################################
    set.seed(seed)
    result <- list(original = svm(.formula, data = .estimation.data.1,
                                  probability = TRUE, cost = cost, ...))
    result$original$call <- cl

    ####################################################################
    ##### Saving results, parameters, and tidying up               #####
    ####################################################################
    # 1. Saving data.
    result$subset <- subset <- row.names %in% rownames(.estimation.data)
    result$weights <- unfiltered.weights
    result$model <- data
    #result$post.missing.data.estimation.sample <- processed.data$post.missing.data.estimation.sample

    # 2. Saving descriptive information.
    class(result) <- "SupportVectorMachine"
    result$outcome.name <- outcome.name
    result$sample.description <- processed.data$description
    result$n.observations <- n
    result$estimation.data <- .estimation.data
    result$numeric.outcome <- numeric.outcome
    result$confusion <- ConfusionMatrix(result, subset, unfiltered.weights)

    # 3. Replacing names with labels
    if (result$show.labels <- show.labels)
    {
        result$outcome.label <- outcome.label
        result$variable.labels <- variable.labels <- variable.labels[-outcome.i]
    }
    else
        result$outcome.label <- outcome.name

    # 4. Saving parameters
    result$formula <- input.formula
    result$output <- output
    result$missing <- missing
    result
}

#' @importFrom flipFormat DeepLearningTable FormatWithDecimals ExtractCommonPrefix
#' @importFrom flipData GetTidyTwoDimensionalArray Observed
#' @importFrom flipU IsCount
#' @importFrom utils read.table
#' @export
print.SupportVectorMachine <- function(x, ...)
{
    if (x$output == "Accuracy")
    {
        title <- paste0("Support Vector Machine: ", x$outcome.label)
        if (x$show.labels)
        {
            predictors <- x$variable.labels
        }
        else
        {
            predictors <- attr(x$original$terms, "term.labels")
        }

        extracted <- ExtractCommonPrefix(predictors)
        if (!is.na(extracted$common.prefix))
        {
            predictors <- extracted$shortened.labels
        }
        predictors <- paste(predictors, collapse = ", ")

        if (!x$numeric.outcome)
        {
            confM <- x$confusion
            tot.cor <- sum(diag(confM))/sum(confM)
            class.cor <- unlist(lapply(1:nrow(confM), function(i) {confM[i,i]/sum(confM[i,])}))
            names(class.cor) <- colnames(confM)
            subtitle <- sprintf("Overall Accuracy: %.2f%%", tot.cor*100)
            tbl <- DeepLearningTable(class.cor*100,
                                     column.labels = "Accuracy by class (%)",
                                     order.values = FALSE,
                                     title = title,
                                     subtitle = paste(subtitle, " (Predictors :", predictors, ")", sep = ""),
                                     footer = x$sample.description)
        }
        else
        {
            obs <- Observed(x)[x$subset == TRUE]    # subset also accounts for NAs
            pred <- predict(x)[x$subset == TRUE]
            rmse <- sqrt(mean((pred - obs)^2))
            rsq <- (cor(pred, obs))^2
            subtitle <- "Measure of fit"
            tbl <- DeepLearningTable(c("Root Mean Squared Error" = rmse, "R-squared" = rsq),
                                     column.labels = " ",
                                     order.values = FALSE,
                                     title = title,
                                     subtitle = paste(subtitle, " (Predictors: ", predictors, ")", sep = ""),
                                     footer = x$sample.description)
        }
        print(tbl)

    }
    else if (x$output == "Confusion Matrix")
    {
        mat <- GetTidyTwoDimensionalArray(x$confusion)
        color <- "Reds"
        n.row <- nrow(mat)
        show.cellnote.in.cell <- (n.row <= 10)
        if (x$numeric.outcome & !IsCount(Observed(x)))
        {
            breakpoints <- read.table(text = gsub("[^.0-9]", " ", rownames(mat)), col.names = c("lower", "upper"))
            rownames(mat) <- breakpoints$upper
            colnames(mat) <- breakpoints$upper
        }

        # create tooltip matrices of percentages
        cell.pct <- 100 * mat / sum(mat)
        cell.pct <- matrix(sprintf("%s%% of all cases",
                                format(round(cell.pct, 2), nsmall = 2)),
                                nrow = n.row, ncol = n.row)

        column.sums <- t(data.frame(colSums(mat)))
        column.sums <- column.sums[rep(row.names(column.sums), n.row), ]
        column.pct <- 100 * mat / column.sums
        column.pct <- matrix(sprintf("%s%% of Predicted class",
                                   format(round(column.pct, 2), nsmall = 2)),
                                   nrow = n.row, ncol = n.row)
        column.pct[mat == 0] <- "-"

        row.sums <- t(data.frame(rowSums(mat)))
        row.sums <- row.sums[rep(row.names(row.sums), n.row), ]
        row.pct <- 100 * mat / t(row.sums)
        row.pct <- matrix(sprintf("%s%% of Observed class",
                                     format(round(row.pct, 2), nsmall = 2)),
                                     nrow = n.row, ncol = n.row)
        row.pct[mat == 0] <- "-"

        heatmap <- rhtmlHeatmap::Heatmap(mat, Rowv = FALSE, Colv = FALSE,
                           scale = "none", dendrogram = "none",
                           xaxis_location = "top", yaxis_location = "left",
                           colors = color, color_range = NULL, cexRow = 0.79,
                           cellnote = mat, show_cellnote_in_cell = show.cellnote.in.cell,
                           xaxis_title = "Predicted", yaxis_title = "Observed",
                           title = paste0("Support Vector Machine Confusion Matrix: ", x$outcome.label),
                           footer = x$sample.description,
                           extra_tooltip_info = list("% cases" = cell.pct,
                                                     "% Predicted" = column.pct,
                                                     "% Observed" = row.pct))
        print(heatmap)
    }
    else
    {
        print(x$original)
        invisible(x)
    }
}



#' \code{ConfusionMatrix}
#'
#' @param obj A model with an outcome variable.
#' @param subset An optional vector specifying a subset of observations to be
#'   used in the fitting process, or, the name of a variable in \code{data}. It
#'   may not be an expression.
#' @param weights An optional vector of sampling weights, or, the name or, the
#'   name of a variable in \code{data}. It may not be an expression.
#' @details Produces a confusion matrix for a trained model. Predictions are based on the
#' training data (not a separate test set).
#' The proportion of observed values that take the same values as the predicted values.
#' Where the outcome variable in the model is not a factor and not a count, observed and predicted
#' values are assigned to buckets.
#' @importFrom stats predict
#' @importFrom methods is
#' @importFrom flipData Observed
#' @importFrom flipU IsCount
#' @importFrom flipRegression ConfusionMatrixFromVariables ConfusionMatrixFromVariablesLinear
#' @export
ConfusionMatrix.SupportVectorMachine <- function(obj, subset = NULL, weights = NULL)
{
    observed <- Observed(obj)
    predicted <- predict(obj)

    if (is.factor(observed))
    {
        return(ConfusionMatrixFromVariables(observed, predicted, subset, weights))
    }
    else if (IsCount(observed))
    {
        return(ConfusionMatrixFromVariablesLinear(observed, predicted, subset, weights))
    }
    else
    {
        # numeric variable and not a count - bucket predicted and observed based on range of values
        min.value <- min(predicted[subset = TRUE], observed[subset = TRUE], na.rm = TRUE)
        max.value <- max(predicted[subset = TRUE], observed[subset = TRUE], na.rm = TRUE)
        range <- max.value - min.value
        buckets <- min(floor(sqrt(length(predicted[subset = TRUE]) / 3)), 30)
        breakpoints <- seq(min.value, max.value, range / buckets)
        return(ConfusionMatrixFromVariables(cut(observed, breakpoints), cut(predicted, breakpoints), subset, weights))
    }
}