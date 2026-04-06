import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from scapy.all import Ether, IP, UDP, Raw

# Forgive intense commenting I'm learning cocotb

async def send_frame(dut, frame_bytes):
    for i, byte in enumerate(frame_bytes):
        dut.tdata.value = byte
        dut.tvalid.value = 1
        dut.tlast.value = 1 if i == len(frame_bytes) - 1 else 0 # Send tlast signal when we are indexed at the last byte in frame_bytes
        await RisingEdge(dut.clk)   # Loop runs once per clock cycle
    dut.tvalid.value = 0
    dut.tlast.value = 0

async def monitor_output(dut):
    for _ in range(200):
        await RisingEdge(dut.clk)
        if dut.packet_valid.value:
            print(f"packet byte: {dut.packet.value}")
        if dut.packet_end.value:
            print(f"packet end received")
            break   

@cocotb.test()
async def test_parser(dut):
    # Start clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset
    dut.nrst.value = 0
    dut.tvalid.value = 0
    dut.tlast.value = 0
    dut.tdata.value = 0
    await Timer(30, units="ns") # equivalent to #30;
    dut.nrst.value = 1
    await RisingEdge(dut.clk)

    # Build Ethernet frame with 4 bytes of test data
    frame = Ether(dst="ff:ff:ff:ff:ff:ff", src="00:11:22:33:44:55") / \
            IP(dst="192.168.1.1", src="192.168.1.2") / \
            UDP(dport=1234, sport=5678) / \
            Raw(load=b'\x01\x02\x03\x04')
    
    preamble = b'\x55' * 7 + b'\xD5'        # scapy doesn't include the preamble and SFD in its Ethernet frames
    frame_bytes = preamble + bytes(frame)

    cocotb.start_soon(monitor_output(dut)) # start a concurrent monitor

    # Send the Ethernet frame
    await send_frame(dut, frame_bytes)
    await Timer(100, units="ns")