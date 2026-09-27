; FUNÇÃO MODA.ASM
;
; ======= CHAMADA =======
; void pdi_moda(const uint8_t *src, int largura, int altura, int canais,
;               uint8_t *dst)
; uint8_t moda_da_janela(uint8_t *janela)          (uso interno)
;
;
; ====== REGISTERS ======
;
; pdi_moda:
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9  = endereço de moda_da_janela (6º argumento de pdi_janela)
;
; moda_da_janela:
; rdi  = janela (9 valores)
; eax  = moda encontrada até agora (retorno em al)
; r8d  = quantas vezes a moda atual aparece na janela
; ecx  = posição i do candidato      r9b = valor do candidato
; edx  = posição j comparada          r10d = quantas vezes o candidato aparece
;
;
; ==== FUNCIONAMENTO ====
;
; pdi_moda:
; 1. Alinha a pilha e passa em r9 o endereço de moda_da_janela
; 2. Chama pdi_janela (os 5 primeiros argumentos não mudam), que chama
;    moda_da_janela para cada pixel de cada canal
; 3. Restaura a pilha e retorna
;
; moda_da_janela:
; 1. Começa supondo que a moda é o pixel central, com 1 ocorrência
; 2. Para cada candidato i de 0 a 8:
;   2.1 Conta em r10d quantos dos 9 valores são iguais ao candidato
;   2.2 Se aparece MAIS vezes que a moda atual, ele vira a nova moda
; 3. Retorna a moda
;
;
; ===== OBSERVAÇÕES =====
;
; Filtro passa-baixa da moda: o pixel vira o valor que mais se repete na
; janela 3x3 (o nível mais "populoso").
; Homogeneíza regiões e reduz ruído mantendo valores que já existem na
; imagem (não cria tons novos, como a média).
; Se nenhum valor se repete, o pixel central é mantido. Em empate, fica o
; primeiro encontrado na janela (de cima para baixo, da esquerda para a
; direita), pois só troca quando a contagem é maior.
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 8 = múltiplo de 16.

%include "comum.inc"

section .text

global pdi_moda:function        ; exporta a função para o Python
extern pdi_janela               ; suporte/janela.asm

pdi_moda:
    sub   rsp, 8                ; alinha a pilha em 16 antes do call
    lea   r9, [moda_da_janela]  ; 6º argumento: a função que escolhe o valor de cada janela
    call  pdi_janela wrt ..plt  ; percorre a imagem chamando moda_da_janela
    add   rsp, 8                ; desfaz o alinhamento
    ret                         ; volta ao chamador; o resultado está em dst

moda_da_janela:
    movzx eax, byte [rdi + 4]   ; supõe que a moda é o pixel central (vale se nada se repetir)
    mov   r8d, 1                ; ...que aparece pelo menos 1 vez
    xor   ecx, ecx              ; começa pelo candidato da posição 0
.candidato:
    mov   r9b, [rdi + rcx]      ; lê o valor do candidato i
    xor   r10d, r10d            ; zera a contagem do candidato
    xor   edx, edx              ; compara a partir da posição 0
.conta:
    cmp   r9b, [rdi + rdx]      ; verifica se o valor da posição j é igual ao candidato
    jne   .diferente            ; diferente: não conta
    inc   r10d                  ; igual: mais uma ocorrência do candidato
.diferente:
    inc   edx                   ; passa para a próxima posição
    cmp   edx, 9                ; verifica se já olhou os 9 valores
    jb    .conta                ; ainda falta: compara o próximo
    cmp   r10d, r8d             ; compara a contagem do candidato com a da moda atual
    jbe   .proximo              ; não aparece mais vezes: a moda continua a mesma
    movzx eax, r9b              ; aparece mais vezes: o candidato vira a moda
    mov   r8d, r10d             ; e sua contagem vira a contagem a superar
.proximo:
    inc   ecx                   ; passa para o próximo candidato
    cmp   ecx, 9                ; verifica se já testou os 9 candidatos
    jb    .candidato            ; ainda falta: testa o próximo
    ret                         ; devolve a moda em al
