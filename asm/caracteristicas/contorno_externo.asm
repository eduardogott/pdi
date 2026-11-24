; FUNÇÃO CONTORNO_EXTERNO.ASM
;
; ======= CHAMADA =======
; void pdi_contorno_externo(const int32_t *rotulos, int largura, int rotulo,
;                           const Medida *m, double *saida)
;
;
; ====== REGISTERS ======
;
; rdi = rotulos (saída de pdi_rotular)
; esi = largura
; edx = rotulo do objeto a medir
; rcx = m (a medida do objeto, com a caixa x_min..x_max, y_min..y_max)
; r8  = saida: saida[0] = área preenchida, saida[1] = perímetro externo
;
; r12 = largura      r13 = x_min       r14 = x_max
; r9  = linha y      r10 = y_max       rsi = início da linha y nos rótulos
; rax = l (coluna mais à esquerda do objeto na linha)
; rcx = r (coluna mais à direita do objeto na linha)
; r11 = l da linha anterior (-1 antes da primeira)   r15 = r da linha anterior
; rbx = área preenchida      xmm0 = perímetro      xmm2 = 1,0
; xmm1 = auxiliar dos cálculos    rdx = rótulo procurado
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados e lê a caixa do objeto
; 2. Para cada linha y da caixa:
;   2.1 Procura l, o primeiro pixel do objeto a partir de x_min, e r, o
;       último, voltando a partir de x_max
;   2.2 Área preenchida += r - l + 1 (a linha toda, de l até r)
;   2.3 Na primeira linha, soma a largura dela (borda de cima); nas outras,
;       soma as distâncias entre as pontas desta linha e as da anterior:
;       raiz((l - l_ant)² + 1) + raiz((r - r_ant)² + 1)
;   2.4 Guarda l e r para a próxima linha
; 3. Soma a largura da última linha (borda de baixo)
; 4. Grava a área e o perímetro em saida, restaura e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Mede o objeto pela sua silhueta externa: em cada linha considera tudo entre
; a primeira e a última coluna do objeto. Assim os furos (ex.: o furo da
; porca, o círculo dentro de um quadrado) e pequenas falhas da borda não
; contam, e o perímetro é só o da fronteira de fora.
; O contorno é o polígono que liga as pontas das linhas; entre linhas
; vizinhas, cada lado anda (l - l_ant) na horizontal e 1 na vertical.
; Vale para formas sem reentrâncias na horizontal (círculos, quadrados,
; hexágonos, losangos), que são as que os exercícios medem.
; Como o objeto é conexo, toda linha entre y_min e y_max tem pixel dele.

%include "comum.inc"

section .rodata
UM      dq 1.0                  ; a distância vertical entre duas linhas

section .text

global pdi_contorno_externo:function ; exporta a função para o Python

pdi_contorno_externo:
    push  rbx                   ; preserva rbx: guardará a área preenchida
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará x_min
    push  r14                   ; preserva r14: guardará x_max
    push  r15                   ; preserva r15: guardará o r da linha anterior
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13, [rcx + 32]       ; x_min da caixa do objeto
    mov   r14, [rcx + 48]       ; x_max da caixa
    mov   r9, [rcx + 40]        ; a primeira linha é y_min
    mov   r10, [rcx + 56]       ; a última é y_max
    xorpd xmm0, xmm0            ; perímetro = 0,0
    movsd xmm2, [UM]            ; xmm2 = 1,0, usado em cada passo entre linhas
    xor   ebx, ebx              ; área preenchida = 0
    mov   r11, -1               ; -1 indica que ainda não houve linha anterior
    cmp   r9, r10               ; caixa vazia (y_min > y_max)? acontece com o rótulo 0
    jg    .grava                ; nada a medir

.linha:
    mov   rax, r9               ; rax = y
    imul  rax, r12              ; rax = y * largura: índice do início da linha
    lea   rsi, [rdi + rax*4]    ; rsi aponta o rótulo do pixel (0, y)
    mov   rax, r13              ; procura l a partir de x_min
.procura_esquerda:
    cmp   [rsi + rax*4], edx    ; este pixel é do objeto?
    je    .achou_esquerda       ; sim: é a ponta esquerda da linha
    inc   rax                   ; não: olha a próxima coluna
    cmp   rax, r14              ; verifica se passou de x_max
    jle   .procura_esquerda     ; ainda dentro da caixa: continua
    jmp   .proxima_linha        ; linha sem o objeto (não ocorre num objeto conexo)
.achou_esquerda:
    mov   rcx, r14              ; procura r voltando a partir de x_max
.procura_direita:
    cmp   [rsi + rcx*4], edx    ; este pixel é do objeto?
    je    .achou_direita        ; sim: é a ponta direita da linha
    dec   rcx                   ; não: olha a coluna anterior (para no l no pior caso)
    jmp   .procura_direita      ; continua voltando
.achou_direita:
    mov   rsi, rcx              ; rsi = r (o ponteiro da linha não é mais necessário)
    sub   rsi, rax              ; rsi = r - l
    lea   rbx, [rbx + rsi + 1]  ; área += r - l + 1: a linha inteira, com os furos
    test  r11, r11              ; verifica se há linha anterior
    jns   .lados                ; há: mede os lados
    inc   rsi                   ; rsi = r - l + 1, a largura da primeira linha
    cvtsi2sd xmm1, rsi          ; converte para double
    addsd xmm0, xmm1            ; borda de cima: a largura da primeira linha
    jmp   .guarda               ; guarda as pontas
.lados:
    mov   rsi, rax              ; rsi = l
    sub   rsi, r11              ; rsi = l - l_ant: quanto o lado esquerdo andou na horizontal
    cvtsi2sd xmm1, rsi          ; converte para double
    mulsd xmm1, xmm1            ; (l - l_ant)²
    addsd xmm1, xmm2            ; + 1² (andou uma linha na vertical)
    sqrtsd xmm1, xmm1           ; distância entre as pontas esquerdas (Pitágoras)
    addsd xmm0, xmm1            ; soma ao perímetro
    mov   rsi, rcx              ; rsi = r
    sub   rsi, r15              ; rsi = r - r_ant: quanto o lado direito andou
    cvtsi2sd xmm1, rsi          ; converte para double
    mulsd xmm1, xmm1            ; (r - r_ant)²
    addsd xmm1, xmm2            ; + 1²
    sqrtsd xmm1, xmm1           ; distância entre as pontas direitas
    addsd xmm0, xmm1            ; soma ao perímetro
.guarda:
    mov   r11, rax              ; l desta linha será o l anterior da próxima
    mov   r15, rcx              ; idem para r
.proxima_linha:
    inc   r9                    ; próxima linha
    cmp   r9, r10               ; verifica se passou de y_max
    jle   .linha                ; ainda há linhas: mede a próxima

    test  r11, r11              ; verifica se alguma linha foi medida
    js    .grava                ; nenhuma: perímetro fica 0
    mov   rsi, r15              ; rsi = r da última linha
    sub   rsi, r11              ; rsi = r - l
    inc   rsi                   ; rsi = largura da última linha
    cvtsi2sd xmm1, rsi          ; converte para double
    addsd xmm0, xmm1            ; borda de baixo: a largura da última linha
.grava:
    cvtsi2sd xmm1, rbx          ; converte a área para double
    movsd [r8], xmm1            ; saida[0] = área preenchida
    movsd [r8 + 8], xmm0        ; saida[1] = perímetro externo
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador
