import numpy as np, sys
rng=np.random.default_rng(7)
if sys.argv[1]=="gen":
    for u in ["s","ms","us","ns"]:
        k=np.concatenate([rng.integers(-2**53,2**53,5000), rng.integers(-2**40,2**40,5000), rng.integers(-10**6,10**6,2000), np.array([2**53,-2**53,2**53-1,0,-1,1,999999,-999999])])
        np.save(f"out4/in_{u}.npy", k.astype(f"<M8[{u}]"))
        np.save(f"out4/ind_{u}.npy", k.astype(f"<m8[{u}]"))
    k=np.concatenate([rng.integers(-2**63+1,2**63-1,5000),np.array([2**63-1,-2**63+1,2**53+1,-2**53-1])])
    np.save("out4/in_bigns.npy", k.astype("<M8[ns]")); np.save("out4/in_bigus.npy", k.astype("<M8[us]"))
else:
    for u in ["s","ms","us","ns"]:
        for p in ["in","ind"]:
            a=np.load(f"out4/{p}_{u}.npy"); b=np.load(f"out4/{p}_{u}.out.npy")
            print(p,u,a.dtype==b.dtype, "mismatch", int((a.view("i8")!=b.view("i8")).sum()), "bytes same", open(f"out4/{p}_{u}.npy","rb").read()==open(f"out4/{p}_{u}.out.npy","rb").read())
    for n in ["bigns","bigus"]:
        a=np.load(f"out4/in_{n}.npy").view("i8"); b=np.load(f"out4/in_{n}.out.npy").view("i8")
        d=np.abs(a.astype(object)-b.astype(object)); print(n,"n",len(a),"mismatch",int((a!=b).sum()),"max abs diff",max(d))
