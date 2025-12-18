# Análise de Resultados

## Resumo Executivo

Este estudo analisa o comportamento de pré-pagamento de hipotecas durante a pandemia de COVID-19 usando dados do Freddie Mac (2016-2023). Os resultados indicam que o pré-pagamento **aumentou significativamente durante o COVID** (4.3x), e que **o aumento foi MAIOR do que seria esperado considerando apenas o incentivo de refinanciamento** (3.1x observado vs 1.8x esperado). O período COVID teve um efeito positivo adicional além da queda nas taxas de juros.

## Dados

- **400,000 empréstimos únicos**
- **16.8 milhões** de observações loan-month
- **186,833** eventos de pré-pagamento

### Taxas de Mercado por Período

| Período | Range | Média |
|---------|-------|-------|
| Pré-COVID (2016 - fev/2020) | 3.44% - 4.87% | 4.01% |
| COVID (mar/2020 - dez/2021) | 2.68% - 3.45% | 2.99% |
| Pós-COVID (2022+) | 3.44% - 7.62% | 6.36% |

## Modelos

### M0: Baseline (sem termo COVID)
```
logit(p) = α + β·incentivo + γ·idade + δ·credit_score + ε·ltv
```

### M1: Com termos COVID
```
logit(p) = α + β·incentivo + γ·idade + δ·credit_score + ε·ltv + η·covid + θ·(covid × incentivo)
```

## Resultados dos Modelos

### Performance

| Modelo | Val Log Loss |
|--------|--------------|
| M0 | 0.1224 |
| M1 | **0.1194** |

### Teste de Razão de Verossimilhança (LRT)

| Estatística | Valor |
|-------------|-------|
| Log-Likelihood M0 | -661,842 |
| Log-Likelihood M1 | -657,633 |
| LR Statistic | **8,418** |
| Graus de Liberdade | 2 |
| P-value | **< 1e-10** |

**Conclusão**: Os termos COVID são estatisticamente significativos.

### Coeficientes do M1

| Termo | Estimativa | Interpretação |
|-------|------------|---------------|
| incentivo | +0.68 | Efeito base do incentivo de juros |
| **covid** | **+0.76** | Aumento no nível base durante COVID |
| **covid_incentive** | **-0.23** | Redução na sensibilidade ao incentivo |

## Interpretação Principal

### Simulação do Efeito COVID

Para entender o efeito líquido, simulamos a probabilidade de prepayment:

| Cenário | Incentivo | COVID | Prob. Prepay |
|---------|-----------|-------|--------------|
| Pré-COVID típico | 0.05% | 0 | 0.43% |
| Hipotético (só incentivo) | 0.89% | 0 | 0.77% |
| **COVID real** | 0.89% | 1 | **1.33%** |

### Conclusão da Simulação:

- **Esperado só pelo incentivo**: 1.8x aumento
- **Observado com COVID**: 3.1x aumento

> **O pré-pagamento durante o COVID foi MAIOR do que seria esperado considerando apenas o incentivo de refinanciamento.**

O coeficiente `covid = +0.76` (positivo) **domina** o efeito de `covid_incentive = -0.23` (negativo), resultando em **aumento líquido**.

### Decomposição dos efeitos:

1. **covid = +0.76**: Shift positivo no nível base (facilidade de refinanciar, políticas de estímulo, digitalização)
2. **covid_incentive = -0.23**: Redução na sensibilidade marginal ao incentivo (possível saturação ou heterogeneidade)

### Possíveis explicações para o AUMENTO além do incentivo:

1. **Políticas de estímulo** → facilitação de refinanciamento
2. **Digitalização acelerada** → processos online mais rápidos
3. **Renda disponível** → menos gastos com viagens/lazer → mais recursos para custos de fechamento
4. **Medo de aumento futuro** → urgência em "travar" taxas baixas

## Contexto Histórico: Modelagem de Pré-Pagamento

### Origem dos Modelos de Prepayment (1980s)

O mercado de títulos lastreados em hipotecas (MBS) nos EUA cresceu rapidamente nos anos 1980 após a criação do mercado secundário pela Ginnie Mae, Fannie Mae e Freddie Mac. O principal desafio era **precificar o risco de pré-pagamento**: quando taxas de juros caem, mutuários refinanciam, e investidores recebem o principal de volta mais cedo que o esperado.

### O Modelo Richard & Roll (1989)

| Aspecto | Detalhes |
|---------|----------|
| **Autores** | Scott F. Richard e Richard Roll |
| **Instituição** | Goldman Sachs |
| **Publicação** | "Prepayments on Fixed-Rate Mortgage-Backed Securities" (1989) |
| **Problema** | Prever taxas de pré-pagamento para precificação de MBS |

#### Inovações do Modelo:

1. **Incentivo de Refinanciamento**: Razão entre taxa do contrato e taxa de mercado
2. **Seasoning (Idade)**: Empréstimos novos prepagam menos (custos de transação recentes)
3. **Burnout**: Empréstimos que "sobrevivem" períodos de taxas baixas têm menor probabilidade futura de prepagar (os mais sensíveis já saíram)
4. **Sazonalidade**: Picos no verão (mudanças de casa)

#### Legado:

O modelo Richard & Roll estabeleceu o paradigma de **forma reduzida** (reduced-form): em vez de modelar a decisão ótima do mutuário, usa-se regressão sobre comportamento histórico. Este paradigma ainda domina a indústria (Fannie Mae, Freddie Mac, bancos de investimento).

### Evolução para Logit Discreto

Nos anos 1990, pesquisadores adaptaram o framework para **regressão logística discreta**:

- Cada mês-empréstimo é uma observação binária (prepagou ou não)
- Permite inclusão direta de covariáveis time-varying
- Computacionalmente eficiente para grandes bases de dados

Referências importantes:
- **Schwartz & Torous (1989)**: "Prepayment and the Valuation of Mortgage-Backed Securities"
- **Deng, Quigley & Van Order (2000)**: "Mortgage Terminations, Heterogeneity and the Exercise of Mortgage Options"

## Escolha Metodológica: Por que Logit e não Cox?

### Comparação: Cox vs Regressão Logística Discreta

| Aspecto | Cox Proportional Hazards | Logit Discreto (usado) |
|---------|--------------------------|------------------------|
| **Tempo** | Contínuo | Discreto (mensal) |
| **Baseline hazard** | Não-paramétrico | Absorvido no intercepto |
| **Covariáveis time-varying** | Complexo de implementar | Simples (cada mês = 1 obs) |
| **Escala** | Lento para milhões de obs | Rápido |
| **Interpretação** | Hazard ratios | Odds ratios ≈ hazard ratios* |

*Quando a probabilidade é baixa (~1% ao mês), odds ratio ≈ hazard ratio.

### Justificativas para Logit Discreto:

1. **Dados naturalmente discretos**: Observações são mensais, não contínuas
2. **Covariáveis time-varying**: Taxa de mercado, incentivo e idade mudam a cada mês
3. **Escala computacional**: 16.8 milhões de observações - Cox seria muito lento
4. **Prática da indústria**: Fannie Mae e Freddie Mac usam modelos logit discretos

### Limitação do Logit:

O modelo assume que cada observação mês-empréstimo é **independente**, ignorando correlação intra-empréstimo. Modelos mais sofisticados incluiriam:
- **Fragilidade** (random effects por empréstimo)
- **GEE** (Generalized Estimating Equations)
- **Modelo de duração paramétrico** (Weibull, log-logistic)

## Limitações Metodológicas

### Ausência de Contrafactual Adequado

| Período | Meses com taxa < 3.5% |
|---------|----------------------|
| Pré-COVID | **apenas 5 meses** |
| COVID | 22 meses |
| Pós-COVID | ~0 meses |

**Problema**: Não existe na amostra um período com taxas de juros semelhantes (~3%) **sem** a presença do COVID. Isso significa que o coeficiente `covid_incentive` pode estar capturando:

1. ✅ Fricções reais causadas pelo COVID
2. ⚠️ **OU** não-linearidade no efeito do incentivo em taxas extremamente baixas
3. ⚠️ **OU** saturação do mercado de refinanciamento

### Alternativas para validação (não implementadas)

- Dados históricos (2008-2012) com taxas baixas pré-crise
- Modelo com splines para capturar não-linearidade
- Diff-in-diff com região/segmento menos afetado

## Conclusão

A análise demonstra que os termos COVID são **estatisticamente significativos** (p < 1e-10) e melhoram a previsão do modelo. A interpretação de que o COVID causou "fricções" no mercado de refinanciamento é **plausível**, mas a **identificação causal é limitada** pela ausência de um contrafactual adequado na amostra.
