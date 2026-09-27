; FUNÇÃO JANELA.ASM
;
; ======= CHAMADA =======
; void pdi_janela(const uint8_t *src, int largura, int altura, int canais,
;                 uint8_t *dst, uint8_t (*escolher)(uint8_t *janela))
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9  = escolher: função que recebe os 9 valores da janela e devolve o novo
;       valor do pixel
;
; rbx = endereço do vizinho de cima-esquerda em src
; r15 = endereço do byte atual em dst
; r12 = função escolher  r13 = bytes de uma linha   r14 = canais
; rbp = bytes que faltam na linha atual
; rdx = endereço do vizinho lido          rdi = posição na janela
; ecx = linhas da janela que faltam copiar
; al  = vizinho copiado / valor escolhido
;
; Pilha (40 bytes):
; [rsp]    = linhas interiores que faltam
; [rsp+8]  = bytes interiores de uma linha
; [rsp+16] .. [rsp+24] = a janela (9 bytes)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados, reserva 40 bytes na pilha e guarda
;    os argumentos
; 2. Copia a imagem inteira para o destino: a moldura de 1 pixel, onde a
;    janela 3x3 não cabe, fica com o pixel original
; 3. Se a imagem tiver menos de 3 linhas ou 3 colunas, termina
; 4. Para cada byte do interior (cada canal de cada pixel):
;   4.1 Copia os 9 vizinhos do mesmo canal para a janela, linha por linha
;   4.2 Chama escolher(janela) e grava o valor devolvido em [r15]
;   4.3 Avança rbx e r15; no fim da linha pula a moldura (último pixel desta
;       linha e primeiro da próxima)
; 5. Libera a pilha, restaura os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Faz o mesmo percurso de convolucao.asm, mas em vez de multiplicar os
; vizinhos por pesos, entrega os 9 valores a uma função que escolhe o novo
; valor. Usada pelos filtros da moda e da mediana, que não são convoluções:
; precisam ordenar ou contar os valores da janela.
; Como a função chamada pode destruir os registradores rax, rcx, rdx, rsi,
; rdi e r8 a r11, tudo o que precisa sobreviver à chamada fica nos
; registradores preservados (rbx, rbp, r12 a r15) ou na pilha.
; Alinhamento: 8 (entrada) + 6 pushes * 8 + 40 = múltiplo de 16 antes do call.

%include "comum.inc"

section .text

global pdi_janela:function      ; exporta para os filtros

pdi_janela:
    push  rbx                   ; preserva rbx: apontará o vizinho de cima-esquerda em src
    push  rbp                   ; preserva rbp: contará os bytes da linha
    push  r12                   ; preserva r12: guardará a função escolher
    push  r13                   ; preserva r13: guardará os bytes de uma linha
    push  r14                   ; preserva r14: guardará os canais
    push  r15                   ; preserva r15: apontará o byte atual em dst
    sub   rsp, 40               ; reserva os 2 contadores e a janela (e alinha a pilha em 16)
    mov   rbx, rdi              ; guarda src, pois rep movsb usa rdi
    mov   r15, r8               ; guarda dst
    mov   r12, r9               ; guarda a função escolher
    mov   r14d, ecx             ; guarda os canais, pois rep movsb usa rcx
    mov   r13d, esi             ; r13 = largura (zera a parte alta)
    imul  r13, r14              ; r13 = largura * canais: bytes de uma linha, distância até o vizinho de baixo
    mov   edx, edx              ; zera a parte alta da altura para as contas de 64 bits

    ; ---------- copia tudo: a moldura mantém o pixel original ----------
    mov   rcx, r13              ; rcx = bytes de uma linha
    imul  rcx, rdx              ; rcx = bytes da imagem inteira
    mov   rsi, rbx              ; rep movsb lê de rsi: a origem
    mov   rdi, r15              ; rep movsb grava em rdi: o destino
    rep   movsb                 ; copia a imagem; o interior será sobrescrito com o filtro

    ; ---------- tamanho do interior ----------
    sub   rdx, 2                ; linhas interiores = altura - 2 (sem a primeira e a última)
    jle   .fim                  ; menos de 3 linhas: não há onde a janela caiba
    mov   [rsp], rdx            ; guarda na pilha, pois a função escolher pode destruir rdx
    mov   rax, r13              ; rax = bytes de uma linha
    sub   rax, r14              ; tira o primeiro pixel da linha (moldura)
    sub   rax, r14              ; tira o último pixel da linha: rax = bytes interiores
    jle   .fim                  ; menos de 3 colunas: não há onde a janela caiba
    mov   [rsp+8], rax          ; guarda na pilha, pelo mesmo motivo
    add   r15, r13              ; desce uma linha no destino...
    add   r15, r14              ; ...e avança um pixel: r15 aponta o pixel (1, 1)
    ; rbx = src: o vizinho de cima-esquerda do pixel (1, 1) é o pixel (0, 0)
.linha:
    mov   rbp, [rsp+8]          ; bytes a filtrar nesta linha
.byte:
    ; ---------- copia os 9 vizinhos para a janela ----------
    lea   rdi, [rsp+16]         ; rdi aponta a primeira posição da janela
    mov   rdx, rbx              ; rdx aponta o vizinho de cima-esquerda
    mov   ecx, 3                ; a janela tem 3 linhas
.copia:
    mov   al, [rdx]             ; lê o vizinho da esquerda nesta linha da janela
    mov   [rdi], al             ; guarda na janela
    mov   al, [rdx + r14]       ; lê o vizinho do meio (um pixel à direita, mesmo canal)
    mov   [rdi + 1], al         ; guarda na janela
    mov   al, [rdx + r14*2]     ; lê o vizinho da direita (dois pixels à direita)
    mov   [rdi + 2], al         ; guarda na janela
    add   rdi, 3                ; próxima linha da janela (3 valores por linha)
    add   rdx, r13              ; desce para a próxima linha da imagem
    dec   ecx                   ; desconta a linha copiada
    jnz   .copia                ; ainda há linhas: copia a próxima

    lea   rdi, [rsp+16]         ; 1º argumento de escolher: o endereço da janela
    call  r12                   ; chama a função cujo endereço está em r12 (moda ou mediana)
    mov   [r15], al             ; grava no destino o valor escolhido
    inc   rbx                   ; a janela anda um byte (próximo canal ou próximo pixel)
    inc   r15                   ; o destino anda junto
    dec   rbp                   ; desconta o byte filtrado
    jnz   .byte                 ; ainda há bytes nesta linha: filtra o próximo
    lea   rbx, [rbx + r14*2]    ; pula o último pixel desta linha e o primeiro da próxima
    lea   r15, [r15 + r14*2]    ; o destino pula junto
    dec   qword [rsp]           ; desconta a linha filtrada
    jnz   .linha                ; ainda há linhas: filtra a próxima
.fim:
    add   rsp, 40               ; libera os contadores e a janela
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
