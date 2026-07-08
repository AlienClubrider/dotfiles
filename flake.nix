{
  description = "bryson's home-manager config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixgl, ... }:
    let
      # Picked up from the machine actually running the switch, so the same
      # flake works unmodified on Linux and Apple Silicon. Requires --impure
      # (rebuild.sh/bootstrap.sh already pass it).
      system = builtins.currentSystem;
      isLinux = nixpkgs.lib.hasSuffix "-linux" system;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = nixpkgs.lib.optional isLinux nixgl.overlay;
      };
    in
    {
      homeConfigurations.bryson = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit isLinux; };
      };
    };
}
