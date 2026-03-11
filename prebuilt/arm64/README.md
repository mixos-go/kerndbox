# prebuilt/arm64

Prebuilt arm64 packages baked into the container image (Dockerfile),
NOT into the guest rootfs.

## ../tools/uml-utilities_arm64.deb
Source: `uml-utilities 20070815-4.2+1` (Debian bookworm, arm64)
Contains: `uml_mconsole`, `uml_switch`, `uml_mkcow`, `uml_moo`,
          `uml_mount`, `uml_net`, `uml_watchdog`, `tunctl`, `port-helper`

Host-side UML management tools. Installed into the container image so
developers can use `uml_mconsole` to attach to a running UML instance.
