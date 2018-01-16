defmodule GenAmqp.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gen_amqp,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      elixirc_paths: elixirc_paths(Mix.env),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {
              :amqp_client,
              git: "https://github.com/dsrosario/amqp_client.git",
              branch: "erlang_otp_19",
              override: true
            }, # Temporary fix
      {:amqp, "~> 0.1.4"},

      {:credo, "~> 0.8", only: :dev},
      {:excoveralls, "~> 0.7", only: :test},
      {:poison, "~> 3.1", only: :test}
    ]
  end
end
