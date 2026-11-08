CFLAGS  := -std=c99 -Wall -O2 -D_REENTRANT
LIBS    := -lpthread -lm

TARGET  := $(shell uname -s | tr '[A-Z]' '[a-z]' 2>/dev/null || echo unknown)

ifeq ($(TARGET), sunos)
	CFLAGS += -D_PTHREADS -D_POSIX_C_SOURCE=200112L
	LIBS   += -lsocket
else ifeq ($(TARGET), darwin)
	# Per https://luajit.org/install.html: If MACOSX_DEPLOYMENT_TARGET
	# is not set then it's forced to 10.4, which breaks compile on Mojave.
	export MACOSX_DEPLOYMENT_TARGET = $(shell sw_vers -productVersion)
	LDFLAGS += -pagezero_size 10000 -image_base 100000000
	CFLAGS += -I/usr/local/include
else ifeq ($(TARGET), linux)
        CFLAGS  += -D_POSIX_C_SOURCE=200809L -D_BSD_SOURCE
	LIBS    += -ldl
	LDFLAGS += -Wl,-E
else ifeq ($(TARGET), freebsd)
	CFLAGS  += -D_DECLARE_C99_LDBL_MATH
	LDFLAGS += -Wl,-E
endif

# OpenSSL lookup order:
#   1. OPENSSL_DIR=<prefix>  e.g. make OPENSSL_DIR=/opt/openssl
#   2. pkg-config            Linux, BSD, MacPorts, MSYS2, Cygwin
#   3. Homebrew              macOS (Intel and Apple Silicon)
#   4. compiler defaults     -lssl -lcrypto
PKG_CONFIG ?= pkg-config

ifneq ($(OPENSSL_DIR),)
	OPENSSL_LIBDIR := $(if $(wildcard $(OPENSSL_DIR)/lib64/libssl.*),$(OPENSSL_DIR)/lib64,$(OPENSSL_DIR)/lib)
	SSL_CFLAGS := -I$(OPENSSL_DIR)/include
	SSL_LIBS   := -L$(OPENSSL_LIBDIR) -Wl,-rpath,$(OPENSSL_LIBDIR) -lssl -lcrypto
else ifeq ($(shell $(PKG_CONFIG) --exists openssl 2>/dev/null && echo yes), yes)
	SSL_CFLAGS := $(shell $(PKG_CONFIG) --cflags openssl)
	SSL_LIBS   := $(shell $(PKG_CONFIG) --libs openssl)
else
	BREW_OPENSSL := $(shell brew --prefix openssl 2>/dev/null)
	ifneq ($(wildcard $(BREW_OPENSSL)/include/openssl/ssl.h),)
		SSL_CFLAGS := -I$(BREW_OPENSSL)/include
		SSL_LIBS   := -L$(BREW_OPENSSL)/lib -lssl -lcrypto
	else
		SSL_LIBS   := -lssl -lcrypto
	endif
endif

CFLAGS += $(SSL_CFLAGS)
LIBS   := $(SSL_LIBS) $(LIBS)

SRC  := wrk.c net.c ssl.c aprintf.c stats.c script.c units.c \
		ae.c zmalloc.c http_parser.c tinymt64.c hdr_histogram.c
BIN  := wrk

ODIR := obj
OBJ  := $(patsubst %.c,$(ODIR)/%.o,$(SRC)) $(ODIR)/bytecode.o

LDIR     = deps/luajit/src
LIBS    := -lluajit $(LIBS)
CFLAGS  += -I$(LDIR)
LDFLAGS += -L$(LDIR)

all: $(BIN)

clean:
	$(RM) $(BIN) obj/*
	@$(MAKE) -C deps/luajit clean

$(BIN): $(OBJ)
	@echo LINK $(BIN)
	@$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

$(OBJ): config.h Makefile $(LDIR)/libluajit.a | $(ODIR)

$(ODIR):
	@mkdir -p $@

$(ODIR)/bytecode.o: src/wrk.lua
	@echo LUAJIT $<
	@$(SHELL) -c 'cd $(LDIR) && ./luajit -b $(CURDIR)/$< $(CURDIR)/$@'

$(ODIR)/%.o : %.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<

$(LDIR)/libluajit.a:
	@echo Building LuaJIT...
	@$(MAKE) -C $(LDIR) BUILDMODE=static

.PHONY: all clean
.SUFFIXES:
.SUFFIXES: .c .o .lua

vpath %.c   src
vpath %.h   src
vpath %.lua scripts
