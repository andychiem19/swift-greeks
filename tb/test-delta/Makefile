SIM = verilator
TOPLEVEL_LANG = verilog
VERILOG_SOURCES += $(PWD)/../../src/cordic.sv
VERILOG_SOURCES += $(PWD)/../../src/cdf.sv
VERILOG_SOURCES += $(PWD)/../../src/delta_top.sv
TOPLEVEL = delta_top
MODULE = test_delta
EXTRA_ARGS += --sv --trace

include $(shell cocotb-config --makefiles)/Makefile.sim