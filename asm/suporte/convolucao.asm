; FUNÇÃO CONVOLUCAO.ASM
;
; ======= CHAMADA =======
; void pdi_convolucao(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst, const int32_t *mascara, int divisor)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9  = mascara (9 pesos int32, linha por linha)
; [rsp+8] = divisor (se for 0 ou 1, a soma não é dividida)
;
; rbx = src              r15 = dst              r12 = máscara
; ebp = divisor          r14 = canais           r13 = bytes de uma linha
; r10 = linhas interiores que faltam
; r9  = bytes interiores de uma linha   r11 = bytes que faltam na linha atual
; rsi = índice do byte central (o mesmo em src e dst)
; rdx = endereço do vizinho da esquerda na linha atual da janela
; r8  = ponteiro do peso atual          ecx = linhas da janela que faltam
; edi = soma ponderada                  eax = vizinho * peso / divisão
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados e guarda os argumentos
; 2. Copia a imagem inteira para o destino: a moldura de 1 pixel, onde a
;    máscara 3x3 não cabe, fica com o pixel original
; 3. Se a imagem tiver menos de 3 linhas ou 3 colunas, termina
; 4. Para cada byte do interior (cada canal de cada pixel), índice rsi:
;   4.1 Aponta rdx para o vizinho de cima-esquerda, no mesmo canal
;   4.2 Para as 3 linhas da janela, soma em edi vizinho * peso das 3 colunas
;   4.3 Se divisor > 1, divide a soma arredondando
;   4.4 Limita a 0..255 e grava em dst[rsi]
;   4.5 Avança rsi; no fim da linha pula a moldura (último pixel desta linha
;       e primeiro da próxima)
; 5. Restaura os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Uma máscara 3x3 "desliza" sobre a imagem. Para cada pixel:
;     soma = Σ peso * vizinho       novo = soma / divisor   (limitado a 0..255)
; Cada canal (R, G, B ou cinza) é filtrado separadamente. Os vizinhos do mesmo
; canal ficam a 'canais' bytes de distância na horizontal e a
; 'largura * canais' bytes na vertical.
; Usada por passa_baixa.asm e passa_alta.asm.

%include "comum.inc"

section .text

global pdi_convolucao:function  ; exporta para os filtros

pdi_convolucao:
    push  rbx                   ; preserva rbx: guardará src
    push  rbp                   ; preserva rbp: guardará o divisor
    push  r12                   ; preserva r12: guardará a máscara
    push  r13                   ; preserva r13: guardará os bytes de uma linha
    push  r14                   ; preserva r14: guardará os canais
    push  r15                   ; preserva r15: guardará dst
    mov   rbx, rdi              ; guarda src, pois rep movsb usa rdi
    mov   r15, r8               ; guarda dst, pois r8 vira o ponteiro dos pesos
    mov   r12, r9               ; guarda a máscara, pois r9 vira um contador
    mov   ebp, [rsp+56]         ; lê o divisor (7º argumento: 6 pushes = 48 bytes + 8 do endereço de retorno)
    mov   r14d, ecx             ; guarda os canais, pois rep movsb usa rcx
    mov   r10d, edx             ; r10 = altura (zera a parte alta)
    mov   r13d, esi             ; r13 = largura (zera a parte alta)
    imul  r13, r14              ; r13 = largura * canais: bytes de uma linha, distância até o vizinho de baixo

    ; ---------- copia tudo: a moldura mantém o pixel original ----------
    mov   rcx, r13              ; rcx = bytes de uma linha
    imul  rcx, r10              ; rcx = bytes da imagem inteira
    mov   rsi, rbx              ; rep movsb lê de rsi: a origem
    mov   rdi, r15              ; rep movsb grava em rdi: o destino
    rep   movsb                 ; copia a imagem; o interior será sobrescrito com o filtro

    ; ---------- tamanho do interior ----------
    sub   r10, 2                ; linhas interiores = altura - 2 (sem a primeira e a última)
    jle   .fim                  ; menos de 3 linhas: não há onde a máscara caiba
    mov   r9, r13               ; r9 = bytes de uma linha
    sub   r9, r14               ; tira o primeiro pixel da linha (moldura)
    sub   r9, r14               ; tira o último pixel da linha: r9 = bytes interiores
    jle   .fim                  ; menos de 3 colunas: não há onde a máscara caiba
    lea   rsi, [r13 + r14]      ; rsi = índice do pixel (1, 1): pula uma linha e um pixel
.linha:
    mov   r11, r9               ; bytes a filtrar nesta linha
.byte:
    mov   rdx, rsi              ; parte do índice do byte central
    sub   rdx, r13              ; sobe uma linha
    sub   rdx, r14              ; volta um pixel, mantendo o canal
    add   rdx, rbx              ; rdx = endereço do vizinho de cima-esquerda em src
    xor   edi, edi              ; zera a soma ponderada deste byte
    mov   r8, r12               ; aponta para o primeiro peso da máscara
    mov   ecx, 3                ; a janela tem 3 linhas
.janela:
    movzx eax, byte [rdx]       ; lê o vizinho da esquerda nesta linha da janela
    imul  eax, [r8]             ; multiplica pelo peso da coluna da esquerda
    add   edi, eax              ; acumula na soma ponderada
    movzx eax, byte [rdx + r14] ; lê o vizinho do meio (um pixel à direita)
    imul  eax, [r8 + 4]         ; multiplica pelo peso da coluna do meio
    add   edi, eax              ; acumula na soma ponderada
    movzx eax, byte [rdx + r14*2] ; lê o vizinho da direita (dois pixels à direita)
    imul  eax, [r8 + 8]         ; multiplica pelo peso da coluna da direita
    add   edi, eax              ; acumula na soma ponderada
    add   r8, 12                ; avança para a próxima linha de pesos (3 pesos * 4 bytes)
    add   rdx, r13              ; desce para a próxima linha da janela
    dec   ecx                   ; desconta a linha somada
    jnz   .janela               ; ainda há linhas: soma a próxima

    ; ---------- divide com arredondamento ----------
    cmp   ebp, 1                ; divisor 0 ou 1 não altera a soma (e 0 daria erro)
    jle   .satura               ; então pula a divisão
    mov   eax, ebp              ; eax = divisor
    shr   eax, 1                ; eax = divisor / 2
    add   eax, edi              ; soma metade do divisor para arredondar em vez de truncar
    cdq                         ; estende o sinal de eax para edx (idiv divide edx:eax)
    idiv  ebp                   ; eax = soma / divisor
    mov   edi, eax              ; o resultado da divisão vira o novo valor
.satura:
    SATURAR edi, eax            ; limita a 0..255, pois o passa-alta pode dar negativo ou mais de 255
    mov   [r15 + rsi], dil      ; grava o byte filtrado na mesma posição do destino
    inc   rsi                   ; próximo byte (próximo canal ou próximo pixel)
    dec   r11                   ; desconta o byte filtrado
    jnz   .byte                 ; ainda há bytes nesta linha: filtra o próximo
    add   rsi, r14              ; pula o último pixel desta linha (moldura)...
    add   rsi, r14              ; ...e o primeiro da próxima: rsi = pixel (1, y+1)
    dec   r10                   ; desconta a linha filtrada
    jnz   .linha                ; ainda há linhas: filtra a próxima
.fim:
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
