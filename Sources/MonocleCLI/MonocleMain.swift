// By Dennis Müller

import ArgumentParser

/// Entry point that forwards execution to the root ArgumentParser command.
@main
enum MonocleMain {
  /// Boots the async monocle command hierarchy.
  static func main() async {
    await MonocleCommand.main()
  }
}
