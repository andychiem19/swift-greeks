SIM = verilator
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/../../src/cordic.sv
TOPLEVEL = cordic
MODULE = test_cordic
EXTRA_ARGS += --sv --trace
COMPILE_ARGS += -GMODE=1 -GROTATE=0

include $(shell cocotb-config --makefiles)/Makefile.sim