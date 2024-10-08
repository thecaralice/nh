# Notice: this file will only exist until this pr is merged https://github.com/LnL7/nix-darwin/pull/942
self: { config, lib, pkgs, ... }:
let
  cfg = config.programs.nh;
  nh_darwin = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  nh = (pkgs.runCommand "${nh_darwin.pname}-docker-compat-${nh_darwin.version}"
    {
      outputs = [ "out" ];
      inherit (nh_darwin) meta;
    } ''
    mkdir -p $out/bin
    ln -s ${nh_darwin}/bin/nh_darwin $out/bin/nh
  '');
in
{
  meta.maintainers = [ lib.maintainers.ToyVo ];

  options.programs.nh = {
    enable = lib.mkEnableOption "nh_darwin, yet another Nix CLI helper. Works on NixOS, NixDarwin, and HomeManager Standalone";

    alias = lib.mkEnableOption "Enable alias of nh_darwin to nh";

    package = lib.mkPackageOption pkgs "nh" { } // {
      default = nh_darwin;
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `FLAKE` environment variable.

        `FLAKE` is used by nh_darwin as the default flake for performing actions, like `nh_darwin os switch`.
      '';
    };

    clean = {
      enable = lib.mkEnableOption "periodic garbage collection with nh_darwin clean all";

      # Not in NixOS module
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User that runs the garbage collector.";
      };

      interval = lib.mkOption {
        type = lib.types.attrs;
        default = { Weekday = 0; };
        description = ''
          How often cleanup is performed. Passed to launchd.StartCalendarInterval

          The format is described in
          {manpage}`crontab(5)`.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "";
        example = "--keep 5 --keep-since 3d";
        description = ''
          Options given to nh_darwin clean when the service is run automatically.

          See `nh_darwin clean all --help` for more information.
        '';
      };
    };
  };

  config = {
    warnings =
      if (!(cfg.clean.enable -> !config.nix.gc.automatic)) then [
        "programs.nh.clean.enable and nix.gc.automatic are both enabled. Please use one or the other to avoid conflict."
      ] else [ ];

    assertions = [
      # Not strictly required but probably a good assertion to have
      {
        assertion = cfg.clean.enable -> cfg.enable;
        message = "programs.nh.clean.enable requires programs.nh.enable";
      }

      {
        assertion = (cfg.flake != null) -> !(lib.hasSuffix ".nix" cfg.flake);
        message = "nh.flake must be a directory, not a nix file";
      }
    ];

    nixpkgs.overlays = [ self.overlays.default ];

    environment = lib.mkIf cfg.enable {
      systemPackages = [ cfg.package ] ++ lib.optionals cfg.alias [ nh ];
      variables = lib.mkIf (cfg.flake != null) {
        FLAKE = cfg.flake;
      };
    };

    launchd = lib.mkIf cfg.clean.enable {
      daemons.nh-clean = {
        command = "exec ${lib.getExe cfg.package} clean all ${cfg.clean.extraArgs}";
        environment.NIX_REMOTE = lib.optionalString config.nix.useDaemon "daemon";
        serviceConfig.RunAtLoad = false;
        serviceConfig.StartCalendarInterval = [ cfg.clean.interval ];
        serviceConfig.UserName = cfg.clean.user;
      };
    };
  };
}
