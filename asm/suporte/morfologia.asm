; FUNÇÃO MORFOLOGIA.ASM
;
; ======= CHAMADA =======
; void pdi_morfologia(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst, int valor, int dilatar)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9d = valor do elemento estruturante (o mesmo nas 5 posições da cruz)
; [rsp+8] = dilatar (1 = dilatação, 0 = erosão)
;
; rdi = endereço do byte central em src    rsi = endereço do byte central em dst
; r13 = bytes de uma linha (distância até o vizinho de baixo)
; r14 = canais (distância até o vizinho da direita)
; r8  = -bytes de uma linha (vizinho de cima)    r9 = -canais (vizinho da esquerda)
; ebp = valor do elemento    r12d = dilatar
; rbx = bytes interiores de uma linha
; r10 = linhas interiores que faltam    r11 = bytes que faltam na linha atual
; eax = vizinho lido / vizinho ± valor   edx = maior soma ou menor diferença
; ecx = auxiliar da macro SATURAR
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados e guarda os argumentos
; 2. Pinta o destino de 0 (posição vazia): o que a cruz nunca cobrir fica 0
; 3. Se a imagem tiver menos de 3 linhas ou 3 colunas, termina
; 4. Para cada byte interior (cada canal de cada pixel), com a cruz centrada nele:
;   4.1 Dilatação: soma o valor do elemento a cada pixel não vazio coberto pela
;       cruz e guarda a maior soma; se todos estiverem vazios, não grava nada
;   4.2 Erosão: subtrai o valor do elemento de cada pixel coberto pela cruz e
;       guarda a menor diferença
;   4.3 Limita o resultado a 0..255 e grava-o nas 5 posições cobertas pela
;       cruz no destino (cima, esquerda, centro, direita, baixo)
;   4.4 Avança; no fim da linha pula a moldura (último pixel desta linha e
;       primeiro da próxima)
; 5. Restaura os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Segue o procedimento "passo a passo" dos slides da disciplina:
;   1. sobrepõe o elemento estruturante à imagem;
;   2. para cada par (pixel da imagem, posição do elemento) calcula a soma
;      (dilatação) ou a diferença (erosão) e escolhe a maior (ou a menor);
;   3. aplica esse valor na imagem resultante em TODAS as posições cobertas
;      pelo elemento;
;   4. avança o elemento para o próximo pixel e repete.
; Como cada posição recebe o valor da última janela que a cobriu, o resultado
; reproduz exatamente o exemplo numérico dos slides (elemento em cruz com
; valor 10).
;
; Elemento estruturante: cruz 3x3 (vizinhança N4), centro na origem:
;        .  v  .
;        v  v  v
;        .  v  .
; Um pixel 0 é tratado como posição vazia: na dilatação não forma par com o
; elemento (por isso uma janela toda vazia não grava nada); na erosão conta
; como 0, e 0 - valor é limitado a 0.
; Em imagens binárias (0 e 255) use valor 0: a dilatação engorda o objeto
; branco e a erosão o emagrece.

%include "comum.inc"

section .text

global pdi_morfologia:function  ; exporta para dilatacao.asm e erosao.asm

; Lê um pixel coberto pela cruz e atualiza a maior soma (dilatação).
%macro MAIOR_SOMA 1
    movzx eax, byte %1          ; lê o pixel coberto por esta posição da cruz
    test  eax, eax              ; verifica se a posição está vazia (0)
    jz    %%vazio               ; vazia: não forma par com o elemento, é ignorada
    add   eax, ebp              ; soma o valor do elemento estruturante ao pixel
    cmp   eax, edx              ; compara com a maior soma encontrada até agora
    cmovg edx, eax              ; a dilatação fica com a maior soma
%%vazio:
%endmacro

; Lê um pixel coberto pela cruz e atualiza a menor diferença (erosão).
%macro MENOR_DIFERENCA 1
    movzx eax, byte %1          ; lê o pixel coberto por esta posição da cruz
    sub   eax, ebp              ; subtrai o valor do elemento estruturante (pode ficar negativo)
    cmp   eax, edx              ; compara com a menor diferença encontrada até agora
    cmovl edx, eax              ; a erosão fica com a menor diferença
%endmacro

pdi_morfologia:
    push  rbx                   ; preserva rbx: guardará os bytes interiores de uma linha
    push  rbp                   ; preserva rbp: guardará o valor do elemento
    push  r12                   ; preserva r12: guardará a operação (dilatar ou erodir)
    push  r13                   ; preserva r13: guardará os bytes de uma linha
    push  r14                   ; preserva r14: guardará os canais
    mov   ebp, r9d              ; guarda o valor do elemento estruturante
    mov   r12d, [rsp+48]        ; lê 'dilatar' (7º argumento: 5 pushes = 40 bytes + 8 do endereço de retorno)
    mov   r14d, ecx             ; guarda os canais, pois rep stosb usa rcx
    mov   r13d, esi             ; r13 = largura (zera a parte alta)
    imul  r13, r14              ; r13 = largura * canais: bytes de uma linha
    mov   r10d, edx             ; r10 = altura (zera a parte alta)
    mov   rsi, r8               ; rsi = dst, pois rep stosb usa rdi
    mov   r11, rdi              ; guarda src, pelo mesmo motivo

    ; ---------- destino vazio ----------
    mov   rdi, rsi              ; rep stosb grava a partir de rdi: o destino
    mov   rcx, r13              ; rcx = bytes de uma linha
    imul  rcx, r10              ; rcx = bytes da imagem inteira
    xor   eax, eax              ; valor gravado: 0 (posição vazia)
    rep   stosb                 ; só recebe valor o que alguma janela cobrir
    mov   rdi, r11              ; volta a apontar src

    ; ---------- tamanho do interior ----------
    sub   r10, 2                ; linhas interiores = altura - 2: a cruz precisa da linha de cima e da de baixo
    jle   .fim                  ; menos de 3 linhas: a cruz não cabe
    mov   rbx, r13              ; rbx = bytes de uma linha
    sub   rbx, r14              ; tira o primeiro pixel da linha (moldura)
    sub   rbx, r14              ; tira o último: rbx = bytes interiores
    jle   .fim                  ; menos de 3 colunas: a cruz não cabe
    mov   r8, r13               ; r8 = bytes de uma linha...
    neg   r8                    ; ...negativo: [ptr + r8] é o vizinho de cima
    mov   r9, r14               ; r9 = canais...
    neg   r9                    ; ...negativo: [ptr + r9] é o vizinho da esquerda
    add   rdi, r13              ; desce uma linha em src...
    add   rdi, r14              ; ...e avança um pixel: rdi aponta o pixel (1, 1)
    add   rsi, r13              ; o mesmo no destino...
    add   rsi, r14              ; ...rsi aponta o pixel (1, 1)
.linha:
    mov   r11, rbx              ; bytes a processar nesta linha
.byte:
    test  r12d, r12d            ; verifica qual operação foi pedida
    jz    .erosao               ; 0: erosão

    ; ---------- dilatação: maior (pixel + valor) entre os não vazios ----------
    mov   edx, -1               ; -1 = nenhum par encontrado ainda
    MAIOR_SOMA [rdi + r8]       ; cima
    MAIOR_SOMA [rdi + r9]       ; esquerda
    MAIOR_SOMA [rdi]            ; centro
    MAIOR_SOMA [rdi + r14]      ; direita
    MAIOR_SOMA [rdi + r13]      ; baixo
    test  edx, edx              ; verifica se sobrou -1 (janela toda vazia)
    js    .proximo              ; nenhum par: a janela não altera o destino
    jmp   .grava                ; há um valor: aplica nas posições da cruz

    ; ---------- erosão: menor (pixel - valor) ----------
.erosao:
    mov   edx, 0x7fffffff       ; começa com o maior inteiro, para qualquer diferença ser menor
    MENOR_DIFERENCA [rdi + r8]  ; cima
    MENOR_DIFERENCA [rdi + r9]  ; esquerda
    MENOR_DIFERENCA [rdi]       ; centro
    MENOR_DIFERENCA [rdi + r14] ; direita
    MENOR_DIFERENCA [rdi + r13] ; baixo

.grava:
    SATURAR edx, ecx            ; limita a 0..255 para caber no byte
    mov   [rsi + r8], dl        ; aplica o valor na posição de cima da cruz
    mov   [rsi + r9], dl        ; na posição da esquerda
    mov   [rsi], dl             ; no centro
    mov   [rsi + r14], dl       ; na posição da direita
    mov   [rsi + r13], dl       ; e na de baixo: todas as posições cobertas pelo elemento
.proximo:
    inc   rdi                   ; a cruz anda um byte (próximo canal ou próximo pixel)
    inc   rsi                   ; o destino anda junto
    dec   r11                   ; desconta o byte processado
    jnz   .byte                 ; ainda há bytes nesta linha: processa o próximo
    lea   rdi, [rdi + r14*2]    ; pula o último pixel desta linha e o primeiro da próxima
    lea   rsi, [rsi + r14*2]    ; o destino pula junto
    dec   r10                   ; desconta a linha processada
    jnz   .linha                ; ainda há linhas: processa a próxima
.fim:
    pop   r14                   ; restaura r14 do chamador (ordem inversa dos pushes)
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
