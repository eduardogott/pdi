; FUNÇÃO MATRIZ_TRANSFORMACAO.ASM
;
; ======= CHAMADA =======
; void pdi_transformar(const uint8_t *src, int largura, int altura, int canais,
;                      uint8_t *dst, int largura_dst, int altura_dst,
;                      const double *inversa)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (avança um pixel por vez)
; r9d = largura_dst
; [rsp+8]  = altura_dst (7º argumento: não cabe mais em registrador)
; [rsp+16] = inversa (8º argumento: 6 doubles a, b, c, d, e, f)
;
; rbx = src          r11 = canais          r10 = altura_dst
; xmm8, xmm9, xmm10   = a, b, c   (linha do xo)
; xmm11, xmm12, xmm13 = d, e, f   (linha do yo)
; r12 = y do destino                r13 = x do destino
; xmm0 = y ou x em double
; xmm1 = b*y + c                    xmm2 = e*y + f
; xmm3 = xo (real)                  xmm4 = yo (real)
; r14 = xo arredondado              r15 = yo arredondado
; rax = endereço do pixel na origem rcx = k (canal)     dil = byte copiado
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Lê altura_dst e o ponteiro da matriz da pilha e salva os registradores
;    preservados
; 2. Carrega a, b, c, d, e, f em xmm8..xmm13
; 3. Pinta o destino inteiro de preto
; 4. Para cada linha y (r12) do destino:
;   4.1 Calcula uma vez por linha xmm1 = b*y + c e xmm2 = e*y + f
;   4.2 Para cada coluna x (r13):
;     4.2.1 Calcula a posição na origem: xo = a*x + xmm1, yo = d*x + xmm2
;     4.2.2 Arredonda xo e yo para o pixel mais próximo (r14, r15)
;     4.2.3 Se (xo, yo) está dentro da origem, copia os 'canais' bytes do
;           pixel para [r8]; se não, o pixel continua preto
;     4.2.4 Avança r8 um pixel
; 5. Restaura os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Todas as transformações geométricas usam esta função. Cada operação monta a
; matriz INVERSA da sua transformação, que diz de onde vem cada pixel:
;
;     xo = a*x + b*y + c          (x, y)   = pixel do destino
;     yo = d*x + e*y + f          (xo, yo) = pixel da origem
;
; Mapeamento inverso: se percorrêssemos a origem jogando cada pixel no destino,
; alguns pixels do destino ficariam sem valor (buracos) ao aumentar ou girar.
; Percorrendo o destino e buscando na origem, todo pixel recebe um valor
; (vizinho mais próximo). O que cai fora da origem fica preto.

%include "comum.inc"

section .text

global pdi_transformar:function ; exporta para as funções de geometria

pdi_transformar:
    mov   r10d, [rsp+8]         ; lê altura_dst agora, antes dos pushes mudarem rsp
    mov   rax, [rsp+16]         ; lê o ponteiro da matriz pelo mesmo motivo
    push  rbx                   ; preserva rbx: guardará src
    push  r12                   ; preserva r12: será o y
    push  r13                   ; preserva r13: será o x
    push  r14                   ; preserva r14: será o xo arredondado
    push  r15                   ; preserva r15: será o yo arredondado
    movsd xmm8,  [rax]          ; a: quanto xo anda quando x anda 1
    movsd xmm9,  [rax+8]        ; b: quanto xo anda quando y anda 1
    movsd xmm10, [rax+16]       ; c: deslocamento de xo
    movsd xmm11, [rax+24]       ; d: quanto yo anda quando x anda 1
    movsd xmm12, [rax+32]       ; e: quanto yo anda quando y anda 1
    movsd xmm13, [rax+40]       ; f: deslocamento de yo
    mov   rbx, rdi              ; guarda src, pois rep stosb usa rdi
    mov   esi, esi              ; zera a parte alta da largura para contas de 64 bits
    mov   edx, edx              ; zera a parte alta da altura
    mov   r11d, ecx             ; guarda os canais, pois rep stosb usa rcx
    mov   r9d, r9d              ; zera a parte alta da largura_dst

    ; ---------- destino todo preto ----------
    mov   rdi, r8               ; rep stosb grava a partir de rdi: o destino
    mov   rcx, r9               ; rcx = largura_dst
    imul  rcx, r10              ; * altura_dst = pixels do destino
    imul  rcx, r11              ; * canais = bytes do destino
    xor   eax, eax              ; valor gravado: 0 (preto)
    rep   stosb                 ; pinta tudo de preto; só os pixels achados na origem serão copiados

    xor   r12d, r12d            ; começa pela linha y = 0 do destino
.linha:
    cmp   r12, r10              ; verifica se ainda há linhas no destino
    jae   .fim                  ; passou da última linha: terminou
    cvtsi2sd xmm0, r12          ; converte y para double para usar na matriz
    movapd xmm1, xmm9           ; copia b
    mulsd xmm1, xmm0            ; xmm1 = b*y
    addsd xmm1, xmm10           ; xmm1 = b*y + c: parte de xo que não muda na linha
    movapd xmm2, xmm12          ; copia e
    mulsd xmm2, xmm0            ; xmm2 = e*y
    addsd xmm2, xmm13           ; xmm2 = e*y + f: parte de yo que não muda na linha
    xor   r13d, r13d            ; começa pela coluna x = 0
.coluna:
    cmp   r13, r9               ; verifica se ainda há colunas nesta linha
    jae   .proxima_linha        ; passou da última coluna: vai para a próxima linha
    cvtsi2sd xmm0, r13          ; converte x para double
    movapd xmm3, xmm8           ; copia a
    mulsd xmm3, xmm0            ; xmm3 = a*x
    addsd xmm3, xmm1            ; xo = a*x + b*y + c: coluna de origem deste pixel
    movapd xmm4, xmm11          ; copia d
    mulsd xmm4, xmm0            ; xmm4 = d*x
    addsd xmm4, xmm2            ; yo = d*x + e*y + f: linha de origem deste pixel
    cvtsd2si r14, xmm3          ; arredonda xo: escolhe o vizinho mais próximo
    cvtsd2si r15, xmm4          ; arredonda yo
    cmp   r14, rsi              ; xo < largura? (sem sinal: xo negativo vira número enorme)
    jae   .proximo_pixel        ; fora da origem: o pixel continua preto
    cmp   r15, rdx              ; yo < altura? (mesmo truque sem sinal)
    jae   .proximo_pixel        ; fora da origem: o pixel continua preto
    mov   rax, r15              ; rax = yo
    imul  rax, rsi              ; * largura: pixels das linhas anteriores
    add   rax, r14              ; + xo: índice do pixel na origem
    imul  rax, r11              ; * canais: posição em bytes
    add   rax, rbx              ; + src: endereço do pixel de origem
    xor   ecx, ecx              ; começa pelo canal k = 0
.copia:
    mov   dil, [rax + rcx]      ; lê o canal k do pixel de origem
    mov   [r8 + rcx], dil       ; copia para o canal k do pixel de destino
    inc   rcx                   ; passa para o próximo canal
    cmp   rcx, r11              ; verifica se ainda há canais a copiar
    jb    .copia                ; falta canal: copia o próximo
.proximo_pixel:
    add   r8, r11               ; avança o destino para o próximo pixel
    inc   r13                   ; próxima coluna
    jmp   .coluna               ; processa a próxima coluna
.proxima_linha:
    inc   r12                   ; próxima linha
    jmp   .linha                ; processa a próxima linha
.fim:
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
