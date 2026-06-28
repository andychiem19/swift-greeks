import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import math

# Q16.16 HELPERS
def to_q16(f):
    return int(f * (1 << 16)) & 0xFFFFFFFF

def from_q16(v):
    if v >= (1 << 31):
        v -= (1 << 32)
    return v / (1 << 16)

ITERATIONS = 16

async def reset(dut):
    dut.nrst.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.z_in.value = 0
    await Timer(30, units="ns")
    dut.nrst.value = 1
    await RisingEdge(dut.clk)

async def run_case(dut, x, y, z, label, expected_x, expected_y, expected_z, tolerance=0.001):
    dut.x_in.value = to_q16(x)
    dut.y_in.value = to_q16(y)
    dut.z_in.value = to_q16(z)

    for _ in range(ITERATIONS + 1):
        await RisingEdge(dut.clk)

    x_out = from_q16(dut.x_out.value.integer)
    y_out = from_q16(dut.y_out.value.integer)
    z_out = from_q16(dut.z_out.value.integer)

    print(f"\n--- {label} ---")
    print(f"  x_out={x_out:.6f}  expected={expected_x:.6f}  err={abs(x_out - expected_x):.6f}")
    print(f"  y_out={y_out:.6f}  expected={expected_y:.6f}  err={abs(y_out - expected_y):.6f}")
    print(f"  z_out={z_out:.6f}  expected={expected_z:.6f}  err={abs(z_out - expected_z):.6f}")

    assert abs(x_out - expected_x) < tolerance, f"{label}: x_out mismatch"
    assert abs(y_out - expected_y) < tolerance, f"{label}: y_out mismatch"
    assert abs(z_out - expected_z) < tolerance, f"{label}: z_out mismatch"

@cocotb.test()
async def test_cordic(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # LINEAR ROTATION: y_out = y + x*z, z->0, x unchanged
    await run_case(dut, x=2.0, y=1.0, z=0.5, label="y + x*z = 1 + 2*0.5 = 2.0",
                   expected_x=2.0,
                   expected_y=2.0,
                   expected_z=0.0)

    await run_case(dut, x=3.0, y=0.0, z=0.25, label="y + x*z = 0 + 3*0.25 = 0.75",
                   expected_x=3.0,
                   expected_y=0.75,
                   expected_z=0.0)

    await run_case(dut, x=1.0, y=0.5, z=0.0, label="y + x*z = 0.5 + 0 = 0.5",
                   expected_x=1.0,
                   expected_y=0.5,
                   expected_z=0.0)