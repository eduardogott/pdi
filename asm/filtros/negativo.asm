; FUNÇÃO NEGATIVO.ASM
;
; ======= CHAMADA =======
; void pdi_negativo(const uint8_t *src, int largura, int altura, int canais,
;                   uint8_t *dst)
;
;
; ====== REGISTERS ======
;
; rdi = src (avança um byte por vez)
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src; avança junto com src)
; rax = bytes que faltam processar
; r9b = 255 - byte lido: o valor invertido
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Calcula em rax o número de bytes (largura * altura * canais); se 0, retorna
; 2. Para cada byte:
;   2.1 Lê o valor de src e calcula 255 - valor
;   2.2 Grava em dst, avança os dois ponteiros e decrementa rax
; 3. Retorna
;
;
; ===== OBSERVAÇÕES =====
;
;   g(x,y) = 255 - f(x,y)       (operação lógica NOT, aplicada a cada canal)
; Claro vira escuro e vice-versa. Usado antes da morfologia e da rotulação
; quando o objeto é escuro sobre fundo claro, pois essas técnicas tratam o
; objeto como a parte clara (255) da imagem.
; 255 - valor nunca sai de 0..255, então não precisa saturar.

%include "comum.inc"

section .text

global pdi_negativo:function    ; exporta a função para o Python

pdi_negativo:
    mov   eax, esi              ; rax = largura (zera a parte alta)
    mov   edx, edx              ; zera a parte alta da altura para as contas de 64 bits
    imul  rax, rdx              ; rax = largura * altura: quantos pixels
    mov   ecx, ecx              ; zera a parte alta dos canais
    imul  rax, rcx              ; rax = bytes da imagem: cada canal é invertido
    test  rax, rax              ; verifica se a imagem está vazia
    jz    .fim                  ; nada a inverter
.byte:
    mov   r9d, 255              ; começa de 255, o branco
    sub   r9b, [rdi]            ; r9b = 255 - valor: o complemento do pixel
    mov   [r8], r9b             ; grava o valor invertido
    inc   rdi                   ; próximo byte da origem
    inc   r8                    ; próximo byte do destino
    dec   rax                   ; desconta o byte processado
    jnz   .byte                 ; ainda há bytes: inverte o próximo
.fim:
    ret                         ; volta ao chamador; o resultado está em dst
