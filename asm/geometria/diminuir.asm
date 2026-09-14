; FUNÇÃO DIMINUIR.ASM
;
; ======= CHAMADA =======
; void pdi_diminuir(const uint8_t *src, int largura, int altura, int canais,
;                   uint8_t *dst, int largura_dst, int altura_dst, double fator)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (largura_dst x altura_dst, mesmos canais de src)
; r9d = largura_dst
; [rsp+8] = altura_dst
; xmm0 = fator (quantas vezes menor, ex.: 2 = metade)
; r10 = altura_dst
; xmm1 = s = fator    xmm2 = (s-1)/2    xmm3 = 0.0
; rax = endereço da matriz
;
; Pilha (72 bytes, mesma organização de transladar.asm):
; [rsp] = altura_dst   [rsp+8] = endereço da matriz   [rsp+16..56] = matriz
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Lê altura_dst da pilha (r10) e reserva 72 bytes
; 2. Usa s = fator e calcula o ajuste de centro (s-1)/2
; 3. Monta a matriz inversa [s 0 (s-1)/2 ; 0 s (s-1)/2]
; 4. Chama pdi_transformar (largura_dst já está em r9)
; 5. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Diminuir f vezes: o pixel x do destino vem do pixel x*f da origem.
; Com o ajuste (s-1)/2, cada pixel do destino pega o pixel CENTRAL do bloco
; f x f correspondente na origem.
; Quem chama aloca o destino com largura/fator por altura/fator.

%include "comum.inc"

section .rodata
UM      dq 1.0                  ; para calcular s - 1
MEIO    dq 0.5                  ; para dividir por 2 multiplicando

section .text

global pdi_diminuir:function    ; exporta a função para o Python
extern pdi_transformar          ; suporte/matriz_transformacao.asm

pdi_diminuir:
    mov   r10d, [rsp+8]         ; lê altura_dst (7º argumento) antes de mexer na pilha
    sub   rsp, 72               ; reserva espaço para os argumentos e a matriz
    movapd xmm1, xmm0           ; s = fator: cada pixel do destino anda 'fator' pixels na origem
    movapd xmm2, xmm1           ; copia s
    subsd xmm2, [UM]            ; xmm2 = s - 1
    mulsd xmm2, [MEIO]          ; xmm2 = (s - 1) / 2: ajuste que pega o centro do bloco
    xorpd xmm3, xmm3            ; xmm3 = 0.0 (xor de um valor com ele mesmo zera todos os bits)
    movsd [rsp+16], xmm1        ; a = s
    movsd [rsp+24], xmm3        ; b = 0
    movsd [rsp+32], xmm2        ; c = (s-1)/2
    movsd [rsp+40], xmm3        ; d = 0
    movsd [rsp+48], xmm1        ; e = s
    movsd [rsp+56], xmm2        ; f = (s-1)/2
    mov   [rsp], r10d           ; 7º argumento: altura_dst (r9 já tem largura_dst)
    lea   rax, [rsp+16]         ; calcula o endereço da matriz montada na pilha
    mov   [rsp+8], rax          ; 8º argumento: endereço da matriz
    call  pdi_transformar wrt ..plt ; aplica a matriz em todos os pixels
    add   rsp, 72               ; libera os argumentos e a matriz
    ret                         ; volta ao chamador; o resultado está em dst
