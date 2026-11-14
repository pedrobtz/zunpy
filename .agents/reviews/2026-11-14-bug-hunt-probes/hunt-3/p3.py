import numpy as np, io, os, warnings
warnings.simplefilter("ignore")
d="out3u"
def sv(a):
    b=io.BytesIO(); np.save(b,a); return b.getvalue()
s=["a","","héllo","\U0001F600x","€","abc"]
def M(l,u): return np.array(l,dtype=f"<M8[{u}]")
exp={
"U": np.array(s), "U_F": np.array(s).reshape((2,3),order="F"), "U_C": np.ascontiguousarray(np.array(s).reshape((2,3),order="F")),
"S": np.array([x.encode() for x in s]), "S_lat": np.array([b"a",b"h\xe9",b"\xff"]),
"S_lat_marked": np.array([b"\xe9t\xe9"]), "S_utf8_from_lat": np.array(["été".encode()]), "S_bytes_lat": np.array([b"\xe9t\xe9"]),
"U_from_lat": np.array(["été"]), "S_bytes": np.array([b"\xff\xfe"]), "S_bytes_utf8enc": np.array([b"\xff\xfe"]),
"U_empty": np.array([],dtype="<U1"), "U_allempty": np.array(["",""]), "S_allempty": np.array([b"",b""]),
"U2astral": np.array(["\U0001F600x"]), "U_na_allow": np.array(["a",""]), "U_allna": np.array([""]),
"fac": np.array(["b","a","","b"]), "fac_ok": np.array(["b","a","b"]), "fac_mat": np.array(["x","yy","x","yy"]).reshape((2,2),order="F"),
"U_trailnul_like": np.array(["a "," a","a\t"]), "U_wide": np.array(["x"*70000]),
"U_leading0": np.array(["a"],dtype="<U7"), "S_leading0": np.array([b"a"],dtype="|S7"),
"date": M(["1970-01-01","2024-02-29","0001-01-01","9999-12-31","NaT","1969-12-31"],"D"),
"date_int": M(["1970-01-01","2024-02-29","NaT"],"D"),
"px_us": M(["1970-01-01T00:00:00","2024-10-08T12:00:00.123456","1969-12-31T23:59:59.999999","0001-01-01","2262-04-11T23:47:16","NaT"],"us"),
"px_ms": M(["1970-01-01","0001-01-01","2262-04-11T23:47:16","NaT"],"ms"),
"px_s": M(["1970-01-01","0001-01-01","2262-04-11T23:47:16","NaT"],"s"),
"px_ns": M(["1970-01-01","NaT"],"ns"),
"px_tz": M(["2024-10-08T16:00:00"],"us"), "px_dtype": M(["1970-01-01T00:00:00","2024-10-08T12:00:00.123456"],"us"),
"px_ns_far": M(["2262-04-11T23:47:16"],"ns"), "px_ns_neg": M(["1677-09-21T00:12:44"],"ns"),
"dt_secs": np.array([1,-3,"NaT",0],dtype="<m8[s]"),"dt_mins": np.array([1,-3,"NaT",0],dtype="<m8[m]"),"dt_hours": np.array([1,-3,"NaT",0],dtype="<m8[h]"),
"dt_days": np.array([1,-3,"NaT",0],dtype="<m8[D]"),"dt_weeks": np.array([1,-3,"NaT",0],dtype="<m8[W]"),
"dt_frac_s": np.array([5400],dtype="<m8[s]"), "dt_wk_s": np.array([14*86400],dtype="<m8[s]"),
"dt_s_ms": np.array([1001,100,1,2500],dtype="<m8[ms]"), "dt_s_ns": np.array([1001000000,100000000,1],dtype="<m8[ns]"),
"dt_min_ms": np.array([6000],dtype="<m8[ms]"), "dt_min_m_own": np.array([7],dtype="<m8[m]"),
"dt_mat": np.arange(1,7,dtype="<m8[m]").reshape((2,3),order="F"),
"date_mat": np.ascontiguousarray(np.arange(1,7).astype("<M8[D]").reshape((2,3),order="F")),
"i64t": np.array([5,"NaT",-1],dtype="<M8[h]"), "i64t_dt": np.array([5,"NaT",-1],dtype="<m8[Y]"),
}
exp["px_notz"]=np.array([10**15],dtype="<M8[us]"); exp["px_int"]=exp["px_notz"]
for f in sorted(os.listdir(d)):
    n=f[:-4]; b=open(os.path.join(d,f),"rb").read()
    try: a=np.load(io.BytesIO(b))
    except Exception as e: print(n,"LOADFAIL",e, b[:100]); continue
    if n in exp:
        e=sv(exp[n])
        if e!=b:
            print(n,"DIFF", b[10:b.index(b"\n")][:70], "| numpy:", e[10:e.index(b"\n")][:70]); print("   got",a.ravel()[:20]); print("   exp",exp[n].ravel()[:20])
    else:
        print(n,"NOEXP", a.dtype, a.shape, a.ravel()[:10], a.tobytes()[:48].hex())
