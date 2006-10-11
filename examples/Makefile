TARGET=
ALL_TARGETS = simple simple_project full_project problem_detection

ifneq ($(TARGET),)
PREFIX=$(TARGET)-
else
PREFIX=
endif

all: $(ALL_TARGETS)

$(ALL_TARGETS):
	make -C $@ PREFIX=$(PREFIX)

clean:
	$(foreach DIR,$(ALL_TARGETS), make -C $(DIR) clean;)

.PHONY: $(ALL_TARGETS) clean
