; FUNÇÃO THRESHOLD.ASM
;
; ======= CHAMADA =======
; void pdi_threshold(const uint8_t *src, int largura, int altura, int canais,
;                    uint8_t *dst, int limiar)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (sempre 1 canal)
; r9d = limiar T
; rbx = ponteiro que percorre o destino
; r12 = limiar (guardado, pois r9 é destruído pela chamada)
; r13 = largura (guardada)
; r14 = altura (guardada)
; rax = quantidade de pixels que faltam processar
; ecx = nível de cinza do pixel atual
; edx = valor de saída (0 ou 255)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva rbx, r12, r13 e r14 (a ABI exige preservá-los) e alinha a pilha
; 2. Guarda dst em rbx, limiar em r12, largura em r13 e altura em r14
; 3. Chama pdi_grayscale com os mesmos argumentos: o destino recebe a imagem
;    em cinza (se já for cinza, só é copiada)
; 4. Calcula em rax o número de pixels; se 0, termina
; 5. Para cada pixel do destino:
;   5.1 Lê o nível de cinza de [rbx] em ecx
;   5.2 Se for menor que o limiar, a saída é 0; senão, 255
;   5.3 Grava a saída em [rbx], avança rbx, decrementa rax e repete
; 6. Restaura a pilha e os registradores e retorna
;
;
; ===== OBSERVAÇÕES =====
;
;   g(x,y) = 255 (objeto) se f(x,y) >= T
;   g(x,y) = 0   (fundo)  se f(x,y) <  T
; A binarização é feita no próprio destino, sobre o cinza que o pdi_grayscale
; gravou lá, então não é preciso alocar memória extra.

%include "comum.inc"

section .text

global pdi_threshold:function   ; exporta a função para o Python
extern pdi_grayscale            ; definida em filtros/grayscale.asm

pdi_threshold:
    push  rbx                   ; preserva rbx: será o ponteiro do destino
    push  r12                   ; preserva r12: guardará o limiar
    push  r13                   ; preserva r13: guardará a largura
    push  r14                   ; preserva r14: guardará a altura
    sub   rsp, 8                ; 4 pushes + 8 bytes: pilha múltipla de 16 antes do call
    mov   rbx, r8               ; guarda dst, pois o call pode destruir r8
    mov   r12d, r9d             ; guarda o limiar, pois o call pode destruir r9
    mov   r13d, esi             ; guarda a largura para contar os pixels depois
    mov   r14d, edx             ; guarda a altura para contar os pixels depois

    ; os 5 argumentos já estão nos registradores certos para pdi_grayscale
    call  pdi_grayscale wrt ..plt ; grava a imagem em cinza direto no destino

    mov   rax, r13              ; rax = largura
    imul  rax, r14              ; rax = largura * altura: quantos pixels binarizar
    test  rax, rax              ; verifica se a imagem não tem nenhum pixel
    jz    .fim                  ; imagem vazia: nada a binarizar
.pixel:
    movzx ecx, byte [rbx]       ; lê o nível de cinza do pixel para comparar com o limiar
    xor   edx, edx              ; supõe que o pixel é fundo (0)
    cmp   ecx, r12d             ; compara o pixel com o limiar (com sinal)
    jl    .grava                ; abaixo do limiar: mantém 0 (fundo)
    mov   edx, 255              ; igual ou acima do limiar: é objeto (255)
.grava:
    mov   [rbx], dl             ; substitui o cinza pelo valor binário
    inc   rbx                   ; avança para o próximo pixel (1 byte cada)
    dec   rax                   ; desconta o pixel processado
    jnz   .pixel                ; ainda há pixels: binariza o próximo
.fim:
    add   rsp, 8                ; desfaz o ajuste de alinhamento da pilha
    pop   r14                   ; restaura r14 do chamador (ordem inversa dos pushes)
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
