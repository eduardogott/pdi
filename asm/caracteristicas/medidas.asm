; FUNÇÃO MEDIDAS.ASM
;
; ======= CHAMADA =======
; void pdi_medir(const int32_t *rotulos, int largura, int altura, int n,
;                Medida *saida)
;
; struct Medida (64 bytes, uma por rótulo, de 0 a n; a 0 é o fundo):
;   +0  int64  area        +8  double perimetro
;   +16 int64  soma_x      +24 int64  soma_y      (centroide = soma / área)
;   +32 int64  x_min       +40 int64  y_min
;   +48 int64  x_max       +56 int64  y_max       (caixa que contém o objeto)
;
;
; ====== REGISTERS ======
;
; rdi = rotulos (saída de pdi_rotular)
; esi = largura
; edx = altura
; ecx = n (quantidade de rótulos)
; r8  = saida (n + 1 medidas)
;
; rbx = rotulos      r12 = largura      r13 = altura      r14 = saida
; r15 = y (linha)    rbp = x (coluna)
; r9  = endereço da medida do rótulo atual    rcx = rótulos que faltam iniciar
; Na área e na caixa:  rdi = ponteiro do pixel   eax = rótulo do pixel
; No perímetro (blocos 2x2):
;   r10 = índice do canto de cima-esquerda do bloco
;   eax, ecx, edx, esi = rótulos dos cantos a, b, c, d (0 se fora da imagem)
;   edi = rótulo do bloco (o maior dos 4)   r8d = padrão do bloco (4 bits)
;   r11 = auxiliar / endereço da tabela     xmm0 = perímetro acumulado
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados e guarda os argumentos
; 2. Inicia as n+1 medidas: tudo 0, caixa "vazia" (mín = tamanho, máx = -1)
; 3. Área, centroide e caixa: para cada pixel com rótulo L != 0:
;   3.1 área[L] += 1, soma_x[L] += x, soma_y[L] += y
;   3.2 Atualiza x_min, y_min, x_max e y_max de L
; 4. Perímetro: para cada bloco 2x2 da imagem, inclusive os que saem pela
;    borda (o lado de fora conta como fundo):
;   4.1 Lê os rótulos dos 4 cantos a b / c d; L = o maior deles
;   4.2 Se L != 0, monta o padrão (bit 0 = a, 1 = b, 2 = c, 3 = d são de L)
;   4.3 perímetro[L] += TABELA[padrão]
; 5. Restaura os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Área: total de pixels do objeto (slides de análise morfométrica).
; Perímetro: soma das distâncias entre pixels vizinhos da fronteira. A
; fronteira passa entre o objeto e o fundo; olhando cada bloco 2x2, o pedaço
; dela que cruza o bloco depende só de quais cantos são objeto:
;   1 ou 3 cantos           -> corta o canto na diagonal: raiz(2)/2
;   2 cantos lado a lado    -> atravessa o bloco reto: 1
;   2 cantos na diagonal    -> corta dois cantos: 2 * raiz(2)/2
;   0 ou 4 cantos           -> não há fronteira no bloco: 0
; Assim as diagonais valem raiz(2) e não 1 ou 2, e um círculo dá perímetro
; próximo de 2*pi*r, o que a circularidade (4*pi*A/P²) precisa.
; Furos também têm fronteira, então entram no perímetro do objeto.
; Na rotulação com vizinhança de 8, dois objetos diferentes nunca aparecem no
; mesmo bloco 2x2 (estariam se tocando), por isso o bloco tem um só rótulo.

%include "comum.inc"

section .rodata
RAIZ2_2 equ 0x3FE6A09E667F3BCD ; raiz(2)/2 = 0,7071 em double
RAIZ2   equ 0x3FF6A09E667F3BCD ; raiz(2)   = 1,4142 em double
UM      equ 0x3FF0000000000000 ; 1,0 em double
TABELA_PERIMETRO:               ; comprimento da fronteira dentro do bloco, por padrão d c b a
    dq 0                        ; 0000: nenhum canto é objeto
    dq RAIZ2_2                  ; 0001: só a (cima-esquerda)
    dq RAIZ2_2                  ; 0010: só b (cima-direita)
    dq UM                       ; 0011: a e b, a linha de cima inteira
    dq RAIZ2_2                  ; 0100: só c (baixo-esquerda)
    dq UM                       ; 0101: a e c, a coluna da esquerda
    dq RAIZ2                    ; 0110: b e c, na diagonal
    dq RAIZ2_2                  ; 0111: três cantos (falta d)
    dq RAIZ2_2                  ; 1000: só d (baixo-direita)
    dq RAIZ2                    ; 1001: a e d, na diagonal
    dq UM                       ; 1010: b e d, a coluna da direita
    dq RAIZ2_2                  ; 1011: três cantos (falta c)
    dq UM                       ; 1100: c e d, a linha de baixo
    dq RAIZ2_2                  ; 1101: três cantos (falta b)
    dq RAIZ2_2                  ; 1110: três cantos (falta a)
    dq 0                        ; 1111: bloco inteiro dentro do objeto

section .text

global pdi_medir:function       ; exporta a função para o Python

pdi_medir:
    push  rbx                   ; preserva rbx: guardará os rótulos
    push  rbp                   ; preserva rbp: será a coluna x
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará a altura
    push  r14                   ; preserva r14: guardará a saída
    push  r15                   ; preserva r15: será a linha y
    mov   rbx, rdi              ; guarda os rótulos
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13d, edx             ; guarda a altura (zera a parte alta)
    mov   r14, r8               ; guarda a saída

    ; ---------- inicia as medidas 0..n ----------
    mov   r9, r14               ; r9 aponta a medida do rótulo 0
    lea   ecx, [rcx + 1]        ; n + 1 medidas (zera a parte alta)
.inicia:
    mov   qword [r9], 0         ; área = 0
    mov   qword [r9 + 8], 0     ; perímetro = 0,0 (todos os bits 0)
    mov   qword [r9 + 16], 0    ; soma_x = 0
    mov   qword [r9 + 24], 0    ; soma_y = 0
    mov   [r9 + 32], r12        ; x_min = largura: qualquer x real é menor
    mov   [r9 + 40], r13        ; y_min = altura: qualquer y real é menor
    mov   qword [r9 + 48], -1   ; x_max = -1: qualquer x real é maior
    mov   qword [r9 + 56], -1   ; y_max = -1: qualquer y real é maior
    add   r9, 64                ; próxima medida
    dec   rcx                   ; desconta a medida iniciada
    jnz   .inicia               ; ainda há medidas: inicia a próxima

    ; ---------- área, somas e caixa ----------
    mov   rdi, rbx              ; rdi percorre os rótulos, pixel por pixel
    xor   r15d, r15d            ; y = 0
.linha:
    cmp   r15, r13              ; verifica se passou da última linha
    jge   .perimetro            ; terminou: vai para o perímetro
    xor   ebp, ebp              ; x = 0
.pixel:
    cmp   rbp, r12              ; verifica se passou da última coluna
    jge   .fim_linha            ; terminou a linha
    mov   eax, [rdi]            ; lê o rótulo do pixel
    test  eax, eax              ; verifica se é fundo
    jz    .proximo_pixel        ; fundo não é medido
    shl   rax, 6                ; rótulo * 64 bytes...
    lea   r9, [r14 + rax]       ; ...r9 aponta a medida deste objeto
    inc   qword [r9]            ; área: mais um pixel do objeto
    add   [r9 + 16], rbp        ; soma o x, para o centroide
    add   [r9 + 24], r15        ; soma o y, para o centroide
    cmp   rbp, [r9 + 32]        ; compara x com o menor x do objeto
    jge   .x_max                ; não é menor
    mov   [r9 + 32], rbp        ; novo x_min
.x_max:
    cmp   rbp, [r9 + 48]        ; compara x com o maior x do objeto
    jle   .y_min                ; não é maior
    mov   [r9 + 48], rbp        ; novo x_max
.y_min:
    cmp   r15, [r9 + 40]        ; compara y com o menor y do objeto
    jge   .y_max                ; não é menor
    mov   [r9 + 40], r15        ; novo y_min
.y_max:
    cmp   r15, [r9 + 56]        ; compara y com o maior y do objeto
    jle   .proximo_pixel        ; não é maior
    mov   [r9 + 56], r15        ; novo y_max
.proximo_pixel:
    add   rdi, 4                ; próximo rótulo (int32)
    inc   rbp                   ; próxima coluna
    jmp   .pixel                ; mede o próximo pixel
.fim_linha:
    inc   r15                   ; próxima linha
    jmp   .linha                ; mede a próxima linha

    ; ---------- perímetro pelos blocos 2x2 ----------
.perimetro:
    mov   r15, -1               ; o primeiro bloco começa uma linha acima da imagem
.linha_bloco:
    mov   rbp, -1               ; e uma coluna à esquerda: pega a fronteira da borda
.bloco:
    mov   r10, r15              ; r10 = y
    imul  r10, r12              ; r10 = y * largura
    add   r10, rbp              ; r10 = índice do canto a (pode ser negativo; só é lido se válido)
    xor   eax, eax              ; a = fundo até prova em contrário
    xor   ecx, ecx              ; b = fundo
    xor   edx, edx              ; c = fundo
    xor   esi, esi              ; d = fundo
    test  r15, r15              ; verifica se a linha de cima está fora da imagem
    js    .linha_de_baixo       ; y = -1: a e b ficam fundo
    test  rbp, rbp              ; verifica se a coluna da esquerda está fora
    js    .canto_b              ; x = -1: a fica fundo
    mov   eax, [rbx + r10*4]    ; a = rótulo de cima-esquerda
.canto_b:
    lea   r11, [rbp + 1]        ; r11 = coluna da direita
    cmp   r11, r12              ; verifica se ela está dentro da imagem
    jge   .linha_de_baixo       ; x + 1 = largura: b fica fundo
    mov   ecx, [rbx + r10*4 + 4] ; b = rótulo de cima-direita
.linha_de_baixo:
    lea   r11, [r15 + 1]        ; r11 = linha de baixo
    cmp   r11, r13              ; verifica se ela está dentro da imagem
    jge   .rotulo_do_bloco      ; y + 1 = altura: c e d ficam fundo
    lea   r9, [r10 + r12]       ; r9 = índice do canto c (uma linha abaixo de a)
    test  rbp, rbp              ; verifica se a coluna da esquerda está fora
    js    .canto_d              ; x = -1: c fica fundo
    mov   edx, [rbx + r9*4]     ; c = rótulo de baixo-esquerda
.canto_d:
    lea   r11, [rbp + 1]        ; r11 = coluna da direita
    cmp   r11, r12              ; verifica se ela está dentro da imagem
    jge   .rotulo_do_bloco      ; x + 1 = largura: d fica fundo
    mov   esi, [rbx + r9*4 + 4] ; d = rótulo de baixo-direita
.rotulo_do_bloco:
    mov   edi, eax              ; começa com a
    cmp   ecx, edi              ; compara b com o maior até agora
    cmova edi, ecx              ; fica com o maior
    cmp   edx, edi              ; compara c com o maior até agora
    cmova edi, edx              ; fica com o maior
    cmp   esi, edi              ; compara d com o maior até agora
    cmova edi, esi              ; edi = rótulo do objeto no bloco
    test  edi, edi              ; verifica se o bloco tem algum objeto
    jz    .proximo_bloco        ; só fundo: não há fronteira aqui
    xor   r8d, r8d              ; monta o padrão do bloco
    cmp   eax, edi              ; a é deste objeto?
    sete  r8b                   ; bit 0 = a
    xor   r11d, r11d            ; auxiliar limpo para o próximo bit
    cmp   ecx, edi              ; b é deste objeto?
    sete  r11b                  ; r11 = 1 se for
    lea   r8d, [r8 + r11*2]     ; bit 1 = b
    cmp   edx, edi              ; c é deste objeto?
    sete  r11b                  ; r11 = 1 se for
    lea   r8d, [r8 + r11*4]     ; bit 2 = c
    cmp   esi, edi              ; d é deste objeto?
    sete  r11b                  ; r11 = 1 se for
    lea   r8d, [r8 + r11*8]     ; bit 3 = d: r8 = padrão de 0 a 15
    shl   rdi, 6                ; rótulo * 64 bytes...
    lea   r9, [r14 + rdi]       ; ...r9 aponta a medida deste objeto
    lea   r11, [TABELA_PERIMETRO] ; endereço da tabela (o RIP não aceita índice junto)
    movsd xmm0, [r9 + 8]        ; perímetro acumulado do objeto
    addsd xmm0, [r11 + r8*8]    ; soma o pedaço de fronteira deste bloco
    movsd [r9 + 8], xmm0        ; guarda o novo perímetro
.proximo_bloco:
    inc   rbp                   ; próximo bloco na linha
    cmp   rbp, r12              ; o último bloco começa na última coluna
    jl    .bloco                ; ainda há blocos: mede o próximo
    inc   r15                   ; próxima linha de blocos
    cmp   r15, r13              ; a última começa na última linha
    jl    .linha_bloco          ; ainda há linhas: mede a próxima

    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; as medidas estão em saida
