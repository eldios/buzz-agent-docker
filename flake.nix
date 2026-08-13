{
  description = "Headless Buzz agent container: buzz-acp harness plus Claude Code and Codex ACP adapters";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Task runner: every routine command lives in the Justfile.
          just

          # Every gate the CI workflow runs, so it can be reproduced locally.
          hadolint
          actionlint
          shellcheck
          act

          # Used by the version-checking recipe.
          curl
          jq
        ];

        shellHook = ''
          echo "buzz-agent-docker dev shell - run 'just' for the task list"
        '';
      };
    });
}
