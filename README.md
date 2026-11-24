# PDI — Processamento Digital de Imagens

Trabalho da cadeira de PDI na Feevale.

**Autor:** Eduardo Gottert — eduardo@gttr.com.br

Programa de processamento de imagens com menus e duas janelas: a imagem
original e a imagem transformada.

- **Interface:** Python 3 + Tkinter (`main.py`)
- **Transformações:** assembly x86-64 (NASM), convenção de chamada
  **System V AMD64**, compiladas na biblioteca `lib/libpdi.so` e chamadas pelo
  Python via `ctypes` (`pdi.py`)

As funções em assembly recebem um buffer de bytes e aceitam imagens de
1 canal (cinza) ou 3 canais (RGB); a quantidade de canais é um argumento.

## Como executar (Linux ou WSL)

Instale as dependências:

```bash
# Arch Linux
sudo pacman -S python tk python-pillow nasm binutils
# Ubuntu / Debian
sudo apt install python3 python3-tk python3-pil nasm binutils
```

Depois:

```bash
./compilar.sh        # na primeira vez e sempre que um .asm for alterado
python3 main.py
```

`nasm` e `binutils` só são necessários para compilar a biblioteca.

## Menus

| Menu | Opções |
|------|--------|
| Arquivo | Abrir imagem, Salvar imagem, Sobre, Sair |
| Transformações Geométricas | Transladar, Rotacionar, Espelhar (horizontal e vertical), Aumentar, Diminuir |
| Filtros | Grayscale, Negativo, Brilho e Contraste, Passa Baixa (Média, Moda, Mediana e Gaussiano), Passa Alta, Threshold, Detecção de Bordas (Roberts e Sobel) |
| Morfologia Matemática | Dilatação, Erosão, Abertura, Fechamento, Afinamento (Zhang-Suen) |
| Exercícios | Desafio 1 (porcas), 2 (dígito par ou ímpar), 3 (comprimidos), 4 (círculos e quadrados), 5 (ferrugem na folha) |

Cada técnica é aplicada sobre a imagem transformada, então elas se acumulam
(ex.: Grayscale → Passa Baixa → Sobel). Para recomeçar, abra a imagem de novo.

Os exercícios sempre partem da imagem original: mostram a imagem numerada (ou
segmentada) como imagem transformada e abrem uma janela com a tabela de
resultados.

## Estrutura

```
main.py            interface (menus, janelas, abrir e salvar arquivos)
pdi.py             carrega lib/libpdi.so e declara as funções
desafios.py        os cinco exercícios: encadeiam as funções em assembly e
                   decidem, pelas medidas, o que é cada objeto
compilar.sh        nasm + ld  ->  lib/libpdi.so
asm/
  comum.inc        resumo da convenção System V e macro SATURAR
  filtros/         grayscale, negativo, contraste, media, moda, mediana,
                   gaussiano, passa_alta, threshold, roberts, sobel
  geometria/       transladar, rotacionar, espelhar, aumentar, diminuir
  morfologia/      dilatacao, erosao, abertura, fechamento, afinamento
  caracteristicas/ rotulacao (floodfill), medidas (área, perímetro,
                   centroide, caixa), contorno_externo, ferrugem (cor)
  suporte/         matriz_transformacao (usada pela geometria),
                   convolucao 3x3 (média, gaussiano e passa-alta),
                   janela 3x3 (moda e mediana),
                   morfologia (varredura com o elemento estruturante),
                   memoria (buffers temporários)
```

Cada arquivo `.asm` começa com um cabeçalho (CHAMADA, REGISTERS,
FUNCIONAMENTO e OBSERVAÇÕES), e cada instrução tem um comentário dizendo o que
faz e para quê.

## Detalhes das técnicas

- **Grayscale:** `R*0,2125 + G*0,7154 + B*0,0721`.
- **Brilho e contraste:** uma única função, `D(x,y) = C·f(x,y) + B`, limitada
  a 0..255.
- **Transformações geométricas:** mapeamento inverso com vizinho mais próximo.
  Cada operação monta a matriz inversa e chama `suporte/matriz_transformacao.asm`.
  A rotação gira em torno do centro (ângulo positivo = sentido horário) e
  mantém o tamanho da imagem.
- **Passa baixa e passa alta:** janela 3x3 em cada canal; a moldura de
  1 pixel mantém o valor original.
  - **Média:** média dos 9 pixels (máscara de uns, dividida por 9).
  - **Moda:** o valor que mais se repete na janela; se nenhum se repete,
    mantém o pixel central.
  - **Mediana:** ordena os 9 valores e pega o do meio.
  - **Gaussiano:** máscara `[1 2 1; 2 4 2; 1 2 1]`, dividida por 16.
  - **Passa alta:** máscara `[-1 -1 -1; -1 8 -1; -1 -1 -1]`.
- **Threshold, Roberts e Sobel:** imagens RGB são convertidas para cinza
  antes, e o resultado tem 1 canal.
- **Detecção de bordas:** é borda (255) onde a magnitude do gradiente passa do
  limiar; o resto fica preto (0).
  - **Roberts:** máscaras 2x2 nas diagonais, `G1 = f(x,y) − f(x+1,y+1)` e
    `G2 = f(x+1,y) − f(x,y+1)`; borda onde `√(G1² + G2²) > limiar`. A última
    linha e a última coluna ficam pretas.
  - **Sobel:** máscaras 3x3 `Sx` e `Sy`; borda onde `√(Gx² + Gy²) > limiar`.
    A moldura de 1 pixel fica preta.
- **Negativo:** `g(x,y) = 255 − f(x,y)` em cada canal.

### Morfologia matemática

- **Dilatação e erosão:** seguem o passo a passo dos slides. O elemento
  estruturante é uma cruz 3x3 com o mesmo valor nas 5 posições (pergunta-se o
  valor; use 0 em imagens binárias). Para cada posição da cruz, calcula-se
  pixel + valor (dilatação, maior soma) ou pixel − valor (erosão, menor
  diferença), e o resultado é aplicado em todas as posições cobertas pela cruz.
  Um pixel 0 é posição vazia. Com a imagem e o elemento do exemplo dos slides
  (cruz com valor 10), o resultado é idêntico ao da aula.
- **Abertura:** erosão seguida de dilatação. **Fechamento:** dilatação seguida
  de erosão (sempre com o mesmo elemento).
- **Afinamento:** algoritmo de Zhang-Suen, em duas etapas por ciclo
  (`2 ≤ B ≤ 6`, `A = 1` e os produtos `P2·P4·P6`, `P4·P6·P8` na etapa 1 e
  `P2·P4·P8`, `P2·P6·P8` na etapa 2), até nenhum pixel ser removido. O objeto é
  a parte clara (≥ 128); para afinar um desenho escuro, aplique antes o
  Negativo.

### Exercícios (desafio final)

Todos usam a rotulação por floodfill (vizinhança 8) e as medidas em
assembly: área (contagem de pixels), perímetro (fronteira medida em blocos
2x2, com diagonais valendo √2), centroide e caixa. A circularidade é
`4·π·A / P²` (1 = círculo perfeito; é o inverso normalizado do `C = P²/A`
dos slides). O limiar dos objetos é calculado pelo método de Otsu.

1. **Porcas:** cinza → mediana → limiar → negativo (porca escura). Cada objeto
   grande é uma porca. Os furos são os pedaços de fundo cercados pela porca; o
   furo da porca é o mais próximo do centro dela (os outros são reflexos do
   metal). Mostra perímetro externo, perímetro interno e área do furo.
2. **Dígito par ou ímpar:** separa o algarismo (descarta molduras, que
   preenchem pouco a própria caixa) e reconhece pela quantidade e posição dos
   furos, pela proporção e pela densidade de tinta numa grade 3x5. Funciona com
   uma imagem de um algarismo ou com vários.
3. **Comprimidos:** comprimido claro sobre fundo escuro. Área e perímetro da
   silhueta externa (o sulco e as rachaduras internas não contam).
   Circularidade < 0,91 → quebrado/borda irregular; largura/altura > 1,1 →
   ovalado; área < 80% da mediana → tamanho fora do padrão.
4. **Círculos e quadrados:** as regiões são as áreas entre as bordas do Sobel
   (assim um círculo branco desenhado sobre um quadrado vermelho vira outra
   região). Cada região é medida pela silhueta externa: circularidade ≥ 0,85 →
   círculo; entre 0,70 e 0,85 com largura ≈ altura → quadrado (inclusive
   girado, como o losango do mosaico).
5. **Ferrugem na folha:** classificação de cada pixel pela cor: pouca diferença
   entre R, G e B → fundo; com cor e `R ≥ G` (amarelo, laranja, marrom) →
   ferrugem; com cor e verde predominando → folha sadia. Percentual =
   ferrugem / (sadia + ferrugem): até 4% saudável, até 30% merece observação,
   acima disso doente.
