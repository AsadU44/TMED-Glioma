library(limma)
library(edgeR)
library(Glimma)
library(AnnotationDbi)
library(org.Hs.eg.db)
library(ggplot2)
library(Homo.sapiens)
library(RColorBrewer)
library(EnhancedVolcano)
library(pheatmap)
library(dplyr)

setwd('E:/Differential Gene Expression/LIMMA Voom')
counts<- read.csv('Raw read count.csv', row.names = 1)

#Initial assessment
#Clustering
htree<- hclust(dist(t(counts)), method = 'average')
plot(htree)

#PCA Plot
pca <- prcomp(t(counts))
pca.dat <- pca$x
pca.var <- pca$sdevˆ2
pca.var.percent <- round(pca.var/sum(pca.var)*100, digits = 2)
pca.dat <- as.data.frame(pca.dat)
ggplot(pca.dat, aes(PC1, PC2)) +
  geom_point() +
  geom_text(label = rownames(pca.dat)) +
  labs(x = paste0('PC1: ', pca.var.percent[1], ' %'),
       y = paste0('PC2: ', pca.var.percent[2], ' %')) + theme_bw()

#Remove samples based on requirement

#Prepare DGElist and assign groups
DGE<- DGEList(counts)
group<- as.factor(rep(c('Healthy', 'COVID-19'), c(5,10)))
severity<-as.factor(rep(c('HT', 'CP', 'BC'), c(5,5,5)))
DGE$samples$group<-group
DGE$samples$severity<-severity

#Removing low expressed genes
table(rowSums(DGE$counts==0)==15) 

# 15 samples in our datasets. We can see aroun 12500 genes habe a count of zero.
# Let's remove those
keep <- filterByExpr(DGE, group=group)
DGE_filtered<- DGE[keep,, keep.lib.sizes=FALSE]
dim(DGE_filtered) #Around 14000 genes remain after filtering

###############################################################################
#Transforming data from the raw scale
cpm <- cpm(DGE)
lcpm <- cpm(DGE, log=TRUE)

L <- mean(DGE$samples$lib.size) * 1e-6
M <- median(DGE$samples$lib.size) * 1e-6
c(L, M)

#Preparing density plot
par(mfrow=c(1,2))
lcpm.cutoff <- log2(10/M + 2/L)
nsamples <- ncol(DGE)
col <- brewer.pal(nsamples, "Paired")
samplenames<- as.character(colnames(DGE))

#Before fitering
lcpm<- lcpm #using lcpm counted before filtering
plot(density(lcpm[,1]), col=col[1], lwd=2, 
ylim=c(0,0.8), las=2, main="", xlab="")
title(main="A. Raw data", xlab="Log-cpm")
abline(v=lcpm.cutoff, lty=3)
for (i in 2:nsamples){
  den <- density(lcpm[,i])
  lines(den$x, den$y, col=col[i], lwd=2)
}
legend("topright", samplenames, text.col=col, bty="n")

#After filtering
lcpm2 <- cpm(DGE_filtered, log=TRUE) #calculating new lcpm value from filtered DGE
plot(density(lcpm2[,1]), col=col[1], lwd=2, 
ylim=c(0,0.8), las=2, main="", xlab="")
title(main="B. Filtered data", xlab="Log-cpm")
abline(v=lcpm.cutoff, lty=3)
for (i in 2:nsamples){
  den <- density(lcpm2[,i])
  lines(den$x, den$y, col=col[i], lwd=2)
}
legend("topright", samplenames, text.col=col, bty="n")


# Clustering of samples
par(mfrow=c(1,2))
#Plotting according to group
col.group <- group
levels(col.group) <-  brewer.pal(nlevels(col.group), "Set1")
col.group <- as.character(col.group)
plotMDS(lcpm, labels=group, col=col.group)
title(main="A. MDS Plot Accoding To Groups")

#Plotting according toseverity 
col.severity <- severity
levels(col.severity) <-  brewer.pal(nlevels(col.severity), "Set2")
col.severity <- as.character(col.severity)
plotMDS(lcpm, labels=severity, col=col.severity, dim=c(3,4))
title(main="B. MDS Plot Accoding To Severity")

#Online
glMDSPlot(lcpm, labels=paste(group, severity, sep="_"), 
          groups=norm.counts$samples[,c(1,4)], launch=FALSE)

###############################################################################
# TMM Normalization and design and contrast
norm.counts<- calcNormFactors(DGE_filtered, method = 'TMM')
norm.counts$samples$norm.factors

#Save normalized counts
TMM_Counts<- data.frame(cpm(norm.counts))
write.csv(TMM_Counts, 'normalized_counts.csv')

design <- model.matrix(~0+severity+group) #Change order to swap intercept
colnames(design) <- gsub("severity", "", colnames(design))
design

contr.matrix <- makeContrasts(
  CPvsHT = CP-HT, 
  BCvsHT = BC-HT, 
  CPvsBC = CP-BC, 
  levels = colnames(design))
contr.matrix

#Setting voom object and performing DEG analysis
par(mfrow=c(1,2))
voom <- voom(norm.counts, design, plot=TRUE)

vfit <- lmFit(voom, design)
vfit <- contrasts.fit(vfit, contrasts=contr.matrix)
efit <- eBayes(vfit)

################################################################################
plotSA(efit, main="Final model: Mean-variance trend")

par(mfrow=c(1,2))
par(mar=c(7,3,3,2))
boxplot(lcpm2, xlab="", ylab="Log2 counts per million",
        las=3,main="Before Normalization", col=col)
abline(h=median(lcpm2),col="red")

boxplot(voom$E, xlab="", ylab="Log2 counts per million",
        las=2,main="After Normalization", col=col)
abline(h=median(voom$E),col="red")
graphics.off()

#Check expression of single gene in all groups
stripchart(voom$E["ENSG00000109743",]~severity,vertical=TRUE,las=2,
           cex.axis=0.8,pch=16,cex=1.3,col=col,method="jitter",xlab='Group',
           ylab= 'Log2 Expression',main="BST1")

DEGs<- topTreat(efit, n=Inf)
DEGs$symbol<- mapIds(org.Hs.eg.db, keys=rownames(DEGs), 
                       keytype = "ENSEMBL", column = "SYMBOL")
par(mar=c(2,2,2,2))
EnhancedVolcano(DEGs,
                lab = DEGs$symbol,
                x =   'logFC',
                y = 'adj.P.Val',
                pCutoff = 0.05,
                FCcutoff = 1,
                pointSize = 3.0,
                labSize = 6.0,
                border = 'full')

################################################################################
# Analyze
sum.fit<- decideTests(efit, lfc = 1)
summary(sum.fit)

#Check individual group
CPvsHT <- topTable(efit, coef=1, n=Inf, lfc = 1, p.value = 0.05) 
BCvsHT <- topTable(efit, coef=2, n=Inf, lfc = 1, p.value = 0.05)
CPvsBC <- topTable(efit, coef=3, n=Inf, lfc = 1, p.value = 0.05)
#Use topTreat in case topTable doesn't work

#Annotation
CPvsHT$symbol<- mapIds(org.Hs.eg.db, keys=rownames(CPvsHT), 
                keytype = "ENSEMBL", column = "SYMBOL")
BCvsHT$symbol<- mapIds(org.Hs.eg.db, keys=rownames(BCvsHT), 
                       keytype = "ENSEMBL", column = "SYMBOL")
CPvsBC$symbol<- mapIds(org.Hs.eg.db, keys=rownames(CPvsBC), 
                       keytype = "ENSEMBL", column = "SYMBOL")
###############################################################################



