{
  description = "Direct-boot NixOS guest bundle for vzm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };

      vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };

      kernelCommandLine = nixpkgs.lib.concatStringsSep " " (
        [
          "console=hvc0"
          "init=${vm.config.system.build.toplevel}/init"
        ]
        ++ vm.config.boot.kernelParams
      );

      guestManifest = pkgs.writeText "manifest.json" (builtins.toJSON {
        schemaVersion = 1;
        architecture = "aarch64";
        kernel = "kernel";
        initrd = "initrd";
        rootMode = "ephemeral";
        commandLine = kernelCommandLine;
        requiredDisks = [ "data" ];
      });

      guestBundle = pkgs.runCommand "guest-bundle" { } ''
        mkdir -p "$out"
        cp ${vm.config.system.build.kernel}/${vm.config.system.boot.loader.kernelFile} "$out/kernel"
        cp ${vm.config.system.build.netbootRamdisk}/initrd "$out/initrd"
        cp ${guestManifest} "$out/manifest.json"
      '';
    in
    {
      nixosConfigurations = {
        vm = vm;
      };

      packages.${system} = {
        guest-bundle = guestBundle;
      };
    };
}
