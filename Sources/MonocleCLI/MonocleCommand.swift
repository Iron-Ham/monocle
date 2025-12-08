import ArgumentParser

struct MonocleCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "monocle",
      abstract: "Inspect Swift symbols using SourceKit-LSP.",
      subcommands: [
        InspectCommand.self,
        DefinitionCommand.self,
        HoverCommand.self,
        StatusCommand.self,
        ServeCommand.self,
        StopCommand.self,
        VersionCommand.self
      ],
      defaultSubcommand: InspectCommand.self
    )
  }
}
