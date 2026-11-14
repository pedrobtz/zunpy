import numpy as np, io
def sv(a):
    b=io.BytesIO(); np.save(b,a); return b.getvalue()
prev={}
for L in range(65300,65451):
    for p,last in (("hl","n"),("hlu","€"),("hll","é"),("hle"," ")):
        nm="n"*(L-1)+last
        a=np.zeros(1,dtype=[(nm,"<i4")]); a[0]=(1,)
        b=open(f"out6/{p}_{L}.npy","rb").read(); e=sv(a)
        if b!=e: print(p,L,"DIFF",b[:12],e[:12],len(b),len(e))
        g=np.load(io.BytesIO(b),max_header_size=10**6)
        if g.dtype.names!=(nm,) or g[0][0]!=1: print(p,L,"READ MISMATCH")
        v=(b[6],len(b))
        if prev.get(p)!=v: print(p,L,"version",b[6],"hdrlen field",int.from_bytes(b[8:10] if b[6]==1 else b[8:12],"little"),"total",len(b)); prev[p]=v
