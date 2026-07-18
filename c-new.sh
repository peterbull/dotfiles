#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: c-new project_name"
    exit 1
fi

project_name=$1

# Create directory structure
mkdir -p "$project_name"/src

# Create main.c
cat > "$project_name/src/main.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello, World!\n");
    return 0;
}
EOF

## gitignore
cat > "$project_name/.gitignore" << 'EOF'
build
EOF

# Create Makefile
cat > "$project_name/Makefile" << 'EOF'
# You can change these variables if you want to use a different compiler or debugger
CC = clang
DBG = lldb

.PHONY: build-main
build-main: build-dir
	$(CC) -Wall -O0 -g -o build/main src/main.c

.PHONY: check
check:
	@which $(CC) > /dev/null && echo "SUCCESS: $(CC) is installed" || echo "ERROR: $(CC) not found, please install clang"
	@which $(DBG) > /dev/null && echo "SUCCESS: $(DBG) is installed" || echo "ERROR: $(DBG) not found, please install lldb"

.PHONY: build-dir
build-dir:
	if [ ! -d build ]; then mkdir build; fi

.PHONY: build-test
build-test: build-dir
	$(CC) -Wall -O0 -g -o build/test src/test.c

.PHONY: run
run: build-main
	./build/main

.PHONY: test
test: build-test
	./build/test

.PHONY: debug
debug: build-main
	$(DBG) ./build/main

.PHONY: debug-test
debug-test: build-test
	$(DBG) ./build/test
EOF

# Create README.md
cat > "$project_name/README.md" << 'EOF'
# C Project

## Quickstart

You will need `make`, `clang` and `lldb` installed.
These are present by default on macOS, and on Ubuntu can be installed with
`sudo apt install clang lldb`.

```shell
# Check `make`, `clang` and `lldb` are installed
make check

# To build and run `src/main.c`
make run

# To run the tests in `src/test.c`
make test

# To start `src/main.c` in the debugger
make debug

# To start `src/test.c` in the debugger
make debug-test
