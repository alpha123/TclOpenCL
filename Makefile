DEBUG := yes

SWIG := swig
CL_INCLUDE_DIR := /usr/local/include
TCL_INCLUDE_DIR := /usr/local/include/tcl86
CL_LIB_DIR := /usr/local/lib
TCL_LIB_DIR := /usr/local/lib/tcl86
OUT := TclOpenCL.so

ifeq ($(DEBUG),yes)
override CFLAGS += -Og -g3 -gdwarf-4
else
override CFLAGS += -O2
endif

.PHONY: all clean

all: $(OUT)

clean:
	rm -f cl_wrap.c cl_wrap.o TclOpenCL.*

cl_wrap.c : cl.i
	$(SWIG) -tcl8 $(SWIGFLAGS) -I$(CL_INCLUDE_DIR) -o $@ $<

cl_wrap.o : cl_wrap.c
	$(CC) -fpic -DUSE_TCL_STUBS $(CFLAGS) -I$(CL_INCLUDE_DIR) -c $< -o $@

$(OUT) : cl_wrap.o
	$(CC) $(CCLINKFLAGS) -L$(CL_LIB_DIR) -shared $< -o $@ -lvectclstub02 -ltclstub86 -lOpenCL
