import Foundation

// mfprobe — minimal input-acquisition probe for MagicForge.
// `mfprobe --help` lists the modes. `--self-check` needs no hardware and is safe on headless CI.

exit(ProbeCommand.run(arguments: Array(CommandLine.arguments.dropFirst())))
