#' Find sets of samples that stay together across clusterings
#' Find sets of samples that stay together across clusterings in order to define
#' a new clustering vector.
#'
#' @param x a matrix or \code{\link{clusterExperiment}} object.
#' @param whichCluster a numeric or character vector that specifies which
#' clusters to compare (missing if x is a matrix)
#' @param clusterFunction the clustering to use (passed to
#' \code{\link{clusterD}}); currently must be of type '01'.
#' @param minSize minimum size required for a set of samples to be considered in
#' a cluster because of shared clustering, passed to \code{\link{clusterD}}
#' @param proportion The proportion of times that two sets of samples should be
#' together in order to be grouped into a cluster (if <1, passed to clusterD via
#' alpha=1-proportion)
#' @param propUnassigned samples with greater than this proportion of
#' assignments equal to '-1' are assigned a '-1' cluster value as a last step
#' (only if proportion < 1)
#'
#' @details The function tries to find a consensus cluster across many different
#' clusterings of the same sample. It does so by creating a \code{nSamples} x
#' \code{nSamples} matrix of the percentage of co-occurance of each sample and
#' then calling clusterD to cluster the co-occurance matrix. The function
#' assumes that '-1' labels indicate clusters that are not assigned to a
#' cluster. Co-occurance with the unassigned cluster is treated differently than
#' other clusters. The percent co-occurance is taken only with respect to those
#' clusterings where both samples were assigned. Then samples with more than
#' \code{propUnassigned} values that are '-1' across all of the clusterings are
#' assigned a '-1' regardless of their cluster assignment.
#'
#' @return If x is a matrix, a list with values
#' \itemize{
#'
#' \item{\code{clustering}}{vector of cluster assignments, with "-1" implying
#' unassigned}
#'
#' \item{\code{percentageShared}}{a nsample x nsample matrix of the percent
#' co-occurance across clusters used to find the final clusters. Percentage is
#' out of those not '-1'}
#' \item{\code{noUnassignedCorrection}{a vector of cluster assignments before
#' samples were converted to '-1' because had >\code{propUnassigned} '-1' values
#' (i.e. the direct output of the \code{clusterD} output.)}}
#' }
#'
#'@return If x is a \code{\link{clusterExperiment}}, a
#'\code{\link{clusterExperiment}} with an added clustering of clusterType equal
#'to `combineMany` and the \code{percentageShared} matrix stored in the
#'\code{coClustering} slot.
#'
#' ps<-c(5,10,50) ## redo example!!!
#' names(ps)<-paste("npc=",ps,sep="")
#' pcaData<-stats::prcomp(simData, center=TRUE, scale=TRUE)
#' cl <- clusterMany(lapply(ps,function(p){pcaData$x[,1:p]}),
#' clusterMethod="pam",ks=2:4,findBestK=c(FALSE),removeSil=TRUE,subsample=FALSE)
#' #make names shorter for plotting
#' colnames(cl$clMat)<-gsub("TRUE","T",colnames(cl$clMat))
#' colnames(cl$clMat)<-gsub("FALSE","F",colnames(cl$clMat))
#' colnames(cl$clMat)<-gsub("k=NA,","",colnames(cl$clMat))

#' #require 100% agreement -- very strict
#' clCommon100<-combineMany(cl$clMat,proportion=1,minSize=10)
#' #require 70% agreement based on clustering of overlap
#' clCommon70<-combineMany(cl$clMat,proportion=0.7,plot=TRUE,minSize=10)
#' oldpar<-par()
#' par(mar=c(1.1,12.1,1.1,1.1))
#' plotClusters(cbind("70%Similarity"=clCommon70$clustering,cl$clMat,"100%Similarity"=clCommon100$clustering),axisLine=-2)
#' par(oldpar)
#'
#' @rdname combineMany
setMethod(
  f = "combineMany",
  signature = signature(x = "matrix", whichClusters = "missing"),
  definition = function(x, whichClusters, proportion=1,
                        clusterFunction="hierarchical",
                        propUnassigned=.5, minSize=5) {

  clusterMat <- x
  if(proportion == 1) {
    singleValueClusters <- apply(clusterMat, 1, paste, collapse=";")
    allUnass <- paste(rep("-1", length=ncol(clusterMat)), collapse=";")
    uniqueSingleValueClusters <- unique(singleValueClusters)
    tab <-	table(singleValueClusters)
    tab <- tab[tab >= minSize]
    tab <- tab[names(tab) != allUnass]
    cl <- match(singleValueClusters, names(tab))
    cl[is.na(cl)] <- -1
    sharedPerct<-NULL
  } else{
    if(is.character(clusterFunction)){
      typeAlg <- .checkAlgType(clusterFunction)
      if(typeAlg!="01") {
        stop("combineMany is only implemented for '01' type clustering functions (see help of clusterD)")
      }
    }
    ##Make clusterMat character, just in case
    clusterMat <- apply(clusterMat, 2, as.character)
    clusterMat[clusterMat == "-1"] <- NA
    sharedPerct <- .hammingdist(t(clusterMat)) #works on columns. gives a nsample x nsample matrix back.
    sharedPerct[is.na(sharedPerct) | is.nan(sharedPerct)] <- 0 #have no clusterings for which they are both not '-1'
    cl <- clusterD(D=sharedPerct, clusterFunction=clusterFunction,
                   alpha=1-proportion, minSize=minSize, format="vector",
                   clusterArgs=list(evalClusterMethod=c("average")))

    if(is.character(cl)) {
      stop("coding error -- clusterD should return numeric vector")
    }
  }
  ##Now define as unassigned any samples with >= propUnassigned '-1' values in clusterMat
  whUnassigned <- which(apply(clusterMat, 2, function(x){
    sum(x== -1)/length(x)>propUnassigned}))
  clUnassigned <- cl
  clUnassigned[whUnassigned] <- -1

  return(list(clustering=clUnassigned, percentageShared=sharedPerct,
              noUnassignedCorrection=cl))
}
)

#' @rdname combineMany
setMethod(
  f = "combineMany",
  signature = signature(x = "ClusterExperiment", whichClusters = "numeric"),
  definition = function(x, whichClusters, proportion=1,
                        clusterFunction="hierarchical",
                        propUnassigned=.5, minSize=5){

    if(!all(whichClusters %in% 1:NCOL(clusterMatrix(x)))) {
      stop("Invalid indices for clusterLabels")
    }

    clusterMat <- clusterMatrix(x)[, whichClusters, drop=FALSE]

    outlist <- combineMany(clusterMat, proportion=proportion,
                                  clusterFunction=clusterFunction,
                                  propUnassigned=propUnassigned,
                                  minSize=minSize)

    newObj <- clusterExperiment(x, outlist$clustering,
                                transformation=transformation(x),
                                clusterType="combineMany")
    clusterLabels(newObj) <- "combineMany"

    if(!is.null(outlist$percentageShared)) {
      coClustering(newObj) <- outlist$percentageShared
    }

    return(addClusters(newObj, x))
  }
)

#' @rdname combineMany
setMethod(
  f = "combineMany",
  signature = signature(x = "ClusterExperiment", whichClusters = "character"),
  definition = function(x, whichClusters, proportion=1,
                        clusterFunction="hierarchical",
                        propUnassigned=.5, plot=FALSE, minSize=5){

    wh <- .TypeIntoIndices(x, whClusters=whichClusters)

    combineMany(x, wh, proportion=proportion,
                       clusterFunction=clusterFunction,
                       propUnassigned=propUnassigned,
                       minSize=minSize)
  }
)

#from: https://johanndejong.wordpress.com/2015/10/02/faster-hamming-distance-in-r-2/
.hammingdist <- function(X, Y,uniqValue=1539263) {
	#samples are in the rows!
    if ( missing(Y) ) {
        uniqs <- na.omit(unique(as.vector(X)))
		if(uniqValue %in% uniqs) stop("uniqValue (",uniqValue,") is in X")
		isobsX<-abs(is.na(X)-1)
		if(any(is.na(X))){
			X[is.na(X)]<-uniqValue
		}
    	U <- X == uniqs[1]
        H <- t(U) %*% U
        N <- t(isobsX) %*% (isobsX)
 		for ( uniq in uniqs[-1] ) {
            U <- X == uniq
            H <- H + t(U) %*% U
        }
    } else {
        uniqs <- na.omit(union(X, Y))
		if(uniqValue %in% uniqs) stop("uniqValue (",uniqValue,") is in either X or Y")
		isobsX<-abs(is.na(X)-1)
		if(any(is.na(X))){
			X[is.na(X)]<-uniqValue
		}
		isobsY<-abs(is.na(Y)-1)
		if(any(is.na(Y))){
			Y[is.na(Y)]<-uniqValue
		}
        H <- t(X == uniqs[1]) %*% (Y == uniqs[1])
        N <- t(isobsX) %*% (isobsY)
 		for ( uniq in uniqs[-1] ) {
			A<-t(X == uniq) %*% (Y == uniq)
           H <- H + A
        }
    }
    H/N
}
