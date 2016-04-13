#' General wrap-around for all clustering methods we're trying.
#'
#' Given a data matrix, SummarizedExperiment, or ClusterExperiment object,
#' this function will find clusters.
#'
#' @param x the data on which to run the clustering (genes in rows)
#' @param subsample logical as to whether to subsample via
#' \code{\link{subsampleClustering}} to get the distance matrix at each
#' iteration; otherwise the distance matrix is dist(x).
#' @param sequential logical whether to use the sequential strategy.
#' @param clusterFunction passed to \code{\link{clusterD}} option
#' 'clusterFunction' to indicate method of clustering, see
#' \code{\link{clusterD}}.
#' @param clusterDArgs list of additional arguments to be passed to
#' \code{\link{clusterD}}.
#' @param subsampleArgs list of arguments to be passed to
#' \code{\link{subsampleClustering}}.
#' @param seqArgs list of additional arguments to be passed to
#' \code{\link{seqCluster}}.
#' @param isCount logical. Whether the data are in counts, in which case the
#' default \code{transFun} argument is set as log(x+1). This is simply a
#' convenience to the user, and can be overridden by giving an explicit function
#' to \code{transFun}.
#' @param transFun function A function to use to transform the input data matrix
#' before clustering.
#' @param dimReduce character A character identifying what type of
#' dimensionality reduction to perform before clustering
#' @param ndims integer An integer identifying how many dimensions to reduce to
#' in the reduction specified by \code{dimReduce}
#'
#' @details If sequential=TRUE, the sequential clustering controls the 'k'
#' argument of the underlying clustering so setting 'k=' in the list given to
#' clusterDArgs or subsampleArgs will not do anything and will produce a warning
#' to that effect.
#'
#' @return A \code{\link{ClusterExperiment}} object.
#'
#' @examples
#' data(simData)
#' \dontrun{
#' #following code takes some time.
#' #use clusterSingle to do sequential clustering
#' #(same as example in seqCluster only using clusterSingle ...)
#' set.seed(44261)
#' clustSeqHier_v2<-clusterSingle(simData,clusterFunction="hierarchical",
#' sequential=TRUE,subsample=TRUE,
#'	subsampleArgs=list(resamp.n=100,samp.p=0.7,clusterFunction="kmeans",
#'	clusterArgs=list(nstart=10)), seqArgs=list(beta=0.8,k0=5),
#'	clusterDArgs=list(minSize=5))
#' }
#' #use clusterSingle to do just clustering k=3 with no subsampling
#' clustNothing<-clusterSingle(simData,clusterFunction="pam",subsample=FALSE,
#' sequential=FALSE, clusterDArgs=list(k=3))
#' @export
#' @aliases clusterSingle clusterSingle-methods clusterSingle,matrix-method
#' clusterSingle,ClusterExperiment-method
#' @rdname clusterSingle
setMethod(
  f = "clusterSingle",
  signature = signature(x = "matrix"),
  definition = function(x, subsample=TRUE, sequential=FALSE,
      clusterFunction=c("tight", "hierarchical", "pam","kmeans"),
      clusterDArgs=NULL, subsampleArgs=NULL, seqArgs=NULL,
      isCount=FALSE,transFun=NULL, dimReduce=c("none","PCA","mostVar"),
      ndims=NA) {

    origX <- x #ngenes x nsamples
    ##########
    ##transformation to data x that will be input to clustering
    ##########
    dimReduce <- match.arg(dimReduce) #should be only 1
    if(length(ndims)>1) {
      stop("clusterSingle only handles one choice of dimensions. If you want to compare multiple choices, try clusterMany")
    }
    if(!is.na(ndims) & dimReduce=="none") {
      warning("specifying ndims has no effect if dimReduce==`none`")
    }
    nPCADims <- ifelse(dimReduce=="PCA", ndims, NA)
    nVarDims <- ifelse(dimReduce=="mostVar", ndims, NA)
    transObj <- .transData(x, nPCADims=nPCADims, nVarDims=nVarDims,
                           dimReduce=dimReduce, transFun=transFun,
                           isCount=isCount)
    x <- transObj$x
    if(is.null(dim(x)) || NCOL(x)!=NCOL(origX)) {
      stop("Error in the internal transformation of x")
    }
    transFun <- transObj$transFun #need it later to create clusterExperimentObject
    N <- dim(x)[2]

    ##########
    ##Checks that arguments make sense:
    ##########
    if(!is.function(clusterFunction)){
      clusterFunction <- match.arg(clusterFunction)
      if(!subsample & clusterFunction !="pam")
        stop("If not subsampling, clusterFunction must be 'pam'")
      typeAlg <- .checkAlgType(clusterFunction)
    }
    else{
      if(! "typeAlg" %in% clusterDArgs)
        stop("if you provide your own clustering algorithm to be passed to
             clusterD, then you must specify 'typeAlg' in clusterDArgs")
      else
        typeAlg <- clusterDArgs[["typeAlg"]]
    }
    if(typeAlg == "K"){
      if("findBestK" %in% names(clusterDArgs) & !subsample & sequential){
        if(clusterDArgs[["findBestK"]])
          stop("Cannot do sequential clustering where subsample=FALSE and
               'findBestK=TRUE' is passed via clusterDArgs.
               See help documentation.")
      }

    }
    if(sequential){
      if(is.null(seqArgs)) {
        stop("must give seqArgs so as to identify k0")
      }
      if(!"k0"%in%names(seqArgs)) {
        stop("seqArgs must contain element 'k0'")
      }
      outlist <- do.call("seqCluster",
                        c(list(x=t(x), subsample=subsample,
                               subsampleArgs=subsampleArgs,
                               clusterDArgs=clusterDArgs,
                               clusterFunction=clusterFunction), seqArgs))
    }
    else{
      if(subsample){
        if(is.null(subsampleArgs) || !("k" %in% names(subsampleArgs))){
          if(!is.null(clusterDArgs) & ("k" %in% names(clusterDArgs))){
            #give by default the clusterDArgs to subsampling.
            warning("did not give 'k' in 'subsampleArgs'.
                    Set to 'k' argument in 'clusterDArgs'")
            if(is.null(subsampleArgs))
              subsampleArgs <- list("k"=clusterDArgs[["k"]])
            else
              subsampleArgs[["k"]] <- clusterDArgs[["k"]]
          }
          else
            stop("if not sequential and do subsampling,
                 must pass 'k' in subsampleArgs")
        }
      }
      else if(typeAlg=="K" && !is.null(clusterDArgs)
              && !"k" %in% names(clusterDArgs)){
        #if don't specify k, then must have findBestK=TRUE in clusterDArgs;
        #is by default, so only need to check that if specified it,
        #set it to TRUE
        if("findBestK" %in% names(clusterDArgs) && !clusterDArgs[["findBestK"]])
          stop("if not sequential and clusterFunction is of type 'K' (e.g. pam)
               and findBestK=FALSE in clusterDArgs, must pass 'k' via
               clusterDArgs list")
      }
      ##########
      ##Actually run the clustering. .clusterWrapper just deciphers choices and makes clustering.
      ##########
      finalClusterList <- .clusterWrapper(t(x), clusterFunction=clusterFunction,
                                          subsample=subsample,
                                          subsampleArgs=subsampleArgs,
                                          clusterDArgs=clusterDArgs,
                                          typeAlg=typeAlg)
      outlist <- list("clustering"=.convertClusterListToVector(finalClusterList$results, N))

    }

    ##########
    ## Convert to clusterExperiment Object
    ##########
    clInfo<-list(list(clusterInfo = outlist$clusterInfo,
                      whyStop = outlist$whyStop,
                      subsample = subsample,
                      sequential = sequential,
                      clusterFunction = clusterFunction,
                      clusterDArgs = clusterDArgs,
                      subsampleArgs = subsampleArgs,
                      seqArgs = seqArgs,
                      dimReduce=dimReduce,
                      ndims=ndims
    ))
    retval <- clusterExperiment(origX, outlist$clustering,
                                transformation=transFun,
                                clusterInfo=clInfo,
                                clusterType="clusterSingle")
    if(subsample) {
      retval@coClustering<-finalClusterList$subsampleCocluster
    }
    validObject(retval)
    return(retval)
  }
)

#' @rdname clusterSingle
setMethod(
  f = "clusterSingle",
  signature = signature(x = "SummarizedExperiment"),
  definition = function(x, ...) {
    outval <- clusterSingle(assay(x), ...)
    retval <- clusterExperiment(x, primaryCluster(outval),
                                transformation(outval))
    retval@clusterInfo <- clusterInfo(outval)
    retval@clusterType <- clusterType(outval) #shouldn't this add to the end
    return(retval)
  }
)


#' @rdname clusterSingle
setMethod(
  f = "clusterSingle",
  signature = signature(x = "ClusterExperiment"),
  definition = function(x, ...) {

    outval <- clusterSingle(assay(x),...)

    ## do we want to add the clustering or replace it?
    ## for now, replacing it
    #     retval <- clusterExperiment(x, primaryCluster(outval), transformation(outval))
    #     retval@clusterInfo <- clusterInfo(outval)
    #     retval@clusterType <- clusterType(outval)

    ## eap: I think we should add it, so I changed it here. You might try a couple of versions.
    retval<-addClusters(outval, x) #should keep primary cluster as most recent, so outval first
    return(retval)
  }
)