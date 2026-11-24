; FUNÇÃO DILATACAO.ASM
;
; ======= CHAMADA =======
; void pdi_dilatacao(const uint8_t *src, int largura, int altura, int canais,
;                    uint8_t *dst, int valor)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9d = valor do elemento estruturante (cruz 3x3)
; [rsp] = 7º argumento de pdi_morfologia: 1 = dilatar
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Reserva espaço na pilha para o 7º argumento e alinha a pilha
; 2. Chama pdi_morfologia com dilatar = 1 (os 6 primeiros argumentos não mudam)
; 3. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Dilatação em tons de cinza: cada janela da cruz recebe a maior soma
; (pixel + valor do elemento) entre os pixels que ela cobre. O objeto claro
; cresce, buracos e quebras pequenas são preenchidos.
; O procedimento completo está em suporte/morfologia.asm.

%include "comum.inc"

section .text

global pdi_dilatacao:function   ; exporta a função para o Python e para abertura/fechamento
extern pdi_morfologia           ; suporte/morfologia.asm

pdi_dilatacao:
    sub   rsp, 8                ; reserva espaço para o 7º argumento e alinha a pilha em 16
    mov   dword [rsp], 1        ; 7º argumento: 1 = dilatar (maior soma)
    call  pdi_morfologia wrt ..plt ; percorre a imagem com o elemento estruturante
    add   rsp, 8                ; libera o espaço do argumento
    ret                         ; volta ao chamador; o resultado está em dst
