; FUNÇÃO MEDIANA.ASM
;
; ======= CHAMADA =======
; void pdi_mediana(const uint8_t *src, int largura, int altura, int canais,
;                  uint8_t *dst)
; uint8_t mediana_da_janela(uint8_t *janela)       (uso interno)
;
;
; ====== REGISTERS ======
;
; pdi_mediana:
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9  = endereço de mediana_da_janela (6º argumento de pdi_janela)
;
; mediana_da_janela:
; rdi = janela (9 valores, que são ordenados no próprio lugar)
; ecx = passadas que faltam      edx = posição j do par comparado
; al  = valor da posição j / retorno: a mediana
; r8b = valor da posição j+1
;
;
; ==== FUNCIONAMENTO ====
;
; pdi_mediana:
; 1. Alinha a pilha e passa em r9 o endereço de mediana_da_janela
; 2. Chama pdi_janela (os 5 primeiros argumentos não mudam), que chama
;    mediana_da_janela para cada pixel de cada canal
; 3. Restaura a pilha e retorna
;
; mediana_da_janela:
; 1. Ordena os 9 valores (bubble sort), repetindo 8 passadas:
;   1.1 Compara cada par vizinho (j, j+1), com j de 0 a 7
;   1.2 Se o da esquerda for maior, troca os dois
; 2. Retorna o valor do meio (posição 4)
;
;
; ===== OBSERVAÇÕES =====
;
; Filtro passa-baixa da mediana: o pixel vira o valor intermediário dos 9
; valores da janela 3x3, depois de ordenados.
; Suaviza a imagem preservando as bordas e remove bem o ruído "sal e pimenta":
; um pixel isolado muito claro ou muito escuro vai para uma ponta da
; ordenação e nunca é o escolhido.
; A cada passada o maior valor ainda fora do lugar "borbulha" até o fim, então
; 8 passadas bastam para ordenar 9 valores.
; Alinhamento: na entrada rsp termina em 8 (mod 16); 8 - 8 = múltiplo de 16.

%include "comum.inc"

section .text

global pdi_mediana:function     ; exporta a função para o Python
extern pdi_janela               ; suporte/janela.asm

pdi_mediana:
    sub   rsp, 8                ; alinha a pilha em 16 antes do call
    lea   r9, [mediana_da_janela] ; 6º argumento: a função que escolhe o valor de cada janela
    call  pdi_janela wrt ..plt  ; percorre a imagem chamando mediana_da_janela
    add   rsp, 8                ; desfaz o alinhamento
    ret                         ; volta ao chamador; o resultado está em dst

mediana_da_janela:
    mov   ecx, 8                ; 8 passadas ordenam os 9 valores
.passada:
    xor   edx, edx              ; cada passada começa pelo par (0, 1)
.compara:
    mov   al, [rdi + rdx]       ; lê o valor da posição j
    mov   r8b, [rdi + rdx + 1]  ; lê o valor da posição j+1
    cmp   al, r8b               ; compara os dois (sem sinal, pois são bytes 0..255)
    jbe   .em_ordem             ; já estão em ordem crescente: não troca
    mov   [rdi + rdx], r8b      ; troca: o menor vai para a posição j...
    mov   [rdi + rdx + 1], al   ; ...e o maior vai para a posição j+1
.em_ordem:
    inc   edx                   ; passa para o próximo par
    cmp   edx, 8                ; o último par é (7, 8)
    jb    .compara              ; ainda há pares nesta passada: compara o próximo
    dec   ecx                   ; desconta a passada feita
    jnz   .passada              ; ainda há passadas: faz a próxima
    movzx eax, byte [rdi + 4]   ; mediana: o 5º dos 9 valores ordenados (posição 4)
    ret                         ; devolve a mediana em al
