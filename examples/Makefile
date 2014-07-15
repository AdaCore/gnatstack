TARGET=
RTS=
CC=g++

# Ada examples
ADA_TARGETS = simple simple_project full_project problem_detection tasking

# C/C++ examples
CPLUSPLUS_TARGETS = c++_simple c++_static_function \
   c++_static_dispatching c++_dynamic_dispatching \
   c++_template_function \
   c++_template_static_dispatching c++_template_dynamic_dispatching

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

all: ada c++

ada: $(ADA_TARGETS)

$(ADA_TARGETS):
	make -C $@ PREFIX=$(PREFIX) RUNTIME=$(RUNTIME) TARGET=$(TARGET)

c++: $(CPLUSPLUS_TARGETS)

$(CPLUSPLUS_TARGETS):
	make -C $@ CC=$(CC)

clean:
	$(foreach DIR,$(ADA_TARGETS) $(CPLUSPLUS_TARGETS), \
	make -C $(DIR) clean;)

.PHONY: $(ADA_TARGETS) $(CPLUSPLUS_TARGETS) clean
