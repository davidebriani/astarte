spark_locals_without_parens = [
  clustering_key: 1,
  partition_key: 1,
  repo: 1
]

[
  import_deps: [:phoenix, :ecto, :skogsra, :stream_data, :ash, :ash_graphql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
