# The dtype table exists three times (design section 20, criterion 4): in
# design section 6.1, in npy_decode()'s documentation, and here, with a
# NumPy fixture for every row. This test keeps them in step.

test_that("every dtype of the table has a NumPy fixture", {
  m <- fixtures_manifest()
  have <- unique(c(
    sub("^[<>|=]", "", m$descr),
    sub("^[<>|=]([SUV]).*$", "\\1", m$descr),
    sub("^[<>|=]([Mm]8).*$", "\\1", m$descr)
  ))
  for (d in table_dtypes()) expect_true(d %in% have, info = d)
})

test_that("npy_decode()'s documentation names every dtype", {
  # The source when testing a checkout, the installed help under R CMD check.
  src <- testthat::test_path("..", "..", "man", "npy_decode.Rd")
  rd <- if (file.exists(src)) {
    tools::parse_Rd(src)
  } else {
    tryCatch(tools::Rd_db("zunpy")[["npy_decode.Rd"]], error = function(e) NULL)
  }
  skip_if(is.null(rd), "documentation not available")
  text <- paste(capture.output(tools::Rd2txt(rd, options = list(underline_titles = FALSE))),
                collapse = " ")
  for (d in table_dtypes()) {
    expect_true(grepl(d, text, fixed = TRUE), info = d)
  }
})

test_that("design section 6.1 lists every dtype", {
  design <- testthat::test_path("..", "..", ".agents", "design.md")
  skip_if_not(file.exists(design), "the design is not in the built package")
  lines <- readLines(design, encoding = "UTF-8")
  start <- grep("^### 6.1 ", lines)
  end <- grep("^### 6.2 ", lines)
  table <- paste(lines[start:end], collapse = " ")
  for (d in table_dtypes()) {
    expect_true(grepl(paste0("`", d), table, fixed = TRUE), info = d)
  }
})
