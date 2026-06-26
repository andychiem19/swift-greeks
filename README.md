### swiftGreeks
A personal educational project developing a low-latency FPGA Ethernet feed handler and an FPGA hardware accelerator, benchmarking against an embedded C++ baseline for the calculation of Black-Scholes options greeks from raw market data.

> **Note:** This project uses the Zybo Z7’s 1Gbps Ethernet for demonstration and testing. In production HFT systems, feed handlers run at 10–100Gbps, but the underlying packet parsing, multicast handling, and FPGA pipeline design principles remain largely the same and this platform suffices for educational purposes.

**Tools Used**

*This project is being developed for the Zybo Z7 SoC and its onboard FPGA, comparable to the Xilinx Artix-7 series FPGA.*

`Xilinx Vivado`
`Verilator`
`cocotb`
`GTKWave`
`SystemVerilog`
`C++`
`Python`

---

#### **File Structure**

`/src` -> C++ code websockets, serialization, and embedded software on the ARM, SystemVerilog for FPGA-side modules and CORDIC core\
`/tb` –> cocotb testbenches for verifying that each hardware module works as intended\
`/docs` -> Additional documentation, including high-level block diagrams and ADRs

---

#### **Learning Objectives**

- **Ethernet Communication** – understand frame structure, MAC/IP/UDP parsing
- **Real-time Data Handling** – process high-speed streaming market data with signal integrity and minimal latency
- **Hardware Acceleration** – use FPGA fabric for low-latency packet parsing and preprocessing
- **Protocol Parsing** – implement packet-level state machines
- **AXI-Stream / FPGA Pipelines** – integrate MAC output to custom RTL logic, interface between onboard ARM and FPGA
- **Sequence Number & Data Integrity Handling** – detect gaps, out-of-order packets, and malformed frames
- **CORDIC** – implement transcendental functions in synthesizable RTL for hardware-accelerated calculations
- **cocotb Verification** – write Python-based hardware testbenches for complex protocol logic
- **Hardware/Software Co-design** – benchmark ARM C++ baseline against FPGA accelerator using AXI-Lite
