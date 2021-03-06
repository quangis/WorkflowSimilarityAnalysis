## [SC] BEFORE RUNNING THE SCRIPT, SET THE PATH TO DIRECTORY WHERE THE R SCRIPT IS!!!!

root <- "";

####################################################################


libraries <- c("stringr", "ggplot2", "reshape2", "ngram")

for(mylibrary in libraries){
  ## [SC] installing gplots package
  if (!(mylibrary %in% rownames(installed.packages()))) {
    install.packages(mylibrary)
  }
  library(mylibrary, character.only = TRUE)
}

inputData <- paste0(root, "pythonOutputData/")
outputData <- paste0(root, "rOutputData/")


measureInterWfSimilarity <- function() {
  wfs <- read.csv(paste0(inputData, "serial_wfs.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  wfs <- cbind(wfs, serialC=gsub("|", "", wfs$serial, fixed=TRUE))
  wfs$serial <- as.character(wfs$serial)
  wfs$serialC <- as.character(wfs$serialC)

  print(wfs)
  
  disimMatrix <- matrix(nrow=nrow(wfs), ncol=nrow(wfs)
                        , dimnames=list(paste(wfs$qid, wfs$serial), paste(wfs$qid, wfs$serial))
                        #, dimnames=list(wfs$qid, wfs$qid)
                        )
  disimMatrixN <- as.matrix(disimMatrix)
  
  for(indexO in 1:nrow(wfs)) {
    for(indexT in 1:nrow(wfs)) {
      disimMatrix[indexO, indexT] <- adist(wfs$serialC[indexO], wfs$serialC[indexT])
      disimMatrixN[indexO, indexT] <- disimMatrix[indexO, indexT]/max(nchar(wfs$serialC[indexO]),nchar(wfs$serialC[indexT]))
    }
  }
  
  disimMatrixN <- round(disimMatrixN, 2)
  
  print("Workflow dissimilarity matrix:")
  print(disimMatrix)
  print("Workflow dissimilarity matrix (normalized):")
  print(disimMatrixN)
  
  par(mfrow=c(1,2))
  plot(hclust(as.dist(disimMatrix)))
  plot(hclust(as.dist(disimMatrixN)))
}

extractSentenxeFeatures <- function() {
  measuresDF <- read.csv(paste0(inputData, "what_intents.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  adjDF <- read.csv(paste0(inputData, "what_adjectives.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  supportsDF <- read.csv(paste0(inputData, "what_objects.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  
  qStatsDF <- data.frame(qid=NA, measure=NA, adjCount=NA, sprtCount=NA, hasAdj=NA, hasSprt=NA)
  
  for(rowIndex in 1:nrow(measuresDF)) {
    row <- measuresDF[rowIndex, ]
    
    adjCount <- 0
    sprtCount <- 0
    
    hasAdj <- 0
    hasSprt <- 0
    
    qAdjDF <- subset(adjDF, adjDF$qid == row$qid)
    if (nrow(qAdjDF)> 0) {
      adjCount <- nrow(qAdjDF) - 1
      hasAdj <- 1
    }
    
    qSprtDF <- subset(supportsDF, supportsDF$qid == row$qid)
    if (nrow(qSprtDF)> 0) {
      sprtCount <- nrow(qSprtDF) - 1
      hasSprt <- 1
    }
    
    qStatsDF <- rbind(qStatsDF, data.frame(qid=row$qid, measure=row$intent
                                           , adjCount=adjCount, sprtCount=sprtCount
                                           , hasAdj=hasAdj, hasSprt=hasSprt))
  }
  
  qStatsDF <- qStatsDF[-1,]
  
  ##############################################################################
  
  wfs <- read.csv(paste0(inputData, "serial_wfs.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  wfs <- cbind(wfs, serialC=gsub("|", "", wfs$serial, fixed=TRUE))
  wfs$serialC <- as.character(wfs$serialC)
  
  pattern <- " across | alon g| among | around | at | based on | based upon | between | by | for | from | given | in | inside | of | on | over | per | since | that | to | with | within "
  phraseCountVC <- numeric()
  for(rowIndex in 1:nrow(wfs)) {
    phraseCount <- length(str_extract_all(wfs$question[rowIndex], pattern)[[1]])
    phraseCountVC <- c(phraseCountVC, phraseCount)
  }
  qStatsDF <- merge(qStatsDF, data.frame(qid=wfs$qid, phraseCount=phraseCountVC))
  
  qStatsDF <- merge(qStatsDF, wfs[, c("qid","serial","serialC")])
  
  qStatsDF <- cbind(qStatsDF, opCount=nchar(qStatsDF$serialC))
  qStatsDF <- cbind(qStatsDF, cycleCount=str_count(qStatsDF$serial, "\\|"))
  
  print(qStatsDF)
  
  ##############################################################################
  
  tools <- read.csv(paste0(inputData, "tools.csv"), sep=";", header=TRUE, stringsAsFactors=FALSE)
  
  for(rowIndex in 1:nrow(tools)){
    qStatsDF <- cbind(qStatsDF, temp=0)
    colnames(qStatsDF)[colnames(qStatsDF)=="temp"] <- paste0("T",tools$letter[rowIndex])
  }
  
  for(rowIndex in 1:nrow(qStatsDF)){
    ops <- strsplit(qStatsDF$serialC[rowIndex], "")[[1]]
    
    for(char in ops) {
      qStatsDF[rowIndex, paste0("T",char)] <- 1
    }
  }
  
  print(qStatsDF)
  
  ##############################################################################
  
  # [SC] calculating co-occurrence matrix
  # [SC] for example, co-occurrence of 2 between measure i and tool j means that j was used in 2 workflows estimating i 
  # [SC]    - (does not account how many times j was used in each workflow of i)
  coocDF <- NULL
  for(rowIndex in 1:nrow(tools)){
    formula <- paste0("T",tools$letter[rowIndex], " ~ measure")
    tempDF <- aggregate(as.formula(formula), data=qStatsDF, sum)
    
    if (is.null(coocDF)){ coocDF <- tempDF }
    else { coocDF <- merge(coocDF, tempDF) }
  }
  coocDF <- coocDF[order(coocDF$measure),]
  
  # [SC] co-occurence matrix normalized relative to the total number of workflows per measure
  mFreqDF <- data.frame(measure=qStatsDF$measure, freq=1)
  mFreqDF <- aggregate(freq ~ measure, data=mFreqDF, sum)
  mFreqDF <- mFreqDF[order(mFreqDF$measure),]
  normCoocDF <- coocDF
  for(rowIndex in 1:nrow(tools)){
    normCoocDF[,paste0("T",tools$letter[rowIndex])] <- round(normCoocDF[,paste0("T",tools$letter[rowIndex])]/mFreqDF$freq, 2)
  }
  
  # [SC] making data.frames compatible with matrix type
  rownames(coocDF) <- coocDF$measure
  coocDF = coocDF[,!(colnames(coocDF) %in% c("measure"))]
  rownames(normCoocDF) <- normCoocDF$measure
  normCoocDF = normCoocDF[,!(colnames(normCoocDF) %in% c("measure"))]
  
  print("Measure - tool co-occurrence matrix:")
  print(coocDF)
  print("Measure - tool co-occurrence matrix (normalized):")
  print(normCoocDF)
  
  # [SC] plotting the co-occurence matrix
  longData<-melt(as.matrix(coocDF))
  longData<-longData[longData$value!=0,]
  print(ggplot(longData, aes(x = Var1, y = Var2)) +
          geom_raster(aes(fill=value)) +
          labs(x="Measure", y="Tool", title="Tool - Measure Co-occurence") +
          theme_bw() + theme(axis.text.x=element_text(size=9, angle=90, vjust=0.3),
                             axis.text.y=element_text(size=9),
                             plot.title=element_text(size=11)))
  
  longData<-melt(as.matrix(normCoocDF))
  longData<-longData[longData$value!=0,]
  print(ggplot(longData, aes(x = Var1, y = Var2)) +
          geom_raster(aes(fill=value)) +
          labs(x="Measure", y="Tool", title="Tool - Measure Co-occurence (normalized)") +
          theme_bw() + theme(axis.text.x=element_text(size=9, angle=90, vjust=0.3),
                             axis.text.y=element_text(size=9),
                             plot.title=element_text(size=11)))
  
  ##############################################################################
  
  # [SC] calculating TF-IDF matrix: how specific is a tool to a particular measure
  #
  # [SC] Term Frequency: the number of times that term t occurs in document d
  # [SC]  - in our context, it is the number of workflows with tool t for measure d
  # [SC] Inverse Document Frequency: dividing the total number of documents by the number of documents containing the term, and then taking the logarithm of that quotient
  # [SC]  - in our context, dividing the total number of unique measures by the number of measures co-occuring with the particular tool 
  
  dfIdfDF <- coocDF
  dfIdfDF[] <- NA
  
  for(colIndex in 1:ncol(coocDF)){
    for(rowIndex in 1:nrow(coocDF)){
      vc <- as.vector(coocDF[,colIndex])
      idf <- log(nrow(coocDF)/(1+length(vc[vc > 0])))
      # [TODO] not sure this normalization is valid
      #tf <- coocDF[rowIndex, colIndex]/sum(coocDF[rowIndex,])
      tf <- coocDF[rowIndex, colIndex]
      
      dfIdfDF[rowIndex, colIndex] <- round(tf * idf, 2)
    }
  }
  
  print("TF-IDF matrix for tools")
  print(dfIdfDF)
  
  longData<-melt(as.matrix(dfIdfDF))
  longData<-longData[longData$value!=0,]
  print(ggplot(longData, aes(x = Var1, y = Var2)) +
          geom_raster(aes(fill=value)) +
          labs(x="Measure", y="Tool", title="Tool - Measure TF-IDF") +
          theme_bw() + theme(axis.text.x=element_text(size=9, angle=90, vjust=0.3),
                             axis.text.y=element_text(size=9),
                             plot.title=element_text(size=11)))
  
  ##############################################################################
  
  # [SC] regression analysis
  lmRes <- lm(opCount ~ measure, data=qStatsDF)
  print(summary(lmRes))
  
  lmRes <- lm(cycleCount ~ measure, data=qStatsDF)
  print(summary(lmRes))
  
  qStatsDF$phraseCount <- qStatsDF$phraseCount - min(qStatsDF$phraseCount)
  
  lmRes <- lm(opCount ~ phraseCount, data=qStatsDF)
  print(summary(lmRes))
  
  lmRes <- lm(cycleCount ~ phraseCount, data=qStatsDF)
  print(summary(lmRes))
  
  ##############################################################################
  # [SC] n-gram analysis
  
  minLength <- 3
  allNGramsVC <- character()
  for(rowIndex in 1:nrow(wfs)){
    serial <- wfs$serial[rowIndex]
    serialLength <- nchar(serial)

    if (serialLength < minLength){
      next
    }
    
    # [SC] adding space between characters, otherwise get.ngrams does not work
    tempSerial <- substring(serial, 1, 1)
    for(index in 2:nchar(serial)){
      tempSerial <- paste(tempSerial, substring(serial, index, index))
    }
    
    # [SC] detect all ngrams and store in a vector
    for(index in minLength:serialLength){
      ng <- ngram(tempSerial, n=index, sep=" ")
      allNGramsVC <- c(allNGramsVC, get.ngrams(ng))
    }
  }
  
  # [SC] convert ngram vector to data.frame and calculate frequency
  ngramDF <- data.frame(ngram=allNGramsVC, freq=1, stringsAsFactors=FALSE)
  ngramDF <- aggregate(freq ~ ngram, data=ngramDF, sum)
  ngramDF <- subset(ngramDF, ngramDF$freq > 2)
  rowsToRemove <- numeric()
  for(rowIndex in 1:nrow(ngramDF)){
    mygram <- ngramDF$ngram[rowIndex]
    
    # [SC] remove unnecessary ngrams
    if (substring(mygram, 1, 1) == "|"){
      rowsToRemove <- c(rowsToRemove, rowIndex)
    }
    else if (substring(mygram, nchar(mygram), nchar(mygram)) != "|") {
      rowsToRemove <- c(rowsToRemove, rowIndex)
    }
  }
  ngramDF <- ngramDF[-rowsToRemove,]
  ngramDF <- ngramDF[order(ngramDF$freq, decreasing=TRUE),]
  print(ngramDF)
  
}

measureInterWfSimilarity()
extractSentenxeFeatures()