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

STAGES = 18

async def reset(dut):
    dut.nrst.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.z_in.value = 0
    await Timer(30, units="ns")
    dut.nrst.value = 1
    await RisingEdge(dut.clk)

async def run_case(dut, x, y, z, label, expected_x, expected_y, expected_z=None, tolerance=0.01):
    dut.x_in.value = to_q16(x)
    dut.y_in.value = to_q16(y)
    dut.z_in.value = to_q16(z)

    for _ in range(STAGES + 1):
        await RisingEdge(dut.clk)

    x_out = from_q16(dut.x_out.value.integer)
    y_out = from_q16(dut.y_out.value.integer)
    z_out = from_q16(dut.z_out.value.integer)

    print(f"\n--- {label} ---")
    print(f"  x_out={x_out:.6f}  expected={expected_x:.6f}  err={abs(x_out - expected_x):.6f}")
    print(f"  y_out={y_out:.6f}  expected={expected_y:.6f}  err={abs(y_out - expected_y):.6f}")
    if expected_z is not None:
        print(f"  z_out={z_out:.6f}  expected={expected_z:.6f}  err={abs(z_out - expected_z):.6f}")
    else:
        print(f"  z_out={z_out:.6f}  (not checked)")

    assert abs(x_out - expected_x) < tolerance, f"{label}: x_out mismatch (got {x_out:.6f}, expected {expected_x:.6f})"
    assert abs(y_out) < tolerance,              f"{label}: y_out did not converge to 0"
    if expected_z is not None:
        assert abs(z_out - expected_z) < tolerance, f"{label}: z_out mismatch (got {z_out:.6f}, expected {expected_z:.6f})"

@cocotb.test()
async def test_cordic(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # HYPERBOLIC VECTORING: x=a+b, y=a-b → z_out=atanh(y/x), y→0
    # NOTE: atanh(y/x) = ln(a/b)/2, so caller must left-shift z_out by 1 to get ln(a/b)

    # atanh((e-1)/(e+1)) ≈ 0.3860
    e = math.e
    a, b = (e + 1) / 2, (e - 1) / 2
    await run_case(dut, x=a+b, y=a-b, z=0.0, label="atanh for ln(e)",
                   expected_x=math.sqrt((a+b)**2 - (a-b)**2),
                   expected_y=0.0,
                   expected_z=math.atanh((a-b)/(a+b)))

    # atanh(0.5) ≈ 0.5493 (gives ln(3)/2 when doubled)
    a, b = 1.5, 0.5
    await run_case(dut, x=a+b, y=a-b, z=0.0, label="atanh for ln(3)",
                   expected_x=math.sqrt((a+b)**2 - (a-b)**2),
                   expected_y=0.0,
                   expected_z=math.atanh((a-b)/(a+b)))

    # sqrt(n): x=(n+1)/2, y=(n-1)/2 → x_out=sqrt(n), identity: x^2-y^2=n
    n = 2.0
    await run_case(dut, x=(n+1)/2, y=(n-1)/2, z=0.0, label="sqrt(2)≈1.4142",
                   expected_x=math.sqrt(n),
                   expected_y=0.0)