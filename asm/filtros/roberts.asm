; FUNÇÃO ROBERTS.ASM
;
; ======= CHAMADA =======
; void pdi_roberts(const uint8_t *src, int largura, int altura, int canais,
;                  uint8_t *dst, int limiar)
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
; rbx = ponteiro do pixel atual (x, y) no destino
; r12 = largura          r13 = linhas que faltam (sem contar a última)
; rbp = limiar²          r11 = colunas que faltam na linha atual
; eax = G1 / G1² + G2²   ecx = G2 / valor de saída   edx = vizinho lido
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados, alinha a pilha, guarda os
;    argumentos e calcula limiar² (rbp)
; 2. Chama pdi_grayscale com os mesmos argumentos: o destino recebe a imagem
;    em cinza (se já for cinza, só é copiada)
; 3. Se a imagem estiver vazia, termina
; 4. Para cada linha, menos a última (r13):
;   4.1 Para cada pixel, menos o último da linha (r11), apontado por rbx:
;     4.1.1 G1 = f(x,y) - f(x+1,y+1)   (diagonal principal)
;     4.1.2 G2 = f(x+1,y) - f(x,y+1)   (outra diagonal)
;     4.1.3 Se G1² + G2² > limiar², grava 255; senão grava 0
;     4.1.4 Avança rbx
;   4.2 Pinta de preto o último pixel da linha e avança rbx
; 5. Pinta de preto a última linha
; 6. Restaura a pilha e os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
;   G1 = [ 1  0 ]     G2 = [  0  1 ]
;        [ 0 -1 ]          [ -1  0 ]
;   G  = raiz(G1² + G2²)              borda se G > limiar
; Comparar G1² + G2² com limiar² dá o mesmo resultado sem calcular a raiz.
; A última linha e a última coluna não têm vizinho à direita ou abaixo, por
; isso ficam pretas.
; O cálculo é feito no próprio destino, sobre o cinza que o pdi_grayscale
; gravou lá, sem memória extra: cada pixel só usa ele mesmo e os vizinhos da
; direita e de baixo, que ainda não foram sobrescritos quando ele é calculado.

%include "comum.inc"

section .text

global pdi_roberts:function     ; exporta a função para o Python
extern pdi_grayscale            ; filtros/grayscale.asm

pdi_roberts:
    push  rbx                   ; preserva rbx: será o ponteiro do pixel atual
    push  rbp                   ; preserva rbp: guardará limiar²
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará a altura
    sub   rsp, 8                ; 4 pushes + 8 bytes: pilha múltipla de 16 antes do call
    mov   rbx, r8               ; guarda dst, pois o call pode destruir r8
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13d, edx             ; guarda a altura (zera a parte alta)
    movsxd rbp, r9d             ; rbp = limiar, estendido com sinal para 64 bits
    imul  rbp, rbp              ; rbp = limiar²: compara com G1² + G2² sem tirar raiz

    ; os 5 argumentos já estão nos registradores certos para pdi_grayscale
    call  pdi_grayscale wrt ..plt ; grava a imagem em cinza direto no destino

    test  r12, r12              ; verifica se a imagem tem largura 0
    jz    .fim                  ; imagem vazia: nada a processar
    sub   r13, 1                ; linhas com vizinho de baixo = altura - 1
    jl    .fim                  ; altura 0: imagem vazia
.linha:
    test  r13, r13              ; verifica se ainda há linhas com vizinho de baixo
    jz    .ultima_linha         ; só sobrou a última linha
    lea   r11, [r12 - 1]        ; colunas com vizinho à direita = largura - 1
.pixel:
    test  r11, r11              ; verifica se ainda há colunas com vizinho à direita
    jz    .ultima_coluna        ; só sobrou a última coluna desta linha
    ; G1 = f(x, y) - f(x+1, y+1)
    movzx eax, byte [rbx]               ; lê o próprio pixel (x, y)
    movzx edx, byte [rbx + r12 + 1]     ; lê o vizinho de baixo-direita (uma linha + um pixel)
    sub   eax, edx                      ; eax = G1: variação na diagonal principal
    ; G2 = f(x+1, y) - f(x, y+1)
    movzx ecx, byte [rbx + 1]           ; lê o vizinho da direita
    movzx edx, byte [rbx + r12]         ; lê o vizinho de baixo (uma linha adiante)
    sub   ecx, edx                      ; ecx = G2: variação na outra diagonal

    imul  eax, eax              ; eax = G1² (o quadrado tira o sinal)
    imul  ecx, ecx              ; ecx = G2²
    add   eax, ecx              ; eax = G1² + G2² = G² (no máximo 130050)
    xor   ecx, ecx              ; supõe que não é borda (0)
    cmp   rax, rbp              ; compara G² com limiar²
    jbe   .grava                ; variação fraca: mantém 0
    mov   ecx, 255              ; variação forte: é borda (255)
.grava:
    mov   [rbx], cl             ; substitui o cinza pelo resultado; ninguém mais lê este pixel
    inc   rbx                   ; avança para o próximo pixel
    dec   r11                   ; desconta a coluna processada
    jmp   .pixel                ; processa a próxima coluna
.ultima_coluna:
    mov   byte [rbx], 0         ; último pixel da linha: sem vizinho à direita, fica preto
    inc   rbx                   ; vai para o primeiro pixel da próxima linha
    dec   r13                   ; desconta a linha processada
    jmp   .linha                ; processa a próxima linha
.ultima_linha:
    mov   rdi, rbx              ; rep stosb grava a partir de rdi: o início da última linha
    mov   rcx, r12              ; rcx = largura: bytes da última linha
    xor   eax, eax              ; valor gravado: 0 (fundo)
    rep   stosb                 ; última linha: sem vizinho de baixo, fica preta
.fim:
    add   rsp, 8                ; desfaz o ajuste de alinhamento da pilha
    pop   r13                   ; restaura r13 do chamador (ordem inversa dos pushes)
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
