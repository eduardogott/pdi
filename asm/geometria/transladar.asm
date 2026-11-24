; FUNÇÃO TRANSLADAR.ASM
;
; ======= CHAMADA =======
; void pdi_transladar(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst, int tx, int ty)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo tamanho e canais de src)
; r9d = tx (deslocamento em x, positivo = direita)
; [rsp+8] = ty (deslocamento em y, positivo = baixo)
; r9  = -tx em 64 bits / depois, largura_dst
; r10 = -ty em 64 bits
; xmm0 = 1.0   xmm1 = 0.0   xmm2 = -tx ou -ty em double
; rax = endereço da matriz
;
; Pilha no momento do call (72 bytes reservados):
; [rsp]    = 7º argumento de pdi_transformar (altura_dst)
; [rsp+8]  = 8º argumento (endereço da matriz)
; [rsp+16] .. [rsp+56] = a matriz inversa (6 doubles)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Lê tx e ty com sinal e troca o sinal dos dois
; 2. Reserva 72 bytes na pilha para os argumentos e a matriz
; 3. Monta a matriz inversa [1 0 -tx ; 0 1 -ty]
; 4. Chama pdi_transformar com o destino do mesmo tamanho da origem
; 5. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Translação: o pixel (x, y) do destino vem do pixel (x - tx, y - ty) da origem.
; O eixo y cresce para baixo: ty positivo move a imagem para baixo.
; O que sai da tela é perdido e a área descoberta fica preta.
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 72 = múltiplo de 16.

%include "comum.inc"

section .rodata
UM      dq 1.0                  ; diagonal da matriz: não altera a escala

section .text

global pdi_transladar:function  ; exporta a função para o Python
extern pdi_transformar          ; suporte/matriz_transformacao.asm

pdi_transladar:
    movsxd r10, dword [rsp+8]   ; lê ty (7º argumento) antes de mexer na pilha, mantendo o sinal
    movsxd r9, r9d              ; estende tx para 64 bits mantendo o sinal (pode ser negativo)
    sub   rsp, 72               ; reserva espaço para os argumentos e a matriz
    neg   r9                    ; -tx: para achar a origem, anda no sentido contrário
    neg   r10                   ; -ty
    movsd xmm0, [UM]            ; xmm0 = 1.0, a diagonal da matriz (translação não muda a escala)
    xorpd xmm1, xmm1            ; xmm1 = 0.0 (xor de um valor com ele mesmo zera todos os bits)
    movsd [rsp+16], xmm0        ; a = 1: xo acompanha x
    movsd [rsp+24], xmm1        ; b = 0: xo não depende de y
    cvtsi2sd xmm2, r9           ; converte -tx para double
    movsd [rsp+32], xmm2        ; c = -tx
    movsd [rsp+40], xmm1        ; d = 0: yo não depende de x
    movsd [rsp+48], xmm0        ; e = 1: yo acompanha y
    cvtsi2sd xmm2, r10          ; converte -ty para double
    movsd [rsp+56], xmm2        ; f = -ty
    mov   r9d, esi              ; 6º argumento: largura_dst = largura (mesmo tamanho)
    mov   [rsp], edx            ; 7º argumento: altura_dst = altura
    lea   rax, [rsp+16]         ; calcula o endereço da matriz montada na pilha
    mov   [rsp+8], rax          ; 8º argumento: endereço da matriz
    call  pdi_transformar wrt ..plt ; aplica a matriz em todos os pixels
    add   rsp, 72               ; libera os argumentos e a matriz
    ret                         ; volta ao chamador; o resultado está em dst
