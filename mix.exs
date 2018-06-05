defmodule GenRMQ.Mixfile do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :gen_rmq,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      description: description(),
      package: package(),
      source_url: "https://github.com/meltwater/gen_rmq",
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/meltwater/gen_rmq"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 0.3.0"},
      {:credo, "~> 0.8", only: :dev},
      {:excoveralls, "~> 0.7", only: :test},
      {:poison, "~> 3.1", only: :test},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.11", only: :dev}
    ]
  end

  defp description() do
    "Set of behaviours meant to be used to create RabbitMQ consumers and publishers."
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Mateusz Korszun"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/meltwater/gen_rmq"}
    ]
  end
end
