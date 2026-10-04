ASM ?= nasm
CC ?= gcc

all: bin/c_compiler

bin/c_compiler: src/main.asm src/*.asm src/*.inc
	mkdir -p bin
	$(ASM) -f elf64 -I ./ src/main.asm -o bin/c_compiler.o
	$(CC) -no-pie bin/c_compiler.o -o bin/c_compiler

clean:
	rm -rf bin
