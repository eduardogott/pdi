; FUNÇÃO CONTRASTE.ASM
;
; ======= CHAMADA =======
; void pdi_brilho_contraste(const uint8_t *src, int largura, int altura,
;                           int canais, uint8_t *dst,
;                           double contraste, double brilho)
;
;
; ====== REGISTERS ======
;
; rdi  = src (avança um byte por vez)
; esi  = largura
; edx  = altura
; ecx  = canais
; r8   = dst (mesmo número de canais de src; avança um byte por vez)
; xmm0 = contraste (C)
; xmm1 = brilho (B)
; xmm2 = C*i + B calculado para um valor i
; r9   = i (valor antigo 0..255) / byte lido da imagem
; r10  = resultado arredondado e limitado da fórmula
; r11  = auxiliar da macro SATURAR
; rax  = quantidade de bytes que faltam processar
; [rsp] .. [rsp+255] = LUT (tabela com o novo valor de cada valor antigo)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Reserva 256 bytes na pilha para a LUT
; 2. Monta a LUT, para i de 0 a 255 (r9):
;   2.1 Calcula C*i + B em xmm2
;   2.2 Arredonda para inteiro em r10 e limita a 0..255
;   2.3 Grava em LUT[i]
; 3. Calcula em rax o total de bytes (largura * altura * canais); se 0, termina
; 4. Para cada byte da imagem:
;   4.1 Lê o byte antigo de [rdi] em r9
;   4.2 Troca pelo valor da tabela: r9 = LUT[r9]
;   4.3 Grava em [r8]
;   4.4 Avança rdi e r8, decrementa rax e repete enquanto rax não for 0
; 5. Libera a LUT da pilha e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; D(x,y) = C * f(x,y) + B, limitado a 0..255.
;   C = contraste (1 = não altera; entre 0 e 1 reduz; maior que 1 aumenta)
;   B = brilho    (0 = não altera; positivo clareia; negativo escurece)
; Como um byte só tem 256 valores possíveis, a fórmula é calculada UMA vez para
; cada valor e guardada na tabela (LUT, "look-up table", como no artigo de
; Albuquerque). Assim a imagem inteira é processada só com consultas, sem
; nenhuma conta de ponto flutuante por pixel.
; Cada canal (R, G, B ou cinza) é tratado da mesma forma.

%include "comum.inc"

section .text

global pdi_brilho_contraste:function ; exporta a função para o Python

pdi_brilho_contraste:
    sub   rsp, 256              ; reserva na pilha 1 byte para cada valor possível (a LUT)
    xor   r9d, r9d              ; começa a tabela pelo valor antigo i = 0
.lut:
    cvtsi2sd xmm2, r9d          ; converte i para double, pois C e B são fracionários
    mulsd xmm2, xmm0            ; aplica o contraste: xmm2 = C * i
    addsd xmm2, xmm1            ; soma o brilho: xmm2 = C * i + B
    cvtsd2si r10, xmm2          ; arredonda o novo valor para o inteiro mais próximo
    SATURAR r10, r11            ; limita a 0..255 para caber num byte
    mov   [rsp + r9], r10b      ; guarda o novo valor na posição i da tabela
    inc   r9d                   ; passa para o próximo valor antigo
    cmp   r9d, 256              ; verifica se já preencheu os 256 valores
    jb    .lut                  ; ainda falta: calcula a próxima posição

    mov   eax, esi              ; rax = largura (zera a parte alta)
    mov   edx, edx              ; zera a parte alta da altura para a conta de 64 bits
    imul  rax, rdx              ; rax = largura * altura = número de pixels
    mov   ecx, ecx              ; zera a parte alta dos canais
    imul  rax, rcx              ; rax = pixels * canais: cada byte é tratado igual
    test  rax, rax              ; verifica se a imagem não tem nenhum byte
    jz    .fim                  ; imagem vazia: só libera a tabela
.byte:
    movzx r9d, byte [rdi]       ; lê o valor antigo do byte (0..255) para usar como índice
    movzx r9d, byte [rsp + r9]  ; consulta a tabela: r9 = novo valor já calculado
    mov   [r8], r9b             ; grava o novo valor no destino
    inc   rdi                   ; avança para o próximo byte da origem
    inc   r8                    ; avança para o próximo byte do destino
    dec   rax                   ; desconta o byte processado
    jnz   .byte                 ; ainda há bytes: processa o próximo
.fim:
    add   rsp, 256              ; devolve os 256 bytes da tabela, deixando a pilha como veio
    ret                         ; volta ao chamador; o resultado está em dst
