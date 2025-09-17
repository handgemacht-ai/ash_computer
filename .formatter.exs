spark_locals_without_parens = []

[
  locals_without_parens: spark_locals_without_parens,
  import_deps: [:ash],
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: [".claude.exs", "{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
