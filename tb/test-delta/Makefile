SIM = verilator
TOPLEVEL_LANG = verilog
VERILOG_SOURCES += $(PWD)/../../src/cordic.sv
VERILOG_SOURCES += $(PWD)/../../src/cdf.sv
VERILOG_SOURCES += $(PWD)/../../src/compute_delta.sv
TOPLEVEL = compute_delta
MODULE = test_delta
EXTRA_ARGS += --sv --trace

include $(shell cocotb-config --makefiles)/Makefile.sim