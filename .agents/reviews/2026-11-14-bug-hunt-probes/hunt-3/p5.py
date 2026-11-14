import numpy as np, io, os, warnings
warnings.simplefilter("ignore")
d="out5"
def sv(a):
    b=io.BytesIO(); np.save(b,a); return b.getvalue()
def rd(n): return open(f"{d}/{n}.npy","rb").read()
def cmp(n, a):
    if not os.path.exists(f"{d}/{n}.npy"): print(n,"MISSING (zunpy refused)"); return
    b=rd(n)
    try: e=sv(a)
    except Exception as ex: print(n,"numpy cannot save:",ex); e=None
    try: g=np.load(io.BytesIO(b))
    except Exception as ex: print(n,"LOADFAIL",repr(ex)[:200], b[:8]); g=None
    if e is not None and e!=b:
        i=next((i for i,(x,y) in enumerate(zip(e,b)) if x!=y), min(len(e),len(b)))
        print(n,"DIFF at",i,"len",len(b),len(e),"zunpy",b[:8],b[max(10,i-20):i+40],"| numpy",e[:8],e[max(10,i-20):i+40])
    return g
names=[ "".join(chr(int(c)) for c in l.split()) for l in open(f"{d}/names.txt",encoding="utf8").read().split("\n")[:-1]]
for i,nm in enumerate(names,1):
    if nm=="": continue
    a=np.zeros(2,dtype=[(nm,"<i4")]); a[nm]=[1,2]
    g=cmp("nm_%02d"%i,a)
    if g is not None and g.dtype.names!=(nm,): print("  nm_%02d"%i,"name read",g.dtype.names,"want",repr(nm))
a=np.zeros(3,dtype=[("i","<i4"),("d","<f8"),("l","?"),("s","<U3"),("c","<c16"),("r","u1"),("dt","<M8[D]"),("px","<M8[us]"),("td","<m8[m]"),("f","<U1")])
NA=np.frombuffer(bytes.fromhex("a20700000000f07f"),dtype="<f8")[0]
a["i"]=[1,2,3]; a["d"]=[1.5,NA,3]; a["l"]=[1,0,1]; a["s"]=["a","bb","€€€"]; a["c"]=[1-1j,2-1j,3-1j]; a["r"]=[1,2,3]
a["dt"]=np.array([0,1,"NaT"],dtype="<M8[D]"); a["px"]=np.array([0,1500000,"NaT"],dtype="<M8[us]"); a["td"]=np.array([1,2,"NaT"],dtype="<m8[m]"); a["f"]=["u","v","u"]
cmp("multi",a)
a=np.zeros(3,dtype=[("i","u1"),("d","<f4"),("s","S4")]); a["i"]=[1,2,3]; a["d"]=[1.5,2,3]; a["s"]=[b"a",b"bb",b"c"]; cmp("multi_dtype",a)
cmp("zero_rows",np.zeros(0,dtype=[("a","<i4"),("s","<U1")]))
for n in ["zero_cols","zero_cols_3rows"]:
    if os.path.exists(f"{d}/{n}.npy"):
        b=rd(n); print(n,b[:120]); 
        try: print("   np.load:",repr(np.load(io.BytesIO(b))))
        except Exception as ex: print("   LOADFAIL",repr(ex)[:300])
        try: print("   numpy saves:", sv(np.zeros(3 if "3" in n else 0,dtype=[]))[:120])
        except Exception as ex: print("   numpy save fail",ex)
def two(nms):
    a=np.zeros(2,dtype=[(x,"<i4") for x in nms]); a[nms[0]]=[1,2]; a[nms[1]]=[3,4]; return a
cmp("lat_then_wide",two(["café","€"])); cmp("lat2",two(["café","üñ"]))
b=np.zeros(6,dtype=[("a","<i4"),("b","<U1")]); b["a"]=range(1,7); b["b"]=list("abcdef")
cmp("shape23",b.reshape((2,3),order="F")); cmp("shape23C",np.ascontiguousarray(b.reshape((2,3),order="F"))); cmp("shape23int",b.reshape((2,3),order="F"))
cmp("shape61",b.reshape(6,1)); cmp("shape16",b.reshape(1,6)); cmp("shape1231",b.reshape((1,2,3,1),order="F")); cmp("shape1231C",np.ascontiguousarray(b.reshape((1,2,3,1),order="F")))
cmp("shape05",np.zeros((0,5),dtype=[("a","<i4")])); cmp("shape50",np.zeros((5,0),dtype=[("a","<i4")]))
a=np.zeros(1,dtype=[("f%d"%i,"<i4") for i in range(1,1025)])
for i in range(1,1025): a["f%d"%i]=i
cmp("c1024",a)
for L in range(65440,65471):
    for p,last in (("hl","n"),("hlu","€"),("hll","é")):
        a=np.zeros(1,dtype=[("n"*(L-1)+last,"<i4")]); a[0]=(1,)
        g=cmp(f"{p}_{L}",a); b=rd(f"{p}_{L}")
        if L in (65440,65455,65456,65457,65470): print(p,L,"version",b[6],"total",len(b))
a=np.zeros(2,dtype=[("a","<i4"),("b","<U1")]); a["a"]=[1,2]; a["b"]=["x","y"]; cmp("tibble",a)
