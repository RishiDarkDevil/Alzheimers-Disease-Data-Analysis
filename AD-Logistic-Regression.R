library(tidyverse)
library(ggplot2)
library(ggpubr)
library(GGally)
library(e1071)
library(caret)
library(modelr)
library(yardstick)
library(jtools)

# Importing the Data
data <- read_csv("AD.csv")

# Prepocessing
conv.to.fac <- colnames(data)[c(1,3, 8:16, 19)]
# data <- data %>%
#   mutate(DX_bl = ifelse(DX_bl == 0, "No", "Yes"))
# data[conv.to.fac] <- lapply(data[conv.to.fac], as.factor)

data

# EDA
data %>%
  ggplot(aes(x = DX_bl, y = AGE, fill = DX_bl)) + 
  geom_boxplot()

data %>%
  ggplot(aes(x = DX_bl, y = PTEDUCAT, fill = DX_bl)) + 
  geom_boxplot()

data %>%
  ggplot(aes(x = DX_bl, y = FDG, fill = DX_bl)) + 
  geom_boxplot()

data %>%
  ggplot(aes(x = DX_bl, y = AV45, fill = DX_bl)) + 
  geom_boxplot()

data %>%
  ggplot(aes(x = DX_bl, y = HippoNV, fill = DX_bl)) + 
  geom_boxplot()

# Wrangle
data1 <- data
data1[conv.to.fac] <- lapply(data1[conv.to.fac], as.factor)

data.long <- data1 %>%
  select(-c(e2_1, e4_1, rs3818361, rs744373, rs11136000, rs610932, rs3851179, rs3764650, rs3865444, ID, PTGENDER, PTEDUCAT)) %>%
  gather('AGE', 'FDG', 'AV45', 'HippoNV', 'MMSCORE', 'TOTAL13', key = "cont.preds", value = "values")

# EDA - Imp Plot
data.long %>%
  ggplot(aes(x= cont.preds, y = values, fill = DX_bl)) +
  geom_boxplot()+
  facet_wrap(~cont.preds, scales = "free")

# Wrangle
data %>%
  gather(e2_1, e4_1, rs3818361, rs744373, rs11136000, rs610932, rs3851179, rs3764650, rs3865444, key = 'gene', value = 'indicator') %>%
  select(DX_bl, gene, indicator) %>%
  group_by(DX_bl, gene) %>%
  tally(indicator == 1) %>% # Counts Number of 1's in DX_bl=1 & 0
  spread(gene, n)

data %>%
  ggpairs(columns = c("AGE", "FDG", "AV45", "HippoNV", "MMSCORE", "TOTAL13"), aes(color = as.factor(DX_bl)), progress = FALSE)

data %>%
  ggplot(aes(MMSCORE, FDG, color = DX_bl)) + 
  geom_point()

# Model
logit.AD.full <- glm(DX_bl~.-ID, data = data, family = "binomial")
summary(logit.AD.full)
summ(logit.AD.full)

logit.AD.sig <- step(logit.AD.full, direction = "both", trace = 0)
summary(logit.AD.sig)
summ(logit.AD.sig)

anova.mods <- anova(logit.AD.full, logit.AD.sig, test = "LRT")
summary(anova.mods)

# Visualizing Model
mods <- plot_summs(logit.AD.full, logit.AD.sig, model.names = c("Full Model", "Reduced Model"), ci_level = .99, plot.distributions = TRUE, rescale.distributions = TRUE) +
  theme(legend.position = "bottom") + ggtitle("Full Model & Reduced Model")

format_reg_table <- function(model, digs = 2){
  mod <- tidy(model, conf.level = .99, conf.int = TRUE) %>%
    mutate(across(where(is.numeric), ~ round(., digits = digs)))
  mod <- mod %>%
    mutate(estimate = as.character(estimate)) %>%
    mutate(estimate = paste(paste(estimate, ifelse(p.value < 0.05, "*",""), ifelse(p.value < 0.01, "*",""), ifelse(p.value < 0.001, "*",""), sep = ""), paste("[", conf.low, ", ", conf.high, "]", sep = ""), sep = "\n"))
  mod <- mod %>%
    select(term, estimate)
  return(mod)
}

mod.full.table <- format_reg_table(logit.AD.full)
mod.sig.table <- format_reg_table(logit.AD.sig)

mod.tables <- mod.full.table %>%
  full_join(mod.sig.table, by = "term") %>%
  rename("Full Model" = "estimate.x","Reduced Model" =  "estimate.y")

mods.tab <- ggtexttable(mod.tables, theme = ttheme("mOrangeWhite"), rows= NULL) %>%
  tab_add_title("Fitted Models", face = "bold")

# Visualizing Models
ggarrange(mods, mods.tab, ncol = 2, widths = c(7,3))

predict.data <- data %>%
  add_predictions(logit.AD.full, var = "full.mod.pred") %>%
  add_predictions(logit.AD.sig, var = "sig.mod.pred")

predict.data <- predict.data %>%
  mutate(full.mod.probs = exp(full.mod.pred)/(1+exp(full.mod.pred)), sig.mod.probs = exp(sig.mod.pred)/(1+exp(sig.mod.pred)),
         full.mod.class = as.numeric(full.mod.probs>0.5), sig.mod.class = as.numeric(sig.mod.probs>0.5))

predict.data %>%
  select(DX_bl, full.mod.class, sig.mod.class)

predict.data.long <- predict.data %>%
  gather(full.mod.probs, sig.mod.probs, key = "model", value = "probs")

# See Class Separation given by Models
predict.data.long %>%
  mutate(DX_bl = as.factor(DX_bl)) %>%
  ggplot(aes(DX_bl, probs, fill = model)) +
  geom_violin()

conf.mat.full <- confusionMatrix(table(predict.data$full.mod.class, predict.data$DX_bl))  
conf.mat.sig <- confusionMatrix(table(predict.data$sig.mod.class, predict.data$DX_bl))  

mod.full.perf <- ggtexttable(tibble(Criteria= c("Accuracy", "Sensitivity", "Specificity"), Values=c(conf.mat.full$overall[1], conf.mat.full$byClass[1:2])), theme = ttheme("mBlueWhite")) %>%
  tab_add_title("Full Model", face = "bold")
mod.sig.perf <- ggtexttable(tibble(Criteria= c("Accuracy", "Sensitivity", "Specificity"), Values=c(conf.mat.sig$overall[1], conf.mat.sig$byClass[1:2])), theme = ttheme("mVioletWhite")) %>%
  tab_add_title("Reduced Model", face = "bold")


predict.data <- predict.data %>%
  mutate(DX_bl=as.factor(DX_bl), full.mod.class=as.factor(full.mod.class), sig.mod.class=as.factor(sig.mod.class))

cm <- conf_mat(predict.data, DX_bl, full.mod.class)
cm.full <- autoplot(cm, type = "heatmap") + 
  scale_fill_gradient(low = "#D6EAF8", high = "#2E86C1")
cm.full <- annotate_figure(cm.full, top = text_grob("Confusion Matrix for Full Model", face = "bold", size = 16))

cm <- conf_mat(predict.data, DX_bl, sig.mod.class)
cm.sig <- autoplot(cm, type = "heatmap") + 
  scale_fill_gradient(low = "#D6EAF8", high = "#2E86C1")
cm.sig <- annotate_figure(cm.sig, top = text_grob("Confusion Matrix for Reduced Model", face = "bold", size = 16))

# Confusion Matrix Plot
ggarrange(cm.full, mod.full.perf, cm.sig, mod.sig.perf, widths = c(6,4))
