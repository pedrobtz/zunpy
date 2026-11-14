# .npz archives (design section 10; roadmap Stage 6).

test_that("every .npz fixture reads as its member fixtures do", {
  m <- fixtures_manifest()
  m <- m[m$descr == "npz", ]
  expect_gte(nrow(m), 5)
  for (i in seq_len(nrow(m))) {
    pairs <- if (nzchar(m$values[i])) strsplit(m$values[i], " ")[[1]] else character()
    keys <- sub("=.*$", "", pairs)
    files <- sub("^.*=", "", pairs)
    got <- npy_decode(fixture_bytes(m$file[i]))
    expected <- stats::setNames(lapply(files, function(f) npy_decode(fixture_bytes(f))),
                                keys)
    expect_identical(got, if (length(keys)) expected else stats::setNames(list(), character()),
                     info = m$file[i])
    expect_identical(npy_names(fixture_bytes(m$file[i])), keys, info = m$file[i])
  }
})

test_that("names = reads only the members named, in that order", {
  x <- fixture_bytes("npz-compressed.npz")
  got <- npy_decode(x, names = c("r", "x"))
  expect_named(got, c("r", "x"))
  expect_identical(got$x, npy_decode(fixture_bytes("f8-le-c.npy")))
  e <- expect_zunpy_error(npy_decode(x, names = "nope"), "zunpy_invalid_argument")
  expect_identical(e$arg, "names")
  expect_zunpy_error(npy_decode(fixture_bytes("f8-le-c.npy"), names = "x"),
                     "zunpy_invalid_argument")
})

test_that("a list writes as NumPy's savez() writes it", {
  x <- fixture_bytes("npz-stored.npz")
  back <- npy_encode(npy_decode(x), dtype = list(x = "<f8", y = "<i4"),
                     order = "C")
  expect_identical(back, x)
  p <- fixture_bytes("npz-positional.npz")
  expect_identical(npy_encode(npy_decode(p), order = "C"), p)
  expect_identical(npy_encode(stats::setNames(list(), character())),
                   fixture_bytes("npz-empty.npz"))
})

test_that("compressed archives round-trip; writing is deterministic", {
  v <- list(a = 1:1000, b = matrix(c(0.5, NA, 2, 3), 2), s = c("x", "y\u00e9"),
            d = data.frame(k = 1:2, t = as.Date("2024-01-01") + 0:1))
  z <- npy_encode(v, compress = TRUE)
  expect_identical(npy_encode(v, compress = TRUE), z)
  expect_identical(npy_decode(z), v)
  expect_lt(length(z), length(npy_encode(v)))
})

test_that("a member's errors name the member", {
  z <- npy_encode(list(ok = 1, bad = c(1L, NA)), na = "allow")
  e <- expect_zunpy_error(npy_decode(z), "zunpy_na_error")
  expect_identical(e$member, "bad")
  expect_identical(npy_decode(z, na = "allow")$bad, c(1L, NA))
  e <- expect_zunpy_error(npy_encode(list(a = 1, b = c(TRUE, NA))), "zunpy_na_error")
  expect_identical(e$member, "b")
})

test_that("member names that are paths, or missing, are refused", {
  for (nm in c("a/b", "a\\b", "..up", "", ".")) {
    v <- list(1)
    names(v) <- nm
    expect_zunpy_error(npy_encode(v), "zunpy_invalid_argument")
  }
  expect_zunpy_error(npy_encode(list(1, 2)), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(list(a = list(1))), "zunpy_unsupported_type")
  expect_zunpy_error(npy_encode(1, compress = TRUE), "zunpy_invalid_argument")
})

test_that("GUARD members: max_members bounds the directory before it is read", {
  x <- fixture_bytes("npz-stored.npz")
  e <- expect_zunpy_error(npy_decode(x, max_members = 1), "zunpy_members_limit")
  expect_identical(e$limit, "max_members")
  expect_zunpy_error(npy_names(x, max_members = 1), "zunpy_members_limit")
  # A ZIP64 directory declaring 2^32 members.
  z <- fixture_bytes("npz-zip64.npz")
  at <- find_sig(z, 0x06064b50)
  z <- put_le(z, at + 24, 2^32, 8)
  z <- put_le(z, at + 32, 2^32, 8)
  expect_zunpy_error(npy_decode(z), "zunpy_members_limit")
  expect_zunpy_error(npy_decode(z, max_members = 2^33), "zunpy_parse_error")
})

test_that("GUARD declared-total: declared sizes are bounded before inflating", {
  x <- fixture_bytes("npz-compressed.npz")
  at <- find_sig(x, 0x02014b50)[1]
  # 2 GiB + 1 declared for a member of a few hundred bytes.
  y <- put_le(x, at + 24, 2^31 + 1, 4)
  e <- expect_zunpy_error(npy_decode(y), "zunpy_size_limit")
  expect_identical(e$limit, "max_size")
})

test_that("a member that inflates past its declared size is stopped there", {
  x <- fixture_bytes("npz-compressed.npz")
  at <- find_sig(x, 0x02014b50)[1]
  y <- put_le(x, at + 24, 100, 4)
  e <- expect_zunpy_error(npy_decode(y), "zunpy_invalid_error")
  expect_identical(e$member, "x")
})

test_that("a CRC-32 mismatch is refused", {
  x <- fixture_bytes("npz-stored.npz")
  x[55 + 150] <- xor(x[55 + 150], as.raw(1))
  e <- expect_zunpy_error(npy_decode(x), "zunpy_invalid_error")
  expect_identical(e$member, "x")
  expect_identical(npy_decode(x, names = "y")$y, npy_decode(fixture_bytes("i4-le-c.npy")))
})

test_that("unsupported ZIP features are classed", {
  x <- fixture_bytes("npz-stored.npz")
  at <- find_sig(x, 0x02014b50)[1]
  expect_zunpy_error(npy_decode(put_le(x, at + 10, 12, 2)), "zunpy_unsupported_type")
  expect_zunpy_error(npy_decode(put_le(x, at + 8, 1, 2)), "zunpy_unsupported_type")
})

test_that("every proper prefix of an archive is refused", {
  x <- fixture_bytes("npz-stored.npz")
  for (n in c(2:30, seq(31, length(x) - 1, by = 7))) {
    expect_zunpy_error(npy_decode(x[seq_len(n)]), "zunpy_parse_error")
  }
})

test_that("pointers outside the archive are refused", {
  x <- fixture_bytes("npz-stored.npz")
  eocd <- find_sig(x, 0x06054b50)
  expect_zunpy_error(npy_decode(put_le(x, eocd + 16, length(x) + 10, 4)),
                     "zunpy_parse_error")
  at <- find_sig(x, 0x02014b50)[1]
  expect_zunpy_error(npy_decode(put_le(x, at + 42, length(x) - 10, 4)),
                     "zunpy_parse_error")
  expect_zunpy_error(npy_decode(put_le(x, at + 20, 2^31, 4)), "zunpy_parse_error")
})

test_that("a member that is not a .npy is a parse error naming it", {
  z <- .Call(zunpy_zip_build, "notes.txt", 0L, .Call(zunpy_crc32, charToRaw("hello")),
             5, list(charToRaw("hello")))
  e <- expect_zunpy_error(npy_decode(z), "zunpy_parse_error")
  expect_identical(e$member, "notes.txt")
})

test_that("#25 member names: the 65,535-byte bound on the stored name", {
  # The stored name is the key and ".npy": 65,531 bytes of key is the most.
  for (len in c(65530, 65531)) {
    key <- strrep("k", len)
    z <- npy_encode(setNames(list(1:2), key))
    expect_identical(npy_names(z), key)
    expect_identical(npy_decode(z)[[key]], 1:2)
  }
  expect_zunpy_error(npy_encode(setNames(list(1:2), strrep("k", 65532))),
                     "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(setNames(list(1:2), strrep("k", 70000))),
                     "zunpy_invalid_argument")
  # In bytes, not characters: 21,844 three-byte characters are 65,532 bytes.
  wide <- strrep("€", 21843)
  expect_identical(npy_names(npy_encode(setNames(list(1L), wide))), wide)
  expect_zunpy_error(npy_encode(setNames(list(1L), paste0(wide, "€"))),
                     "zunpy_invalid_argument")
})

test_that("#25 the archive builder refuses a name too long to store", {
  out <- .Call(zunpy:::zunpy_zip_build, strrep("k", 65536), 0L, 0, 0,
               list(raw()))
  expect_null(out)
})

test_that("#25 member and field names must be valid UTF-8", {
  bad <- "a\xff"
  Encoding(bad) <- "bytes"
  expect_zunpy_error(npy_encode(setNames(list(1:2), bad)),
                     "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(setNames(data.frame(1:2), bad)),
                     "zunpy_invalid_argument")
  latin <- "caf\xe9"
  Encoding(latin) <- "latin1"
  z <- npy_encode(setNames(list(1:2), latin))
  expect_identical(npy_names(z), "café")
  r <- npy_decode(npy_encode(setNames(data.frame(1:2), latin)))
  expect_identical(names(r), "café")
})

test_that("#25 a hostile member name is a classed error, not a base one", {
  z <- npy_encode(list(ab = 1:2))
  at <- find_bytes(z, charToRaw("ab.npy"))
  expect_length(at, 2)
  nul <- z
  for (i in at) nul[i + 1] <- as.raw(0)
  expect_zunpy_error(npy_names(nul), "zunpy_parse_error")
  expect_zunpy_error(npy_decode(nul), "zunpy_parse_error")
  # Flagged as UTF-8 (a non-ASCII name sets the flag), but not UTF-8.
  z <- npy_encode(setNames(list(1:2), "é"))
  at <- find_bytes(z, as.raw(c(0xc3, 0xa9)))
  expect_length(at, 2)
  bad <- z
  for (i in at) bad[i + 0:1] <- as.raw(c(0xff, 0xfe))
  expect_zunpy_error(npy_names(bad), "zunpy_parse_error")
  expect_zunpy_error(npy_decode(bad), "zunpy_parse_error")
})
