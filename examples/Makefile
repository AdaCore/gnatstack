TARGET=
RTS=
CC=g++

# Ada examples
ALL_TARGETS = simple simple_project full_project problem_detection

# C/C++ examples
ALL_TARGETS += c++_simple c++_static_dispatching c++_dynamic_dispatching \
   c++_template_function

ifneq ($(TARGET),)
PREFIX=$(TARGET)-
else
PREFIX=
endif

ifneq ($(RTS),)
RUNTIME=--RTS=$(RTS)
else
RUNTIME=
endif

all: $(ALL_TARGETS)

$(ALL_TARGETS):
	make -C $@ PREFIX=$(PREFIX) RUNTIME=$(RUNTIME) CC=$(CC)

clean:
	$(foreach DIR,$(ALL_TARGETS), make -C $(DIR) clean;)

.PHONY: $(ALL_TARGETS) clean
