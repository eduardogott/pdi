; FUNÇÃO SOBEL.ASM
;
; ======= CHAMADA =======
; void pdi_sobel(const uint8_t *src, int largura, int altura, int canais,
;                uint8_t *dst, int limiar)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (sempre 1 canal: 255 = borda, 0 = fundo)
; r9d = limiar
; rbx = imagem em cinza (buffer temporário)
; r12 = largura          r13 = altura / linhas interiores que faltam
; r14 = canais           r15 = dst          rbp = limiar²
; rsi = índice do pixel central (o mesmo no cinza e no destino)
; rdx = endereço do vizinho de cima-esquerda no cinza
; r11 = colunas que faltam na linha atual
; eax = Gx / Gx² + Gy²   ecx = Gy / valor de saída   r8d = vizinho lido
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados, alinha a pilha, guarda os
;    argumentos e calcula limiar² (rbp)
; 2. Pede largura*altura bytes ao kernel (pdi_aloca); se falhar, termina
; 3. Converte a imagem para cinza nesse buffer (pdi_grayscale)
; 4. Pinta o destino de preto (a moldura de 1 pixel fica preta)
; 5. Se a imagem tiver menos de 3 linhas ou 3 colunas, pula para o passo 7
; 6. Para cada pixel interior (índice rsi, janela em rdx):
;   6.1 Gx = coluna da direita - coluna da esquerda (linha do meio pesa 2)
;   6.2 Gy = linha de baixo - linha de cima (coluna do meio pesa 2)
;   6.3 Se Gx² + Gy² > limiar², grava 255 no destino; senão fica 0
;   6.4 Avança rsi e rdx; no fim da linha pula a moldura (2 pixels)
; 7. Devolve o buffer de cinza (pdi_libera), restaura e retorna
;
;
; ===== OBSERVAÇÕES =====
;
;   Sx = [-1 0 1; -2 0 2; -1 0 1]     Sy = [-1 -2 -1; 0 0 0; 1 2 1]
;   G  = raiz(Gx² + Gy²)              borda se G > limiar
; Comparar Gx² + Gy² com limiar² dá o mesmo resultado sem calcular a raiz.
; A imagem é convertida para cinza antes, pois a borda é uma variação de
; brilho. O cinza vai para um buffer separado porque cada pixel precisa dos
; vizinhos originais enquanto o resultado é gravado.

%include "comum.inc"

section .text

global pdi_sobel:function       ; exporta a função para o Python
extern pdi_aloca                ; suporte/memoria.asm
extern pdi_libera               ; suporte/memoria.asm
extern pdi_grayscale            ; filtros/grayscale.asm

pdi_sobel:
    push  rbx                   ; preserva rbx: guardará a imagem em cinza
    push  rbp                   ; preserva rbp: guardará limiar²
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará a altura
    push  r14                   ; preserva r14: guardará os canais
    push  r15                   ; preserva r15: guardará dst
    sub   rsp, 8                ; 6 pushes + 8 bytes: pilha múltipla de 16 antes dos calls
    mov   rbx, rdi              ; guarda src até a conversão para cinza
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13d, edx             ; guarda a altura (zera a parte alta)
    mov   r14d, ecx             ; guarda os canais
    mov   r15, r8               ; guarda dst
    movsxd rbp, r9d             ; rbp = limiar, estendido com sinal para 64 bits
    imul  rbp, rbp              ; rbp = limiar²: compara com Gx² + Gy² sem tirar raiz

    ; ---------- imagem em cinza num buffer temporário ----------
    mov   rdi, r12              ; rdi = largura
    imul  rdi, r13              ; rdi = largura * altura: 1 byte de cinza por pixel
    call  pdi_aloca wrt ..plt   ; pede a memória ao kernel
    test  rax, rax              ; verifica se conseguiu memória
    jz    .fim                  ; faltou memória: sai sem processar
    mov   rdi, rbx              ; 1º argumento de pdi_grayscale: a imagem original
    mov   rbx, rax              ; a partir daqui rbx guarda o buffer de cinza
    mov   esi, r12d             ; 2º argumento: largura
    mov   edx, r13d             ; 3º argumento: altura
    mov   ecx, r14d             ; 4º argumento: canais da original
    mov   r8, rbx               ; 5º argumento: destino = buffer de cinza
    call  pdi_grayscale wrt ..plt ; converte: a borda é medida sobre o brilho

    ; ---------- destino preto ----------
    mov   rdi, r15              ; rep stosb grava a partir de rdi: o destino
    mov   rcx, r12              ; rcx = largura
    imul  rcx, r13              ; rcx = largura * altura: bytes do destino
    xor   eax, eax              ; valor gravado: 0 (fundo)
    rep   stosb                 ; pinta tudo de preto; só as bordas viram 255

    ; ---------- tamanho do interior ----------
    sub   r13, 2                ; linhas interiores = altura - 2
    jle   .libera               ; menos de 3 linhas: a janela 3x3 não cabe
    cmp   r12, 3                ; verifica se há pelo menos 3 colunas
    jb    .libera               ; menos de 3 colunas: a janela 3x3 não cabe
    lea   rsi, [r12 + 1]        ; rsi = índice do pixel (1, 1): uma linha + um pixel
    mov   rdx, rbx              ; o vizinho de cima-esquerda de (1, 1) é o pixel (0, 0)
.linha:
    lea   r11, [r12 - 2]        ; colunas interiores = largura - 2
.pixel:
    ; Gx = (cima-dir + 2*dir + baixo-dir) - (cima-esq + 2*esq + baixo-esq)
    movzx eax, byte [rdx + 2]           ; lê o vizinho de cima-direita
    movzx r8d, byte [rdx + r12 + 2]     ; lê o vizinho da direita
    lea   eax, [rax + r8*2]             ; soma a direita com peso 2
    movzx r8d, byte [rdx + r12*2 + 2]   ; lê o vizinho de baixo-direita
    add   eax, r8d                      ; eax = coluna da direita ponderada
    movzx r8d, byte [rdx]               ; lê o vizinho de cima-esquerda
    sub   eax, r8d                      ; subtrai: Gx é a diferença entre direita e esquerda
    movzx r8d, byte [rdx + r12]         ; lê o vizinho da esquerda
    sub   eax, r8d                      ; subtrai a esquerda uma vez...
    sub   eax, r8d                      ; ...e de novo, pois pesa 2
    movzx r8d, byte [rdx + r12*2]       ; lê o vizinho de baixo-esquerda
    sub   eax, r8d                      ; eax = Gx: variação horizontal do brilho
    ; Gy = (baixo-esq + 2*baixo + baixo-dir) - (cima-esq + 2*cima + cima-dir)
    movzx ecx, byte [rdx + r12*2]       ; lê o vizinho de baixo-esquerda
    movzx r8d, byte [rdx + r12*2 + 1]   ; lê o vizinho de baixo
    lea   ecx, [rcx + r8*2]             ; soma o de baixo com peso 2
    movzx r8d, byte [rdx + r12*2 + 2]   ; lê o vizinho de baixo-direita
    add   ecx, r8d                      ; ecx = linha de baixo ponderada
    movzx r8d, byte [rdx]               ; lê o vizinho de cima-esquerda
    sub   ecx, r8d                      ; subtrai: Gy é a diferença entre baixo e cima
    movzx r8d, byte [rdx + 1]           ; lê o vizinho de cima
    sub   ecx, r8d                      ; subtrai o de cima uma vez...
    sub   ecx, r8d                      ; ...e de novo, pois pesa 2
    movzx r8d, byte [rdx + 2]           ; lê o vizinho de cima-direita
    sub   ecx, r8d                      ; ecx = Gy: variação vertical do brilho

    imul  eax, eax              ; eax = Gx² (o quadrado tira o sinal)
    imul  ecx, ecx              ; ecx = Gy²
    add   eax, ecx              ; eax = Gx² + Gy² = G² (no máximo ~2 milhões, cabe em 32 bits)
    xor   ecx, ecx              ; supõe que não é borda (0)
    cmp   rax, rbp              ; compara G² com limiar²
    jbe   .grava                ; variação fraca: mantém 0
    mov   ecx, 255              ; variação forte: é borda (255)
.grava:
    mov   [r15 + rsi], cl       ; grava o pixel de saída
    inc   rsi                   ; próximo pixel do destino
    inc   rdx                   ; a janela anda uma coluna para a direita
    dec   r11                   ; desconta a coluna processada
    jnz   .pixel                ; ainda há colunas: processa a próxima
    add   rsi, 2                ; pula o último pixel desta linha e o primeiro da próxima
    add   rdx, 2                ; a janela pula junto
    dec   r13                   ; desconta a linha processada
    jnz   .linha                ; ainda há linhas: processa a próxima

.libera:
    mov   rdi, rbx              ; argumento: o buffer de cinza, que não é mais necessário
    call  pdi_libera wrt ..plt  ; devolve a memória ao kernel
.fim:
    add   rsp, 8                ; desfaz o ajuste de alinhamento
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
