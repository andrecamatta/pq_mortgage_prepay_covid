# Análise de Resultados

## Resumo Executivo

Este estudo analisa o comportamento de pré-pagamento de hipotecas durante a pandemia de COVID-19 usando dados do Freddie Mac (2016-2023). Os resultados indicam que, embora o pré-pagamento tenha aumentado significativamente durante o COVID, **o aumento foi menor do que seria esperado considerando apenas o efeito mecânico da queda nas taxas de juros**.

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

O coeficiente negativo de `covid_incentive` (-0.23) indica que:

> **O pré-pagamento durante o COVID foi menor do que seria esperado se considerássemos apenas o efeito mecânico da queda nas taxas de juros.**

### Decomposição do efeito do incentivo:

- **Fora do COVID**: β = 0.68
- **Durante COVID**: β = 0.68 - 0.23 = **0.45** (33% menor)

### Possíveis explicações para a fricção:

1. **Incerteza no emprego** → famílias evitaram refinanciar
2. **Restrições de liquidez** → dificuldade em pagar custos de fechamento
3. **Aperto de crédito** → bancos mais conservadores
4. **Atrasos operacionais** → escritórios e cartórios fechados

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
