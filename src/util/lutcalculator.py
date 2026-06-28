import math

Q = 16  # fractional bits

print("Circular (atan):")
for i in range(20):
    val = math.atan(2**-i)
    fixed = round(val * 2**Q)
    print(f"  [{i}] = 32'h{fixed:08X};  // {val:.6f}")

print("\nHyperbolic (atanh):")
for i in range(1, 21):  # starts at 1, atanh(2^0) = atanh(1) = undefined
    val = math.atanh(2**-i)
    fixed = round(val * 2**Q)
    print(f"  [{i-1}] = 32'h{fixed:08X};  // {val:.6f}")

print("\nLinear:")
for i in range(20):
    val = 2**-i
    fixed = round(val * 2**Q)
    print(f"  [{i}] = 32'h{fixed:08X};  // {val:.6f}")