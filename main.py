#!/usr/bin/env python3
"""
main.py - Processamento Digital de Imagens (trabalho da disciplina)

Interface em Python/Tkinter: menus, as duas janelas (imagem original e
imagem transformada) e os diálogos. Toda transformação de imagem é feita em
assembly (pasta asm/, biblioteca lib/libpdi.so), chamada pelo módulo pdi.py.
Os exercícios do desafio final (menu Exercícios) estão em desafios.py.
Abrir e salvar arquivos usa a biblioteca Pillow.

Uso:  python3 main.py
"""

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

from PIL import Image as ImagemPIL

import desafios
import pdi

AUTORES = [("Eduardo Gottert", "eduardo@gttr.com.br")]
TITULO = "Processamento Digital de Imagens"
COR_TOPO = "#1f4e79"

INTEIRO = simpledialog.askinteger
REAL = simpledialog.askfloat


# ---------------------------------------------------------------- arquivos

def abrir_arquivo(caminho):
    """Lê o arquivo como cinza (1 canal) ou colorido RGB (3 canais)."""
    with ImagemPIL.open(caminho) as figura:
        modo = "L" if figura.mode in ("1", "L", "I", "I;16", "F") else "RGB"
        figura = figura.convert(modo)
    canais = 1 if modo == "L" else 3
    return pdi.Imagem(figura.width, figura.height, canais, bytearray(figura.tobytes()))


def salvar_arquivo(img, caminho):
    modo = "L" if img.canais == 1 else "RGB"
    ImagemPIL.frombytes(modo, (img.largura, img.altura), bytes(img.dados)).save(caminho)


def para_tela(img, largura_max, altura_max):
    """PhotoImage do Tk, reduzida por um fator inteiro até caber no espaço dado."""
    tipo = b"P5" if img.canais == 1 else b"P6"   # formato PGM/PPM, que o Tk lê direto
    ppm = b"%s %d %d 255\n" % (tipo, img.largura, img.altura) + bytes(img.dados)
    foto = tk.PhotoImage(data=ppm, format="ppm")
    fator = max(1, -(-img.largura // largura_max), -(-img.altura // altura_max))
    return foto.subsample(fator)


# ---------------------------------------------------------------- interface

class Painel(tk.LabelFrame):
    """Moldura com título que mostra uma imagem reduzida para caber nela."""

    def __init__(self, mestre, titulo):
        super().__init__(mestre, text=titulo, padx=4, pady=4)
        self.pack_propagate(False)     # a imagem não muda o tamanho do painel
        self.tela = tk.Label(self, background="#2b2b2b")
        self.tela.pack(fill="both", expand=True)
        self.foto = None               # guarda a referência, senão o Tk descarta a imagem

    def mostrar(self, img):
        self.update_idletasks()
        self.foto = para_tela(img, self.tela.winfo_width(), self.tela.winfo_height())
        self.tela.configure(image=self.foto)


class JanelaResultado(tk.Toplevel):
    """Janela com o resumo e a tabela de resultados de um exercício."""

    def __init__(self, mestre, titulo, resultado):
        super().__init__(mestre)
        self.title(titulo)
        # cada coluna com a largura do texto mais comprido (cerca de 8 pixels por letra)
        larguras = [20 + 8 * max(len(str(texto)) for texto in [coluna] + [l[k] for l in resultado.linhas])
                    for k, coluna in enumerate(resultado.colunas)]
        self.geometry(f"{max(480, min(1100, sum(larguras) + 40))}x400")
        tk.Label(self, text=resultado.resumo, font=("DejaVu Sans", 11, "bold"),
                 wraplength=max(440, sum(larguras)), justify="left").pack(anchor="w", padx=10, pady=(10, 6))
        quadro = tk.Frame(self)
        quadro.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        tabela = ttk.Treeview(quadro, columns=resultado.colunas, show="headings")
        for coluna, largura in zip(resultado.colunas, larguras):
            tabela.heading(coluna, text=coluna)
            tabela.column(coluna, anchor="center", width=largura)
        for linha in resultado.linhas:
            tabela.insert("", "end", values=linha)
        rolagem = ttk.Scrollbar(quadro, orient="vertical", command=tabela.yview)
        tabela.configure(yscrollcommand=rolagem.set)
        tabela.pack(side="left", fill="both", expand=True)
        rolagem.pack(side="right", fill="y")


class Aplicacao:
    def __init__(self, raiz):
        self.raiz = raiz
        self.original = None     # imagem aberta
        self.resultado = None    # imagem transformada; as técnicas se acumulam sobre ela
        raiz.title(TITULO)
        raiz.geometry("1200x750")

        topo = tk.Frame(raiz, background=COR_TOPO)
        topo.pack(fill="x")
        tk.Label(topo, text=TITULO, fg="white", bg=COR_TOPO,
                 font=("DejaVu Sans", 15, "bold")).pack(side="left", padx=12, pady=8)
        autores = "Autores: " + ", ".join(f"{nome} <{email}>" for nome, email in AUTORES)
        tk.Label(topo, text=autores, fg="white", bg=COR_TOPO).pack(side="right", padx=12)

        corpo = tk.Frame(raiz)
        corpo.pack(fill="both", expand=True, padx=8, pady=8)
        corpo.columnconfigure((0, 1), weight=1, uniform="painel")
        corpo.rowconfigure(0, weight=1)
        self.painel_original = Painel(corpo, "Imagem original")
        self.painel_original.grid(row=0, column=0, sticky="nsew", padx=(0, 4))
        self.painel_resultado = Painel(corpo, "Imagem transformada")
        self.painel_resultado.grid(row=0, column=1, sticky="nsew", padx=(4, 0))

        self.criar_menus()

    def criar_menus(self):
        barra = tk.Menu(self.raiz)
        self.raiz.config(menu=barra)

        def menu(titulo, itens):
            submenu = tk.Menu(barra, tearoff=False)
            for rotulo, comando in itens:
                submenu.add_command(label=rotulo, command=comando)
            barra.add_cascade(label=titulo, menu=submenu)

        aplicar = self.aplicar
        menu("Arquivo", [
            ("Abrir imagem...", self.abrir),
            ("Salvar imagem...", self.salvar),
            ("Sobre", self.sobre),
            ("Sair", self.raiz.destroy),
        ])
        menu("Transformações Geométricas", [
            ("Transladar...", lambda: aplicar(
                pdi.transladar,
                (INTEIRO, "Deslocamento em x (pixels, positivo = direita):", -10000, 10000),
                (INTEIRO, "Deslocamento em y (pixels, positivo = baixo):", -10000, 10000))),
            ("Rotacionar...", lambda: aplicar(
                pdi.rotacionar, (REAL, "Ângulo em graus (positivo = sentido horário):", -360, 360))),
            ("Espelhar na horizontal", lambda: aplicar(lambda img: pdi.espelhar(img, True))),
            ("Espelhar na vertical", lambda: aplicar(lambda img: pdi.espelhar(img, False))),
            ("Aumentar...", lambda: aplicar(pdi.aumentar, (REAL, "Aumentar quantas vezes?", 1, 10))),
            ("Diminuir...", lambda: aplicar(pdi.diminuir, (REAL, "Diminuir quantas vezes?", 1, 100))),
        ])
        menu("Filtros", [
            ("Grayscale", lambda: aplicar(pdi.grayscale)),
            ("Negativo", lambda: aplicar(pdi.negativo)),
            ("Brilho e Contraste...", lambda: aplicar(
                pdi.brilho_contraste,
                (REAL, "Contraste C (1 = sem alteração):", 0, 10),
                (REAL, "Brilho B (0 = sem alteração):", -255, 255))),
            ("Passa Baixa (Média)", lambda: aplicar(pdi.media)),
            ("Passa Baixa (Moda)", lambda: aplicar(pdi.moda)),
            ("Passa Baixa (Mediana)", lambda: aplicar(pdi.mediana)),
            ("Passa Baixa (Gaussiano)", lambda: aplicar(pdi.gaussiano)),
            ("Passa Alta", lambda: aplicar(pdi.passa_alta)),
            ("Threshold...", lambda: aplicar(pdi.threshold, (INTEIRO, "Limiar T (0 a 255):", 0, 255))),
            ("Detecção de Bordas (Roberts)...", lambda: aplicar(
                pdi.roberts, (INTEIRO, "Limiar (é borda se G > limiar):", 0, 360))),
            ("Detecção de Bordas (Sobel)...", lambda: aplicar(
                pdi.sobel, (INTEIRO, "Limiar (é borda se G > limiar):", 0, 1500))),
        ])
        elemento = (INTEIRO, "Valor do elemento estruturante em cruz 3x3\n"
                             "(0 para imagens binárias):", 0, 255)
        menu("Morfologia Matemática", [
            ("Dilatação...", lambda: aplicar(pdi.dilatacao, elemento)),
            ("Erosão...", lambda: aplicar(pdi.erosao, elemento)),
            ("Abertura...", lambda: aplicar(pdi.abertura, elemento)),
            ("Fechamento...", lambda: aplicar(pdi.fechamento, elemento)),
            ("Afinamento (Zhang-Suen)", lambda: aplicar(pdi.afinamento)),
        ])
        menu("Exercícios", [
            (rotulo, lambda r=rotulo, f=exercicio: self.exercicio(r, f))
            for rotulo, exercicio in desafios.EXERCICIOS])

    # ------------------------------------------------------------ técnicas
    def tem_imagem(self):
        if self.resultado is None:
            messagebox.showinfo(TITULO, "Abra uma imagem primeiro (Arquivo → Abrir imagem).")
        return self.resultado is not None

    def aplicar(self, funcao, *perguntas):
        """Pergunta os parâmetros e aplica a técnica sobre a imagem transformada.

        Cada pergunta é (diálogo, texto, mínimo, máximo)."""
        if not self.tem_imagem():
            return
        valores = []
        for dialogo, texto, minimo, maximo in perguntas:
            valor = dialogo(TITULO, texto, parent=self.raiz, minvalue=minimo, maxvalue=maximo)
            if valor is None:            # o usuário cancelou
                return
            valores.append(valor)
        self.resultado = funcao(self.resultado, *valores)
        self.painel_resultado.mostrar(self.resultado)

    def exercicio(self, titulo, funcao):
        """Roda um exercício sobre a imagem original e mostra a imagem e a tabela."""
        if not self.tem_imagem():
            return
        try:
            resultado = funcao(self.original)
        except ValueError as erro:
            messagebox.showerror(TITULO, str(erro))
            return
        self.resultado = resultado.imagem
        self.painel_resultado.mostrar(self.resultado)
        JanelaResultado(self.raiz, titulo, resultado)

    # ------------------------------------------------------------ arquivo
    def abrir(self):
        caminho = filedialog.askopenfilename(
            parent=self.raiz, title="Abrir imagem",
            filetypes=[("Imagens", "*.png *.jpg *.jpeg *.bmp *.gif *.tif *.tiff *.webp"),
                       ("Todos os arquivos", "*")])
        if not caminho:
            return
        try:
            self.original = abrir_arquivo(caminho)
        except OSError as erro:
            messagebox.showerror(TITULO, f"Não foi possível abrir a imagem:\n{erro}")
            return
        self.resultado = self.original
        self.painel_original.mostrar(self.original)
        self.painel_resultado.mostrar(self.resultado)

    def salvar(self):
        if not self.tem_imagem():
            return
        caminho = filedialog.asksaveasfilename(
            parent=self.raiz, title="Salvar imagem transformada", defaultextension=".png",
            filetypes=[("PNG", "*.png"), ("JPEG", "*.jpg"), ("BMP", "*.bmp")])
        if not caminho:
            return
        try:
            salvar_arquivo(self.resultado, caminho)
        except (OSError, ValueError) as erro:
            messagebox.showerror(TITULO, f"Não foi possível salvar a imagem:\n{erro}")

    def sobre(self):
        autores = "\n".join(f"{nome} <{email}>" for nome, email in AUTORES)
        messagebox.showinfo("Sobre", f"{TITULO}\n\nAutores:\n{autores}\n\n"
                                     "Interface: Python + Tkinter\n"
                                     "Transformações: assembly x86-64 (NASM, System V AMD64)")


if __name__ == "__main__":
    janela = tk.Tk()
    Aplicacao(janela)
    janela.mainloop()
