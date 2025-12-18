# Análise de Pré-Pagamento Hipotecário durante COVID-19

Este projeto analisa como a pandemia de COVID-19 afetou o comportamento de pré-pagamento de hipotecas nos EUA, usando dados do Freddie Mac (2016-2023). A análise revela um **mercado de duas velocidades**: famílias em residências primárias impulsionaram um boom histórico, enquanto investidores retraíram drasticamente devido a moratórias de despejo.

## Principais Descobertas

- **Boom Desigual**: Taxa de prepay aumentou 4.3x durante COVID, mas o efeito foi 100% concentrado em residências primárias (+0.35% excesso), compensando retração de investidores (-2.20% excesso)
- **Freio Comportamental**: Inércia (Sunk Cost) em empréstimos antigos reduziu o boom potencial em 44%
- **Drivers Identificados**: WFH/Migração (validado por geografia), Eviction Moratorium (validado por ocupação), Digitalização (literatura)

Para análise completa, veja [RESULTADOS.md](RESULTADOS.md).

## Estrutura do Projeto

### Pipeline de Análise

```
01_download_or_load_data.jl  → Carrega dados do Freddie Mac
02_build_panel.jl            → Constrói painel loan-month (16.8M obs)
03_fit_models.jl             → Estima modelos M0, M1, M2 (regressão logística)
04_plots.jl                  → Gráficos principais (A-D)
05_eda.jl                    → Análise exploratória adicional
06_behavioral_plots.jl       → Visualizações de vieses comportamentais
07_quantify_biases.jl        → Quantifica impacto contrafactual (-44%)
08_validate_drivers.jl       → Validação geográfica/ocupação
09_exploratory_plots.jl      → Plots E-F (divergências WFH/Eviction)
```

### Modelos Estimados

| Modelo | Especificação | LRT vs M0 | Achado Principal |
|--------|---------------|-----------|------------------|
| **M0** | Baseline (incentive + controls) | - | R² padrão |
| **M1** | + COVID dummy + interação incentivo | p < 1e-10 | Efeito COVID significativo |
| **M2** | + COVID×loan_age + COVID×credit_score | p < 1e-10 | **Inércia em empréstimos antigos** |

**M2 é o modelo final**, testando vieses comportamentais:
- `COVID × loan_age` (negativo): Sunk-cost fortalecido durante pandemia
- `COVID × credit_score` (não significativo): Overconfidence não confirmado

## Requisitos e Setup

### Sistema
- Julia 1.9+
- 2GB RAM (construção de painel)
- 16GB disco (dados raw)

### Instalação

```bash
# Clone e instale dependências
git clone <repo-url>
cd pq_mortgage_prepay_covid
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Obtenção dos Dados

1. Registre-se em [Freddie Mac Single Family Loan-Level Dataset](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset)
2. Baixe o **Sample Dataset** (não o dataset completo) para 2016-2023
3. Estruture os arquivos:
   ```
   data/raw/freddiemac/orig/sample_orig_2016.txt
   data/raw/freddiemac/orig/sample_orig_2017.txt
   ...
   data/raw/freddiemac/svcg/sample_svcg_2016.txt
   data/raw/freddiemac/svcg/sample_svcg_2017.txt
   ...
   ```

## Execução do Pipeline

### Opção 1: Pipeline Completo

```bash
# Executar tudo sequencialmente
julia --project=. 01_download_or_load_data.jl
julia --project=. 02_build_panel.jl
julia --project=. 03_fit_models.jl
julia --project=. 04_plots.jl
julia --project=. 07_quantify_biases.jl
julia --project=. 08_validate_drivers.jl
julia --project=. 09_exploratory_plots.jl
```

### Opção 2: Análise Específica

```bash
# Apenas modelos (assume painel já existe)
julia --project=. 03_fit_models.jl

# Apenas validação de drivers
julia --project=. 08_validate_drivers.jl
```

## Artefatos Gerados

### Dados Processados (`data/processed/`)
- `loan_month_panel.arrow`: Painel completo (16.8M linhas)
- `aggregate_series.csv`: Séries temporais mensais

### Resultados (`data/results/`)
- `m0_coefficients.csv`, `m1_coefficients.csv`, `m2_coefficients.csv`
- `model_metrics.csv`: Log loss por modelo
- `lrt_results.csv`: Testes de razão de verossimilhança
- `quantification_results.csv`: Quantificação do drag comportamental
- `validation_regional.csv`, `validation_occupancy.csv`

### Gráficos (`data/plots/`)
- **A-D**: Análise principal (prepay vs market rate, observado vs previsto, coeficientes, interação)
- **E-F**: Validação de drivers (divergência geográfica, divergência por ocupação)
- **behavioral_***: Análises comportamentais detalhadas
- **eda_***: Exploratórias adicionais

## Metodologia

### Por Que Regressão Logística (não Cox)?

| Aspecto | Cox Survival | Logit Discreto (usado) |
|---------|--------------|------------------------|
| Dados | Contínuo | Mensal (natural) |
| Covariáveis time-varying | Complexo | Simples |
| Escala | Lento (16M obs) | Rápido |
| Indústria | Raro | Padrão (Fannie/Freddie) |

### Limitações

1. **Identificação Causal**: Termo COVID é agregado (não separa WFH de Digitalização de Liquidez)
2. **Contrafactual**: Pré-COVID não teve taxas <3% (confounding possível)
3. **Seleção**: Freddie Mac = classe média (não inclui Jumbo/FHA/VA)

## Contexto e Referências

Este projeto se baseia no paradigma de **forma reduzida** (reduced-form) estabelecido por Richard & Roll (1989) para modelagem de prepayment em MBS, adaptado para incluir choques estruturais (COVID) e heterogeneidade comportamental.

**Referências Chave**:
- Deng, Quigley & Van Order (2000): "Mortgage Terminations, Heterogeneity and the Exercise of Mortgage Options"
- Brookings Institution (2021): "The Pandemic and Small Landlords"
- NY Fed (2021): "FinTech and Mortgage Markets During COVID-19"

## Licença

MIT
