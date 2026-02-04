
all: hlssplitter

C_SOURCES = $(wildcard src/[^~]*.c)
LIB_SOURCES = $(wildcard lib/[^~]*.c)

C_OBJECTS=$(patsubst src/%.c,build/%.o,$(C_SOURCES))
LIB_OBJECTS=$(patsubst lib/%.c,build/lib/%.o,$(LIB_SOURCES))
C_FLAGS=-O2 -Wall -DHTTP_SERVER_DESCRIPTION=\"STB100/Splitter\"

build/%.o : src/%.c
	@echo Compile $<
	@mkdir -p build
	@gcc -Ilib $< -E -o $(patsubst src/%.c,build/%.i,$<)
	@type staticanalyzer > /dev/null 2>&1 && staticanalyzer add $(patsubst src/%.c,build/%.i,$<) $< ; exit 0
	@gcc $(C_FLAGS) -Ilib -c $< -o $(patsubst src/%.c,build/%.o,$<)

build/lib/%.o : lib/%.c
	@echo Compile $<
	@mkdir -p build/lib
	@gcc -Ilib $< -E -o $(patsubst lib/%.c,build/lib/%.i,$<)
	@type staticanalyzer > /dev/null 2>&1 && staticanalyzer add $(patsubst lib/%.c,build/lib/%.i,$<) $< ; exit 0
	@gcc $(C_FLAGS) -Ilib -c $< -o $(patsubst lib/%.c,build/lib/%.o,$<)

hlssplitter: $(C_OBJECTS) $(LIB_OBJECTS)
	@echo Build application from object code
	gcc $(C_FLAGS) $(C_OBJECTS) $(LIB_OBJECTS) -Ilib -o $@ -lpthread -lrt

clean:
	rm -rf hlssplitter build
