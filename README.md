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
| Filtros | Grayscale, Brilho e Contraste, Passa Baixa (média 3x3), Passa Alta, Threshold, Detecção de Bordas (Sobel) |
| Morfologia Matemática | Dilatação, Erosão, Abertura, Fechamento, Afinamento (próximas entregas) |
| Extração de Características | Desafio (a definir) |

Cada técnica é aplicada sobre a imagem transformada, então elas se acumulam
(ex.: Grayscale → Passa Baixa → Sobel). Para recomeçar, abra a imagem de novo.

## Estrutura

```
main.py            interface (menus, janelas, abrir e salvar arquivos)
pdi.py             carrega lib/libpdi.so e declara as funções
compilar.sh        nasm + ld  ->  lib/libpdi.so
asm/
  comum.inc        resumo da convenção System V e macro SATURAR
  filtros/         grayscale, contraste, threshold, passa_baixa, passa_alta, sobel
  geometria/       transladar, rotacionar, espelhar, aumentar, diminuir
  suporte/         matriz_transformacao (usada pela geometria),
                   convolucao 3x3 (passa-baixa e passa-alta),
                   memoria (buffer temporário do Sobel)
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
- **Passa baixa e passa alta:** convolução 3x3 em cada canal; a moldura de
  1 pixel mantém o valor original.
- **Threshold e Sobel:** imagens RGB são convertidas para cinza antes, e o
  resultado tem 1 canal. No Sobel, é borda onde `√(Gx² + Gy²) > limiar`.
