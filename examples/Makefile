TARGET=
RTS=

ALL_TARGETS = simple simple_project full_project problem_detection

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
	make -C $@ PREFIX=$(PREFIX) RUNTIME=$(RUNTIME)

clean:
	$(foreach DIR,$(ALL_TARGETS), make -C $(DIR) clean;)

.PHONY: $(ALL_TARGETS) clean
