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

def bs_delta(S, K, r, sigma, T):
    d1 = (math.log(S/K) + (r + sigma**2/2)*T) / (sigma*math.sqrt(T))
    return 0.5 * (1 + math.erf(d1 / math.sqrt(2)))

async def reset(dut):
    dut.nrst.value = 0
    dut.start.value = 0
    dut.S.value = 0
    dut.K.value = 0
    dut.sigma.value = 0
    dut.r.value = 0
    dut.T.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.nrst.value = 1
    await RisingEdge(dut.clk)

async def calc(dut, S, K, sigma, r, T, tolerance=1e-3):
    dut.S.value     = to_q16(S)
    dut.K.value     = to_q16(K)
    dut.sigma.value = to_q16(sigma)
    dut.r.value     = to_q16(r)
    dut.T.value     = to_q16(T)

    await RisingEdge(dut.clk)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # full pipeline ~60 cycles; cap generously
    for _ in range(120):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break
    else:
        assert False, f"S={S} K={K}: done never asserted"

    result = from_q16(dut.delta.value.integer)
    expected = bs_delta(S, K, r, sigma, T)
    err = abs(result - expected)
    print(f"  S={S:>3.0f} K={K:>3.0f} vol={sigma:.2f} r={r:.2f} T={T:.3f} "
          f"-> delta={result:.5f}  true={expected:.5f}  err={err:.2e}")
    assert err < tolerance, f"S={S} K={K}: delta {result:.5f} vs true {expected:.5f}"

@cocotb.test()
async def test_delta_standard(dut):
    """Standard moneyness/vol/time scenarios."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- standard scenarios ---")
    await calc(dut, 100, 100, 0.20, 0.04, 1.0)    # ATM 1yr
    await calc(dut, 110, 100, 0.20, 0.04, 1.0)    # ITM
    await calc(dut,  90, 100, 0.20, 0.04, 1.0)    # OTM
    await calc(dut, 100, 100, 0.20, 0.04, 0.25)   # ATM 3mo
    await calc(dut, 105, 100, 0.30, 0.05, 0.5)    # mixed
    await calc(dut, 100, 100, 0.40, 0.02, 0.5)    # high vol
    await calc(dut,  95, 100, 0.15, 0.03, 0.75)   # low vol OTM

@cocotb.test()
async def test_delta_clamp(dut):
    """Extreme moneyness where d1 exceeds CORDIC range and delta saturates."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- clamp cases (d1 out of CORDIC range) ---")
    # deep ITM short-dated: d1 ~ +19, delta -> ~1
    await calc(dut, 130, 100, 0.10, 0.04, 0.0192, tolerance=1e-3)
    # deep OTM short-dated: d1 ~ -26, delta -> ~0
    await calc(dut,  70, 100, 0.10, 0.04, 0.0192, tolerance=1e-3)
    # moderately deep ITM
    await calc(dut, 120, 100, 0.15, 0.04, 0.1, tolerance=1e-3)

@cocotb.test()
async def test_delta_back_to_back(dut):
    """FSM returns to IDLE and accepts new requests cleanly."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    print("\n--- back-to-back requests ---")
    await calc(dut, 100, 100, 0.20, 0.04, 1.0)
    await calc(dut, 110, 100, 0.25, 0.03, 0.5)
    await calc(dut,  95, 100, 0.18, 0.04, 0.3)