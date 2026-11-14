import numpy as np, warnings
warnings.simplefilter("ignore")
s=np.load("out2/f2_src.npy"); g=np.load("out2/f2.npy"); e=s.astype("<f2")
bad=g.view("u2")!=e.view("u2")
via=s.astype("<f4").astype("<f2")
print("mismatch",bad.sum(),"all explained by double rounding via f4:", (via.view("u2")==g.view("u2")).all())
print("ulp diff max", np.abs(g.view("i2").astype(int)-e.view("i2").astype(int))[bad].max())
print("subnormal results among mismatches:", (np.abs(e[bad])<6.1e-5).sum())
# c8/f4 hold; simple documented example
for v in [1.0+2**-11+2**-40, 2**-25*(1+2**-52), 1.00048828125000001]:
    print(repr(v), "numpy f2:", np.float64(v).astype("<f2").tobytes().hex(), float(np.float64(v).astype("<f2")))
