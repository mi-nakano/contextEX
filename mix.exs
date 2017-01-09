defmodule ContextEX.Mixfile do
  use Mix.Project

  def project do
    [app: :contextEX,
     version: "0.3.6",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "Context-oriented Programming with Elixir",
     package: [
       maintainers: ["mi-nakano"],
       licenses: ["MIT"],
       links: %{"GitHub" => "https://github.com/mi-nakano/contextEX"}
     ],
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger],
     registered: [ContextEXAgent],
     mod: {ContextEX, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:ex_doc, "~> 0.10", only: :dev}]
  end
end
