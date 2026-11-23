; FUNÇÃO ROTULACAO.ASM
;
; ======= CHAMADA =======
; int pdi_rotular(const uint8_t *src, int largura, int altura, int32_t *rotulos)
;
;
; ====== REGISTERS ======
;
; rdi = src (1 canal: 0 = fundo, qualquer outro valor = objeto)
; esi = largura
; edx = altura
; rcx = rotulos (um int32 por pixel: 0 = fundo, 1..n = número do objeto)
; eax = retorno: quantidade de objetos (n), ou -1 se faltar memória
;
; rbx = src      r15 = rotulos      r13 = largura      r12 = pilha
; r14 = quantidade de índices na pilha (topo)
; ebp = rótulo atual (também a quantidade de objetos encontrados)
; r8  = índice do pixel na varredura    [rsp] = largura * altura
; rcx = -largura     rsi = largura - 1     rdi = altura - 1
; r9  = índice do pixel desempilhado     r10 = sua linha (y)   r11 = sua coluna (x)
; rax = índice do vizinho examinado      rdx = resto da divisão
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados, alinha a pilha e guarda os argumentos
; 2. Zera os rótulos; se a imagem estiver vazia, retorna 0
; 3. Pede ao kernel uma pilha de largura*altura índices (pdi_aloca); se
;    faltar memória, retorna -1
; 4. Varre a imagem (índice r8). Ao achar um pixel do objeto ainda sem rótulo:
;   4.1 Cria um rótulo novo (ebp + 1), rotula o pixel e o empilha
;   4.2 Enquanto a pilha não estiver vazia (flood fill):
;     4.2.1 Desempilha um pixel e calcula sua linha e coluna
;     4.2.2 Para cada um dos 8 vizinhos dentro da imagem que é objeto e ainda
;           não tem rótulo: dá o mesmo rótulo e empilha
; 5. Devolve a pilha (pdi_libera), restaura e retorna a quantidade de rótulos
;
;
; ===== OBSERVAÇÕES =====
;
; Rotulação de componentes conexos por preenchimento (floodfill) com pilha,
; como nos slides de extração de características: cada região conexa recebe
; um número único, o que permite contar e medir os objetos.
; Vizinhança de 8: pixels que se tocam pela diagonal são do mesmo objeto.
; A pilha é explícita (memória do kernel) em vez de recursão: um objeto
; grande teria milhões de chamadas recursivas e estouraria a pilha do
; programa. Cada pixel recebe o rótulo quando é empilhado, por isso entra na
; pilha no máximo uma vez e largura*altura posições sempre bastam.
; Alinhamento: 8 (entrada) + 6 pushes * 8 + 24 = 80, múltiplo de 16.

%include "comum.inc"

section .text

global pdi_rotular:function     ; exporta a função para o Python
extern pdi_aloca                ; suporte/memoria.asm
extern pdi_libera               ; suporte/memoria.asm

; Rotula e empilha o vizinho de índice rax, se for objeto ainda sem rótulo.
%macro EXPANDE 0
    cmp   byte [rbx + rax], 0       ; verifica se o vizinho é fundo
    je    %%fim                     ; fundo não faz parte do objeto
    cmp   dword [r15 + rax*4], 0    ; verifica se o vizinho já tem rótulo
    jne   %%fim                     ; já rotulado (e já empilhado uma vez)
    mov   [r15 + rax*4], ebp        ; o vizinho é do mesmo objeto: recebe o rótulo atual
    mov   [r12 + r14*4], eax        ; empilha o vizinho para examinar os vizinhos dele
    inc   r14                       ; a pilha cresceu um índice
%%fim:
%endmacro

pdi_rotular:
    push  rbx                   ; preserva rbx: guardará src
    push  rbp                   ; preserva rbp: guardará o rótulo atual
    push  r12                   ; preserva r12: guardará a pilha
    push  r13                   ; preserva r13: guardará a largura
    push  r14                   ; preserva r14: guardará o topo da pilha
    push  r15                   ; preserva r15: guardará os rótulos
    sub   rsp, 24               ; espaço para a quantidade de pixels (e alinha a pilha em 16)
    mov   rbx, rdi              ; guarda src
    mov   r13d, esi             ; guarda a largura (zera a parte alta)
    mov   r15, rcx              ; guarda o vetor de rótulos
    mov   [rsp+8], rdx          ; guarda a altura (só os 32 bits baixos valem)
    mov   eax, esi              ; rax = largura
    mov   edx, edx              ; zera a parte alta da altura
    imul  rax, rdx              ; rax = largura * altura: quantidade de pixels
    mov   [rsp], rax            ; guarda na pilha, para o fim da varredura e o tamanho da pilha
    xor   ebp, ebp              ; nenhum objeto encontrado ainda
    test  rax, rax              ; verifica se a imagem está vazia
    jz    .fim                  ; vazia: retorna 0 objetos

    ; ---------- zera os rótulos ----------
    mov   rdi, r15              ; rep stosd grava a partir de rdi: os rótulos
    mov   rcx, rax              ; rcx = um int32 por pixel
    xor   eax, eax              ; valor gravado: 0 (sem rótulo)
    rep   stosd                 ; todos os pixels começam sem rótulo

    ; ---------- pilha de índices (4 bytes cada) ----------
    mov   rdi, [rsp]            ; rdi = quantidade de pixels
    shl   rdi, 2                ; * 4 bytes por índice
    call  pdi_aloca wrt ..plt   ; pede a memória ao kernel
    test  rax, rax              ; verifica se conseguiu memória
    jz    .sem_memoria          ; faltou memória: avisa com -1
    mov   r12, rax              ; r12 = base da pilha

    mov   rcx, r13              ; rcx = largura...
    neg   rcx                   ; ...negativo: índice + rcx é o vizinho de cima
    lea   rsi, [r13 - 1]        ; rsi = última coluna (largura - 1)
    mov   edi, [rsp+8]          ; rdi = altura (zera a parte alta)
    dec   rdi                   ; rdi = última linha (altura - 1)
    xor   r8d, r8d              ; a varredura começa no pixel 0
.varre:
    cmp   byte [rbx + r8], 0    ; verifica se o pixel é fundo
    je    .seguinte             ; fundo: não começa objeto
    cmp   dword [r15 + r8*4], 0 ; verifica se o pixel já tem rótulo
    jne   .seguinte             ; já faz parte de um objeto rotulado
    inc   ebp                   ; achou um objeto novo: próximo número
    mov   [r15 + r8*4], ebp     ; rotula a semente do preenchimento
    mov   [r12], r8d            ; empilha a semente
    mov   r14d, 1               ; a pilha tem 1 índice
.desempilha:
    dec   r14                   ; tira o índice do topo da pilha
    mov   r9d, [r12 + r14*4]    ; r9 = índice do pixel a expandir
    mov   rax, r9               ; dividendo: o índice
    xor   edx, edx              ; parte alta do dividendo = 0
    div   r13                   ; índice / largura: rax = linha, rdx = coluna
    mov   r10, rax              ; r10 = y
    mov   r11, rdx              ; r11 = x

    ; ---------- linha de cima ----------
    test  r10, r10              ; verifica se o pixel está na primeira linha
    jz    .meio                 ; primeira linha: não há vizinhos acima
    lea   rax, [r9 + rcx]       ; vizinho de cima
    EXPANDE                     ; rotula e empilha se for objeto
    test  r11, r11              ; verifica se está na primeira coluna
    jz    .cima_direita         ; sem vizinho à esquerda
    lea   rax, [r9 + rcx - 1]   ; vizinho de cima-esquerda
    EXPANDE                     ; rotula e empilha se for objeto
.cima_direita:
    cmp   r11, rsi              ; verifica se está na última coluna
    jae   .meio                 ; sem vizinho à direita
    lea   rax, [r9 + rcx + 1]   ; vizinho de cima-direita
    EXPANDE                     ; rotula e empilha se for objeto
    ; ---------- mesma linha ----------
.meio:
    test  r11, r11              ; verifica se está na primeira coluna
    jz    .direita              ; sem vizinho à esquerda
    lea   rax, [r9 - 1]         ; vizinho da esquerda
    EXPANDE                     ; rotula e empilha se for objeto
.direita:
    cmp   r11, rsi              ; verifica se está na última coluna
    jae   .baixo                ; sem vizinho à direita
    lea   rax, [r9 + 1]         ; vizinho da direita
    EXPANDE                     ; rotula e empilha se for objeto
    ; ---------- linha de baixo ----------
.baixo:
    cmp   r10, rdi              ; verifica se está na última linha
    jae   .vizinhos_feitos      ; última linha: não há vizinhos abaixo
    lea   rax, [r9 + r13]       ; vizinho de baixo
    EXPANDE                     ; rotula e empilha se for objeto
    test  r11, r11              ; verifica se está na primeira coluna
    jz    .baixo_direita        ; sem vizinho à esquerda
    lea   rax, [r9 + r13 - 1]   ; vizinho de baixo-esquerda
    EXPANDE                     ; rotula e empilha se for objeto
.baixo_direita:
    cmp   r11, rsi              ; verifica se está na última coluna
    jae   .vizinhos_feitos      ; sem vizinho à direita
    lea   rax, [r9 + r13 + 1]   ; vizinho de baixo-direita
    EXPANDE                     ; rotula e empilha se for objeto
.vizinhos_feitos:
    test  r14, r14              ; verifica se a pilha esvaziou
    jnz   .desempilha           ; ainda há pixels do objeto a expandir

.seguinte:
    inc   r8                    ; próximo pixel da varredura
    cmp   r8, [rsp]             ; verifica se chegou ao fim da imagem
    jb    .varre                ; ainda há pixels: continua procurando objetos

    mov   rdi, r12              ; argumento: a pilha, que não é mais necessária
    call  pdi_libera wrt ..plt  ; devolve a memória ao kernel
    jmp   .fim                  ; retorna a quantidade de objetos
.sem_memoria:
    mov   ebp, -1               ; -1 avisa o chamador que faltou memória
.fim:
    mov   eax, ebp              ; retorno: quantidade de objetos (ou -1)
    add   rsp, 24               ; libera o espaço reservado
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador
