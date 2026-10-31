# qs-lintr.R - run lintr with the generated .lintr file.
#   Rscript --vanilla qs-lintr.R <lintr-config> <files...>   exit 1 if any lint
args <- commandArgs(trailingOnly = TRUE)
options(lintr.linter_file = args[1])
found <- FALSE
for (f in args[-1]) {
  res <- lintr::lint(f)
  if (length(res) > 0) {
    print(res)
    found <- TRUE
  }
}
quit(status = if (found) 1 else 0)
