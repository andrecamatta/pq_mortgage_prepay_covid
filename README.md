# Análise de Pré-Pagamento Hipotecário durante COVID

Pipeline em Julia para análise de comportamento de pré-pagamento de hipotecas durante a COVID-19 usando dados do Freddie Mac.

## Requisitos

- Julia 1.9+
- ~2GB RAM para construção do painel
- ~16GB disco para dados do Freddie Mac

## Configuração dos Dados

1. Registre-se no [Freddie Mac](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset)
2. Baixe o **Sample Dataset** (não o dataset completo) para os anos 2016-2023
3. Extraia e coloque os arquivos:
   ```
   data/raw/freddiemac/orig/sample_orig_YYYY.txt
   data/raw/freddiemac/svcg/sample_svcg_YYYY.txt
   ```

## Instalação

```bash
git clone <repo-url>
cd pq_mortgage_prepay_covid
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Executando o Pipeline

```bash
# 1. Carregar e validar dados
julia --project=. 01_download_or_load_data.jl

# 2. Construir painel loan-month
julia --project=. 02_build_panel.jl

# 3. Ajustar modelos (M0 baseline, M1 com termos COVID)
julia --project=. 03_fit_models.jl

# 4. Gerar gráficos
julia --project=. 04_plots.jl

# 5. Análise exploratória (opcional)
julia --project=. 05_eda.jl
```

## Estrutura do Projeto

```
├── 01_download_or_load_data.jl  # Carregamento de dados
├── 02_build_panel.jl            # Construção do painel
├── 03_fit_models.jl             # Modelos de regressão logística
├── 04_plots.jl                  # Visualizações
├── 05_eda.jl                    # Análise exploratória
├── config/columns.jl            # Mapeamento de colunas
└── data/                        # Diretório de dados (gitignored)
```

## Licença

MIT
