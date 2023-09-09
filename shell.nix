# Configuration file for Nix(OS) to provide a temporary development enviroment

{ pkgs ? import <nixpkgs> {} }:
let
	unstable = import <nixpkgs> {};
in
	pkgs.mkShell {
		name = "armbian-build";
		buildInputs = with pkgs; [
			bash # For evaluation
			nil # Language server for nix
			shellcheck # For linting shell
			util-linux # Needed for uuidgen
		];
	}
