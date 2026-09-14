; ARQUIVO COMUM.INC (incluído no início de todos os .asm)
;
; ======= CHAMADA =======
; %include "comum.inc"
; SATURAR valor, auxiliar          ; macro: limita 'valor' ao intervalo 0..255
;
;
; ====== REGISTERS ======
;
; Macro SATURAR:
; %1 = valor a limitar (registrador de 32 ou 64 bits, com sinal); é alterado
; %2 = registrador auxiliar do mesmo tamanho; seu conteúdo é destruído
;
;
; ==== FUNCIONAMENTO ====
;
; 1. Configura o NASM para gerar código de 64 bits com endereços relativos ao
;    RIP (obrigatório numa biblioteca .so, que pode ser carregada em qualquer
;    endereço de memória)
; 2. Marca a pilha como não executável (o linker avisa se isso faltar)
; 3. Define a macro SATURAR:
;   3.1 Se valor < 0, troca por 0
;   3.2 Se valor > 255, troca por 255
;   (usa cmov, que copia só quando a condição é verdadeira, sem desvios)
;
;
; ===== OBSERVAÇÕES =====
;
; CONVENÇÃO DE CHAMADA: System V AMD64 ABI (padrão do Linux)
;   Argumentos inteiros/ponteiros, na ordem: rdi, rsi, rdx, rcx, r8, r9
;   Do 7º argumento em diante: na pilha ([rsp+8], [rsp+16], ... na entrada)
;   Argumentos double, na ordem: xmm0, xmm1, ..., xmm7
;   Retorno inteiro: rax  |  retorno double: xmm0
;
;   Registradores que a função PODE destruir ("caller-saved"):
;       rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11, xmm0-xmm15
;   Registradores que a função DEVE preservar ("callee-saved"):
;       rbx, rbp, r12, r13, r14, r15  (se usar, salve com push e restaure com pop)
;
;   Antes de qualquer "call", rsp precisa ser múltiplo de 16.
;   Na entrada de uma função rsp NÃO é múltiplo de 16 (o call empilhou 8 bytes
;   de endereço de retorno), por isso as funções ajustam a pilha antes de chamar.
;
;   Um "int" (32 bits) chega na parte baixa do registrador (edi, esi, ...).
;   A parte alta (32 bits de cima) pode conter lixo, então SEMPRE copiamos com
;   "mov r32, r32" (zera a parte alta) ou "movsxd" (estende o sinal) antes de
;   usar o valor em contas de 64 bits.
;
; CONVENÇÃO DAS IMAGENS
;   Uma imagem é um buffer de bytes, linha por linha, da esquerda para a direita.
;   canais = 1  -> 1 byte por pixel (nível de cinza 0..255)
;   canais = 3  -> 3 bytes por pixel, na ordem R, G, B
;   Pixel (x, y), canal k  ->  buffer[(y * largura + x) * canais + k]

%ifndef COMUM_INC               ; se este arquivo ainda não foi incluído...
%define COMUM_INC               ; ...marca como incluído, para não definir tudo duas vezes

bits 64                         ; gera instruções de 64 bits (x86-64)
default rel                     ; endereços relativos ao RIP: a .so funciona em qualquer endereço

; Seção vazia que avisa o linker que a pilha não precisa ser executável.
section .note.GNU-stack noalloc noexec nowrite progbits

%macro SATURAR 2
    xor   %2, %2                ; aux = 0, o menor valor que um byte de pixel aceita
    cmp   %1, 0                 ; compara o valor com 0 para saber se ficou negativo
    cmovl %1, %2                ; negativo não cabe num byte: vira 0
    mov   %2, 255               ; aux = 255, o maior valor que um byte de pixel aceita
    cmp   %1, %2                ; compara o valor com 255 para saber se estourou
    cmovg %1, %2                ; acima de 255 não cabe num byte: vira 255
%endmacro

%endif                          ; fim do bloco protegido contra inclusão dupla
