import numpy as np, io, os, zipfile, subprocess, warnings
warnings.simplefilter("ignore")
d="out7"
def savez(comp=False, **kw):
    b=io.BytesIO(); (np.savez_compressed if comp else np.savez)(b, **kw); return b.getvalue()
def rd(n): return open(f"{d}/{n}","rb").read()
def chk(n, exp=None, **kw):
    b=rd(n+".npz")
    zf=zipfile.ZipFile(io.BytesIO(b)); bad=zf.testzip()
    u=subprocess.run(["unzip","-tq",f"{d}/{n}.npz"],capture_output=True,text=True)
    print(n,"testzip",bad,"| unzip:",u.stdout.strip()[-60:],u.stderr.strip()[-80:],"| n",len(zf.namelist()))
    if exp is not None:
        e=savez(**exp)
        if e!=b:
            i=next((i for i,(x,y) in enumerate(zip(e,b)) if x!=y), min(len(e),len(b)))
            print("   DIFF vs numpy at",i,len(b),len(e),b[i-8:i+24].hex(),e[i-8:i+24].hex())
        else: print("   identical to numpy.savez")
        z=np.load(io.BytesIO(b))
        for k,v in exp.items():
            if not (z[k].dtype==v.dtype and z[k].shape==v.shape and z[k].tobytes()==v.tobytes()): print("   VALUE MISMATCH",k)
    return zf
basic=dict(a=np.array([1,2,3],dtype="<i4"), b=np.asfortranarray(np.array([[1.5,3],[2,4]])), s=np.array(["x","yy"]), e=np.zeros(0))
chk("basic",basic)
zf=chk("basic_c"); z=np.load(f"{d}/basic_c.npz"); print("   compressed values ok:", all(z[k].tobytes()==v.tobytes() and z[k].dtype==v.dtype for k,v in basic.items()), [ (i.compress_type,i.date_time,i.external_attr>>16,i.flag_bits,i.extract_version,i.create_version,i.create_system) for i in zf.infolist()][:1])
e=zipfile.ZipFile(io.BytesIO(savez(True,**basic))).infolist()[0]; print("   numpy compressed info:",(e.compress_type,e.date_time,e.external_attr>>16,e.flag_bits,e.extract_version,e.create_version,e.create_system))
zf=chk("big_c"); z=np.load(f"{d}/big_c.npz"); print("   ", (z["z"]==0).all(), (z["r"]==np.arange(1,200001)).all())
chk("utf8name",{"café":np.array([1,2],dtype="<i4"),"\U0001F600":np.array([3,4],dtype="<i4")})
chk("spaces",{"a b":np.array([1,2],dtype="<i4"),"x.npy":np.array([3,4],dtype="<i4"),"-dash":np.array([5],dtype="<i4")})
chk("one",{"x":np.array([1],dtype="<i4")}); chk("empty_member",{"e":np.zeros(0,dtype="<i4")})
chk("long_ok",{"k"*65531:np.array([1],dtype="<i4")}); chk("long_utf8_ok",{"k"*65528+"€":np.array([1],dtype="<i4")})
chk("colon",{"C:x":np.array([1.0])}); chk("lead_dot",{".hidden":np.array([1.0])})
dd=np.zeros(2,dtype=[("a","<i4"),("b","<U1")]); dd["a"]=[1,2]; dd["b"]=["u","v"]
chk("df_member",{"d":dd,"v":np.array([1,2],dtype="<i4")})
chk("dtype_list",{"a":np.array([1,2,3],dtype="u1"),"b":np.array([1.0,2])})
for n in (65534,65535,65536):
    chk(f"n{n}",{f"m{i}":np.zeros(0,dtype="<i4") for i in range(1,n+1)})
zf=chk("dup_norm"); print("   names:",zf.namelist()); z=np.load(f"{d}/dup_norm.npz"); print("   numpy sees keys",list(z.keys()),[z[k] for k in z.keys()])
try: a=np.load(f"{d}/df_dup_norm.npy"); print("df_dup_norm loads?!",a.dtype)
except Exception as ex: print("df_dup_norm numpy:",repr(ex)[:200])
print(rd("df_dup_norm.npy")[:80])
