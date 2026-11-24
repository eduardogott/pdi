; FUNÇÃO FECHAMENTO.ASM
;
; ======= CHAMADA =======
; void pdi_fechamento(const uint8_t *src, int largura, int altura, int canais,
;                   uint8_t *dst, int valor)
;
;
; ====== REGISTERS ======
;
; rdi = src
; esi = largura
; edx = altura
; ecx = canais
; r8  = dst (mesmo número de canais de src)
; r9d = valor do elemento estruturante (cruz 3x3)
; rbx = src  r12 = largura  r13 = altura  r14 = canais  r15 = dst
; rbp = valor do elemento
; [rsp] = buffer intermediário (resultado da primeira operação)
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Salva os registradores preservados, alinha a pilha e guarda os argumentos
; 2. Pede largura*altura*canais bytes ao kernel (pdi_aloca); se falhar, termina
; 3. Dilata src para o buffer intermediário (pdi_dilatacao)
; 4. Erode o buffer intermediário para dst (pdi_erosao), com o mesmo
;    elemento estruturante
; 5. Devolve o buffer (pdi_libera), restaura e retorna
;
;
; ===== OBSERVAÇÕES =====
;
; Fechamento = dilatação seguida de erosão com o mesmo elemento estruturante.
; A dilatação preenche falhas, furos e quebras menores que o elemento; a
; erosão devolve aos objetos o tamanho aproximado, sem reabrir essas falhas.
; O buffer intermediário existe porque a erosão precisa ler a imagem
; dilatada inteira enquanto grava o resultado.

%include "comum.inc"

section .text

global pdi_fechamento:function  ; exporta a função para o Python
extern pdi_aloca                ; suporte/memoria.asm
extern pdi_libera               ; suporte/memoria.asm
extern pdi_erosao               ; morfologia/erosao.asm
extern pdi_dilatacao            ; morfologia/dilatacao.asm

pdi_fechamento:
    push  rbx                   ; preserva rbx: guardará src
    push  rbp                   ; preserva rbp: guardará o valor do elemento
    push  r12                   ; preserva r12: guardará a largura
    push  r13                   ; preserva r13: guardará a altura
    push  r14                   ; preserva r14: guardará os canais
    push  r15                   ; preserva r15: guardará dst
    sub   rsp, 8                ; 6 pushes + 8 bytes: pilha múltipla de 16; o espaço guarda o buffer
    mov   rbx, rdi              ; guarda src, pois os calls destroem rdi
    mov   r12d, esi             ; guarda a largura (zera a parte alta)
    mov   r13d, edx             ; guarda a altura (zera a parte alta)
    mov   r14d, ecx             ; guarda os canais
    mov   r15, r8               ; guarda dst
    mov   ebp, r9d              ; guarda o valor do elemento estruturante

    ; ---------- buffer intermediário do tamanho da imagem ----------
    mov   rdi, r12              ; rdi = largura
    imul  rdi, r13              ; rdi = largura * altura
    imul  rdi, r14              ; rdi = largura * altura * canais: bytes da imagem
    call  pdi_aloca wrt ..plt   ; pede a memória ao kernel
    test  rax, rax              ; verifica se conseguiu memória
    jz    .fim                  ; faltou memória: sai sem processar
    mov   [rsp], rax            ; guarda o endereço do buffer na pilha

    ; ---------- 1º: dilatação de src para o buffer ----------
    mov   rdi, rbx              ; 1º argumento: a imagem original
    mov   esi, r12d             ; 2º argumento: largura
    mov   edx, r13d             ; 3º argumento: altura
    mov   ecx, r14d             ; 4º argumento: canais
    mov   r8, rax               ; 5º argumento: destino = buffer intermediário
    mov   r9d, ebp              ; 6º argumento: valor do elemento
    call  pdi_dilatacao wrt ..plt ; preenche as falhas menores que o elemento

    ; ---------- 2º: erosão do buffer para dst ----------
    mov   rdi, [rsp]            ; 1º argumento: a imagem dilatada
    mov   esi, r12d             ; 2º argumento: largura
    mov   edx, r13d             ; 3º argumento: altura
    mov   ecx, r14d             ; 4º argumento: canais
    mov   r8, r15               ; 5º argumento: destino final
    mov   r9d, ebp              ; 6º argumento: o mesmo elemento estruturante
    call  pdi_erosao wrt ..plt  ; devolve aos objetos o seu tamanho, sem reabrir as falhas

    mov   rdi, [rsp]            ; argumento: o buffer, que não é mais necessário
    call  pdi_libera wrt ..plt  ; devolve a memória ao kernel
.fim:
    add   rsp, 8                ; desfaz o ajuste de alinhamento
    pop   r15                   ; restaura r15 do chamador (ordem inversa dos pushes)
    pop   r14                   ; restaura r14 do chamador
    pop   r13                   ; restaura r13 do chamador
    pop   r12                   ; restaura r12 do chamador
    pop   rbp                   ; restaura rbp do chamador
    pop   rbx                   ; restaura rbx do chamador
    ret                         ; volta ao chamador; o resultado está em dst
