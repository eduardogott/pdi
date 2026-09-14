; FUNÇÃO MEMORIA.ASM
;
; ======= CHAMADA =======
; void *pdi_aloca(uint64_t bytes)
; void  pdi_libera(void *ptr)
;
;
; ====== REGISTERS ======
;
; pdi_aloca:
; rdi = quantidade de bytes desejada (vira o tamanho total arredondado)
; rsi = 2º argumento do mmap (tamanho) / tamanho recuperado após a syscall
; edx = 3º argumento do mmap (proteção)
; r10 = 4º argumento do mmap (flags)
; r8  = 5º argumento do mmap (descritor de arquivo)
; r9  = 6º argumento do mmap (deslocamento)
; rax = número da syscall / retorno: ponteiro para a memória (zerada) ou 0
;
; pdi_libera:
; rdi = ponteiro devolvido por pdi_aloca (0 é aceito e ignorado)
; rsi = tamanho do bloco (lido do cabeçalho)
; rax = número da syscall
;
;
; ==== FUNCIONAMENTO ====
;
; pdi_aloca:
; 1. Soma 8 bytes de cabeçalho ao pedido e arredonda para múltiplo de 4096
;    (o kernel entrega memória em páginas de 4096 bytes)
; 2. Guarda o tamanho total na pilha (a syscall destrói alguns registradores)
; 3. Preenche os argumentos e chama o mmap (syscall 9)
; 4. Recupera o tamanho; se o mmap devolveu um código de erro, retorna 0
; 5. Grava o tamanho nos 8 primeiros bytes do bloco (cabeçalho)
; 6. Retorna o endereço logo após o cabeçalho
;
; pdi_libera:
; 1. Se o ponteiro for 0, retorna sem fazer nada
; 2. Volta 8 bytes até o cabeçalho e lê o tamanho do bloco
; 3. Chama o munmap (syscall 11) para devolver a memória ao kernel
;
;
; ===== OBSERVAÇÕES =====
;
; Algumas técnicas precisam de buffers auxiliares (ex.: uma cópia em cinza da
; imagem). Como a biblioteca não usa a libc (não existe malloc), a memória é
; pedida direto ao kernel Linux.
; Syscall no Linux x86-64: número em rax; argumentos em rdi, rsi, rdx, r10, r8,
; r9 (r10 no lugar de rcx); a instrução "syscall" destrói rcx e r11.
; A memória nova do mmap já vem zerada pelo kernel.

%include "comum.inc"

section .text

global pdi_aloca:function       ; exporta para os outros .asm (e para o Python)
global pdi_libera:function      ; exporta para os outros .asm (e para o Python)

pdi_aloca:
    add   rdi, 8 + 4095         ; soma o cabeçalho de 8 bytes e 4095 para o arredondamento para cima
    and   rdi, -4096            ; zera os 12 bits baixos: tamanho vira múltiplo de uma página
    push  rdi                   ; guarda o tamanho total, pois a syscall pode destruir registradores
    mov   rsi, rdi              ; 2º argumento do mmap: quantos bytes reservar
    xor   edi, edi              ; 1º argumento: endereço 0 deixa o kernel escolher onde
    mov   edx, 3                ; 3º argumento: PROT_READ | PROT_WRITE, para ler e gravar pixels
    mov   r10d, 0x22            ; 4º argumento: MAP_PRIVATE | MAP_ANONYMOUS, memória nova sem arquivo
    mov   r8, -1                ; 5º argumento: -1, pois não há arquivo associado
    xor   r9d, r9d              ; 6º argumento: deslocamento 0 (não usado sem arquivo)
    mov   eax, 9                ; escolhe a syscall 9, mmap
    syscall                     ; pede a memória ao kernel; o endereço volta em rax
    pop   rsi                   ; recupera o tamanho total para gravar no cabeçalho
    cmp   rax, -4095            ; o kernel sinaliza erro devolvendo -4095..-1
    jae   .erro                 ; comparação sem sinal: esses valores são os maiores possíveis
    mov   [rax], rsi            ; grava o tamanho no cabeçalho para pdi_libera saber quanto devolver
    add   rax, 8                ; entrega ao chamador o endereço logo após o cabeçalho
    ret                         ; volta com o ponteiro em rax
.erro:
    xor   eax, eax              ; devolve 0 para o chamador saber que faltou memória
    ret                         ; volta ao chamador

pdi_libera:
    test  rdi, rdi              ; verifica se recebeu ponteiro nulo
    jz    .fim                  ; nulo: não há bloco para devolver (facilita a limpeza em erros)
    sub   rdi, 8                ; volta ao início real do bloco, onde está o cabeçalho
    mov   rsi, [rdi]            ; 2º argumento do munmap: tamanho guardado no cabeçalho
    mov   eax, 11               ; escolhe a syscall 11, munmap
    syscall                     ; devolve o bloco inteiro ao kernel
.fim:
    ret                         ; volta ao chamador
