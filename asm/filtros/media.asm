; FUNÇÃO MEDIA.ASM
;
; ======= CHAMADA =======
; void pdi_media(const uint8_t *src, int largura, int altura, int canais,
;                uint8_t *dst)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9  = endereço da máscara (6º argumento de pdi_convolucao)
; [rsp] = divisor (7º argumento de pdi_convolucao)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Reserva 8 bytes na pilha e coloca neles o divisor 9
; 2. Passa em r9 a máscara 3x3 de pesos iguais a 1
; 3. Chama pdi_convolucao (os 5 primeiros argumentos não mudam)
; 4. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Filtro passa-baixa da média: cada pixel vira a média dos 9 pixels da
; janela 3x3.
; Efeito: suaviza (borra) a imagem e reduz ruído.
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 8 = múltiplo de 16.

%include "comum.inc"

section .rodata
MASCARA:     dd 1, 1, 1         ; todos os vizinhos pesam igual:
             dd 1, 1, 1         ; soma dos 9 pixels,
             dd 1, 1, 1         ; que depois é dividida por 9

section .text

global pdi_media:function       ; exporta a função para o Python
extern pdi_convolucao           ; suporte/convolucao.asm

pdi_media:
    sub   rsp, 8                ; reserva espaço para o 7º argumento e alinha a pilha em 16
    mov   dword [rsp], 9        ; 7º argumento: divide por 9, a quantidade de pixels da janela
    lea   r9, [MASCARA]         ; 6º argumento: endereço da máscara de uns
    call  pdi_convolucao wrt ..plt ; aplica a máscara em todos os pixels
    add   rsp, 8                ; libera o espaço do argumento
    ret                         ; volta ao chamador; o resultado está em dst
