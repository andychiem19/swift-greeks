### swiftGreeks
A personal educational project developing a low-latency FPGA Ethernet feed handler and an FPGA hardware accelerator, benchmarking against an embedded C++ baseline for the calculation of Black-Scholes options greeks from raw market data.

> **Note:** This project uses the Zybo Z7’s 1Gbps Ethernet for demonstration and testing. In production HFT systems, feed handlers run at 10–100Gbps, but the underlying packet parsing, multicast handling, and FPGA pipeline design principles remain largely the same and this platform suffices for educational purposes.

**Tools Used**

*This project is being developed for the Zybo Z7 SoC and its onboard FPGA, comparable to the Xilinx Artix-7 series FPGA.*

`Xilinx Vivado`
`Questa/ModelSim`
`cocotb`
`SystemVerilog`
`C++`

---

#### **File Structure**

`/src` -> Main C++ code for websockets, serialization, and embedded software on the ARM\
`/hdl` –> Main SystemVerilog code for FPGA-side modules\
`/tb` –> cocotb testbenches for verifying that each module works as intended\
`/docs` -> Additional documentation, including high-level block diagrams

---

#### **Learning Objectives**

> **Note:** This section needs to be updated.

- **Ethernet Communication** – understand frame structure, MAC/IP/UDP parsing
- **Real-time Data Handling** – process high-speed streaming market data with minimal latency
- **Hardware Acceleration** – use FPGA fabric for low-latency packet parsing and preprocessing
- **Protocol Parsing** – implement packet-level state machines for multicast feeds
- **AXI-Stream / FPGA Pipelines** – integrate MAC output to custom RTL logic
- **Sequence Number & Data Integrity Handling** – detect gaps, out-of-order packets, and malformed frames
- **Integration with Trading Logic** – forward processed payloads to FPGA-based order book or simulator
