import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import math

# Q16.16 helpers
def to_q16(f):
    return int(f * (1 << 16)) & 0xFFFFFFFF

def from_q16(v):
    # interpret as signed 32-bit
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

async def run_case(dut, x, y, z_deg, label):
    z_rad = math.radians(z_deg)

    dut.x_in.value = to_q16(x)
    dut.y_in.value = to_q16(y)
    dut.z_in.value = to_q16(z_rad)

    # wait ITERATIONS cycles for result to propagate through pipeline
    for _ in range(ITERATIONS + 1):
        await RisingEdge(dut.clk)

    x_out = from_q16(dut.x_out.value.integer)
    y_out = from_q16(dut.y_out.value.integer)
    z_out = from_q16(dut.z_out.value.integer)

    expected_x = x * math.cos(z_rad) - y * math.sin(z_rad)
    expected_y = x * math.sin(z_rad) + y * math.cos(z_rad)

    print(f"\n--- {label} ---")
    print(f"  x_out={x_out:.6f}  expected={expected_x:.6f}  err={abs(x_out - expected_x):.6f}")
    print(f"  y_out={y_out:.6f}  expected={expected_y:.6f}  err={abs(y_out - expected_y):.6f}")
    print(f"  z_out={z_out:.6f}  expected≈0")

    tolerance = 0.001
    assert abs(x_out - expected_x) < tolerance, f"{label}: x_out mismatch"
    assert abs(y_out - expected_y) < tolerance, f"{label}: y_out mismatch"
    assert abs(z_out) < tolerance,              f"{label}: z_out did not converge to 0"

@cocotb.test()
async def test_cordic(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await run_case(dut, x=1.0, y=0.0, z_deg=45.0, label="45 degrees")
    await run_case(dut, x=1.0, y=0.0, z_deg=0.0,  label="0 degrees")
    await run_case(dut, x=1.0, y=0.0, z_deg=90.0, label="90 degrees")