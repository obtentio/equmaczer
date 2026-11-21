// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Generates the privileged operation without treating paths as shell source.
enum DriverInstallScript {
    static func shellLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    static func install(source: String, directory: String, destination: String, legacy: String) -> String {
        """
        set -eu
        destination=\(shellLiteral(destination))
        /bin/mkdir -p \(shellLiteral(directory))
        stage=$(/usr/bin/mktemp -d \(shellLiteral(directory + "/.equmaczer-stage.XXXXXX")))
        previous=0
        committed=0
        cleanup() {
            result=$?
            trap - EXIT
            if [ "$committed" -eq 0 ] && [ "$previous" -eq 1 ]; then
                if ! /bin/mv "$stage/previous.driver" "$destination"; then
                    /usr/bin/printf 'Restore failed; previous driver retained at %s\\n' "$stage/previous.driver" >&2
                    exit 1
                fi
            fi
            /bin/rm -rf "$stage"
            exit "$result"
        }
        trap cleanup EXIT
        /usr/bin/ditto \(shellLiteral(source)) "$stage/equmaczer.driver"
        /usr/bin/codesign --verify --deep --strict "$stage/equmaczer.driver"
        /usr/sbin/chown -R root:wheel "$stage/equmaczer.driver"
        /bin/chmod -R 755 "$stage/equmaczer.driver"
        if [ -e "$destination" ] || [ -L "$destination" ]; then
            /bin/mv "$destination" "$stage/previous.driver"
            previous=1
        fi
        /bin/mv "$stage/equmaczer.driver" "$destination"
        committed=1
        /bin/rm -rf \(shellLiteral(legacy))
        /usr/bin/killall coreaudiod || true
        """
    }
}
