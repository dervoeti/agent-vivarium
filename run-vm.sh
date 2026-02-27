#!/usr/bin/env bash
set -e

nixos-rebuild build-vm --flake .#devVM
./result/bin/run-devVM-vm
