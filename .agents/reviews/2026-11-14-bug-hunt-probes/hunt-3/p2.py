import numpy as np, warnings
warnings.simplefilter("ignore")
for t in ["f2","f4","c8"]:
    s=np.load(f"out2/{t}_src.npy"); g=np.load(f"out2/{t}.npy"); e=s.astype("<"+t)
    bad=np.nonzero(g.view("u"+str(g.itemsize//(2 if t=="c8" else 1))).reshape(len(g),-1)!=e.view("u"+str(g.itemsize//(2 if t=="c8" else 1))).reshape(len(g),-1))[0]
    print(t,len(s),"mismatches",len(bad))
    for i in bad[:8]: print("   ",repr(s[i]), s[i].hex() if t!="c8" else "", "zunpy",g[i],"numpy",e[i])
s=np.load("out2/nan_src.npy")
print([x.tobytes().hex() for x in s])
for t in ["f4","f2"]:
    g=np.load(f"out2/nan_{t}.npy"); print(t,[x.tobytes().hex() for x in g],"numpy",[x.tobytes().hex() for x in s.astype("<"+t)])
print(np.load("out2/nan_c8.npy").tobytes().hex())
