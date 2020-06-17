defmodule GenRMQ.Mixfile do
  use Mix.Project

  @version "3.0.0"

  def project do
    [
      app: :gen_rmq,
      version: @version,
      elixir: "~> 1.8",
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
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "examples"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.1"},
      {:telemetry, "~> 0.4.1"},
      {:credo, "~> 1.0", only: :dev},
      {:excoveralls, "~> 0.13.0", only: :test},
      {:jason, "~> 1.1", only: [:dev, :test]},
      {:earmark, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.21.0", only: :dev},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false}
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
