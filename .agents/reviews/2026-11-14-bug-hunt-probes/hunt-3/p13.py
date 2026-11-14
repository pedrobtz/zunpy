import zipfile, struct
b=open("out13/fake_usize.npz","rb").read()
zf=zipfile.ZipFile("out13/fake_usize.npz")
for i in zf.infolist(): print(i.filename, "file_size", i.file_size, "compress_size", i.compress_size, "offset", i.header_offset)
# raw central directory entries
p=b.find(b"PK\x01\x02")
while b[p:p+4]==b"PK\x01\x02":
    csz,usz,nl,xl=struct.unpack("<IIHH",b[p+20:p+32]); print(" cd raw: csize32=%#x usize32=%#x extra=%s"%(csz,usz,b[p+46+nl:p+46+nl+xl].hex())); p+=46+nl+xl
print("python would use ZIP64 extra (both sizes) when file_size >", zipfile.ZIP64_LIMIT)
