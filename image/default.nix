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
  # A configuration file whose bytes the plan holds is written here, because the
  # reading realises nothing. The image then shows it from that store path, which
  # its own closure carries, so the attach step assembles nothing for it.
  reader = import ./read.nix {
    inherit planner;
    assemble = name: text: "${pkgs.writeText name text}";
  };

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

      # One shell word, quoted whether or not this value happens to need it.
      # `lib.escapeShellArg`, which every argument below spends, leaves a word
      # of safe-looking characters bare, and a rendering that quotes only what
      # looks dangerous is one a reader cannot check by reading it.
      quoted = value: "'${builtins.replaceStrings [ "'" ] [ "'\\''" ] value}'";

      # What a message says a value is. The double-quoted string the message is
      # written in is closed around the word, because a `$(…)` inside double
      # quotes is a command substitution whatever the quoting within them. A
      # grammar refuses such a value one layer above and this holds
      # independently of it: the escape is what covers a value that reaches a
      # script before its rule does.
      escapedWord = value: "\"${quoted value}\"";

      # The literals and the references of one recipe, concatenated into a file the
      # caller created owner-only. Both the assembly and the staleness check go
      # through this, so the bytes a report compares are the bytes an attach writes.
      appends =
        file: target:
        concatStringsSep "" (
          map (
            item:
            if item ? text then
              ''
                printf '%s' ${lib.escapeShellArg item.text} >> ${target}
              ''
            else
              ''
                [ -e "$root"${lib.escapeShellArg item.ref} ] || fail "the reference ${escapedWord item.ref} that ${escapedWord file.path} is assembled from is not on this machine"
                cat "$root"${lib.escapeShellArg item.ref} >> ${target}
              ''
          ) (if file.render == null then [ ] else file.render)
        );

      # Assembling a configuration file on the host: a source file is copied out of the
      # store, a render list is concatenated from its literals and reference paths.
      # Neither needs an evaluator or the daemon, which is why it happens here.
      #
      # `install -m` is what puts the file where the unit reads it, and it creates its
      # destination owner-only before it writes a byte and chmods to the declared mode
      # after, so the file is never readable by anyone the declaration excludes. A
      # render is concatenated into an owner-only file beside it first, because the
      # declared mode may carry no write bit and appending to a `0444` file is a
      # privilege rather than a right.
      #
      # Creating the file with `: >` and chmod-ing at the end, which is what this did,
      # left a configuration file rendering a secret at the attaching login's umask for
      # the length of the append and at that mode for good if the script stopped there.
      #
      # The candidate is compared against what the machine already holds and installed
      # only where they differ, so a second run of this script writes nothing and the
      # units a file names are reloaded exactly when its bytes moved. The mode is
      # re-applied either way: an unchanged file at a widened mode is still wrong.
      #
      # $root is PORTABLE_PLANNER_ROOT, empty on a machine attaching its own images and
      # a directory when the assembly is staged elsewhere. It prefixes host state and
      # never a store path.
      assemble =
        index: file:
        let
          staged = ''"$root"'' + lib.escapeShellArg file.staged;
          partial = ''"$root"'' + lib.escapeShellArg "${file.staged}.assembling";
          candidate = if file.source != null then lib.escapeShellArg file.source else partial;
        in
        (
          if file.source != null then
            ''
              [ -e ${lib.escapeShellArg file.source} ] || fail "the source of ${escapedWord file.path} is not on this machine: "${quoted file.source}
            ''
          else
            ''
              install -m 0600 /dev/null ${partial}
            ''
            + appends file partial
        )
        + ''
          if [ -e ${staged} ] && cmp -s ${candidate} ${staged}; then
            chmod ${lib.escapeShellArg file.mode} ${staged}
          else
            install -m ${lib.escapeShellArg file.mode} ${candidate} ${staged}
            echo "assembled "${quoted file.path}
            changed=1
            changed_${toString index}=1
          fi
        ''
        + (
          if file.source != null then
            ""
          else
            ''
              rm -f ${partial}
            ''
        );

      # A file rendered over a set with an absent entry has no recipe to assemble, so
      # attaching refuses rather than writing an empty file over what the service reads.
      incomplete = filter (f: !f.computed) image.configFiles;

      # Only a recipe that reads a path on the machine is assembled here. A source
      # file and a recipe of nothing but literals are store objects the image
      # already carries, so staging them would copy a store path to `/run` to bind
      # it back.
      staged = filter (f: f.computed && f.disposition == "reference") image.configFiles;

      # Every directory the staging tree needs, each named rather than left to
      # `install -d` to create along the way: a component install creates for
      # itself is created at the umask and not at the mode, so a mode named for
      # the leaf alone leaves the tree above it listable. The chain starts at
      # the parent of the image's own directory, which holds one directory per
      # attached entry, and stops there: `/run` is the machine's.
      stagingDirectories =
        let
          under =
            file:
            let
              parts = filter (p: p != "") (
                lib.splitString "/" (lib.removePrefix image.staging (builtins.dirOf file.staged))
              );
            in
            lib.genList (i: "${image.staging}/${concatStringsSep "/" (lib.take (i + 1) parts)}") (
              builtins.length parts
            );
        in
        lib.unique (
          [
            (builtins.dirOf image.staging)
            image.staging
          ]
          ++ builtins.concatLists (map under staged)
        );

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
          [ -e "$root"${lib.escapeShellArg path} ] || fail "the host file ${escapedWord path} this entry is assembled from is not on this machine yet"
        '') (map (g: g.path) (filter (g: g.kind == "generated-file") attachment.hostPaths))
      );

      # The unit the replacement question is asked of. Every unit of one entry runs
      # from one image, and a timer has no `RootImage` of its own, so the first
      # service unit answers for the entry.
      firstUnit = image.units.${builtins.head unitNames}.file;

      # One shell function rather than a line per pair: a unit two changed files name
      # is reloaded once, and a unit that is not running is left alone, which is what
      # keeps a reload from starting something an operator stopped.
      reloader = ''
        reloaded=""
        reload_unit() {
          case " $reloaded " in
            *" $1 "*) return 0 ;;
          esac
          systemctl is-active --quiet "$1" || return 0
          systemctl "$2" "$1"
          reloaded="$reloaded $1"
          echo "$3 $1 for $4"
          changed=1
        }
      '';

      reloads = concatStringsSep "" (
        lib.imap0 (
          index: file:
          concatStringsSep "" (
            map (
              unitName:
              let
                unit = image.units.${unitName};
                verb = if unit ? reloadCommand then "try-reload-or-restart" else "try-restart";
                word = if unit ? reloadCommand then "reloaded" else "restarted";
              in
              ''
                if [ -n "''${changed_${toString index}:-}" ]; then
                  reload_unit ${lib.escapeShellArg unit.file} ${verb} ${word} ${lib.escapeShellArg file.path}
                fi
              ''
            ) (if file.reload == null then [ ] else file.reload)
          )
        ) staged
      );

      # The unit list as one escaped word per unit rather than one joined
      # string, so a name carrying a shell metacharacter is a word the command
      # refuses instead of a pattern the shell expands. `echo` joins its
      # arguments with a space, which is what the message below spends.
      unitWords = concatStringsSep " " (map quoted attachment.units);

      attach = pkgs.writeShellScript "${image.name}-attach" (
        preamble
        + guards
        + concatStringsSep "" (
          map (f: ''
            fail "the configuration file ${escapedWord f.path} of ${escapedWord image.key} is recorded as not computed, so there is nothing to assemble"
          '') incomplete
        )
        + references
        + ''
          changed=0
        ''
        + reloader
        + ''
          install -d -m 0711 ${
            concatStringsSep " " (map (d: ''"$root"'' + lib.escapeShellArg d) stagingDirectories)
          }
        ''
        + concatStringsSep "" (lib.imap0 assemble staged)
        + ''
          # Which image this entry runs from, read from the service manager because two
          # builds of one entry render the same unit file names.
          held="$(systemctl show -P RootImage ${lib.escapeShellArg firstUnit} 2> /dev/null || true)"
          if [ -n "$held" ] && [ "$held" != ${raw}/${attachment.image} ]; then
            systemctl stop ${unitWords}
            portablectl detach "$held" > /dev/null
            echo "replaced $held"
            changed=1
          fi

          # Starting is the attachment's own step, so a unit an operator stopped
          # stays stopped and a rerun over a running entry replaces no process.
          # Which units run at all is decided here and never by the reload below.
          if [ "$(portablectl is-attached ${raw}/${attachment.image} 2> /dev/null || echo detached)" = detached ]; then
            portablectl attach --profile=${lib.escapeShellArg image.profile} ${raw}/${attachment.image} > /dev/null
            echo "attached ${attachment.image}"
            systemctl start ${unitWords}
            echo "started "${unitWords}
            changed=1
          fi
        ''
        + reloads
        + ''
          [ "$changed" = 1 ] || echo "nothing changed"
        ''
      );

      # Detaching removes the units and the directory attaching created and touches
      # nothing it was shown: a generated file and a source store path are the host's.
      detach = pkgs.writeShellScript "${image.name}-detach" (
        preamble
        + ''
          systemctl stop ${unitWords}
          portablectl detach ${raw}/${attachment.image}
          rm -rf "$root"${lib.escapeShellArg image.staging}
        ''
      );

      # What the machine holds at each assembled path, against the bytes this build
      # would assemble there. An image's version digest excludes a configuration
      # file's bytes on purpose, so an identity match is evidence about the image
      # and about nothing beside it; this is the other half, and it reads the same
      # recipe the attach step writes, so the two cannot disagree. A reference the
      # machine does not hold yet is `unreadable` rather than a refusal: a report
      # asks and never changes anything.
      check = pkgs.writeShellScript "${image.name}-check" (
        preamble
        + concatStringsSep "" (
          map (
            file:
            let
              stagedPath = ''"$root"'' + lib.escapeShellArg file.staged;
              refs = map (i: i.ref) (filter (i: i ? ref) (if file.render == null then [ ] else file.render));
              present = concatStringsSep " && " (map (ref: ''[ -e "$root"${lib.escapeShellArg ref} ]'') refs);
            in
            ''
              part="$(mktemp)"
              chmod 0600 "$part"
              if ${if refs == [ ] then "true" else present}; then
              ${appends file ''"$part"''}
                if [ -e ${stagedPath} ] && cmp -s "$part" ${stagedPath}; then
                  echo "config ${escapedWord file.path} current"
                else
                  echo "config ${escapedWord file.path} stale"
                fi
              else
                echo "config ${escapedWord file.path} unreadable"
              fi
              rm -f "$part"
            ''
          ) staged
        )
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
            check
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
        ln -s ${check} "$out/bin/check"
      '';
}
