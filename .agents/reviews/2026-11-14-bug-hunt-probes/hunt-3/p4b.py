import numpy as np
for u in ["ms","us","ns"]:
    a=np.load(f"out4/in_{u}.npy").view("i8"); b=np.load(f"out4/in_{u}.out.npy").view("i8")
    m=a!=b; print(u,"mismatch",m.sum(),"min |k| mismatched 2^%.2f"%np.log2(np.abs(a[m]).min()), "max diff", np.abs(a[m]-b[m]).max(), "examples", a[m][:3], b[m][:3])
for n in ["bigns","bigus"]:
    a=np.load(f"out4/in_{n}.keep.npy").view("i8"); b=np.load(f"out4/in_{n}.out.npy").view("i8")
    d=np.abs(a.astype(object)-b.astype(object)); print(n,"n",len(a),"mismatch",int((a!=b).sum()),"max abs diff",max(d))
