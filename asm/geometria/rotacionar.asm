; FUNÇÃO ROTACIONAR.ASM
;
; ======= CHAMADA =======
; void pdi_rotacionar(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst, double graus)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo tamanho e canais de src)
; xmm0 = ângulo em graus (vira radianos)
; xmm1 = cos     xmm2 = sen     xmm3 = -sen
; xmm4 = cx      xmm5 = cy      (centro da imagem)
; xmm6 = 0.5     xmm0, xmm7 = contas de c e f
; eax = largura-1 ou altura-1 / rax = endereço da matriz
;
; Pilha (72 bytes):
; [rsp] = altura_dst   [rsp+8] = endereço da matriz   [rsp+16..56] = matriz
; [rsp+64] = área de troca de valores com a FPU x87
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Reserva 72 bytes na pilha
; 2. Converte o ângulo para radianos e calcula cosseno e seno na FPU x87,
;    gravando-os direto nas posições a e b da matriz
; 3. Calcula o centro da imagem (cx, cy)
; 4. Completa a matriz inversa [cos sen c ; -sen cos f], com
;    c = cx - cos*cx - sen*cy   e   f = cy + sen*cx - cos*cy
; 5. Chama pdi_transformar com o destino do mesmo tamanho da origem
; 6. Libera a pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Gira em torno do centro. Para achar a origem de um pixel do destino, gira
; a posição dele pelo ângulo contrário:
;     xo - cx =  cos*(x - cx) + sen*(y - cy)
;     yo - cy = -sen*(x - cx) + cos*(y - cy)
; Como o eixo y da tela cresce para BAIXO, ângulo positivo = sentido HORÁRIO.
; O destino tem o mesmo tamanho da origem: as pontas que saem são cortadas e
; os cantos descobertos ficam pretos.
; Seno e cosseno vêm da FPU x87 (instrução fsincos), já que não usamos a libc.
; A x87 é uma calculadora de ponto flutuante embutida no processador, com
; pilha própria (ST0, ST1, ...), que só troca dados pela memória.

%include "comum.inc"

section .rodata
MEIO        dq 0.5                      ; para calcular o centro (n-1)/2
GRAUS_P_RAD dq 0.017453292519943295     ; pi / 180: converte graus em radianos

section .text

global pdi_rotacionar:function  ; exporta a função para o Python
extern pdi_transformar          ; suporte/matriz_transformacao.asm

pdi_rotacionar:
    sub   rsp, 72               ; reserva argumentos, matriz e área da x87 (8 - 72 = múltiplo de 16)
    mulsd xmm0, [GRAUS_P_RAD]   ; converte o ângulo para radianos, que é o que o seno espera
    movsd [rsp+64], xmm0        ; coloca o ângulo na memória, única forma de passá-lo à x87
    fld   qword [rsp+64]        ; empilha o ângulo na pilha da FPU (ST0)
    fsincos                     ; calcula os dois de uma vez: ST0 = cos, ST1 = sen
    fstp  qword [rsp+16]        ; a = cos (tira o cosseno da pilha x87 direto para a matriz)
    fstp  qword [rsp+24]        ; b = sen (a pilha x87 fica vazia, como a ABI exige)
    movsd xmm1, [rsp+16]        ; xmm1 = cos, para as contas com SSE
    movsd xmm2, [rsp+24]        ; xmm2 = sen
    movsd [rsp+48], xmm1        ; e = cos
    xorpd xmm3, xmm3            ; xmm3 = 0.0 (xor de um valor com ele mesmo zera todos os bits)
    subsd xmm3, xmm2            ; xmm3 = -sen
    movsd [rsp+40], xmm3        ; d = -sen

    movsd xmm6, [MEIO]          ; xmm6 = 0.5, para dividir por 2 multiplicando
    lea   eax, [rsi-1]          ; eax = largura - 1 (índice da última coluna)
    cvtsi2sd xmm4, eax          ; converte para double
    mulsd xmm4, xmm6            ; cx = (largura-1)/2: coluna central
    lea   eax, [rdx-1]          ; eax = altura - 1 (índice da última linha)
    cvtsi2sd xmm5, eax          ; converte para double
    mulsd xmm5, xmm6            ; cy = (altura-1)/2: linha central

    ; c = cx - cos*cx - sen*cy: faz o centro do destino buscar o centro da origem
    movapd xmm0, xmm1           ; copia cos
    mulsd xmm0, xmm4            ; xmm0 = cos*cx
    movapd xmm7, xmm4           ; parte de cx
    subsd xmm7, xmm0            ; xmm7 = cx - cos*cx
    movapd xmm0, xmm2           ; copia sen
    mulsd xmm0, xmm5            ; xmm0 = sen*cy
    subsd xmm7, xmm0            ; xmm7 = cx - cos*cx - sen*cy
    movsd [rsp+32], xmm7        ; grava c na matriz

    ; f = cy + sen*cx - cos*cy
    movapd xmm0, xmm2           ; copia sen
    mulsd xmm0, xmm4            ; xmm0 = sen*cx
    movapd xmm7, xmm5           ; parte de cy
    addsd xmm7, xmm0            ; xmm7 = cy + sen*cx
    movapd xmm0, xmm1           ; copia cos
    mulsd xmm0, xmm5            ; xmm0 = cos*cy
    subsd xmm7, xmm0            ; xmm7 = cy + sen*cx - cos*cy
    movsd [rsp+56], xmm7        ; grava f na matriz

    mov   r9d, esi              ; 6º argumento: largura_dst = largura (mesmo tamanho)
    mov   [rsp], edx            ; 7º argumento: altura_dst = altura
    lea   rax, [rsp+16]         ; calcula o endereço da matriz montada na pilha
    mov   [rsp+8], rax          ; 8º argumento: endereço da matriz
    call  pdi_transformar wrt ..plt ; aplica a matriz em todos os pixels
    add   rsp, 72               ; libera argumentos, matriz e área da x87
    ret                         ; volta ao chamador; o resultado está em dst
