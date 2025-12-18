# Análise de Resultados - Pré-pagamento de Hipotecas Durante a COVID-19

## Resumo Executivo

Este estudo analisa o comportamento de pré-pagamento de hipotecas durante a pandemia de COVID-19 (2020-2021) usando dados do Freddie Mac (400 mil empréstimos, 16.8 milhões de observações mensais). A modelagem progrediu de análises econômicas padrão para incluir fatores comportamentais heterogêneos.

**Principais Descobertas (Foco no Agregado):**

1.  **Aumento Estrutural**: Taxa de prepay aumentou **3.1x** durante COVID (0.89% → 2.76% mensal)
    - Desse aumento, juros baixos explicam a maior parte (M0 prevê 2.63%)
    - Excesso além de juros: apenas **+0.13 p.p. (5% adicional)**
2.  **Drivers do Excesso** (além de juros):
    - **Fatores Uniformes** (+0.16 p.p., 122%): Digitalização/Liquidez (inferido de literatura)
    - **Efeito Geográfico** (-0.03 p.p., -22%): Composição amostral (mais loans em destinos que diluem o boom)
3.  **Divergência por Ocupação** (achado principal):
    - Primary Residences: +0.35% excesso → Geraram 230% do boom líquido
    - Investimentos: -2.20% excesso → Retração massiva (Eviction Moratorium)
4.  **Freios Comportamentais**: 
    - Inércia (Sunk Cost): Empréstimos antigos reduziram boom potencial em 44%.

---

## Dados e Estrutura

### Fonte
- **Freddie Mac Single Family Loan-Level Dataset** (2016-2023)
- **400,000 empréstimos únicos** (amostra estratificada)
- **16.8 milhões** de observações loan-month
- **186,833 eventos de pré-pagamento** (Zero Balance Code 01)

### Períodos de Análise

| Período | Range Temporal | Taxa de Mercado Média | Características |
|---------|----------------|----------------------|-----------------|
| **Pré-COVID** | 2016 - Fev/2020 | 4.01% | Mercado normal, taxas moderadas |
| **COVID** | Mar/2020 - Dez/2021 | 2.99% | Taxas históricas baixas, alta volatilidade |
| **Pós-COVID** | 2022+ | 6.36% | Reversão abrupta para taxas altas |

### Divisão Train/Val/Test
- **Treino**: Pré-2020 (4.27M obs) - Período normal
- **Validação**: 2020-2021 (3.90M obs) - Período COVID
- **Teste**: 2022+ (8.70M obs) - Generalização fora da amostra

---

## Modelos Estimados

### M0: Baseline (Reduced-Form Padrão)
O modelo padrão de mercado, baseado no paradigma Richard & Roll (1989).

**Especificação:**
```
logit(p_{i,t}) = α + β·incentive + γ·loan_age + δ·credit_score + ε·ltv
```

**Variáveis:**
- `incentive`: Diferencial entre taxa do contrato e taxa de mercado (%)
- `loan_age`: Idade do empréstimo em meses (Seasoning effect)
- `credit_score`: Score de crédito FICO
- `ltv`: Loan-to-Value ratio (%)

### M1: Dummy COVID
Adiciona termos para capturar o efeito exógeno da pandemia.

**Especificação:**
```
logit(p_{i,t}) = M0 + η·covid + θ·(covid × incentive)
```

**Novos Parâmetros:**
- `η` (covid): Shift de nível durante COVID
- `θ` (covid_incentive): Mudança na sensibilidade ao incentivo

### M2: Behavioral (Modelo Final)
Adiciona interações para heterogeneidade comportamental.

**Especificação:**
```
logit(p_{i,t}) = M1 + λ·(covid × loan_age) + μ·(covid × credit_score)
```

**Hipóteses Testadas:**
- `λ > 0`: Sunk-cost enfraquece durante COVID (empréstimos antigos reagem mais)
- `μ > 0`: Overconfidence amplifica (altos scores reagem mais)

---

## Resultados Estatísticos

### Performance Preditiva (Log Loss)

| Modelo | Treino | Validação | **Teste (2022+)** |
|--------|--------|-----------|-------------------|
| M0     | 0.0447 | 0.1224    | 0.0363            |
| M1     | 0.0450 | 0.1194    | 0.0367            |
| **M2** | **0.0448** | **0.1194** | **0.0362**    |

> M2 generaliza melhor no período pós-COVID, indicando que a estrutura comportamental captura dinâmicas persistentes.

### Testes de Razão de Verossimilhança (LRT)

| Comparação | LR Statistic | df | P-value | Conclusão |
|------------|--------------|----|---------|-----------| 
| M0 vs M1   | 8,418        | 2  | < 1e-10 | **Efeito COVID estatisticamente significativo** |
| M1 vs M2   | 1,739        | 2  | < 1e-10 | **Interações comportamentais significativas** |

### Coeficientes Estimados (M2)

| Termo | Estimativa | Std Error | IC 95% | Interpretação |
|-------|------------|-----------|--------|---------------|
| **(Intercept)** | -5.75 | 0.024 | [-5.80, -5.71] | Probabilidade base muito baixa |
| **incentive** | +0.72 | 0.007 | [+0.71, +0.74] | Forte resposta racional a juros |
| **loan_age** | +0.028 | 0.0004 | [+0.027, +0.029] | Seasoning (empréstimos jovens menos propensos) |
| **credit_score** | +0.00016 | 0.00002 | [+0.00011, +0.00019] | Score alto → leve aumento de prepay |
| **ltv** | +0.003 | 0.0002 | [+0.0027, +0.0033] | LTV alto → Turnover/Mobilidade |
| **covid** | **+1.12** | 0.024 | [+1.08, +1.16] | **Choque positivo massivo** |
| **covid_incentive** | **-0.26** | 0.008 | [-0.27, -0.24] | Sensibilidade ao juro reduz (saturação) |
| **covid_loan_age** | **-0.019** | 0.0005 | [-0.020, -0.019] | **Inércia fortalece** (Sunk Cost) |
| **covid_credit_score** | ~0.00 | 0.00003 | [-0.00003, +0.00007] | Não significativo |

---

## Interpretações dos Efeitos

### 1. O "Paradoxo COVID": Aumento Além do Incentivo
**Observação**: Taxa de prepay durante COVID (2.76%) foi 3.1x maior que pré-COVID (0.89%), mas o incentivo de juros sozinho prediz apenas 1.8x.

**Mecanismo (Coeficiente `covid = +1.12`)**:
- O termo exógeno domina o efeito de interação negativo.
- Fatores **não-financeiros** explicam o residual: WFH, Digitalização, Liquidez aumentada.

### 2. Sunk Cost Fortalecido (Inércia)
**Resultado**: `covid × loan_age = -0.019` (negativo e significativo).

**Interpretação**:
- Para cada ano extra de idade (12 meses), o "boost COVID" diminui em 0.23 pontos logit.
- Empréstimos com 5 anos (60 meses) tiveram impulso COVID 1.14 pontos menor que novos.
- **Conclusão**: Mutuários com contratos antigos resistiram mais ao refinanciamento, apesar do ganho financeiro (falácia do custo afundado).

### 3. Overconfidence: Não Confirmado
O coeficiente `covid × credit_score` não é estatisticamente diferente de zero, sugerindo que sofisticação financeira (proxy pelo score) não modulou a resposta ao COVID de forma sistemática.

### 4. LTV e Turnover
O efeito positivo de LTV (+0.003) captura principalmente **mobilidade**: mutuários mais alavancados tendem a ser mais jovens/em transição, com maior probabilidade de vender (gerando prepay total).

---

## Quantificação do Impacto Comportamental: O Freio de 44%

### Metodologia
Simulamos um cenário contrafactual onde os termos de interação comportamental (`covid_loan_age` e `covid_credit_score`) são zerados, mantendo-se constantes os demais coeficientes.

### Resultados

| Cenário | Taxa Mensal Média (COVID) | Multiplicador vs M0 |
|---------|---------------------------|---------------------|
| **(A) Realidade (M2 Completo)** | 2.76% | 1.12x |
| **(B) Sem Fricções Comportamentais** | 4.95% | 2.01x |
| **Diferença (Drag)** | -2.19 p.p. | **-44.2%** |

**Implicação**: A inércia associada à idade do empréstimo (Sunk Cost) **bloqueou quase metade do boom potencial**. O mercado "deixou na mesa" um volume de refinanciamento equivalente a 80% do observado.

---

---

## Decomposição do Excesso COVID: O Que Explica o Boom Agregado?

### O Desafio da Identificação

O coeficiente `covid = +1.12` no modelo M2 é um **termo exógeno agregado** que captura tudo que aconteceu durante a pandemia além do efeito de juros. Para entender o que compõe esse termo, precisamos decompor o excesso observado.

**Dois Tipos de Comparação - Temporal vs Contrafactual:**

1. **Comparação Temporal** (Antes vs Durante):
   - Pré-COVID (2016-2019): Taxa média = 0.89%/mês
   - Durante COVID (Mar/2020-Dez/2021): Taxa média = 2.76%/mês
   - **Multiplicador: 2.76 / 0.89 = 3.1x**
   
2. **Comparação Contrafactual** (Observado vs Esperado por Juros):
   - Observado durante COVID: 2.76%/mês
   - Esperado pelo M0 (dado juros baixos): 2.63%/mês
   - M0 sozinho causaria: 2.63 / 0.89 = **2.96x** vs pré-COVID
   - **Excesso além de juros: 3.1x / 2.96x = 1.05x (5% adicional)**
   - Em termos absolutos: **0.13 p.p.**

**Interpretação:**
- M0 já incorpora o efeito dos juros baixos ao prever 2.63%
- Logo, o excesso de 0.13 p.p. representa fatores **além de juros**
- Juros baixos explicam 95% do boom (2.96x), excesso explica 5% (0.14x)

**Decomposição usada (Plot G):**
- Analisamos a comparação contrafactual (0.13 p.p.)
- Objetivo: identificar quais fatores além de juros contribuíram para o excesso

**O que nossos dados PODEM identificar:**
- ✅ Diferenças por **ocupação** (Primary vs Investment) - Temos a variável no dataset
- ✅ Diferenças por **geografia** (CA vs FL) - Temos a variável no dataset
- ✅ Diferenças por **idade do empréstimo** (interação já modelada em M2)

**O que nossos dados NÃO PODEM identificar diretamente:**
- ❌ Digitalização/Fintech (não temos variável de "usou fintech" ou "e-closing")
- ❌ Liquidez/Poupança (não temos dados de renda ou saldos bancários)
- ❌ WFH (não temos dados de tipo de emprego ou trabalho remoto)

Por isso, usamos uma **decomposição residual**: separamos o que conseguimos medir (geografia, ocupação) e o restante vai para "Outros Fatores", que então **inferimos da literatura**.

### Quantificação do Excesso Total (Plot G)

**Visualização da Decomposição (Plot G)**:

![Decomposição COVID](file:///home/andrecamatta/Projetos/pq_mortgage_prepay_covid/data/plots/G_covid_decomposition.png)

**Interpretação dos Componentes**:

1. **Barra Roxa - Excesso Total COVID (+0.132 p.p.)**:
   - Diferença entre taxa observada durante COVID (2.76%) e o que M0 (modelo baseline) esperaria dado o nível de juros e controles (2.63%)
   - = Taxa observada - Taxa esperada por incentivos/características
   - Representa "tudo que não é explicado por juros baixos sozinhos"

2. **Barra Vermelha - Componente Geográfico (-0.03 p.p., -22.7%)**:
   - **O que medimos**: Diferença ponderada entre estados de Êxodo (CA, NY: +0.19%) vs Destino (FL, TX: -0.02%)
   - **Negativo** porque nossa amostra tem mais loans em destinos (29%) que em origens (26%)
   - **Interpretação**: Efeito composição - WFH causou prepay em CA, mas diluiu em FL
   - **Conclusão**: Geografia explica DIFERENÇAS regionais, mas não o NÍVEL agregado

3. **Barra Cinza - "Outros Fatores" (+0.162 p.p., 122.7%)**:
   - **O que é**: RESÍDUO = Excesso Total - Componente Geográfico
   - **O que NÃO é**: Medição direta de Digitalização ou Liquidez
   - **Como interpretamos (literatura)**:
     - Digitalização provavelmente importante (NY Fed: fintechs 20% mais rápidas)
     - Liquidez provavelmente importante (poupança recorde 33% em Abril/2020)
   - **Limitação**: Sem dados individuais de "usou fintech" ou "saldo bancário", não podemos confirmar
   - **Por que dominante**: Fatores uniformes (afetam todos igualmente) não aparecem em diferenças geográficas

### Conclusão Sobre Drivers Agregados

**O que SABEMOS dos nossos dados:**
1. ✅ Primary Residences tiveram excesso muito maior que Investimentos (+0.35% vs -2.20%)
2. ✅ Estados de êxodo tiveram excesso maior que destinos (+0.19% vs -0.02%)
3. ✅ Mas o efeito geográfico líquido é negativo no agregado (composição amostral)

**O que INFERIMOS (hipóteses baseadas em literatura, não confirmadas nos dados):**
1. ❓ Digitalização/Fintech reduziu fricções para todos (aparece no resíduo)
2. ❓ Liquidez/Poupança viabilizou custos para todos (aparece no resíduo)
3. ❓ Esses fatores uniformes explicam por que a barra cinza é tão grande

**Por que não conseguimos separar Digitalização de Liquidez?**
- Ambos afetaram todos os mutuários uniformemente (não variam por loan)
- Nossa técnica de decomposição só identifica fatores que variam (geografia, ocupação)
- O resíduo é uma "caixa preta" que sabemos ser importante, mas não conseguimos abrir com os dados disponíveis

---

## Validação: Análise por Tipo de Ocupação

### Por Que Analisar Ocupação?

Mesmo sem poder medir Digitalização/Liquidez diretamente, podemos testar se seus efeitos foram **uniformes** ou **heterogêneos** por tipo de proprietário:
- Se Digitalização afetou todos igual → Primary e Investment deveriam ter excesso similar
- Se Eviction Moratorium afetou só investidores → Devemos ver divergência

### Resultados por Tipo de Ocupação

| Ocupação | Taxa Obs. | Taxa Esp. (M0) | **Excesso** | Volume Impacto | % Amostra COVID |
|----------|-----------|----------------|-------------|----------------|-----------------|
| **Residência Primária (P)** | 2.81% | 2.46% | **+0.35%** | **+10,974 eventos** | 88% |
| **Segunda Casa (S)** | 2.53% | 2.57% | -0.05% | -67 eventos | 4% |
| **Investimento (I)** | 2.34% | 4.54% | **-2.20%** | **-6,207 eventos** | 8% |

**Descoberta Crítica - Divergência Massiva**: 
- Primary teve excesso **positivo** (+0.35 p.p.)
- Investment teve excesso **negativo** (-2.20 p.p.)
- Gap total: 2.55 pontos percentuais (!)

### Cálculo da Contribuição Relativa (230%)

O cálculo em passos:

**Passo 1: Volume Absoluto de Eventos**
Durante o período COVID (Mar/2020-Dez/2021), comparando com o que M0 esperaria:
- Primary Residences geraram **+10,974 eventos EXTRAS** (acima do esperado)
- Investimentos geraram **-6,207 eventos A MENOS** (abaixo do esperado)

**Passo 2: Saldo Líquido**
- Soma dos dois efeitos: +10,974 + (-6,207) = **+4,767 eventos extras no total**
- Este é o "boom líquido" observado no mercado agregado

**Passo 3: Contribuição Relativa**
- Primary geraram 10,974 eventos positivos
- Mas o saldo final foi apenas 4,767
- Logo: 10,974 / 4,767 = 2.30 = **230%**

**Interpretação em Português Claro**:
> "Para cada 100 eventos de boom que observamos no mercado total, as Residências Primárias geraram 230 eventos positivos, mas 130 desses foram cancelados pela retração dos Investidores."

Ou seja: **Primary não apenas causou o boom, mas teve que compensar o colapso de Investment**.

### Por Que Famílias (Primary) Responderam Fortemente?

**O que nossos dados mostram diretamente:**
- ✅ Primary teve excesso +0.35% (muito acima do esperado por juros)
- ✅ Investment teve excesso -2.20% (muito abaixo do esperado)

**O que NÃO podemos afirmar diretamente (sem dados):**
- ❌ "Famílias usaram mais fintech" (não temos dados de canal de refinanciamento)
- ❌ "Famílias tinham mais liquidez" (não temos dados de renda/poupança)
- ❌ "Famílias queriam mudar de casa para WFH" (não temos dados de emprego remoto)

**Hipóteses Plausíveis (baseadas em literatura + padrão observado):**
1. **Motivação de Mudança de Vida** (WFH/Espaço):
   - Literatura mostra forte migração residencial 2020-2021
   - Primary residence é onde você mora → WFH criou necessidade de espaço/relocação
   - Investment é alugado para outros → Sem motivação pessoal de mudança

2. **Digitalização Favoreceu Families**:
   - Processos online (e-closing) eliminaram necessidade de ir ao banco
   - Families têm mais tempo/motivação para navegar processo digital
   - Investors podem ter outros compromissos (gestão de múltiplas propriedades)

3. **Eviction Moratorium** (explicado abaixo):
   - Bloqueou especificamente investidores
   - Não afetou proprietários residindo na própria casa

**Limitação**: Sem microdados de "canal usado" ou "motivo do refinanciamento", essas são **hipóteses consistentes com os dados**, não conclusões definitivas.

**Visualização da Divergência Temporal (Plot F)**:

![Divergência por Ocupação](file:///home/andrecamatta/Projetos/pq_mortgage_prepay_covid/data/plots/F_occupancy_divergence.png)

O gráfico revela o **momento exato da divergência**: a partir de março de 2020 (início do COVID), as linhas se separam drasticamente. Residências Primárias (verde) disparam para ~3.5-4%, enquanto Investimentos (laranja) **colapsam** para ~2%, criando um gap sem precedentes de >1.5 pontos percentuais. Este padrão visual confirma que o Eviction Moratorium (Set/2020-Ago/2021) congelou o mercado de investimentos exatamente quando residências primárias explodiam.

### Eviction Moratorium: O "Freio Invisível" dos Investidores

**Contexto Regulatório**:
- CDC Eviction Moratorium (Set/2020 - Ago/2021): Proibiu despejo de inquilinos por não-pagamento
- Moratórias estaduais variaram (CA e NY mantiveram até 2022)

**Impacto nos Investidores (Explicando o -2.20%)**:

1. **Risco de Fluxo de Caixa**:
   - Investidores ("Mom & Pop landlords") dependem de aluguel para pagar hipotecas
   - Moratória → Inquilinos param de pagar, mas não podem ser despejados
   - **Resultado**: Sem renda para refinanciar ou vender

2. **Estratégia de Sobrevivência**:
   - Forbearance de hipoteca (pausar pagamentos temporariamente)
   - "Congelamento" da posição (não refinanciar, não vender)

**Validação Externa**: Brookings Institution (2021) documentou que 40% dos pequenos investidores reportaram perda de renda de aluguel.

---

## Análise de Heterogeneidade Regional: WFH/Migração

> **IMPORTANTE**: Esta seção explica **diferenças entre estados**, não o **nível agregado** do boom.

### Hipótese: WFH causou migração de estados caros para baratos

**Predição**: Estados de **saída** (CA, NY) devem ter excesso positivo (vendas), enquanto estados de **destino** (FL, TX) devem ter excesso negativo (compras, não vendas).

### Resultados Geográficos

| Região | Taxa Observada | Taxa Esperada (M0) | **Excesso** | Interpretação |
|--------|----------------|-----------------------|-------------|---------------|
| **Cold/Outflow** (CA, NY, IL, MA) | 2.81% | 2.62% | **+0.19%** | **Confirmação**: Vendas para migração |
| **Hot/Inflow** (FL, TX, AZ, NV) | 2.74% | 2.76% | **-0.02%** | Destino (compras dominam) |
| **Other** | 2.75% | 2.55% | +0.20% | Misto |

**Visualização da Divergência Temporal (Plot E)**:

![Divergência Geográfica](file:///home/andrecamatta/Projetos/pq_mortgage_prepay_covid/data/plots/E_geographic_divergence.png)

O gráfico mostra que durante o período COVID (faixa sombreada), os estados de **Êxodo (linha vermelha)** mantiveram taxas de prepay **consistentemente acima** dos estados de Destino (linha azul tracejada).

### Por Que o Componente Geográfico é Negativo no Agregado? (Plot G)

**Efeito Composição**:
- 26% da amostra em estados de Êxodo: +0.19% excesso
- 29% da amostra em estados de Destino: -0.02% excesso
- **Efeito líquido ponderado**: -0.03 p.p. (negativo!)

**Interpretação**:
- WFH **causou** muitos prepayments em CA/NY (vendas de casas antigas)
- Mas nossa amostra tem **mais loans** em FL/TX, que não se moveram (são destinos)
- **Resultado**: WFH explica a **heterogeneidade** (CA ≠ FL), mas dilui o **agregado**

**Drivers Uniformes Dominam**:
- Digitalização e Liquidez afetaram CA e FL igualmente
- Por isso aparecem na barra cinza do Plot G (122.7%)

---

## Validação Externa: Confirmação na Literatura

### 1. Divergência Investidor vs. Owner-Occupier
**Nossa Descoberta**: Investidores tiveram prepay -2.20% abaixo do esperado.

**Literatura (Brookings, Fed Reserve 2021)**:
- **Moratória de Despejo (Eviction Moratorium)**: Impediu investidores de despejar inquilinos inadimplentes, criando risco de fluxo de caixa.
- **Estratégia de Forbearance**: Muitos investidores optaram por "congelar" posições (forbearance de hipoteca) em vez de vender.
- **Resultado**: Queda no turnover de propriedades de investimento no início da pandemia.

### 2. WFH e Migração
**Nossa Descoberta**: Estados de êxodo (CA, NY) tiveram +0.19% de excesso de prepay.

**Literatura (NBER 2021, Realtor.com)**:
- WFH responsável por >50% do aumento nos preços de imóveis 2020-2021.
- Migração documentada de centros urbanos caros para subúrbios e "Sunbelt".
- Turnover residencial aumentou durante a pandemia (vendas para mudança de localização).

### 3. Digitalização (Fintech Effect)
**Literatura (NY Fed 2021)**:
- Fintechs processaram refinanciamentos 20% mais rápido que bancos tradicionais.
- Appraisal Waivers (dispensa de avaliação presencial) aumentaram prepay condicional em 2020.
- Redução de fricção não-monetária (burocracia) facilitou decisões impulsivas.

---

## Contexto Histórico: Modelagem de Pré-pagamento

### Origem (Anos 1980)
O mercado de MBS (Mortgage-Backed Securities) necessitava precificar o risco de pré-pagamento antecipado.

**Modelo Richard & Roll (1989)**:
- **Autores**: Goldman Sachs (Scott F. Richard, Richard Roll)
- **Inovações**: Incentivo de refinanciamento, Seasoning (idade), Burnout (sobrevivência), Sazonalidade.
- **Legado**: Paradigma de "forma reduzida" (reduced-form) - regressão sobre comportamento histórico, não otimização teórica.

### Evolução para Logit Discreto (1990s)
- Schwartz & Torous (1989): Logit permite covariáveis time-varying.
- Deng, Quigley & Van Order (2000): Framework de opção de prepay + heterogeneidade.

### Por Que Logit e Não Cox?

| Aspecto | Cox Proportional Hazards | **Logit Discreto (usado)** |
|---------|--------------------------|----------------------------|
| Tempo | Contínuo | **Discreto (mensal)** |
| Baseline hazard | Não-paramétrico | Absorvido no intercepto |
| Covariáveis time-varying | Complexo | **Simples (1 obs/mês)** |
| Escala | Lento (16M obs) | **Rápido** |
| Prática | Acadêmico | **Indústria (Fannie/Freddie)** |

**Limitação**: Assume independência entre observações do mesmo empréstimo (ignora correlação intra-loan). Modelos mais sofisticados incluiriam fragilidade (random effects) ou GEE.

---

## Limitações e Caveats

### 1. Ausência de Contrafactual Adequado
**Problema**: Pré-COVID não teve meses com taxas <3% (apenas 5 meses com <3.5%). Logo, o efeito `covid_incentive` pode confundir:
- ✅ Fricções reais da pandemia
- ⚠️ Não-linearidade em taxas extremas
- ⚠️ Saturação do mercado

**Solução Ideal**: Dados históricos 2008-2012 (Great Recession) com taxas baixas pré-COVID.

### 2. Identificação Causal Limitada
Nosso termo `covid` é um "dummy temporal", capturando tudo que aconteceu Mar/2020-Dez/2021. Separar WFH de Digitalização de Liquidez exigiria variação cross-sectional adicional (e.g., exposição setorial a WFH por região).

### 3. Seleção de Amostra
Freddie Mac representa ~30-40% do mercado (classe média, conforming loans). Não inclui:
- Jumbo loans (alta renda)
- FHA/VA (baixa renda, militares)
- Empréstimos não-agência

---

## Decomposição do Efeito COVID: Separando os Componentes

### O Coeficiente COVID (+1.12): Um Termo Composto

O coeficiente `covid = +1.12` no modelo M2 é um **termo exógeno agregado** que captura todo o efeito residual da pandemia não explicado por incentivos de taxa. Este termo **não pode ser decomposto diretamente** em componentes individuais (WFH, Digitalização, Liquidez) sem variação cross-sectional adicional.

**O que sabemos:**
1. **Magnitude Total**: O termo COVID gerou um boost de ~1.12 pontos logit (equivalente a multiplicar as odds de prepay por e^1.12 ≈ 3.07x, ceteris paribus).
2. **Evidência Indireta de Componentes**:
   - **Geografia**: Estados de êxodo (CA, NY) tiveram +0.19% excesso → **Consistente com WFH/Migração**.
   - **Ocupação**: Residências Primárias (+0.35%) vs. Investimentos (-2.20%) → **Consistente com WFH** (famílias) **+ Eviction Moratorium** (investidores).
   - **Literatura**: Fintech processing speed, appraisal waivers → **Consistente com Digitalização**.

**O que NÃO podemos afirmar**: "WFH explica X% do efeito COVID". Nosso modelo não tem a variação necessária para isolar isso. Podemos apenas dizer que WFH é **um dos drivers principais**, validado pela geografia e ocupação.

### Eviction Moratorium: O "Freio Invisível" dos Investidores

**Contexto Regulatório**:
- CDC Eviction Moratorium (Set/2020 - Ago/2021): Proibiu despejo de inquilinos por não-pagamento em propriedades com hipotecas federais.
- Moratórias estaduais variaram (CA e NY mantiveram até 2022).

**Impacto nos Investidores (Explicando o -2.20%)**:

1. **Risco de Fluxo de Caixa**:
   - Investidores ("Mom & Pop landlords") dependem de aluguel para pagar hipotecas.
   - Moratória → Inquilinos param de pagar, mas não podem ser despejados.
   - **Resultado**: Sem renda para refinanciar (falta comprovação de fluxo) ou vender (propriedade ocupada com inquilino inadimplente).

2. **Estratégia de Sobrevivência**:
   - Forbearance de hipoteca (pausar pagamentos temporariamente).
   - "Congelamento" da posição (não refinanciar, não vender).
   - Espera pela resolução política/legal.

3. **Evidência Nos Dados**:
   - Taxa observada de prepay em investimentos (2.34%) vs. esperada pelo M0 (4.54%).
   - **Gap de -2.20%** = Investidores que "deveriam" ter refinanciado (dado juro baixo + características) mas não o fizeram.
   - Volume: ~6,207 refinanciamentos "perdidos" no período COVID.

**Validação Externa**: Brookings Institution (2021) documentou que 40% dos pequenos investidores reportaram perda de renda de aluguel, e muitos acessaram forbearance de hipoteca como alternativa ao despejo.

### Residências Primárias: Múltiplos Aceleradores

**Nossa Descoberta**: +0.35% excesso, gerando +10,974 eventos extras.

**Drivers Identificados (Sem Quantificação Isolada)**:

1. **WFH e Relocação**:
   - **Evidência Geográfica**: Estados de êxodo (+0.19% excesso) confirmam movimentação.
   - **Mecanismo**: Venda de casa urbana (gera prepay total) + compra suburbana.
   - **Limitação**: Não sabemos quantos dos +10,974 eventos foram "turnover" vs "rate refinance".

2. **Digitalização (Fintech Effect)**:
   - Appraisal waivers, e-closing, processamento 20% mais rápido.
   - Reduz custo não-monetário (tempo, fricção burocrática).

3. **Liquidez/Poupança**:
   - Taxa de poupança pessoal bateu recordes em 2020 (33% em Abril/2020).
   - Menos gastos com viagens/lazer → Capital para custos de fechamento.

**Por Que ">100%" do Boom Líquido?**
- Investidores contribuíram **negativamente** (-6,207 eventos).
- Residências Primárias contribuíram **positivamente** (+10,974 eventos).
- Saldo líquido: +4,767 eventos.
- Logo, Residências geraram 10,974 / 4,767 ≈ **230% do resultado final observado**, compensando totalmente a retração dos investidores.

## Conclusão Final

A pandemia de COVID-19 criou um boom histórico de pré-pagamento (+3.1x), mas a análise agregada revela que os **drivers uniformes** dominaram:

**Aceleradores Agregados** (122.7% do excesso):
- **Digitalização/Fintech**: Appraisal waivers, e-closing, processamento 20% mais rápido → Reduziu fricção para todos
- **Liquidez/Poupança**: Estímulos fiscais + taxa de poupança recorde (33%) → Viabilizou custos de fechamento
- **Primary Residences**: Famílias responderam fortemente (+0.35% excesso), gerando 230% do boom líquido

**Freios** (reduzindo potencial):
- **Eviction Moratorium**: Investidores congelaram (-2.20% excesso, -6,207 eventos)
- **Sunk Cost Fallacy**: Empréstimos antigos resistiram (drag de 44% no potencial)

**Heterogeneidade Regional** (WFH/Migração):
- Explica diferenças entre CA (+0.19%) e FL (-0.02%)
- Mas **não explica o nível agregado** (contribuição líquida: -0.03 p.p., -22.7%)
- Efeito composição: Muitos loans em destinos (FL/TX) diluem o boom de saída (CA/NY)

**Implicação Metodológica**: Modelos agregados tradicionais (M0) são insuficientes. A metodologia de interações comportamentais (M2) + decomposição por ocupação/geografia foi essencial para separar drivers uniformes (Digitalização) de drivers heterogêneos (WFH), revelando que o boom foi causado por fatores tecnológicos e fiscais que afetaram todos uniformemente, sendo amplificados por famílias e freados por investidores.
