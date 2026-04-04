## ADR-000: Toolchain Selection

**Context**\
The first task I had to address when I thought of this project was choosing a simulation and verification toolchain capable enough for the size of the task, aligned with my personal goals, and open-source enough that I wouldn't have to pay for any tools. 

Given the likely simplicity of the hardware designs, likely any toolchain would have worked just fine (a perfectly functional alternative would have been Icarus Verilog, GTKWave, paired with Verilog testbenching). However, this project served as a prime opportunity for me to become more familiar with the tools used in industry, and bring that knowledge with me to my co-op.

**Decision**\
cocotb for effective, Python-based testbenching, Questa/ModelSim for waveform verification and simulation, and Xilinx Vivado for synthesis and implementation. 

**Reasoning**\
cocotb is now used widely in many FPGA development spaces in industry, and is almost a standard among FPGA hobbyists. By learning it early on, I develop the skills to write hardware testbenches in Python quickly and effectively, skills which are also in-demand at my co-op. However, I didn't want to give up the waveform verification I would get with XSim and Verilog testbenching, so I supplemented the verification toolchain with Questa. 

I may still switch to Verilator for simulation, but in the interests of minimizing software switching overhead, I will use Questa's built-in simulator for now. With regards to synthesis and implementation, Vivado is what I'm used to using, and obviously works best with the Xilinx SoC I'm using.

*Andy Chiem; 4/2/2026*

---
\
*Update -- 4/3/2026*\
Switched from Questa to Verilator for simulation, and development moved to a WSL remote distro where cocotb integrates more cleanly with Verilator. GTKWave will be the new waveform viewer as it works natively in WSL and is much more lightweight given that the only role of Questa would have been viewing .vcd files. GTKWave more than suffices for the time being. Also advances the goal of using as many fully open-source tools as possible.