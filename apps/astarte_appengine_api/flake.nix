{
  description = "Elixir 1.15.7 with OTP 26.1";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
      elixir = pkgs.beam.packages.erlang_26.elixir_1_15;
    in {
      default = pkgs.mkShell {
        buildInputs = [ elixir ];
      };
    };
  };
}
