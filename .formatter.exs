spark_locals_without_parens = [
  compute: 1,
  description: 1,
  event: 1,
  event: 2,
  initial: 1
]

[
  locals_without_parens: spark_locals_without_parens,
  import_deps: [:spark],
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: [".claude.exs", "{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
