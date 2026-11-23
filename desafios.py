"""
desafios.py - os cinco exercícios do desafio final (menu Exercícios).

Cada exercício encadeia técnicas da biblioteca em assembly (módulo pdi):
cinza, mediana, threshold, negativo, Sobel, rotulação, medidas e
classificação por cor. Aqui ficam só as decisões (qual objeto é o quê, a
partir das medidas) e a montagem do resultado: a imagem numerada e a tabela.

Medidas em pixels. Circularidade = 4·π·A / P², que vale 1 num círculo
perfeito e diminui quanto mais irregular for a forma (é o inverso
normalizado do C = P²/A dos slides, que vale 4π no círculo).
"""

import math
from collections import Counter
from dataclasses import dataclass

from PIL import Image as ImagemPIL, ImageDraw, ImageFont

import pdi


@dataclass
class Resultado:
    imagem: pdi.Imagem   # imagem anotada, mostrada como imagem transformada
    colunas: list        # títulos da tabela
    linhas: list         # uma tupla por objeto
    resumo: str          # texto mostrado acima da tabela


# ------------------------------------------------------------------ auxiliares

def limiar_otsu(cinza):
    """Limiar que melhor separa o histograma em dois grupos (método de Otsu)."""
    histograma = [0] * 256
    for valor, quantidade in Counter(cinza.dados).items():
        histograma[valor] = quantidade
    total = sum(histograma)
    soma_total = sum(i * q for i, q in enumerate(histograma))
    peso_fundo = soma_fundo = 0
    melhor, limiar = -1.0, 128
    for t in range(256):
        peso_fundo += histograma[t]
        peso_frente = total - peso_fundo
        if peso_fundo == 0 or peso_frente == 0:
            continue
        soma_fundo += t * histograma[t]
        media_fundo = soma_fundo / peso_fundo
        media_frente = (soma_total - soma_fundo) / peso_frente
        variancia = peso_fundo * peso_frente * (media_fundo - media_frente) ** 2
        if variancia > melhor:
            melhor, limiar = variancia, t + 1   # o threshold marca objeto quando cinza >= T
    return limiar


def mascara(img, objeto_claro):
    """Imagem binária com o objeto em 255: cinza, mediana, Otsu e, se o
    objeto for escuro, negativo. A mediana final tira pontos soltos."""
    cinza = pdi.mediana(pdi.grayscale(img))
    binaria = pdi.threshold(cinza, limiar_otsu(cinza))
    if not objeto_claro:
        binaria = pdi.negativo(binaria)
    return pdi.mediana(binaria)


class Objetos:
    """Rotulação de uma máscara binária com as medidas de cada objeto."""

    def __init__(self, binaria):
        self.largura, self.altura = binaria.largura, binaria.altura
        self.rotulos, n = pdi.rotular(binaria)
        self.medidas = pdi.medir(self.rotulos, self.largura, self.altura, n)
        self.n = n

    def lista(self, area_minima):
        """Rótulos dos objetos com pelo menos area_minima pixels (o resto é ruído)."""
        return [i for i in range(1, self.n + 1) if self.medidas[i].area >= area_minima]

    def toca_borda(self, i, margem=0):
        m = self.medidas[i]
        return (m.x_min <= margem or m.y_min <= margem or
                m.x_max >= self.largura - 1 - margem or m.y_max >= self.altura - 1 - margem)

    def externo(self, i):
        """(área, perímetro) da silhueta externa, sem furos."""
        return pdi.contorno_externo(self.rotulos, self.largura, i, self.medidas[i])


def contem(fora, dentro):
    """A caixa 'dentro' está inteira na caixa 'fora'?"""
    return (fora.x_min <= dentro.x_min and dentro.x_max <= fora.x_max and
            fora.y_min <= dentro.y_min and dentro.y_max <= fora.y_max)


def circularidade(area, perimetro):
    return 4 * math.pi * area / perimetro ** 2 if perimetro else 0.0


def ordem_de_leitura(itens):
    """Ordena itens (cuja posição 0 é a medida) por linhas, de cima para baixo,
    e em cada linha da esquerda para a direita."""
    if not itens:
        return []
    altura_tipica = sorted(item[0].altura for item in itens)[len(itens) // 2]
    restantes = sorted(itens, key=lambda item: item[0].centro[1])
    ordem = []
    while restantes:
        topo = restantes[0][0].centro[1]
        linha = [item for item in restantes if item[0].centro[1] - topo < altura_tipica / 2]
        restantes = restantes[len(linha):]
        ordem += sorted(linha, key=lambda item: item[0].centro[0])
    return ordem


def fonte(tamanho):
    for nome in ("DejaVuSans-Bold.ttf", "arialbd.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(nome, tamanho)
        except OSError:
            pass
    return ImageFont.load_default()


def anotar(img, marcas):
    """Desenha caixas e números sobre a imagem.

    marcas: (texto, medida ou None, (x, y) do texto, cor)."""
    modo = "L" if img.canais == 1 else "RGB"
    figura = ImagemPIL.frombytes(modo, (img.largura, img.altura), bytes(img.dados)).convert("RGB")
    desenho = ImageDraw.Draw(figura)
    escala = max(img.largura, img.altura)
    letra = fonte(max(14, escala // 30))
    linha = max(2, escala // 400)
    for texto, m, (x, y), cor in marcas:
        if m is not None:
            desenho.rectangle((m.x_min, m.y_min, m.x_max, m.y_max), outline=cor, width=linha)
        desenho.text((x, y), texto, fill=cor, font=letra, anchor="mm",
                     stroke_width=max(2, linha), stroke_fill="white")
    return pdi.Imagem(figura.width, figura.height, 3, bytearray(figura.tobytes()))


# ---------------------------------------------------------- Desafio 1: porcas

def porcas(img):
    """Conta as porcas e mede perímetro externo, perímetro do furo e área do furo.

    Porca = parte escura (Otsu + negativo). Furo = pedaço de fundo cercado pela
    porca (não toca a borda da imagem): rotulação do negativo da máscara."""
    porca = mascara(img, objeto_claro=False)
    area_minima = img.largura * img.altura * 0.002
    pecas = Objetos(porca)
    fundo = Objetos(pdi.negativo(porca))
    furos = [j for j in fundo.lista(area_minima / 20) if not fundo.toca_borda(j)]

    linhas, marcas = [], []
    ordem = ordem_de_leitura([(pecas.medidas[i], i) for i in pecas.lista(area_minima)])
    for numero, (m, i) in enumerate(ordem, 1):
        _, perimetro_externo = pecas.externo(i)
        dentro = [j for j in furos if contem(m, fundo.medidas[j])]
        if dentro:
            # O furo fica no centro da porca; os outros "buracos" são reflexos do metal.
            centro = ((m.x_min + m.x_max) / 2, (m.y_min + m.y_max) / 2)
            furo = min(dentro, key=lambda j: math.dist(fundo.medidas[j].centro, centro))
            area_furo, perimetro_furo = fundo.externo(furo)
            posicao = fundo.medidas[furo].centro
        else:
            area_furo = perimetro_furo = 0
            posicao = m.centro
        linhas.append((numero, f"{perimetro_externo:.1f}", f"{perimetro_furo:.1f}", f"{area_furo:.0f}"))
        marcas.append((str(numero), m, posicao, "red"))

    resumo = f"{len(linhas)} porca(s) encontrada(s)."
    return Resultado(anotar(img, marcas),
                     ["Porca", "Perímetro externo (px)", "Perímetro interno (px)", "Área do furo (px²)"],
                     linhas, resumo)


# -------------------------------------------------------- Desafio 2: dígitos

def densidade_por_zonas(binaria, m, colunas=3, linhas=5):
    """Fração de pixels do objeto em cada zona de uma grade sobre a caixa do dígito."""
    largura, dados = binaria.largura, binaria.dados
    zonas = []
    for j in range(linhas):
        y0 = m.y_min + m.altura * j // linhas
        y1 = m.y_min + m.altura * (j + 1) // linhas
        for i in range(colunas):
            x0 = m.x_min + m.largura * i // colunas
            x1 = m.x_min + m.largura * (i + 1) // colunas
            tinta = sum(dados[y * largura + x0:y * largura + x1].count(255) for y in range(y0, y1))
            zonas.append(tinta / max(1, (y1 - y0) * (x1 - x0)))
    return zonas


def reconhecer_digito(m, furos, zonas):
    """Árvore de decisão com as características do algarismo.

    furos: medidas dos furos dentro do dígito; zonas: densidade 3x5
    (índice = linha * 3 + coluna)."""
    z = lambda linha, coluna: zonas[linha * 3 + coluna]
    if len(furos) >= 2:
        return 8
    if len(furos) == 1:
        furo = furos[0]
        altura_relativa = (furo.centro[1] - m.y_min) / m.altura   # 0 = topo, 1 = base
        if altura_relativa < 0.42:
            return 9                         # furo em cima
        if altura_relativa > 0.58:
            return 6                         # furo embaixo
        if furo.area / (m.largura * m.altura) > 0.18:
            return 0                         # furo grande e central
        return 4                             # furo pequeno (o triângulo do 4)
    if m.largura / m.altura < 0.45:
        return 1                             # traço estreito
    if z(4, 2) < 0.2:
        return 7                             # base vazia à direita
    if z(1, 0) > 0.5 and z(1, 2) < 0.4:
        return 5                             # parte de cima cheia à esquerda e vazia à direita
    if z(3, 2) > 0.4:
        return 3                             # curva de baixo fechada pela direita
    return 2


def digitos(img):
    """Reconhece os algarismos da imagem e diz se são pares ou ímpares."""
    tinta = mascara(img, objeto_claro=False)
    pecas = Objetos(tinta)
    # Molduras e linhas preenchem pouco a própria caixa; dígitos não.
    candidatos = [i for i in pecas.lista(img.largura * img.altura * 0.002)
                  if pecas.medidas[i].area / (pecas.medidas[i].largura * pecas.medidas[i].altura) >= 0.15]
    if not candidatos:
        return Resultado(img, ["Dígito", "Número", "Classificação"], [], "Nenhum algarismo encontrado.")
    maior = max(pecas.medidas[i].area for i in candidatos)
    escolhidos = [(pecas.medidas[i],) for i in candidatos if pecas.medidas[i].area >= 0.25 * maior]

    fundo = Objetos(pdi.negativo(tinta))
    vazios = [fundo.medidas[j] for j in fundo.lista(1) if not fundo.toca_borda(j)]

    linhas, marcas = [], []
    for numero, (m,) in enumerate(ordem_de_leitura(escolhidos), 1):
        furos = [f for f in vazios if contem(m, f) and f.area >= 0.01 * m.largura * m.altura]
        valor = reconhecer_digito(m, furos, densidade_por_zonas(tinta, m))
        paridade = "par" if valor % 2 == 0 else "ímpar"
        linhas.append((numero, valor, paridade.capitalize()))
        marcas.append((f"{valor}: {paridade}", m, (m.centro[0], m.y_max + m.altura * 0.12), "red"))

    if len(linhas) == 1:
        resumo = f"Número reconhecido: {linhas[0][1]} ({linhas[0][2].lower()})."
    else:
        resumo = f"{len(linhas)} algarismos reconhecidos: " + ", ".join(str(l[1]) for l in linhas) + "."
    return Resultado(anotar(img, marcas), ["Dígito", "Número", "Classificação"], linhas, resumo)


# ----------------------------------------------------- Desafio 3: comprimidos

CIRCULARIDADE_MINIMA = 0.91   # comprimidos inteiros medem 0,92 a 0,95
PROPORCAO_MAXIMA = 1.10       # largura/altura acima disso: ovalado
TAMANHO_MINIMO = 0.80         # área abaixo de 80% da mediana: fora do padrão


def comprimidos(img):
    """Conta os comprimidos, mede área, perímetro e circularidade e aponta defeitos.

    As medidas usam a silhueta externa, então o sulco e as rachaduras internas
    não alteram a área nem o perímetro; lascas na borda reduzem a circularidade."""
    pilula = mascara(img, objeto_claro=True)
    pecas = Objetos(pilula)
    ordem = ordem_de_leitura([(pecas.medidas[i],) + pecas.externo(i)
                              for i in pecas.lista(img.largura * img.altura * 0.002)])
    areas = sorted(area for _, area, _ in ordem)
    area_tipica = areas[len(areas) // 2] if areas else 0

    linhas, marcas, defeituosos = [], [], 0
    for numero, (m, area, perimetro) in enumerate(ordem, 1):
        c = circularidade(area, perimetro)
        proporcao = max(m.largura, m.altura) / min(m.largura, m.altura)
        if proporcao > PROPORCAO_MAXIMA:
            situacao = "Formato irregular (ovalado)"
        elif c < CIRCULARIDADE_MINIMA:
            situacao = "Quebrado / borda irregular"
        elif area < TAMANHO_MINIMO * area_tipica:
            situacao = "Tamanho fora do padrão"
        else:
            situacao = "OK"
        defeituosos += situacao != "OK"
        linhas.append((numero, f"{area:.0f}", f"{perimetro:.1f}", f"{c:.3f}", situacao))
        marcas.append((str(numero), m, m.centro, "green" if situacao == "OK" else "red"))

    resumo = (f"{len(linhas)} comprimido(s): {len(linhas) - defeituosos} OK e "
              f"{defeituosos} com problema (em vermelho).")
    return Resultado(anotar(img, marcas),
                     ["Nº", "Área (px²)", "Perímetro (px)", "Circularidade", "Situação"], linhas, resumo)


# ------------------------------------------------ Desafio 4: círculos e quadrados

LIMIAR_BORDA = 100    # Sobel: variação de brilho que separa uma região da outra


def formas(img):
    """Conta círculos e quadrados e mede área e perímetro de cada um.

    As regiões são as áreas entre as bordas do Sobel (cada cor ou contorno
    vira uma região). Cada região é medida pela silhueta externa, para que um
    quadrado com um círculo desenhado dentro continue sendo um quadrado."""
    regioes = pdi.negativo(pdi.sobel(img, LIMIAR_BORDA))
    pecas = Objetos(regioes)
    achados = []
    for i in pecas.lista(img.largura * img.altura * 0.002):
        if pecas.toca_borda(i, margem=1):
            continue                                  # fundo em volta do tabuleiro
        m = pecas.medidas[i]
        area, perimetro = pecas.externo(i)
        if m.area < 0.3 * area:
            continue                                  # só um contorno (anel ou rede de linhas)
        c = circularidade(area, perimetro)
        proporcao = m.largura / m.altura
        if c >= 0.85:
            achados.append((m, "Círculo", area, perimetro))
        elif c >= 0.70 and 0.9 <= proporcao <= 1.1:
            achados.append((m, "Quadrado", area, perimetro))   # círculo ≈ 0,94; quadrado ≈ 0,79

    linhas, marcas = [], []
    for numero, (m, tipo, area, perimetro) in enumerate(ordem_de_leitura(achados), 1):
        linhas.append((numero, tipo, f"{area:.0f}", f"{perimetro:.1f}"))
        if tipo == "Círculo":
            marcas.append((str(numero), m, m.centro, "black"))
        else:   # no canto, para não cobrir o número de um círculo desenhado dentro do quadrado
            canto = (m.x_min + m.largura * 0.2, m.y_min + m.altura * 0.2)
            marcas.append((str(numero), m, canto, "magenta"))
    circulos = sum(1 for l in linhas if l[1] == "Círculo")
    resumo = f"{circulos} círculo(s) e {len(linhas) - circulos} quadrado(s)."
    return Resultado(anotar(img, marcas), ["Nº", "Forma", "Área (px²)", "Perímetro (px)"], linhas, resumo)


# --------------------------------------------------------- Desafio 5: folhas

CORES_FOLHA = {0: (255, 255, 255), 128: (40, 160, 40), 255: (255, 120, 0)}


def folha(img):
    """Separa folha, tecido sadio e ferrugem pela cor e classifica a folha."""
    if img.canais != 3:
        raise ValueError("a análise da folha precisa de uma imagem colorida")
    classes = pdi.mediana(pdi.ferrugem(img))           # 0 fundo, 128 sadia, 255 ferrugem
    sadia = classes.dados.count(128)
    ferrugem = classes.dados.count(255)
    area_folha = sadia + ferrugem
    percentual = 100 * ferrugem / area_folha if area_folha else 0.0
    if percentual <= 4:
        estado = "Saudável"
    elif percentual <= 30:
        estado = "Merece observação"
    else:
        estado = "Doente"

    figura = ImagemPIL.frombytes("P", (img.largura, img.altura), bytes(classes.dados))
    paleta = [0] * 768
    for indice, cor in CORES_FOLHA.items():
        paleta[indice * 3:indice * 3 + 3] = cor
    figura.putpalette(paleta)
    figura = figura.convert("RGB")
    segmentada = pdi.Imagem(figura.width, figura.height, 3, bytearray(figura.tobytes()))

    linhas = [("Área total da folha", f"{area_folha} px²"),
              ("Área com ferrugem", f"{ferrugem} px²"),
              ("Área sadia", f"{sadia} px²"),
              ("Superfície comprometida", f"{percentual:.2f} %"),
              ("Classificação", estado)]
    resumo = (f"{estado}: {percentual:.2f}% da folha com ferrugem "
              "(verde = sadia, laranja = ferrugem, branco = fundo).")
    return Resultado(segmentada, ["Medida", "Valor"], linhas, resumo)


EXERCICIOS = [
    ("Desafio 1: Porcas (metalúrgica)", porcas),
    ("Desafio 2: Dígito par ou ímpar", digitos),
    ("Desafio 3: Comprimidos", comprimidos),
    ("Desafio 4: Círculos e quadrados", formas),
    ("Desafio 5: Ferrugem na folha", folha),
]
