defmodule MishkaInstaller.MixProject do
  use Mix.Project
  @version "0.0.2"

  def project do
    [
      app: :mishka_installer,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Mishka Installer",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      homepage_url: "https://github.com/mishka-group",
      source_url: "https://github.com/mishka-group/mishka_installer",
      xref: [exclude: [EctoEnum.Use]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MishkaInstaller.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:mishka_developer_tools, "~> 0.0.7"},
      {:jason, "~> 1.3"},
      {:finch, "~> 0.12.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:phoenix_live_view, "~> 0.17.9"},
      {:sourceror, "~> 0.11.1"},
      {:timex, git: "https://github.com/bitwalker/timex", tag: "3.7.8"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager and run time installer for elixir."
  end

  defp package() do
    [
      files: ~w(lib priv .formatter.exs mix.exs LICENSE README*),
      licenses: ["Apache License 2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{"GitHub" => "https://github.com/mishka-group/mishka_installer"}
    ]
  end
end