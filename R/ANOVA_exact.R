#' Simulates an exact dataset (mu, sd, and r represent empirical not population mean and covariance matrix) from the design to calculate power
#' @param design_result Output from the ANOVA_design function
#' @param alpha_level Alpha level used to determine statistical significance
#' @param correction Set a correction of violations of sphericity. This can be set to "none", "GG" Greenhouse-Geisser, and "HF" Huynh-Feldt
#' @param verbose Set to FALSE to not print results (default = TRUE)
#' @param emm Set to FALSE to not perform analysis of estimated marginal means
#' @param emm_model Set model type ("multivariate", or "univariate") for estimated marginal means
#' @param contrast_type Select the type of comparison for the estimated marginal means. Default is pairwise. See ?emmeans::`contrast-methods` for more details on acceptable methods.
#' @param emm_comp Set the comparisons for estimated marginal means comparisons. This is a factor name (a), combination of factor names (a+b), or for simple effects a | sign is needed (a|b)
#' @return Returns dataframe with simulation data (power and effect sizes!), anova results and simple effect results, plot of exact data, and alpha_level. Note: Cohen's f = sqrt(pes/1-pes) and the noncentrality parameter is = f^2*df(error)
#' 
#' \describe{
#'   \item{\code{"dataframe"}}{A dataframe of the simulation result.}
#'   \item{\code{"aov_result"}}{\code{aov} object returned from \code{\link{aov_car}}.}
#'   \item{\code{"aov_result"}}{\code{emmeans} object returned from \code{\link{emmeans}}.}
#'   \item{\code{"main_result"}}{The power analysis results for ANOVA level effects.}
#'   \item{\code{"pc_results"}}{The power analysis results for the pairwise (t-test) comparisons.}
#'   \item{\code{"emm_results"}}{The power analysis results of the pairwise comparison results.}
#'   \item{\code{"manova_results"}}{Default is "NULL". If a within-subjects factor is included, then the power of the multivariate (i.e. MANOVA) analyses will be provided.}
#'   \item{\code{"alpha_level"}}{The alpha level, significance cut-off, used for the power analysis.}
#'   \item{\code{"plot"}}{A plot of the dataframe from the simulation; should closely match the meansplot in \code{\link{ANOVA_design}}}
#' 
#' }
#' 
#' @examples
#' ## Set up a within design with 2 factors, each with 2 levels,
#' ## with correlation between observations of 0.8,
#' ## 40 participants (who do all conditions), and standard deviation of 2
#' ## with a mean pattern of 1, 0, 1, 0, conditions labeled 'condition' and
#' ## 'voice', with names for levels of "cheerful", "sad", amd "human", "robot"
#' design_result <- ANOVA_design(design = "2w*2w", n = 40, mu = c(1, 0, 1, 0),
#'       sd = 2, r = 0.8, labelnames = c("condition", "cheerful",
#'       "sad", "voice", "human", "robot"))
#' exact_result <- ANOVA_exact(design_result, alpha_level = 0.05)
#' @section Warnings:
#' Varying the sd or r (e.g., entering multiple values) violates assumptions of homoscedascity and sphericity respectively
#' @importFrom stats pnorm pt qnorm qt as.formula median qf power.t.test pf sd power
#' @importFrom utils combn
#' @importFrom reshape2 melt
#' @importFrom MASS mvrnorm
#' @importFrom afex aov_car
#' @importFrom graphics pairs
#' @importFrom magrittr '%>%'
#' @importFrom dplyr select mutate everything
#' @import emmeans
#' @import ggplot2
#' @export
#'

ANOVA_exact <- function(design_result, 
                        correction = Superpower_options("correction"), 
                        alpha_level = Superpower_options("alpha_level"), 
                        verbose = Superpower_options("verbose"),
                        emm = Superpower_options("emm"),
                        emm_model = Superpower_options("emm_model"),
                        contrast_type = Superpower_options("contrast_type"),
                        emm_comp) {
  
  #Need this to avoid "undefined" global error from occuring
  cohen_f <- partial_eta_squared <- non_centrality <- NULL
  #New checks for emmeans input
  if (missing(emm)) {
    emm = FALSE
  }
  
  if (missing(emm_model)) {
    emm_model = "multivariate"
  }
  
  #Follow if statements limit the possible input for emmeans specifications
  if (emm == TRUE) {
    if (is.element(emm_model, c("univariate", "multivariate")) == FALSE ) {
      stop("emm_model must be set to \"univariate\" or \"multivariate\". ")
    }
    if (is.element(contrast_type, 
                  c("pairwise", 
                    "revpairwise",
                    "eff",
                    "consec",
                    "poly",
                    "del.eff",
                    "trt.vs.ctrl",
                    "trt.vs.ctrl1",
                    "trt.vs.ctrlk",
                    "mean_chg"
                    )) == FALSE ) {
      stop("contrast_type must be of an accepted format. 
           The tukey & dunnett options currently not supported in ANOVA_exact. 
           See help(\"contrast-methods\") for details on the exact methods")
    }
  }
  if (is.element(correction, c("none", "GG", "HF")) == FALSE ) {
    stop("Correction for sphericity can only be none, GG, or HF")
  }
  


  #Errors with very small sample size; issue with mvrnorm function from MASS package
  if (design_result$n < prod(as.numeric(unlist(regmatches(design_result$design,
                                       gregexpr("[[:digit:]]+", design_result$design)))))
  ) {
    stop("ANOVA_exact cannot handle small sample sizes (n < the product of the factors) at this time; please pass this design_result to the ANOVA_power function to simulate power")
  }



  #Check to ensure there is a within subject factor -- if none --> no MANOVA
  run_manova <- grepl("w", design_result$design)



  round_dig <- 4 #Set digits to which you want to round the output.

  if (missing(alpha_level)) {
    alpha_level <- 0.05
  }

  if (alpha_level >= 1 | alpha_level <= 0  ) {
    stop("alpha_level must be less than 1 and greater than zero")
  }

  #Read in all variables from the design_result object
  design <- design_result$design #String used to specify the design
  factornames <- design_result$factornames #Get factor names
  n <- design_result$n
  if (length(n) != 1 ) {
    warning("Unequal n designs can only be passed to ANOVA_power")
  }
  mu = design_result$mu # population means - should match up with the design
  sd <- design_result$sd #population standard deviation (currently assumes equal variances)
  r <- design_result$r # correlation between within factors (currently only 1 value can be entered)
  factors <- design_result$factors
  design_factors <- design_result$design_factors
  sigmatrix <- design_result$sigmatrix
  dataframe <- design_result$dataframe
  design_list <- design_result$design_list



  ###############
  #Specify factors for formula ----
  ###############

  frml1 <- design_result$frml1
  frml2 <- design_result$frml2

  aov_result <- suppressMessages({aov_car(frml1, #here we use frml1 to enter formula 1 as designed above on the basis of the design
                                          data = dataframe, include_aov = if (emm_model == "univariate"){
                                            TRUE
                                          } else {
                                            FALSE
                                          },
                                          anova_table = list(es = "pes")) }) #This reports PES not GES

  #Run MANOVA if within subject factor is included; otherwise ignored
  if (run_manova == TRUE) {
    manova_result <- Anova_mlm_table(aov_result$Anova)
  }

  ###############
  # Set up dataframe for storing empirical results
  ###############

  #How many possible planned comparisons are there (to store p and es)
  possible_pc <- (((prod(
    as.numeric(strsplit(design, "\\D+")[[1]])
  )) ^ 2) - prod(as.numeric(strsplit(design, "\\D+")[[1]])))/2

  #create empty dataframe to store simulation results
  #number of columns for ANOVA results and planned comparisons, times 2 (p-values and effect sizes)
  sim_data <- as.data.frame(matrix(
    ncol = 2 * (2 ^ factors - 1) + 2 * possible_pc,
    nrow = 1
  ))

  paired_tests <- combn(unique(dataframe$cond),2)
  paired_p <- numeric(possible_pc)
  paired_d <- numeric(possible_pc)
  within_between <- sigmatrix[lower.tri(sigmatrix)] #based on whether correlation is 0 or not, we can determine if we should run a paired or independent t-test

  #Dynamically create names for the data we will store
  names(sim_data) = c(paste("anova_",
                            rownames(aov_result$anova_table),
                            sep = ""),
                      paste("anova_es_",
                            rownames(aov_result$anova_table),
                            sep = ""),
                      paste("p_",
                            paste(paired_tests[1,],paired_tests[2,],sep = "_"),
                            sep = ""),
                      paste("d_",
                            paste(paired_tests[1,],paired_tests[2,], sep = "_"),
                            sep = ""))

  #We simulate a new y variable, melt it in long format, and add it to the dataframe (surpressing messages)
  #empirical set to true to create "exact" dataset

  dataframe$y <- suppressMessages({
    melt(as.data.frame(mvrnorm(
      n = n,
      mu = mu,
      Sigma = as.matrix(sigmatrix),
      empirical = TRUE
    )))$value
  })

  # We perform the ANOVA using AFEX
  aov_result <- suppressMessages({aov_car(frml1, #here we use frml1 to enter fromula 1 as designed above on the basis of the design
                                          data = dataframe, include_aov = if(emm_model == "univariate"){
                                            TRUE
                                          } else {
                                            FALSE
                                          }, #Need development code to get aov_include function
                                          anova_table = list(es = "pes",
                                                             correction = correction))}) #This reports PES not GES



  #Add additional statistics
  #Create dataframe from afex results
  anova_table <- as.data.frame(aov_result$anova_table)
  colnames(anova_table) <- c("num_Df", "den_Df", "MSE", "F", "pes", "p")

  #Calculate cohen's f
  anova_table$f2 <- anova_table$pes/(1 - anova_table$pes)
  #Calculate noncentrality
  anova_table$lambda <- anova_table$f2*anova_table$den_Df

  #minusalpha<- 1-alpha_level
  anova_table$Ft <- qf((1 - alpha_level), anova_table$num_Df, anova_table$den_Df)
  #Calculate power
  anova_table$power <- (1 - pf(anova_table$Ft, anova_table$num_Df, anova_table$den_Df, anova_table$lambda))*100

  #MANOVA exact results

  # Store MANOVA result if there are within subject factors
  if (run_manova == TRUE) {
    manova_result <- Anova_mlm_table(aov_result$Anova)



  manova_result$f2 <- manova_result$test_stat / (1 - manova_result$test_stat)
  manova_result$lambda <-   manova_result$f2 *   manova_result$den_Df
  manova_result$Ft <- qf((1 - alpha_level), manova_result$num_Df,   manova_result$den_Df)
  manova_result$power <- (1 - pf(manova_result$Ft,
                                             manova_result$num_Df,
                                             manova_result$den_Df,
                                             manova_result$lambda)) * 100

  }
  
  if(emm == TRUE){
    #Call emmeans with specifcations given in the function
    #Limited to specs and model
    if(missing(emm_comp)){
      emm_comp = as.character(frml2)[2]
    }

    specs_formula <- as.formula(paste(contrast_type," ~ ",emm_comp))
    emm_result <- suppressMessages({emmeans(aov_result, 
                          specs = specs_formula,
                          model = emm_model,
                          adjust = "none")})
    #plot_emm = plot(emm_result, comparisons = TRUE)
    #make comparison based on specs; adjust = "none" in exact; No solution for multcomp in exact simulation
    pairs_result <- emm_result$contrasts
    pairs_result_df <- as.data.frame(pairs_result)
    #Need for exact; not necessary for power function
    #Convert t-ratio to F-stat
    pairs_result_df$F.value <- (pairs_result_df$t.ratio)^2
    #Calculate pes -- The formula for partial eta-squared is equation 13 from Lakens (2013)
    pairs_result_df$pes <- pairs_result_df$F.value/(pairs_result_df$F.value + pairs_result_df$df) 
    #Calculate cohen's f
    pairs_result_df$f2 <- pairs_result_df$pes/(1 - pairs_result_df$pes)
    #Calculate noncentrality
    pairs_result_df$lambda <- pairs_result_df$f2*pairs_result_df$df
    #minusalpha<- 1-alpha_level
    pairs_result_df$Ft <- qf((1 - alpha_level), 1, pairs_result_df$df)
    #Calculate power
    pairs_result_df$power <- (1 - pf(pairs_result_df$Ft, 1, pairs_result_df$df, pairs_result_df$lambda))*100
    
    pairs_result_df <- pairs_result_df %>% mutate(partial_eta_squared = .data$pes,
                                                  cohen_f = sqrt(.data$f2),
                                                  non_centrality = .data$lambda) %>%
      select(-.data$p.value,-.data$F.value,-.data$t.ratio,-.data$Ft,-.data$SE,
             -.data$f2,-.data$lambda,-.data$pes, -.data$estimate, -.data$df) %>%
      select(-.data$power, -.data$partial_eta_squared, -.data$cohen_f, -.data$non_centrality,
             .data$power, .data$partial_eta_squared, .data$cohen_f, .data$non_centrality)
    

      
    
  } else{
    pairs_result_df = NULL
    #plot_emm = NULL
    emm_result = NULL
  }
  ###

  for (j in 1:possible_pc) {
    x <- dataframe$y[which(dataframe$cond == paired_tests[1,j])]
    y <- dataframe$y[which(dataframe$cond == paired_tests[2,j])]
    #this can be sped up by tweaking the functions that are loaded to only give p and dz
    ifelse(within_between[j] == 0,
           t_test_res <- effect_size_d_exact(x, y, alpha_level = alpha_level),
           t_test_res <- effect_size_d_paired_exact(x, y, alpha_level = alpha_level))
    paired_p[j] <- (t_test_res$power*100)
    paired_d[j] <- ifelse(within_between[j] == 0,
                          t_test_res$d,
                          t_test_res$d_z)
  }

  # store p-values and effect sizes for calculations
  sim_data[1,] <- c(aov_result$anova_table[[6]], #p-value for ANOVA
                    aov_result$anova_table[[5]], #partial eta squared
                    paired_p, #power for paired comparisons, dropped correction for multiple comparisons
                    paired_d) #effect sizes

  ###############
  #Sumary of power and effect sizes of main effects and contrasts ----
  ###############
  #ANOVA
  main_results <- data.frame(anova_table$power,
                                   anova_table$pes,
                                   sqrt(anova_table$f2),
                                   anova_table$lambda)
  
  rownames(main_results) <- rownames(anova_table)
  colnames(main_results) <- c("power", "partial_eta_squared", "cohen_f", "non_centrality")
  main_results$power <- main_results$power
  #MANOVA
  if (run_manova == TRUE) {
  manova_results <- data.frame(manova_result$power,
                                     manova_result$test_stat,
                                     sqrt(manova_result$f2),
                                     manova_result$lambda)
  
  rownames(manova_results) <- rownames(manova_result)
  colnames(manova_results) <- c("power", "pillai_trace", "cohen_f", "non_centrality")
  
  }

  #Data summary for pairwise comparisons
  power_paired = as.data.frame(apply(as.matrix(sim_data[(2 * (2 ^ factors - 1) + 1):(2 * (2 ^ factors - 1) + possible_pc)]), 2,
                                     function(x) x))

  es_paired = as.data.frame(apply(as.matrix(sim_data[(2 * (2 ^ factors - 1) + possible_pc + 1):(2*(2 ^ factors - 1) + 2 * possible_pc)]), 2,
                                  function(x) x))

  pc_results <- data.frame(power_paired, es_paired)
  names(pc_results) = c("power","effect_size")

  #Create plot

  if (factors == 1) {meansplot = ggplot(dataframe, aes_string(y = "y", x = factornames[1]))}
  if (factors == 2) {meansplot = ggplot(dataframe, aes_string(y = "y",
                                                              x = factornames[1])) + facet_wrap(  paste("~",factornames[2],sep = ""))}
  if (factors == 3) {meansplot = ggplot(dataframe, aes_string(y = "y",
                                                              x = factornames[1])) + facet_grid(  paste(factornames[3],"~",factornames[2], sep = ""))}

  meansplot2 = meansplot +
    geom_jitter(position = position_jitter(0.2)) +
    stat_summary(
      fun.data = "mean_sdl",
      fun.args = list(mult = 1),
      geom = "crossbar",
      color = "red"
    ) +
    coord_cartesian(ylim = c(min(dataframe$y), max(dataframe$y))) +
    theme_bw() + ggtitle("Exact data for each condition in the design")

  #######################
  # Return Results ----
  #######################
  if (verbose == TRUE) {
    # The section below should be blocked out when in Shiny
    cat("Power and Effect sizes for ANOVA tests")
    cat("\n")
    print(round(main_results, round_dig))
    cat("\n")
    cat("Power and Effect sizes for pairwise comparisons (t-tests)")
    cat("\n")
    print(round(pc_results, 2))
    if (emm == TRUE) {
      cat("\n")
      cat("Power and Effect sizes for estimated marginal means")
      cat("\n")
      print_emm <- pairs_result_df %>%
        mutate(power = round(power,2),
               partial_eta_squared = round(partial_eta_squared,round_dig),
               cohen_f = round(cohen_f,round_dig),
               non_centrality = round(non_centrality,round_dig))
      print(print_emm)
    }
  }

  if (run_manova == FALSE) {
  manova_results = NULL
    }

  # Return results in list()
  invisible(list(dataframe = dataframe,
                 aov_result = aov_result,
                 emmeans = emm_result,
                 main_results = main_results,
                 pc_results = pc_results,
                 emm_results = pairs_result_df,
                 manova_results = manova_results,
                 alpha_level = alpha_level,
                 plot = meansplot2))
}
