; FUNÇÃO PASSA_ALTA.ASM
;
; ======= CHAMADA =======
; void pdi_passa_alta(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst)
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
; 1. Reserva 8 bytes na pilha e coloca neles o divisor 1
; 2. Passa em r9 a máscara passa-alta 3x3
; 3. Chama pdi_convolucao (os 5 primeiros argumentos não mudam)
; 4. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Realça variações bruscas (bordas, linhas, detalhes). A soma dos pesos é 0,
; então regiões uniformes ficam pretas e só as variações aparecem.
; O divisor é 1 porque não faz sentido dividir pela soma dos pesos (0).
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 8 = múltiplo de 16.

%include "comum.inc"

section .rodata
MASCARA:     dd -1, -1, -1      ; centro * 8 menos os 8 vizinhos:
             dd -1,  8, -1      ; região uniforme dá 0 (preto),
             dd -1, -1, -1      ; só as variações sobram

section .text

global pdi_passa_alta:function  ; exporta a função para o Python
extern pdi_convolucao           ; suporte/convolucao.asm

pdi_passa_alta:
    sub   rsp, 8                ; reserva espaço para o 7º argumento e alinha a pilha em 16
    mov   dword [rsp], 1        ; 7º argumento: divisor 1, a soma não é dividida
    lea   r9, [MASCARA]         ; 6º argumento: endereço da máscara passa-alta
    call  pdi_convolucao wrt ..plt ; aplica a máscara em todos os pixels
    add   rsp, 8                ; libera o espaço do argumento
    ret                         ; volta ao chamador; o resultado está em dst
