; FUNÇÃO AFINAMENTO.ASM
;
; ======= CHAMADA =======
; void pdi_afinamento(const uint8_t *src, int largura, int altura, int canais,
;                     uint8_t *dst)
; int etapa(uint8_t *img, int largura, int altura, int grupos)   (uso interno)
;
;
; ====== REGISTERS ======
;
; pdi_afinamento:
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (sempre 1 canal: 255 = esqueleto, 0 = fundo)
; rbx = dst      r12 = largura      r13 = altura
; r14 = largura * altura           r15 = pixels removidos no ciclo
; rdi = ponteiro que percorre o destino    rcx = contador / colunas
;
; etapa:
; rdi = imagem (0 = fundo, 1 = objeto) / ponteiro do pixel avaliado (P1)
; esi = largura   r9 = -largura (vizinho de cima)
; edx = altura / auxiliar
; cl  = 1º grupo de vizinhos que precisa ter um fundo (P2,P4,P6 ou P2,P4,P8)
; ch  = 2º grupo de vizinhos que precisa ter um fundo (P4,P6,P8 ou P2,P6,P8)
; r10 = linhas interiores que faltam    r11 = colunas que faltam na linha
; eax = os 8 vizinhos, um por bit (bit 0 = P2, bit 1 = P3, ..., bit 7 = P9)
; edx = B (vizinhos do objeto) / A (mudanças de 0 para 1)
; r8d = auxiliar         ebx = pixels marcados nesta etapa (retorno em eax)
;
;
; ==== FUNCIONAMENTO ====
;
; pdi_afinamento:
; 1. Salva os registradores preservados e guarda dst, largura e altura
; 2. Converte para cinza no destino (pdi_grayscale) e binariza: pixel claro
;    (>= 128) vira 1 (objeto) e o resto vira 0 (fundo)
; 3. Apaga a moldura de 1 pixel (não tem os 8 vizinhos); se a imagem tiver
;    menos de 3 linhas ou colunas, pula para o passo 5
; 4. Repete enquanto algum pixel for removido:
;   4.1 Etapa 1: etapa(..., grupos P2·P4·P6 e P4·P6·P8)
;   4.2 Etapa 2: etapa(..., grupos P2·P4·P8 e P2·P6·P8)
; 5. Troca 1 por 255 (o esqueleto fica branco), restaura e retorna
;
; etapa:
; 1. Para cada pixel interior P1 que vale 1:
;   1.1 Junta os 8 vizinhos em eax, um bit cada (vizinho 1 ou 2 = objeto)
;   1.2 B = quantidade de bits 1; se não estiver entre 2 e 6, mantém P1
;   1.3 A = mudanças de 0 para 1 na volta P2, P3, ..., P9, P2; se A != 1,
;       mantém P1
;   1.4 Se os 3 vizinhos de um dos grupos forem todos objeto, mantém P1
;   1.5 Senão marca P1 com 2 (ainda conta como objeto para os vizinhos)
; 2. Apaga (troca por 0) todos os pixels marcados com 2
; 3. Retorna quantos pixels foram apagados
;
;
; ===== OBSERVAÇÕES =====
;
; Algoritmo de Zhang-Suen (slides de afinamento). Vizinhança de P1:
;     P9 P2 P3
;     P8 P1 P4
;     P7 P6 P5
; P1 é apagado quando TODAS as condições da etapa são verdadeiras:
;   Etapa 1: 2 <= B <= 6,  A = 1,  P2·P4·P6 = 0,  P4·P6·P8 = 0
;   Etapa 2: 2 <= B <= 6,  A = 1,  P2·P4·P8 = 0,  P2·P6·P8 = 0
; B < 2 é uma ponta (fica para o traço não encurtar); B > 6 é um pixel do
; interior; A = 1 garante que apagar P1 não separa o objeto em dois.
; Os pixels são marcados e só apagados no fim da etapa, para que todas as
; decisões da etapa usem a mesma imagem. A etapa 1 tira as bordas sul e leste
; (e o canto noroeste); a etapa 2, as bordas norte e oeste (e o canto sudeste).
; O objeto é a parte CLARA: para afinar um desenho escuro em fundo claro,
; aplique o Negativo antes.
; Um produto P2·P4·P6 é 0 quando algum dos três é fundo: com os vizinhos num
; byte, basta ver se (vizinhos AND grupo) é diferente do grupo.
; A = popcnt(NOT vizinhos AND vizinhos girados 1 bit): o bit i fica 1 quando
; o vizinho i é 0 e o seguinte na volta é 1.
; Alinhamento: 8 (entrada) + 5 pushes * 8 = 48, múltiplo de 16 antes dos calls.

%include "comum.inc"

section .text

global pdi_afinamento:function  ; exporta a função para o Python e para os exercícios
extern pdi_grayscale            ; filtros/grayscale.asm

; Põe no bit %2 de al o valor (0 ou 1) do vizinho %1.
%macro VIZINHO 2
    cmp   byte %1, 0            ; verifica se o vizinho é fundo
    setne dl                    ; dl = 1 se for objeto (1 ou marcado com 2), 0 se fundo
    shl   dl, %2                ; leva o bit para a posição deste vizinho
    or    al, dl                ; junta aos vizinhos já lidos
%endmacro

pdi_afinamento:
    push  rbx                   ; preserva rbx: guardará dst
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará a altura
    push  r14                   ; preserva r14: guardará a quantidade de pixels
    push  r15                   ; preserva r15: contará os pixels removidos no ciclo
    mov   rbx, r8               ; guarda dst, pois o call pode destruir r8
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13d, edx             ; guarda a altura (zera a parte alta)
    mov   r14, r12              ; r14 = largura
    imul  r14, r13              ; r14 = largura * altura: pixels do destino
    ; os 5 argumentos já estão nos registradores certos para pdi_grayscale
    call  pdi_grayscale wrt ..plt ; grava a imagem em cinza no destino
    test  r14, r14              ; verifica se a imagem está vazia
    jz    .fim                  ; nada a afinar

    ; ---------- binariza: 1 = objeto (claro), 0 = fundo ----------
    mov   rdi, rbx              ; começa no primeiro pixel
    mov   rcx, r14              ; rcx = pixels a binarizar
.binariza:
    cmp   byte [rdi], 128       ; compara o cinza com o meio da escala
    setae al                    ; al = 1 se o pixel for claro (objeto), 0 se escuro
    mov   [rdi], al             ; o afinamento trabalha só com 0 e 1
    inc   rdi                   ; próximo pixel
    dec   rcx                   ; desconta o pixel binarizado
    jnz   .binariza             ; ainda há pixels: binariza o próximo

    ; ---------- apaga a moldura de 1 pixel ----------
    mov   rdi, rbx              ; rep stosb grava a partir da primeira linha
    mov   rcx, r12              ; rcx = largura: uma linha inteira
    xor   eax, eax              ; valor gravado: 0 (fundo)
    rep   stosb                 ; primeira linha: não tem vizinhos de cima
    lea   rdi, [rbx + r14]      ; fim da imagem...
    sub   rdi, r12              ; ...menos uma linha: início da última linha
    mov   rcx, r12              ; rcx = largura
    rep   stosb                 ; última linha: não tem vizinhos de baixo
    mov   rdi, rbx              ; volta ao primeiro pixel
    mov   rcx, r13              ; rcx = altura: uma passada por linha
.moldura:
    mov   byte [rdi], 0         ; primeira coluna: não tem vizinhos à esquerda
    mov   byte [rdi + r12 - 1], 0 ; última coluna: não tem vizinhos à direita
    add   rdi, r12              ; desce uma linha
    dec   rcx                   ; desconta a linha
    jnz   .moldura              ; ainda há linhas: apaga as pontas da próxima
    cmp   r12, 3                ; verifica se há pelo menos 3 colunas
    jb    .branco               ; não há pixel interior para avaliar
    cmp   r13, 3                ; verifica se há pelo menos 3 linhas
    jb    .branco               ; não há pixel interior para avaliar

    ; ---------- ciclos de duas etapas até nada mudar ----------
.ciclo:
    mov   rdi, rbx              ; 1º argumento: a imagem binária
    mov   esi, r12d             ; 2º argumento: largura
    mov   edx, r13d             ; 3º argumento: altura
    mov   ecx, 0x5415           ; 4º: grupos da etapa 1, cl = P2,P4,P6 (bits 0,2,4) e ch = P4,P6,P8 (bits 2,4,6)
    call  etapa                 ; apaga as bordas sul e leste
    mov   r15, rax              ; começa a contagem do ciclo
    mov   rdi, rbx              ; 1º argumento: a imagem já atualizada pela etapa 1
    mov   esi, r12d             ; 2º argumento: largura
    mov   edx, r13d             ; 3º argumento: altura
    mov   ecx, 0x5145           ; 4º: grupos da etapa 2, cl = P2,P4,P8 (bits 0,2,6) e ch = P2,P6,P8 (bits 0,4,6)
    call  etapa                 ; apaga as bordas norte e oeste
    add   r15, rax              ; total removido no ciclo
    jnz   .ciclo                ; removeu algo: o esqueleto ainda pode afinar mais

    ; ---------- esqueleto branco ----------
.branco:
    mov   rdi, rbx              ; começa no primeiro pixel
    mov   rcx, r14              ; rcx = pixels
.converte:
    neg   byte [rdi]            ; 1 vira 255 (0xFF) e 0 continua 0
    inc   rdi                   ; próximo pixel
    dec   rcx                   ; desconta o pixel convertido
    jnz   .converte             ; ainda há pixels: converte o próximo
.fim:
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst

etapa:
    push  rbx                   ; preserva rbx: contará os pixels marcados
    mov   esi, esi              ; zera a parte alta da largura
    mov   edx, edx              ; zera a parte alta da altura
    mov   rax, rsi              ; rax = largura
    imul  rax, rdx              ; rax = largura * altura
    push  rax                   ; guarda a quantidade de pixels para a fase de apagar
    push  rdi                   ; guarda o início da imagem para a fase de apagar
    xor   ebx, ebx              ; nenhum pixel marcado ainda
    mov   r9, rsi               ; r9 = largura...
    neg   r9                    ; ...negativo: [ptr + r9] é o vizinho de cima
    lea   r10, [rdx - 2]        ; linhas interiores = altura - 2
    lea   rdi, [rdi + rsi + 1]  ; rdi aponta o pixel (1, 1)
.linha:
    lea   r11, [rsi - 2]        ; colunas interiores = largura - 2
.pixel:
    cmp   byte [rdi], 1         ; só avalia pixels do objeto
    jne   .proximo              ; fundo: nada a apagar
    xor   eax, eax              ; nenhum vizinho lido ainda
    VIZINHO [rdi + r9], 0       ; P2: cima
    VIZINHO [rdi + r9 + 1], 1   ; P3: cima-direita
    VIZINHO [rdi + 1], 2        ; P4: direita
    VIZINHO [rdi + rsi + 1], 3  ; P5: baixo-direita
    VIZINHO [rdi + rsi], 4      ; P6: baixo
    VIZINHO [rdi + rsi - 1], 5  ; P7: baixo-esquerda
    VIZINHO [rdi - 1], 6        ; P8: esquerda
    VIZINHO [rdi + r9 - 1], 7   ; P9: cima-esquerda

    ; B = quantidade de vizinhos do objeto
    popcnt edx, eax             ; conta os bits 1: os vizinhos que são objeto
    cmp   edx, 2                ; menos de 2 vizinhos: P1 é uma ponta
    jb    .proximo              ; ponta fica, para o traço não encurtar
    cmp   edx, 6                ; mais de 6 vizinhos: P1 está no interior
    ja    .proximo              ; interior fica (ainda não é borda)

    ; A = mudanças de 0 para 1 na volta P2 -> P3 -> ... -> P9 -> P2
    mov   edx, eax              ; copia os vizinhos
    ror   dl, 1                 ; gira: o bit i passa a ser o vizinho seguinte ao vizinho i
    mov   r8d, eax              ; copia os vizinhos de novo
    not   r8d                   ; bit i = 1 onde o vizinho i é fundo
    and   edx, r8d              ; bit i = 1 onde o vizinho i é 0 e o seguinte é 1
    popcnt edx, edx             ; A = quantas mudanças de 0 para 1
    cmp   edx, 1                ; mais de uma mudança: P1 liga partes diferentes
    jne   .proximo              ; apagar P1 separaria o objeto: fica

    ; produtos dos grupos: cada grupo precisa ter pelo menos um fundo
    mov   edx, eax              ; copia os vizinhos
    and   dl, cl                ; mantém só os vizinhos do 1º grupo
    cmp   dl, cl                ; os três são objeto? (produto = 1)
    je    .proximo              ; produto 1: P1 fica nesta etapa
    mov   edx, eax              ; copia os vizinhos
    and   dl, ch                ; mantém só os vizinhos do 2º grupo
    cmp   dl, ch                ; os três são objeto? (produto = 1)
    je    .proximo              ; produto 1: P1 fica nesta etapa

    mov   byte [rdi], 2         ; todas as condições valem: marca P1 para apagar
    inc   ebx                   ; conta o pixel marcado
.proximo:
    inc   rdi                   ; próximo pixel
    dec   r11                   ; desconta a coluna avaliada
    jnz   .pixel                ; ainda há colunas: avalia a próxima
    add   rdi, 2                ; pula o último pixel desta linha e o primeiro da próxima
    dec   r10                   ; desconta a linha avaliada
    jnz   .linha                ; ainda há linhas: avalia a próxima

    ; ---------- apaga os marcados de uma vez ----------
    pop   rdi                   ; volta ao início da imagem
    pop   rcx                   ; rcx = quantidade de pixels
.apaga:
    cmp   byte [rdi], 2         ; verifica se o pixel foi marcado
    jne   .mantem               ; não marcado: continua como está
    mov   byte [rdi], 0         ; marcado: vira fundo
.mantem:
    inc   rdi                   ; próximo pixel
    dec   rcx                   ; desconta o pixel
    jnz   .apaga                ; ainda há pixels: verifica o próximo
    mov   eax, ebx              ; retorna quantos pixels foram apagados
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta para pdi_afinamento
