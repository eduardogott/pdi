; FUNÇÃO ESPELHAR.ASM
;
; ======= CHAMADA =======
; void pdi_espelhar(const uint8_t *src, int largura, int altura, int canais,
;                   uint8_t *dst, int horizontal)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo tamanho e canais de src)
; r9d = horizontal (diferente de 0 -> horizontal; 0 -> vertical)
;       depois, largura_dst
; xmm0 = 1.0 e depois -1.0     xmm1 = 0.0
; xmm2 = largura-1 ou altura-1 em double
; eax  = largura-1 ou altura-1 / rax = endereço da matriz
;
; Pilha (72 bytes, mesma organização de transladar.asm):
; [rsp] = altura_dst   [rsp+8] = endereço da matriz   [rsp+16..56] = matriz
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Reserva 72 bytes na pilha para os argumentos e a matriz
; 2. Monta a matriz identidade [1 0 0 ; 0 1 0]
; 3. Horizontal: a = -1 e c = largura-1
;    Vertical:   e = -1 e f = altura-1
; 4. Chama pdi_transformar com o destino do mesmo tamanho da origem
; 5. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
;   Horizontal: xo = -x + largura-1   (a coluna 0 vem da última coluna)
;   Vertical:   yo = -y + altura-1    (a linha 0 vem da última linha)
; Espelhar duas vezes volta ao original, então a matriz inversa é a própria
; matriz do espelhamento.

%include "comum.inc"

section .rodata
UM        dq 1.0                ; diagonal da identidade
MENOS_UM  dq -1.0               ; inverte o sentido de um eixo

section .text

global pdi_espelhar:function    ; exporta a função para o Python
extern pdi_transformar          ; suporte/matriz_transformacao.asm

pdi_espelhar:
    sub   rsp, 72               ; reserva espaço para os argumentos e a matriz (alinhado em 16)
    movsd xmm0, [UM]            ; carrega 1.0
    xorpd xmm1, xmm1            ; xmm1 = 0.0 (xor de um valor com ele mesmo zera todos os bits)
    movsd [rsp+16], xmm0        ; começa com a identidade: a = 1
    movsd [rsp+24], xmm1        ; b = 0
    movsd [rsp+32], xmm1        ; c = 0
    movsd [rsp+40], xmm1        ; d = 0
    movsd [rsp+48], xmm0        ; e = 1
    movsd [rsp+56], xmm1        ; f = 0
    movsd xmm0, [MENOS_UM]      ; carrega -1.0, que inverte o eixo escolhido
    test  r9d, r9d              ; verifica se o espelhamento é horizontal
    jz    .vertical             ; 0: espelha na vertical
    movsd [rsp+16], xmm0        ; a = -1: inverte o x (esquerda troca com direita)
    lea   eax, [rsi-1]          ; eax = largura - 1, a última coluna
    cvtsi2sd xmm2, eax          ; converte para double
    movsd [rsp+32], xmm2        ; c = largura - 1: traz a imagem de volta para a tela
    jmp   .chama                ; matriz pronta
.vertical:
    movsd [rsp+48], xmm0        ; e = -1: inverte o y (cima troca com baixo)
    lea   eax, [rdx-1]          ; eax = altura - 1, a última linha
    cvtsi2sd xmm2, eax          ; converte para double
    movsd [rsp+56], xmm2        ; f = altura - 1: traz a imagem de volta para a tela
.chama:
    mov   r9d, esi              ; 6º argumento: largura_dst = largura (mesmo tamanho)
    mov   [rsp], edx            ; 7º argumento: altura_dst = altura
    lea   rax, [rsp+16]         ; calcula o endereço da matriz montada na pilha
    mov   [rsp+8], rax          ; 8º argumento: endereço da matriz
    call  pdi_transformar wrt ..plt ; aplica a matriz em todos os pixels
    add   rsp, 72               ; libera os argumentos e a matriz
    ret                         ; volta ao chamador; o resultado está em dst
