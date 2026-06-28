## ADR-01: LUT Approximation

**Context**\
The first issue that came up that absolutely required the use of LUT approximations was a squared exponential (e^(-x^2/2)) inside my CDF module. Within completely nominal values for d1, the calculation would leave the range of rotation of the CORDIC hyperbolic calculation (around d1 = 1.5), thus making a pure, direct CORDIC calculation of N(d1) impossible. 

There were other, more logic heavy approaches to forcing the CORDIC algorithm to work (range reduction, pre-scaling, clamping d1 and approximating otherwise) but all of them either required significant additional logic or sacrificed significant amounts of accuracy, so I did some research..

And found this paper discussing similar hardware implementations for options pricing.
https://accu.org/journals/overload/20/110/wang_1906/
> "The square root and logarithm are implemented CORDIC rolled, while the exponential is implemented using table lookup."

**Decision**\
I concluded that supplementing the CORDIC algorithm with LUTs in some cases and the use of my platform's more than sufficient memory resources would be fair to improve overall performance and reduce development time.

**Reasoning**\
The goal at this early stage of the project is to ship a functional, end-to-end, and benchmarked FPGA-accelerator for options pricing. Spending significant, extra development time on solutions that may not even be better does not serve this purpose. I may return to these optimization decisions when the architecture is complete.

*Andy Chiem; 6/28/2026*