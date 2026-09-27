; FUNÇÃO GAUSSIANO.ASM
;
; ======= CHAMADA =======
; void pdi_gaussiano(const uint8_t *src, int largura, int altura, int canais,
;                    uint8_t *dst)
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
; 1. Reserva 8 bytes na pilha e coloca neles o divisor 16
; 2. Passa em r9 a máscara gaussiana 3x3
; 3. Chama pdi_convolucao (os 5 primeiros argumentos não mudam)
; 4. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Filtro passa-baixa gaussiano: forma discreta 3x3 da função gaussiana.
;          1 [ 1 2 1 ]
;   G  =  -- [ 2 4 2 ]
;         16 [ 1 2 1 ]
; Como a média, suaviza e reduz ruído, mas o pixel central e os vizinhos mais
; próximos pesam mais, então borra menos que a média.
; O divisor é 16 porque é a soma dos pesos.
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 8 = múltiplo de 16.

%include "comum.inc"

section .rodata
MASCARA:     dd 1, 2, 1         ; os cantos pesam 1, os vizinhos
             dd 2, 4, 2         ; de lado pesam 2 e o centro pesa 4:
             dd 1, 2, 1         ; quanto mais perto do centro, maior o peso

section .text

global pdi_gaussiano:function   ; exporta a função para o Python
extern pdi_convolucao           ; suporte/convolucao.asm

pdi_gaussiano:
    sub   rsp, 8                ; reserva espaço para o 7º argumento e alinha a pilha em 16
    mov   dword [rsp], 16       ; 7º argumento: divide por 16, a soma dos pesos
    lea   r9, [MASCARA]         ; 6º argumento: endereço da máscara gaussiana
    call  pdi_convolucao wrt ..plt ; aplica a máscara em todos os pixels
    add   rsp, 8                ; libera o espaço do argumento
    ret                         ; volta ao chamador; o resultado está em dst
