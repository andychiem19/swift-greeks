import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import math

# Q16.16 HELPERS
def to_q16(f):
    return int(round(f * (1 << 16))) & 0xFFFFFFFF

def from_q16(v):
    if v >= (1 << 31):
        v -= (1 << 32)
    return v / (1 << 16)

def true_cdf(x):
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))

async def reset(dut):
    dut.nrst.value = 0
    dut.start.value = 0
    dut.d1.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.nrst.value = 1
    await RisingEdge(dut.clk)

async def run_case(dut, x, tolerance=1e-3):
    dut.d1.value = to_q16(x)
    await RisingEdge(dut.clk)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # wait for done (FSM takes ~11 cycles; cap the wait generously)
    for _ in range(50):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break
    else:
        assert False, f"N({x}): done never asserted"

    result = from_q16(dut.cdf_out.value.integer)
    expected = true_cdf(x)
    err = abs(result - expected)
    print(f"  N({x:+.2f}) = {result:.6f}  expected={expected:.6f}  err={err:.2e}")
    assert err < tolerance, f"N({x}) mismatch: got {result:.6f}, expected {expected:.6f}"

@cocotb.test()
async def test_cdf(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- CDF accuracy sweep ---")
    for x in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0,
              -0.5, -1.0, -1.5, -2.0, -3.0]:
        await run_case(dut, x)

@cocotb.test()
async def test_cdf_back_to_back(dut):
    # verify the FSM returns to IDLE and accepts a new start cleanly
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- back-to-back requests ---")
    await run_case(dut, 1.0)
    await run_case(dut, -1.0)
    await run_case(dut, 0.25)

@cocotb.test()
async def test_cdf_clamp(dut):
    # values beyond the table domain [0,4] should clamp, N saturates near 0/1
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- clamping beyond domain ---")
    # use looser tolerance since clamp introduces small error at the tails
    await run_case(dut, 5.0, tolerance=1e-2)
    await run_case(dut, -5.0, tolerance=1e-2)