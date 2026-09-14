; FUNÇÃO GRAYSCALE.ASM
;
; ======= CHAMADA =======
; void pdi_grayscale(const uint8_t *src, int largura, int altura, int canais,
;                    uint8_t *dst)
;
;
; ====== REGISTERS ======
;
; rdi = src (avança um pixel por vez)
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (sempre 1 canal: largura*altura bytes; avança um byte por vez)
; rax = quantidade de pixels que faltam processar
; r9  = valor lido de um canal / valor de cinza calculado
; r10 = 255 (limite máximo)
; r11 = canais (tamanho do passo na origem)
; xmm0 = soma ponderada (valor de cinza em double)
; xmm1 = parcela de um canal (G*peso ou B*peso)
; xmm2, xmm3, xmm4 = pesos 0.2125, 0.7154 e 0.0721
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Calcula em rax o número de pixels (largura * altura); se for 0, retorna
; 2. Verifica se a imagem já tem só um canal; se sim, copia src para dst
; 3. Se não, carrega r11 = canais e os pesos em xmm2, xmm3 e xmm4 e inicia o laço:
;   3.1 Lê R, G e B de rdi para r9, converte para double, multiplica cada um
;       pelo seu peso (R*0.2125 + G*0.7154 + B*0.0721) e acumula em xmm0
;   3.2 Arredonda xmm0 para o inteiro mais próximo em r9 e limita a 255
;   3.3 Grava o valor de cinza no destino [r8]
;   3.4 Avança rdi em 'canais' bytes e r8 em 1 byte; decrementa rax e repete
;       enquanto rax não for 0
; 4. Retorna (o resultado fica em dst; não há valor de retorno)
;
;
; ===== OBSERVAÇÕES =====
;
; Pesos da ITU-R BT.709. O olho humano é mais sensível ao verde, por isso ele
; pesa mais. Como os pesos somam 1.0, o resultado nunca passa muito de 255: só
; o arredondamento de 255*1.0 com erro de ponto flutuante poderia dar 256.

%include "comum.inc"

section .rodata
PESO_R  dq 0.2125               ; peso do vermelho na fórmula do cinza
PESO_G  dq 0.7154               ; peso do verde (o olho é mais sensível a ele)
PESO_B  dq 0.0721               ; peso do azul (o olho é menos sensível a ele)

section .text

global pdi_grayscale:function   ; exporta a função para o Python e os outros .asm

pdi_grayscale:
    mov   eax, esi              ; rax = largura (mov de 32 bits zera a parte alta com lixo)
    mov   edx, edx              ; zera a parte alta de rdx para usar a altura em 64 bits
    imul  rax, rdx              ; rax = largura * altura: quantos pixels converter
    test  rax, rax              ; verifica se a imagem não tem nenhum pixel
    jz    .fim                  ; imagem vazia: não há o que converter
    cmp   ecx, 1                ; verifica se a imagem já está em cinza (1 canal)
    je    .copia                ; já é cinza: basta copiar os bytes para o destino
    mov   r11d, ecx             ; r11 = canais: quantos bytes pular para o próximo pixel

    movsd xmm2, [PESO_R]        ; carrega o peso do vermelho fora do laço (não muda)
    movsd xmm3, [PESO_G]        ; carrega o peso do verde fora do laço
    movsd xmm4, [PESO_B]        ; carrega o peso do azul fora do laço
.pixel:
    movzx r9d, byte [rdi]       ; lê o vermelho (R) do pixel, estendendo o byte para 32 bits
    cvtsi2sd xmm0, r9d          ; converte R para double, pois os pesos são fracionários
    mulsd xmm0, xmm2            ; xmm0 = R * 0.2125: começa a soma ponderada pelo vermelho
    movzx r9d, byte [rdi+1]     ; lê o verde (G) do pixel
    cvtsi2sd xmm1, r9d          ; converte G para double
    mulsd xmm1, xmm3            ; xmm1 = G * 0.7154: parcela do verde
    addsd xmm0, xmm1            ; acumula a parcela do verde no brilho do pixel
    movzx r9d, byte [rdi+2]     ; lê o azul (B) do pixel
    cvtsi2sd xmm1, r9d          ; converte B para double
    mulsd xmm1, xmm4            ; xmm1 = B * 0.0721: parcela do azul
    addsd xmm0, xmm1            ; acumula a parcela do azul: xmm0 = brilho completo
    cvtsd2si r9d, xmm0          ; arredonda o brilho para o inteiro mais próximo
    mov   r10d, 255             ; r10 = 255, o maior valor que cabe num byte
    cmp   r9d, r10d             ; verifica se o arredondamento passou de 255
    cmova r9d, r10d             ; se passou, limita a 255 para caber no byte
    mov   [r8], r9b             ; grava o nível de cinza no pixel do destino
    add   rdi, r11              ; pula os 'canais' bytes do pixel lido: vai ao próximo
    inc   r8                    ; o destino tem 1 byte por pixel: avança 1
    dec   rax                   ; desconta o pixel que acabou de ser convertido
    jnz   .pixel                ; ainda há pixels: converte o próximo
.fim:
    ret                         ; volta ao chamador; o resultado está em dst

.copia:
    mov   rcx, rax              ; rcx = bytes a copiar (1 byte por pixel em cinza)
    mov   rsi, rdi              ; rsi = origem, onde rep movsb lê
    mov   rdi, r8               ; rdi = destino, onde rep movsb escreve
    rep   movsb                 ; copia a imagem cinza inteira de uma vez
    ret                         ; volta ao chamador
