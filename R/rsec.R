#' Resampling-based Sequential Ensemble Clustering
#' 
#' Implementation of the RSEC algorithm (Resampling-based Sequential Ensemble 
#' Clustering) for single cell sequencing data. This is a wrapper function 
#' around the existing clusterExperiment workflow that results in the output of
#' RSEC.
#' @param combineProportion passed to \code{proportion} in \code{\link{combineMany}}
#' @param combineMinSize passed to \code{minSize} in \code{\link{combineMany}}
#' @param dendroReduce passed to \code{dimReduce} in \code{\link{makeDendrogram}}
#' @param dendroNDims passed to \code{ndims} in \code{\link{makeDendrogram}}
#' @inheritParams clusterMany,matrix-method
#' @aliases RSEC RSEC-methods RSEC,ClusterExperiment-method RSEC,matrix-method
#' @inheritParams mergeClusters,matrix-method
#' @export
setMethod(
    f = "RSEC",
    signature = signature(x = "matrix"),
    definition = function(x, isCount=FALSE,transFun=NULL,
        dimReduce="PCA",nVarDims=NA,
        nPCADims=c(50), ks=4:15, 
        clusterFunction=c("tight","hierarchical"), 
        alphas=c(0.1,0.2),betas=0.9, minSizes=5,
        combineProportion=0.7, combineMinSize=5,
        dendroReduce="mad",dendroNDims=1000,
        mergeMethod="adjP",verbose=FALSE,
        clusterDArgs=NULL,
        subsampleArgs=list(resamp.num=50),
        seqArgs=list(verbose=FALSE),
        ncores=1, random.seed=NULL, run=TRUE
    )
{
    ce<-clusterMany(x,ks=ks,clusterFunction=clusterFunction,alphas=alphas,betas=betas,minSizes=minSizes,
                    sequential=TRUE,removeSil=FALSE,subsample=TRUE,silCutoff=0,distFunction=NA,
                    isCount=isCount,transFun=transFun,
                    dimReduce=dimReduce,nVarDims=nVarDims,nPCADims=nPCADims,
                    clusterDArgs=clusterDArgs,subsampleArgs=subsampleArgs, 
                    seqArgs=seqArgs,ncores=ncores,random.seed=random.seed,run=run)
    ce<-combineMany(ce,whichClusters="clusterMany",proportion=combineProportion,minSize=combineMinSize)
    if(any(primaryCluster(ce)!= -1)){
        ce<-makeDendrogram(ce,dimReduce=dendroReduce,ndims=dendroNDims,ignoreUnassignedVar=TRUE)
        ce<-mergeClusters(ce,mergeMethod=mergeMethod,plotMethod="none",isCount=isCount)
        
    }
    return(ce)
})