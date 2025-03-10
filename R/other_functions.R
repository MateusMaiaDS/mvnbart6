# A fucction to retrive the number which are the factor columns
base_dummyVars <- function(df) {
        num_cols <- sapply(df, is.numeric)
        factor_cols <- sapply(df, is.factor)

        return(list(continuousVars = names(df)[num_cols], facVars = names(df)[factor_cols]))
}

# functions ####
# ESS function
spectrum0.ar <- function (x){
        x <- matrix(x, ncol = 1)
        v0 <- order <- numeric(ncol(x))
        names(v0) <- names(order) <- colnames(x)
        z <- 1:nrow(x)
        for (i in 1:ncol(x)) {
                lm.out <- stats::lm(x[, i] ~ z)
                if (identical(all.equal(stats::sd(stats::residuals(lm.out)), 0), TRUE)) {
                        v0[i] <- 0
                        order[i] <- 0
                }
                else {
                        ar.out <- stats::ar(x[, i], aic = TRUE)
                        v0[i] <- ar.out$var.pred/(1 - sum(ar.out$ar))^2
                        order[i] <- ar.out$order
                }
        }
        return(list(spec = v0, order = order))
}

#' Calculate the ESS
#'
#' @param x a single-chain from a MCMC sampler
#'
#' @export
#'
ESS <- function (x){
        if(!is.matrix(x)){
                x <- matrix(x, ncol = 1)
                # warning("The chain was converted into a matrix of 1 column.")
        }
        spec <- spectrum0.ar(x)$spec
        ans <- ifelse(spec == 0, 0, nrow(x) * apply(x, 2, stats::var)/spec)
        return(ans)
}


# Normalize BART function (Same way ONLY THE COVARIATE NOW)
normalize_covariates_bart <- function(y, a = NULL, b = NULL) {

     # Defining the a and b
     if( is.null(a) & is.null(b)){
          a <- min(y)
          b <- max(y)
     }
     # This will normalize y between -0.5 and 0.5
     y  <- (y - a)/(b - a)
     return(y)
}


#' Coverage for the prediction intervals
#'
#' @export
#'
pi_coverage <- function(y, y_hat_post, sd_post, prob = 0.5,n_mcmc_replications = 1000){

        # Getting the number of posterior samples and columns, respect.
        if(!is.null(dim(y))){
                stop("Insert a vector for y.")
        }

        # Checking the shape of the posterior samples inserted there
        if(nrow(y_hat_post)!= length(y)){
                stop("Insert the posterior samples as a matrix of n \\times mcmc shape.")
        }

        # Setting the size of n_test
        n_test <- length(y)

        # Settina all predictions samples matrix
        all_predictions_samples = matrix(NA, nrow = n_test, ncol = n_mcmc_replications)

        for(i in 1:n_test){
                y_hats <- y_hat_post[i,]
                n_gs <- sample(1:ncol(y_hat_post),size = n_mcmc_replications,replace = TRUE)

                for(k in 1:n_mcmc_replications){
                        y_hat_draw = y_hats[n_gs[k]]
                        sig_draw = sd_post[n_gs[k]]
                        all_predictions_samples[i,k] = stats::rnorm(n = 1,mean = y_hat_draw,sd = sig_draw)
                }
        }

        # Calculating the quantiles for the lower and upper quantiles we have
        pi_lower_bd <- numeric(n_test)
        pi_upper_bd <- numeric(n_test)

        for(i in 1:n_test){
                pi_lower_bd[i] <- stats::quantile(c(all_predictions_samples[i,]), (1-prob)/2)
                pi_upper_bd[i] <- stats::quantile(c(all_predictions_samples[i,]), (1+prob)/2)
        }


        pi_cov <- sum((y<=pi_upper_bd) & (y>=pi_lower_bd))/n_test

        return(pi_cov)
}

#' A function to calculate coverage of the credible interval
#' @export
cr_coverage <- function(f_true, f_post, prob = 0.5){


        if(length(f_true) != nrow(f_post)){
                stop("Insert the posterior matrix in the shape of n \\times _mcmc")
        }
        # Getting the lower and upper boundary
        cr_low_bd <- apply(f_post,1,function(x) stats::quantile((x), prob = (1-prob)/2))
        cr_up_bd <- apply(f_post,1,function(x) stats::quantile((x), prob = (1+prob)/2))


        if((length(cr_low_bd) != length(f_true)) || (length(cr_up_bd) != length(f_true)) ){
                stop("Something wrong with the cr_low_bd or cr_up_bd")
        }

        # Calculating the coverage
        cr_cov <- mean( (f_true>=cr_low_bd) & (f_true<=cr_up_bd) )

        return(cr_cov )

}

# Normalize BART function (Same way ONLY THE COVARIATE NOW)
normalize_bart <- function(y, a = NULL, b = NULL) {

     # Defining the a and b
     if( is.null(a) & is.null(b)){
          a <- min(y,na.rm = TRUE)
          b <- max(y,na.rm = TRUE)
     }
     # This will normalize y between -0.5 and 0.5
     y  <- (y - a)/(b - a) - 0.5
     return(y)
}

# Getting back to the original scale
unnormalize_bart <- function(z, a, b) {
     # Just getting back to the regular BART
     y <- (b - a) * (z + 0.5) + a
     return(y)
}


# Naive sigma_estimation
naive_sigma <- function(x,y){

     # Getting the valus from n and p
     n <- length(y)

     # Getting the value from p
     p <- ifelse(is.null(ncol(x)), 1, ncol(x))

     # Adjusting the df
     df <- data.frame(x,y)
     colnames(df)<- c(colnames(x),"y")

     # Naive lm_mod
     lm_mod <- stats::lm(formula = y ~ .,
                         data =  df,
                         na.action = na.omit)

     # Getting sigma
     sigma <- summary(lm_mod)$sigma
     return(sigma)

}






#' Recoding variables
#' @export
#'
recode_vars <- function(x_train, dummy_obj){

        vars <- numeric()
        j <- 0
        i <- 0
        c <- 1
        while(!is.na(colnames(x_train)[c])){
                if(colnames(x_train)[c] %in% dummy_obj$facVars){
                        curr_levels <- dummy_obj$lvls[[colnames(x_train)[c]]]
                        for(k in 1:length(curr_levels)){
                             i = i+1
                             vars[i] <- j
                        }
                } else {

                     i = i+1
                     vars[i] <- j
                }
                j = j+1
                c = c+1
        }

        return(vars)
}

#' RMSE: Calculating the rmse
#'
#' @export
#'
rmse <- function(x,y){
     return(sqrt(mean((y-x)^2)))
}

#' Calculating CRPS from (https://arxiv.org/pdf/1709.04743.pdf)
#' @export
#'
crps <- function(y,means,sds){

     # scaling the observed y
     z <- (y-means)/sds

     crps_vector <- sds*(z*(2*stats::pnorm(q = z,mean = 0,sd = 1)-1) + 2*stats::dnorm(x = z,mean = 0,sd = 1) - 1/(sqrt(pi)) )

     return(list(CRPS = mean(crps_vector), crps = crps_vector))
}


#' Calculating a Frequentist confidence interval covarage
#' @export
#'
ci_coverage <- function(y_,
                        y_hat_,
                        sd_,
                        prob_ = 0.5){

        # Calculating the coverage based on the mean values
        up_ci <- y_hat_ + sd_*stats::qnorm(p = 1-prob_/2)
        low_ci <- y_hat_ + sd_*stats::qnorm(p = prob_/2)

        ci_cov <- mean((y_<= up_ci)&(y_ >= low_ci))

        return(ci_cov)
}

#' Binary classification metrics
#' @export
logloss <- function(y_true, y_hat){


        # # Debugging the function
        # y_true <- cv_element_$test$y_true[,1]
        # y_hat <- pnorm(mvbart_mod$y_hat_test_mean[,1])


        # Some previous error checking messages
        if(!is.vector(y_true)){
                stop("Insert a valid vector for the true observed value of y")
        }
        if(!is.vector(y_hat)){
                stop("Insert a valid vector for the true observed value of y")
        }
        if(any(y_hat<0) | any(y_hat>1)){
                stop("Something wrong with the predicted probabilities")
        }

        if(length(y_hat)!=length(y_true)){
                stop("y_hat and y_true must be the same size.")
        }

        neg_loglike <- -mean(y_true*log(y_hat) + (1-y_true)*log(1-y_hat))
        if(is.nan(neg_loglike)){
                stop("Insert values for y_hat")
        }
        return( neg_loglike)

}

#' Brier Score
#
#' @export
#'
brierscore <- function(y_true, y_hat){


        # # Debugging the function
        # y_true <- cv_element_$test$y_true[,1]
        # y_hat <- pnorm(mvbart_mod$y_hat_test_mean[,1])


        # Some previous error checking messages
        if(!is.vector(y_true)){
                stop("Insert a valid vector for the true observed value of y")
        }
        if(!is.vector(y_hat)){
                stop("Insert a valid vector for the true observed value of y")
        }
        if(any(y_hat<0) | any(y_hat>1)){
                stop("Something wrong with the predicted probabilities")
        }
        if(length(y_hat)!=length(y_true)){
                stop("y_hat and y_true must be the same size.")
        }
        # Returning the brier-score it should be between 0 and one
        return( mean((y_true-y_hat)^2))

}

#' Getting the accuracy
#'
#' @export
#'
acc <- function(y_true, y_hat){


        # # Debugging the function
        # y_true <- cv_element_$test$y_true[,1]
        # y_hat <- mvbart_mod$y_hat_test_mean_class[,1]

        # Some previous error checking messages
        if(!is.vector(y_true)){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(!is.vector(y_hat)){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(length(unique(y_hat))>2 | length(unique(y_true))>2){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(length(y_hat)!=length(y_true)){
                stop("y_hat and y_true must be the same size.")
        }
        # Returning the brier-score it should be between 0 and one
        return( sum(diag(table(y_hat,y_true)))/length(y_hat))

}

#' Getting the mcc
#'
#' @export
#'
mcc <- function(y_true, y_hat){


        # # Debugging the function
        # y_true <- cv_element_$test$y_true[,1]
        # y_hat <- mvbart_mod$y_hat_test_mean_class[,1]

        # Some previous error checking messages
        if(!is.vector(y_true)){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(!is.vector(y_hat)){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(length(unique(y_hat))>2 | length(unique(y_true))>2){
                stop("Enter a valid vector with the binary outcomes.")
        }
        if(length(y_hat)!=length(y_true)){
                stop("y_hat and y_true must be the same size.")
        }
        # Returning the brier-score it should be between 0 and one
        cf <- (table(y_hat,y_true))
        mcc <- (cf[1,1]*cf[2,2]-cf[1,2]*cf[2,1])/(sqrt((cf[1,1]+cf[1,2])*(cf[1,1]+cf[2,1])*(cf[2,2]+cf[1,2])*(cf[2,2]+cf[2,1])))
        return(mcc)

}


partial_dependance_plot <- function(variable_index,
                                    use_quantiles = TRUE,
                                    n_points = NULL,
                                    x_train,
                                    y_train,...){

     if(isFALSE(use_quantiles)){
          x_points <- sort(unique(x_train[,variable_index]))
     } else {

          if(is.null(n_points)){
              n_points <- 10
          }

          x_points <- quantile(x = x_train[,variable_index],probs = seq(from = 0, to = 1,length.out = (n_points+2))[-c(1,n_points+2)])

     }

     pd_test_replications <- subart_replications <- vector("list",length = length(x_points))
     for(i in 1:length(x_points)){
          pd_test_replications[[i]] <- x_train
          pd_test_replications[[i]][,variable_index] <- x_points[i]
     }

     pd_test_matrix <- do.call(rbind,pd_test_replications)
     pd_index <- split(1:nrow(pd_test_matrix),cut(1:nrow(pd_test_matrix),breaks = length(x_points),labels = FALSE))
     subart_ppd <- subart::subart(x_train = x_train,
                                                y_mat = y_train,
                                                x_test = pd_test_matrix,...)

     y_hat_pd_var <- do.call(rbind,lapply(pd_index,function(x_point_index){colMeans(subart_ppd$y_hat_test_mean[x_point_index,])}))

     if(ncol(y_train)<=3){
          par(mfrow = c(1,ncol(y_train)))
     } else {
          par(mfrow = c(2,ncol(y_train)))
     }

     for(i in 1:ncol(y_train)){
          plot(x_points,y_hat_pd_var[,i]-mean(y_hat_pd_var[,i]),type ="b",
               col = i,pch=4,xlim = range(x_points),
               ylim = c(-3,3),
               ylab = "", xlab = paste0("x.",variable_index),main =  bquote(y^{.(i)}))
     }


}

