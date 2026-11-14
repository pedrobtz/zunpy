import numpy as np, io, os, sys, warnings
warnings.simplefilter("ignore")
d="out1"
def sv(a):
    b=io.BytesIO(); np.save(b,a); return b.getvalue()
F=np.asfortranarray
nan=np.nan; inf=np.inf
NA=np.frombuffer(bytes.fromhex("a207000000 00f07f".replace(" ","")),dtype="<f8")[0]
exp={
"vec_d": np.array([1.5,-0.0,nan,inf,-inf,NA]),
"vec_i": np.arange(1,6,dtype="<i4"),
"vec_l": np.array([True,False]),
"vec_raw": np.arange(256,dtype="u1"),
"empty_d": np.zeros(0),
"mat23": F(np.arange(1,7,dtype="<i4").reshape(3,2).T),
"mat23C": np.ascontiguousarray(np.arange(1,7,dtype="<i4").reshape(3,2).T),
"arr234": np.arange(1,25,dtype="<i4").reshape((2,3,4),order="F"),
"arr234C": np.ascontiguousarray(np.arange(1,25,dtype="<i4").reshape((2,3,4),order="F")),
"arr0_3": np.zeros((0,3)), "arr3_0": np.zeros((3,0)), "arr3_0C": np.zeros((3,0)),
"arr1_5": np.arange(1,6,dtype="<i4").reshape(1,5),
"arr5_1": np.arange(1,6,dtype="<i4").reshape(5,1),
"arr1_5_1": np.arange(1,6,dtype="<i4").reshape(1,5,1),
"arr1_5_1C": np.arange(1,6,dtype="<i4").reshape(1,5,1),
"arr1d": np.arange(1,6,dtype="<i4"),
"arr1_1": np.array([[7.0]]),
"arr2_1_3": np.arange(1,7,dtype="<i4").reshape((2,1,3),order="F"),
"arr2_1_3C": np.ascontiguousarray(np.arange(1,7,dtype="<i4").reshape((2,1,3),order="F")),
"arr5d": np.arange(1,121,dtype="<i4").reshape((2,3,4,5,1),order="F"),
"arr5dC": np.ascontiguousarray(np.arange(1,121,dtype="<i4").reshape((2,3,4,5,1),order="F")),
"big_axis": np.zeros(123456,dtype="<i4"),
"matbig": np.zeros((100000,2),dtype="<i4",order="F"),
"matbig2": np.zeros((2,100000),dtype="<i4",order="F"),
"matbig2C": np.zeros((2,100000),dtype="<i4"),
"f2": np.array([0, -0.0, 1, 65504, -65504, 65519.99, 1e-8, 5.960464477539063e-08, 2.98023223876953125e-08, 2.980232238769532e-08, 8.940696716308594e-08, 1+2**-11, 1+3*2**-11, nan, inf, -inf, 6.1e-5, 1/3]).astype("<f2"),
"f2_over": np.array([65520.0]).astype("<f2"),
"f4": np.array([0, -0.0, 1, 3.4028234663852886e38, 3.4028235677973362e38, 1e-45, 7.006492321624085e-46, 7.0064923216240854e-46*1.0000001, 1.401298464324817e-45, 1+2**-24, 1+3*2**-24, 0.1, nan, inf, 1e-50]).astype("<f4"),
"f4_over": np.array([3.4028235677973366e38]).astype("<f4"),
"i1": np.array([-128,127],dtype="i1"), "u1": np.array([0,255],dtype="u1"), "u1_negzero": np.array([0],dtype="u1"),
"i2": np.array([-32768,32767],dtype="<i2"), "u2": np.array([0,65535],dtype="<u2"),
"i4d": np.array([-2147483647,2147483647],dtype="<i4"), "i4min": np.array([-2147483648],dtype="<i4"),
"u4": np.array([0,4294967295],dtype="<u4"),
"i8": np.array([-2**63, 2**53, -2**53, 2**62, 9007199254740992],dtype="<i8"),
"u8": np.array([0,2**63,2**64-2048],dtype="<u8"),
"b1_from_int01": np.array([False,True]),
"int_na_allow": np.array([1,-2147483648],dtype="<i4"),
"int_na_f8": np.array([1,nan]), "int_na_f4": np.array([1,nan],dtype="<f4"),
"lgl_i4": np.array([1,0],dtype="<i4"), "lgl_f8": np.array([1.0,0]),
"lgl_na_allow": np.array([True,False]),
"i64": np.array([9223372036854775807,-9223372036854775807,0,9007199254740993],dtype="<i8"),
"i64_u8": np.array([9223372036854775807,0],dtype="<u8"),
"i64mat": F(np.arange(1,7,dtype="<i8").reshape(3,2).T),
}
seen=set()
for f in sorted(os.listdir(d)):
    n=f[:-4]; b=open(os.path.join(d,f),"rb").read(); seen.add(n)
    try: a=np.load(io.BytesIO(b))
    except Exception as e: print(n,"LOADFAIL",e); continue
    if n in exp:
        e=sv(exp[n])
        if e!=b:
            print(n,"DIFF", b[:10], b[10:b.index(b"\n")][:90], "| numpy:", e[10:e.index(b"\n")][:90]); print("   got",a.ravel()[:20], a.tobytes()[:64].hex()); print("   exp",exp[n].ravel()[:20], exp[n].tobytes()[:64].hex())
    else:
        print(n,"NOEXP", a.dtype, a.shape, a.flags.f_contiguous, a.ravel()[:10], a.tobytes()[:48].hex())
print("missing", set(exp)-seen)
