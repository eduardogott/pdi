#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# compilar.sh - monta todos os arquivos asm/**/*.asm e gera lib/libpdi.so
#
#   nasm -f elf64  : gera arquivos objeto (.o) no formato ELF de 64 bits (Linux)
#   ld -shared     : junta os objetos numa biblioteca compartilhada (.so),
#                    que o Python carrega com ctypes
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build lib
objetos=()

while IFS= read -r fonte; do
    objeto="build/$(basename "$(dirname "$fonte")")_$(basename "${fonte%.asm}").o"
    echo "nasm  $fonte"
    nasm -f elf64 -I asm/ -o "$objeto" "$fonte"
    objetos+=("$objeto")
done < <(find asm -name '*.asm' | sort)

echo "ld    lib/libpdi.so"
ld -shared -z noexecstack --no-undefined -o lib/libpdi.so "${objetos[@]}"
echo "ok"
