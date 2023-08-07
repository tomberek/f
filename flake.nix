{
  inputs = {
    nixpkgs.url = "nixpkgs";
  };
  outputs = inputs: let
    proc = set:
    builtins.mapAttrs (
      system: pkgs:
        builtins.mapAttrs (name: func:
          if func == {} then pkgs.${name} else
          pkgs.callPackage func {}) set
    )
    {inherit (inputs.nixpkgs.legacyPackages) x86_64-linux;};
    seed = 0;
  in {
    apps.x86_64-linux.default = {
      type = "app";
      program = with inputs.nixpkgs.legacyPackages.x86_64-linux; "${writeScript "script.sh" ''
        #!/usr/bin/env bash
        cd $(mktemp -d)
        export PATH=${lib.makeBinPath [age gnugrep coreutils]}:$PATH
        set -euo pipefail
        INPUT="$1"
        while read -r line; do
            echo "$line"
            if pub=$(echo -n "$line" | grep -oP ".*Public key: \K\w+" ); then
                pubTrim=$(echo -n "$pub" | tail -c 10)
            else
                continue
            fi
            echo "continue"
            packetnum=0
            while read -r line; do
                sleep 0.2
                echo "sent $packetnum . $line" >&2
                cp ${inputs.self.packages.x86_64-linux.rock} "./rock.$pubTrim.$packetnum.$line"
                { "./rock.$pubTrim.$packetnum.$line" || true ; } 2>/dev/null >/dev/null
                rm "./rock.$pubTrim.$packetnum.$line"
                packetnum=$(( packetnum + 1 ))
            done < <(printf "%s" "$INPUT" | age -r "$pub" -a | tr '/' '%')
        done < <(nix build path://${inputs.self.outPath}#paper -L 2>&1 )
      ''}";
    };
    packages = proc {
      rock = {runCommandCC}: runCommandCC "rock" { } ''
        gcc ${./main.c}
        mv a.out $out
      '';
      paper = {runCommandCC,util-linux, age, gawk}: runCommandCC "paper" {
        buildInputs = [util-linux age gawk];
        __impure =true;
        } ''
        set -euo pipefail
        : ${toString seed}
        key="$(mktemp)"
        age-keygen > "$key"
        pub="$(cat "$key" | age-keygen -y)"
        pub="$(echo -n "$pub" | tail -c 10)"
        for try in {1..10}; do
          if data="$(dmesg --since '30 seconds ago' | grep "rock.$pub" )" && (echo -n "$data" | grep -F "END AGE" >/dev/null); then
            SECRET="$(echo -n "$data" | awk -v pub="$pub" -v key="$key" '
              match($0,"in rock.(" pub ").([0-9]+).([^[]+)",m){
                gsub("%","/",m[3])
                a[m[2]]=m[3]
               }
              END {
                command = "age --decrypt -i " key
                b = 0
                while (a[b] != "-----END AGE ENCRYPTED FILE-----" && b < 100 ) {
                  print("got " a[b]) > "/dev/stderr"
                  print a[b++] |& command
                }
                print a[b] |& command
                close(command,"to")
                while ((command |& getline line) > 0){
                  print line
                }
                close(command)
               }
            ')"
            if [ $? != 0 ]; then exit 2; fi
            if [ -n "$SECRET" ] ; then
              echo "thank you for the secret value '$SECRET', continuing build...." >&2
              break
            fi
          fi
          sleep 1
        done
        touch $out
      '';
    };
  };
}
