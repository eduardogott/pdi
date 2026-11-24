; FUNÇÃO FERRUGEM.ASM
;
; ======= CHAMADA =======
; void pdi_ferrugem(const uint8_t *src, int largura, int altura, int canais,
;                   uint8_t *dst)
;
;
; ====== REGISTERS ======
;
; rdi = src (avança um pixel por vez)
; esi = largura
; edx = altura
; ecx = canais (precisa ser 3: a classificação é pela cor)
; r8  = dst (sempre 1 canal: 0 = fundo, 128 = folha sadia, 255 = ferrugem)
; rax = pixels que faltam classificar
; r9d = vermelho (R)   r10d = verde (G)   r11d = azul (B)
; esi = maior canal    edx = menor canal / diferença (saturação)
; cl  = classe do pixel
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Calcula em rax o número de pixels; se for 0, retorna
; 2. Se a imagem não tiver 3 canais, não há cor: pinta tudo como fundo
; 3. Para cada pixel:
;   3.1 Lê R, G e B e calcula o maior e o menor dos três
;   3.2 Se maior - menor < 40, o pixel é cinza/branco: fundo (0)
;   3.3 Senão, se R >= G, o tom vai do vermelho ao amarelo (laranja,
;       marrom, amarelo): ferrugem (255)
;   3.4 Senão o verde predomina: folha sadia (128)
;   3.5 Grava a classe, avança e repete
; 4. Retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Segmentação por cor do Desafio 5 (análise de plantas):
;   maior - menor  -> mede a saturação: o fundo é branco ou cinza, com os
;                     três canais quase iguais; a folha é colorida
;   R >= G         -> as manchas de ferrugem são amareladas, alaranjadas ou
;                     marrons, tons em que o vermelho alcança ou passa o verde;
;                     no tecido sadio o verde é sempre maior que o vermelho
; O resultado já é uma imagem em 3 níveis, que serve para mostrar a
; segmentação e para contar as áreas (pixels 128 e 255 formam a folha).

%include "comum.inc"

LIMIAR_COR equ 40               ; diferença mínima entre canais para o pixel ter cor

section .text

global pdi_ferrugem:function    ; exporta a função para o Python

pdi_ferrugem:
    mov   eax, esi              ; rax = largura (zera a parte alta)
    mov   edx, edx              ; zera a parte alta da altura
    imul  rax, rdx              ; rax = largura * altura: pixels a classificar
    test  rax, rax              ; verifica se a imagem está vazia
    jz    .fim                  ; nada a classificar
    cmp   ecx, 3                ; verifica se a imagem é colorida (R, G, B)
    je    .pixel                ; colorida: classifica pela cor
    mov   rcx, rax              ; sem cor não há como separar folha e fundo:
    mov   rdi, r8               ; rep stosb grava no destino
    xor   eax, eax              ; valor gravado: 0 (fundo)
    rep   stosb                 ; pinta tudo como fundo
    ret                         ; volta ao chamador
.pixel:
    movzx r9d, byte [rdi]       ; lê o vermelho (R)
    movzx r10d, byte [rdi + 1]  ; lê o verde (G)
    movzx r11d, byte [rdi + 2]  ; lê o azul (B)
    mov   esi, r9d              ; maior = R
    cmp   r10d, esi             ; compara G com o maior
    cmova esi, r10d             ; G é maior: maior = G
    cmp   r11d, esi             ; compara B com o maior
    cmova esi, r11d             ; B é maior: maior = B
    mov   edx, r9d              ; menor = R
    cmp   r10d, edx             ; compara G com o menor
    cmovb edx, r10d             ; G é menor: menor = G
    cmp   r11d, edx             ; compara B com o menor
    cmovb edx, r11d             ; B é menor: menor = B
    sub   esi, edx              ; esi = maior - menor: o quanto o pixel tem de cor
    xor   ecx, ecx              ; supõe fundo (0)
    cmp   esi, LIMIAR_COR       ; compara a saturação com o limiar
    jb    .grava                ; quase sem cor (branco/cinza): é fundo
    mov   ecx, 128              ; tem cor: supõe folha sadia (128)
    cmp   r9d, r10d             ; compara o vermelho com o verde
    jb    .grava                ; verde predomina: tecido sadio
    mov   ecx, 255              ; vermelho >= verde: amarelo/laranja/marrom, ferrugem (255)
.grava:
    mov   [r8], cl              ; grava a classe do pixel
    add   rdi, 3                ; próximo pixel da origem (3 bytes)
    inc   r8                    ; próximo pixel do destino (1 byte)
    dec   rax                   ; desconta o pixel classificado
    jnz   .pixel                ; ainda há pixels: classifica o próximo
.fim:
    ret                         ; volta ao chamador; o resultado está em dst
