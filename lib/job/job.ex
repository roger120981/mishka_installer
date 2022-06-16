defmodule MishkaInstaller.Job do
  @spec start_oban_in_runtime :: {:error, any} | {:ok, pid}
  def start_oban_in_runtime() do
    Application.put_env(:mishka_installer, Oban,
      repo: MishkaInstaller.repo,
      plugins: [Oban.Plugins.Pruner],
      queues: [default: 10]
    )
    Supervisor.start_link(
      [{Oban, Application.fetch_env!(:mishka_installer, Oban)}],
      [strategy: :one_for_one, name: MishkaInstaller.RunTimeObanSupervisor]
    )
  end
end
