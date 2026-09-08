# The systemd portable service image of one placed plan entry. read.nix is the
# whole reading, and everything here is derivations over what that read returned.
#
# The image carries an operating-system identity file, one unit file per recorded
# unit and the entry's declared closure roots. It never carries a configuration
# file's bytes or a generated file's bytes: those reach the units from the host at
# attach time, which is what keeps an image byte-identical across a configuration
# edit.
{
  lib,
  pkgs,
  planner,
}:
let
  reader = import ./read.nix { inherit planner; };

  inherit (builtins) attrNames concatStringsSep filter;
in
{
  inherit reader;

  # plan is the whole plan, key the placed entry to build, profile the confinement
  # profile the attachment is stated to run under. compression is a build input
  # like the profile and never a plan fact.
  build =
    {
      plan,
      key,
      profile,
      compression ? "xz -Xdict-size 100%",
    }:
    let
      image = reader.read { inherit plan key profile; };

      unitNames = attrNames image.units;

      unitFiles = map (
        unitName:
        pkgs.writeTextFile {
          name = image.units.${unitName}.file;
          text = reader.renderUnit image unitName;
        }
      ) unitNames;

      timerFiles = map (
        unitName:
        pkgs.writeTextFile {
          name = image.units.${unitName}.timer;
          text = reader.renderTimer image unitName;
        }
      ) (filter (unitName: image.units.${unitName}.timer != null) unitNames);

      # A plan naming another store directory names the same hashes under another
      # prefix, which is what a relocated store is. Rewriting the prefix keeps the
      # string's context, so the bytes are still this evaluation's while the image
      # places them where the plan means.
      relocated = image.storeDir != builtins.storeDir;

      localOf = root: builtins.replaceStrings [ image.storeDir ] [ builtins.storeDir ] root;

      symlinks = map (root: {
        object = localOf root;
        symlink = "${lib.removePrefix "/" image.storeDir}/${baseNameOf root}";
      }) (if relocated then image.closure else [ ]);

      # The image's own root: systemd's layout, the unit files, and an empty file at
      # every host path the entry is shown.
      #
      # Those empty files are load-bearing rather than tidy. A unit's bind mount needs
      # its destination to exist inside the image, and the image root is a read-only
      # squashfs on the machine, so a missing one is not a missing file at run time but
      # a unit that cannot start at all.
      osRelease = pkgs.writeText "${image.name}-os-release" ''
        PORTABLE_ID=${image.name}
        PORTABLE_PRETTY_NAME=${image.instance}:${image.service} on ${image.machine}
        ID=nixos
        PRETTY_NAME=NixOS
        BUILD_ID=rolling
      '';

      imageRoot = pkgs.runCommand "${image.name}-root" { } (
        ''
          mkdir -p $out/etc/systemd/system $out/proc $out/sys $out/dev $out/run \
                   $out/tmp $out/var/tmp $out/var/lib $out/var/cache $out/var/log
          touch $out/etc/resolv.conf $out/etc/machine-id
          cp ${osRelease} $out/etc/os-release
        ''
        + concatStringsSep "" (
          map (unit: ''
            cp ${unit} $out/etc/systemd/system/${unit.name}
          '') (unitFiles ++ timerFiles)
        )
        + concatStringsSep "" (
          map (host: ''
            install -D -m ${
              lib.escapeShellArg (host.mode or "0444")
            } /dev/null "$out"${lib.escapeShellArg host.path}
          '') image.hostPaths
        )
        + concatStringsSep "" (
          map (link: ''
            mkdir -p "$(dirname "$out"/${lib.escapeShellArg link.symlink})"
            ln -s ${link.object} "$out"/${lib.escapeShellArg link.symlink}
          '') symlinks
        )
      );

      raw =
        pkgs.runCommand "${image.name}-img-${image.version}"
          {
            nativeBuildInputs = [ pkgs.squashfsTools ];
            closureInfo = pkgs.closureInfo {
              rootPaths = [ imageRoot ] ++ map localOf image.closure;
            };
          }
          ''
            mkdir -p nix/store
            for path in $(< $closureInfo/store-paths); do
              cp -a "$path" "''${path:1}"
            done

            mkdir -p $out
            # `SOURCE_DATE_EPOCH` and `-all-root` are what make two builds of one
            # plan the same bytes (https://github.com/NixOS/nixpkgs/issues/390696).
            SOURCE_DATE_EPOCH=0 mksquashfs nix ${imageRoot}/* $out/${attachment.image} \
              -quiet -noappend -exit-on-error -keep-as-directory \
              -all-root -root-mode 755 -b 1M -comp ${compression}
          '';

      attachment = reader.attachment image;

      description = pkgs.writeText "${image.name}-attachment.json" (builtins.toJSON attachment);

      # Assembling a configuration file on the host: a source file is copied out of the
      # store, a render list is concatenated from its literals and reference paths.
      # Neither needs an evaluator or the daemon, which is why it happens here.
      #
      # $root is PORTABLE_PLANNER_ROOT, empty on a machine attaching its own images and
      # a directory when the assembly is staged elsewhere. It prefixes host state and
      # never a store path.
      assemble =
        file:
        ''
          install -d -m 0755 "$root$(dirname ${lib.escapeShellArg file.staged})"
        ''
        + (
          if file.source != null then
            ''
              [ -e ${lib.escapeShellArg file.source} ] || fail "the source of ${file.path} is not on this machine: ${file.source}"
              cat ${lib.escapeShellArg file.source} > "$root"${lib.escapeShellArg file.staged}
            ''
          else
            ''
              : > "$root"${lib.escapeShellArg file.staged}
            ''
            + concatStringsSep "" (
              map (
                item:
                if item ? text then
                  ''
                    printf '%s' ${lib.escapeShellArg item.text} >> "$root"${lib.escapeShellArg file.staged}
                  ''
                else
                  ''
                    [ -e "$root"${lib.escapeShellArg item.ref} ] || fail "the reference ${item.ref} that ${file.path} is assembled from is not on this machine"
                    cat "$root"${lib.escapeShellArg item.ref} >> "$root"${lib.escapeShellArg file.staged}
                  ''
              ) (if file.render == null then [ ] else file.render)
            )
        )
        + ''
          chmod ${lib.escapeShellArg file.mode} "$root"${lib.escapeShellArg file.staged}
        '';

      # A file rendered over a set with an absent entry has no recipe to assemble, so
      # attaching refuses rather than writing an empty file over what the service reads.
      incomplete = filter (f: !f.computed) image.configFiles;

      preamble = ''
        set -eu
        root="''${PORTABLE_PLANNER_ROOT:-}"

        fail() {
          echo "planner image ${image.name}: $1" >&2
          exit 1
        }
      '';

      guards = ''
        # The target the image was built for, compared before anything starts.
        actualSystem="$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
        [ "$actualSystem" = ${lib.escapeShellArg attachment.target.system} ] || fail \
          "built for system ${attachment.target.system} and this machine is $actualSystem"

        if command -v systemctl > /dev/null 2>&1; then
          actualManager=systemd
        else
          actualManager=unknown
        fi
        [ "$actualManager" = ${lib.escapeShellArg attachment.target.serviceManager} ] || fail \
          "built for service manager ${attachment.target.serviceManager} and this machine runs $actualManager"
      '';

      # Every host path the assembly reads, checked before it writes anything, so a
      # machine that has not generated its secret yet gets a refusal naming the path
      # rather than a directory of half-assembled files.
      references = concatStringsSep "" (
        map (path: ''
          [ -e "$root"${lib.escapeShellArg path} ] || fail "the host file ${path} this entry is assembled from is not on this machine yet"
        '') (map (g: g.path) (filter (g: g.disposition == "reference") attachment.hostPaths))
      );

      attach = pkgs.writeShellScript "${image.name}-attach" (
        preamble
        + guards
        + concatStringsSep "" (
          map (f: ''
            fail "the configuration file ${f.path} of ${image.key} is recorded as not computed, so there is nothing to assemble"
          '') incomplete
        )
        + references
        + ''
          install -d -m 0755 "$root"${lib.escapeShellArg image.staging}
        ''
        + concatStringsSep "" (map assemble (filter (f: f.computed) image.configFiles))
        + ''
          portablectl attach --profile=${lib.escapeShellArg image.profile} ${raw}/${attachment.image}
          systemctl start ${concatStringsSep " " attachment.units}
        ''
      );

      # Detaching removes the units and the directory attaching created and touches
      # nothing it was shown: a generated file and a source store path are the host's.
      detach = pkgs.writeShellScript "${image.name}-detach" (
        preamble
        + ''
          systemctl stop ${concatStringsSep " " attachment.units}
          portablectl detach ${raw}/${attachment.image}
          rm -rf "$root"${lib.escapeShellArg image.staging}
        ''
      );
    in
    pkgs.runCommand "${image.name}-portable-service"
      {
        passthru = {
          inherit
            image
            attachment
            raw
            attach
            detach
            ;
          units = builtins.listToAttrs (
            map (unitName: {
              name = image.units.${unitName}.file;
              value = reader.renderUnit image unitName;
            }) unitNames
          );
        };
      }
      ''
        mkdir -p "$out/bin"
        ln -s ${raw}/${attachment.image} "$out/${attachment.image}"
        ln -s ${description} "$out/attachment.json"
        ln -s ${attach} "$out/bin/attach"
        ln -s ${detach} "$out/bin/detach"
      '';
}
