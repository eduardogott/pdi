"""
pdi.py - ponte entre o Python e as funções em assembly (lib/libpdi.so).

Toda a transformação das imagens acontece em assembly. Este módulo só:
  * carrega a biblioteca com ctypes e declara os tipos dos argumentos
    (o ctypes então segue a convenção System V AMD64 ao chamar);
  * reserva o buffer de saída com o tamanho certo;
  * passa os endereços dos buffers para as funções.

Se lib/libpdi.so não existir, rode ./compilar.sh.
"""

import ctypes
import os
from dataclasses import dataclass

CAMINHO_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib", "libpdi.so")


@dataclass
class Imagem:
    """Buffer de bytes linha por linha; canais = 1 (cinza) ou 3 (R, G, B)."""

    largura: int
    altura: int
    canais: int
    dados: bytearray


_lib = ctypes.CDLL(CAMINHO_LIB)

_U8P = ctypes.POINTER(ctypes.c_uint8)
_INT = ctypes.c_int
_DOUBLE = ctypes.c_double
_IMAGEM = [_U8P, _INT, _INT, _INT, _U8P]   # src, largura, altura, canais, dst


def _declarar(nome, *extras):
    """Todas as funções recebem a imagem e o destino, seguidos dos parâmetros extras."""
    funcao = getattr(_lib, nome)
    funcao.argtypes = _IMAGEM + list(extras)
    funcao.restype = None
    return funcao


_grayscale = _declarar("pdi_grayscale")
_brilho_contraste = _declarar("pdi_brilho_contraste", _DOUBLE, _DOUBLE)
_threshold = _declarar("pdi_threshold", _INT)
_passa_baixa = _declarar("pdi_passa_baixa")
_passa_alta = _declarar("pdi_passa_alta")
_sobel = _declarar("pdi_sobel", _INT)
_transladar = _declarar("pdi_transladar", _INT, _INT)
_rotacionar = _declarar("pdi_rotacionar", _DOUBLE)
_espelhar = _declarar("pdi_espelhar", _INT)
_aumentar = _declarar("pdi_aumentar", _INT, _INT, _DOUBLE)
_diminuir = _declarar("pdi_diminuir", _INT, _INT, _DOUBLE)


def _endereco(buffer):
    """Endereço do bytearray, sem copiar: o assembly lê e escreve direto nele."""
    return (ctypes.c_uint8 * len(buffer)).from_buffer(buffer)


def _executar(funcao, img, canais, *extras, largura=None, altura=None):
    """Cria a imagem de saída (por padrão, do mesmo tamanho) e chama o assembly."""
    largura = largura or img.largura
    altura = altura or img.altura
    saida = Imagem(largura, altura, canais, bytearray(largura * altura * canais))
    funcao(_endereco(img.dados), img.largura, img.altura, img.canais,
           _endereco(saida.dados), *extras)
    return saida


# ------------------------------------------------------------------ filtros

def grayscale(img):
    return _executar(_grayscale, img, 1)


def brilho_contraste(img, contraste, brilho):
    return _executar(_brilho_contraste, img, img.canais, contraste, brilho)


def threshold(img, limiar):
    return _executar(_threshold, img, 1, limiar)


def passa_baixa(img):
    return _executar(_passa_baixa, img, img.canais)


def passa_alta(img):
    return _executar(_passa_alta, img, img.canais)


def sobel(img, limiar):
    return _executar(_sobel, img, 1, limiar)


# ---------------------------------------------------- transformações geométricas

def transladar(img, tx, ty):
    return _executar(_transladar, img, img.canais, tx, ty)


def rotacionar(img, graus):
    return _executar(_rotacionar, img, img.canais, graus)


def espelhar(img, horizontal):
    return _executar(_espelhar, img, img.canais, 1 if horizontal else 0)


def aumentar(img, fator):
    largura = max(1, round(img.largura * fator))
    altura = max(1, round(img.altura * fator))
    return _executar(_aumentar, img, img.canais, largura, altura, fator,
                     largura=largura, altura=altura)


def diminuir(img, fator):
    largura = max(1, round(img.largura / fator))
    altura = max(1, round(img.altura / fator))
    return _executar(_diminuir, img, img.canais, largura, altura, fator,
                     largura=largura, altura=altura)
