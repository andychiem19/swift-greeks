import re
import socket
import struct
import threading
import time
from datetime import date, datetime, timezone

from alpaca.data.live import OptionDataStream, StockDataStream
from alpaca.data.enums import OptionsFeed

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------

API_KEY    = "YOUR_KEY_ID"
API_SECRET = "YOUR_SECRET"

OPTION_FEED = OptionsFeed.INDICATIVE

OPTION_SYMBOLS = ["AAPL260918C00200000"]

FPGA_IP    = "192.168.1.10"   # the Zybo's static IP (set to match GEM init)
FPGA_PORT  = 5005
LOCAL_PORT = 5006             # port we listen on for the FPGA's response

RISK_FREE_RATE = 0.04         # r: set to current T-bill rate; static config
DEFAULT_SIGMA  = 0.25         # sigma: indicative feed has no clean IV; placeholder

RECV_TIMEOUT_S = 1.0          # how long to wait for the FPGA reply

# ----------------------------------------------------------------------------

# Q16.16 packing
def to_q16(x: float) -> int:
    v = int(round(x * (1 << 16)))
    return max(-(1 << 31), min((1 << 31) - 1, v))

def from_q16(v: int) -> float:
    if v >= (1 << 31):
        v -= (1 << 32)
    return v / (1 << 16)

def pack_payload(S, K, sigma, r, T) -> bytes:
    return struct.pack(
        ">iiiii",
        to_q16(S), to_q16(K), to_q16(sigma), to_q16(r), to_q16(T)
    )

# OCC option symbol parsing -> strike (K) and expiry (for T)
_OCC_RE = re.compile(r'^([A-Z]+)(\d{2})(\d{2})(\d{2})([CP])(\d{8})$')

def parse_occ(sym: str):
    """AAPL240315C00172500 -> (root, expiry_date, 'C'/'P', strike_float)."""
    m = _OCC_RE.match(sym)
    if not m:
        raise ValueError(f"bad OCC symbol: {sym}")
    root, yy, mm, dd, cp, strike = m.groups()
    expiry = date(2000 + int(yy), int(mm), int(dd))
    K = int(strike) / 1000.0
    return root, expiry, cp, K

def years_to_expiry(expiry: date) -> float:
    days = (expiry - datetime.now(timezone.utc).date()).days
    return max(days, 0) / 365.0

# Shared spot cache
class SpotCache:
    """Latest mid price per underlying. Single-float dict writes are GIL-atomic."""
    def __init__(self):
        self._spots = {}

    def update(self, root: str, mid: float):
        self._spots[root] = mid

    def get(self, root: str):
        return self._spots.get(root)

# UDP send + timed round trip
class FpgaLink:
    def __init__(self, fpga_ip, fpga_port, local_port, recv_timeout):
        self.addr = (fpga_ip, fpga_port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", local_port))
        self.sock.settimeout(recv_timeout)

    def send_and_time(self, payload: bytes):
        """Send payload, wait for the 4-byte Q16.16 delta reply, return (delta, latency_ns)."""
        t0 = time.perf_counter_ns()
        self.sock.sendto(payload, self.addr)
        try:
            data, _ = self.sock.recvfrom(64)
        except socket.timeout:
            return None, None
        t1 = time.perf_counter_ns()
        delta = from_q16(struct.unpack(">i", data[:4])[0])
        return delta, (t1 - t0)

def main():
    link  = FpgaLink(FPGA_IP, FPGA_PORT, LOCAL_PORT, RECV_TIMEOUT_S)
    spots = SpotCache()

    # static per-contract info, and the set of underlying roots to stream
    contracts = {}
    roots = set()
    for sym in OPTION_SYMBOLS:
        root, expiry, cp, K = parse_occ(sym)
        contracts[sym] = {"root": root, "expiry": expiry, "cp": cp, "K": K}
        roots.add(root)

    # --- stock stream: cache latest spot ---
    stock_stream = StockDataStream(API_KEY, API_SECRET)

    async def on_stock_quote(q):
        mid = (q.bid_price + q.ask_price) / 2.0
        spots.update(q.symbol, mid)

    stock_stream.subscribe_quotes(on_stock_quote, *roots)

    # --- option stream: on each option quote, build + send a packet ---
    option_stream = OptionDataStream(API_KEY, API_SECRET, feed=OPTION_FEED)

    async def on_option_quote(q):
        info = contracts.get(q.symbol)
        if info is None:
            return

        S = spots.get(info["root"])
        if S is None:
            return  # no spot yet; wait for the stock stream to warm up

        K = info["K"]
        sigma = DEFAULT_SIGMA
        r = RISK_FREE_RATE
        T = years_to_expiry(info["expiry"])
        if T <= 0:
            return  # expired

        payload = pack_payload(S, K, sigma, r, T)
        delta, latency_ns = link.send_and_time(payload)

        if delta is None:
            print(f"{q.symbol}: no FPGA response (timeout)")
        else:
            print(f"{q.symbol}  S={S:.2f} K={K:.1f} sig={sigma:.2f} "
                  f"r={r:.2f} T={T:.3f}  ->  delta={delta:.5f}  "
                  f"rt={latency_ns/1000:.1f}us")

    option_stream.subscribe_quotes(on_option_quote, *OPTION_SYMBOLS)

    # run both streams in parallel threads (each manages its own event loop)
    stock_thread = threading.Thread(target=stock_stream.run, daemon=True)
    stock_thread.start()

    print(f"streaming spots {sorted(roots)} (IEX) + options {OPTION_SYMBOLS} "
          f"({OPTION_FEED}) -> FPGA at {FPGA_IP}:{FPGA_PORT}")

    # option stream runs in the main thread; blocks until interrupted
    option_stream.run()

if __name__ == "__main__":
    main()