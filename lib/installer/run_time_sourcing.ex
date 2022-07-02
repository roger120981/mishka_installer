defmodule MishkaInstaller.Installer.RunTimeSourcing do
  @moduledoc """
  This module is created just for compiling and sourcing, hence if you want to work with Json file and the other compiling dependencies
  please see the `MishkaInstaller.Installer.DepHandler` module.
  """
  use Agent
  @module "run_time_sourcing"

  @type ensure() :: :bad_directory | :load | :no_directory | :sure_all_started
  @type do_runtime() :: :application_ensure | :prepend_compiled_apps
  @type app_name() :: String.t() | atom()

  @spec do_runtime(atom(), atom()) ::
          {:ok, :application_ensure} | {:error, do_runtime(), ensure(), any}
  def do_runtime(app, :add) when is_atom(app) do
    get_build_path()
    |> File.ls!()
    |> Enum.reject(&(&1 == ".DS_Store"))
    |> compare_dependencies()
    |> prepend_compiled_apps()
    |> application_ensure(app, :add)
  end

  def do_runtime(app, :force_update) when is_atom(app) do
    if(Atom.to_string(app) in File.ls!(get_build_path()), do: ["#{app}"], else: false)
    |> prepend_compiled_apps()
    |> application_ensure(app, :force_update)
  end

  def do_runtime(app, :uninstall) when is_atom(app) do
    Application.stop(app)
    Application.unload(app)

    if(Atom.to_string(app) in File.ls!(get_build_path()), do: "#{app}", else: false)
    |> delete_app_dir()
  end

  @spec subscribe :: :ok | {:error, {:already_registered, pid}}
  def subscribe do
    Phoenix.PubSub.subscribe(MishkaInstaller.PubSub, @module)
  end

  @spec compare_dependencies([tuple()], [String.t()]) :: [String.t()]
  def compare_dependencies(installed_apps \\ Application.loaded_applications(), files_list) do
    installed_apps =
      Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)

    Enum.map(files_list, fn app_name ->
      case Map.fetch(installed_apps, app_name) do
        :error ->
          app_name

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil(&1))
  end

  @spec do_deps_compile(String.t() | :cmd | :port) ::
          {:ok, :do_deps_compile, String.t()}
          | {:error, :do_deps_compile, String.t(), [{:operation, String.t()} | {:output, any}]}
  def do_deps_compile(app, type \\ :cmd) do
    with _cd_path <- File.cd(MishkaInstaller.get_config(:project_path)),
         :ok <- exec("deps.get", type, app, :do_deps_compile),
         deps_path <- Path.join(MishkaInstaller.get_config(:project_path), ["deps/", "#{app}"]),
         :ok <- change_dir(deps_path, app),
         :ok <- exec("deps.get", type, app, :do_deps_compile),
         :ok <- exec("deps.compile", type, app, :do_deps_compile),
         :ok <- exec("compile", type, app, :do_deps_compile) do
      {:ok, :do_deps_compile, app}
    end
  after
    # Maybe a developer does not consider changed-path, so for preventing issues we back to the project path after each compiling
    File.cd(MishkaInstaller.get_config(:project_path))
  end

  @spec prepend_compiled_apps(any) ::
          {:ok, :prepend_compiled_apps} | {:error, do_runtime(), ensure(), list}
  def prepend_compiled_apps(false), do: {:error, :prepend_compiled_apps, :no_directory, []}
  def prepend_compiled_apps([]), do: {:error, :prepend_compiled_apps, :no_directory, []}

  def prepend_compiled_apps(files_list) do
    files_list
    |> Enum.map(
      &{String.to_atom(&1),
       Path.join(get_build_path() <> "/" <> &1, "ebin") |> Code.prepend_path()}
    )
    |> Enum.filter(fn {_app, status} -> status == {:error, :bad_directory} end)
    |> case do
      [] -> {:ok, :prepend_compiled_apps}
      list -> {:error, :prepend_compiled_apps, :bad_directory, list}
    end
  end

  @spec get_build_path(atom()) :: binary
  def get_build_path(mode \\ Mix.env()) do
    Path.join(MishkaInstaller.get_config(:project_path), [
      "_build/",
      "#{mode}/",
      "lib"
    ])
  end

  # Ref: https://elixirforum.com/t/how-to-get-vsn-from-app-file/48132/2
  # Ref: https://github.com/elixir-lang/elixir/blob/main/lib/mix/lib/mix/tasks/compile.all.ex#L153-L154
  @spec read_app(binary(), app_name()) :: {:error, atom} | {:ok, binary}
  def read_app(lib_path, sub_app) do
    File.read("#{lib_path}/_build/#{Mix.env()}/lib/#{sub_app}/ebin/#{sub_app}.app")
  end

  @spec consult_app_file(binary) ::
          {:error, {non_neg_integer | {non_neg_integer, pos_integer}, atom, any}}
          | {:ok, any}
          | {:error, {non_neg_integer | {non_neg_integer, pos_integer}, atom, any},
             non_neg_integer | {non_neg_integer, pos_integer}}
  def consult_app_file(bin) do
    # The path could be located in an .ez archive, so we use the prim loader.
    with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(bin)) do
      :erl_parse.parse_term(tokens)
    end
  end

  defp exec(command, type, app, fn_atom, operation \\ "mix")

  defp exec(command, :cmd, app, fn_atom, operation) do
    {stream, status} =
      System.cmd(operation, [command],
        into: IO.stream(),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "#{Mix.env()}"}]
      )

      if status == 0, do: :ok, else: {:error, fn_atom, app, operation: command, output: stream}
  end

  # Ref: https://hexdocs.pm/elixir/Port.html#module-spawn_executable
  # Ref: https://elixirforum.com/t/how-to-send-line-by-line-of-system-cmd-to-liveview-when-a-task-is-running/48336/
  defp exec(command, :port, app, fn_atom, operation) do
    path = System.find_executable("#{operation}")

    port =
      Port.open({:spawn_executable, path}, [
        :binary,
        :exit_status,
        args: [command],
        line: 1000,
        env: [{'MIX_ENV', '#{Mix.env()}'}]
      ])

    start_exec_satet([])
    %{status: status, output: output} = loop(port, command)

    if status == 0, do: :ok, else: {:error, fn_atom, app, operation: command, output: output}
  end

  defp application_ensure({:ok, :prepend_compiled_apps}, app, :add) do
    with {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <-
           {:sure_all_started, Application.ensure_all_started(app)} do
      {:ok, :application_ensure}
    else
      {:load, {:error, term}} ->
        {:error, :application_ensure, :load, term}

      {:sure_all_started, {:error, {app, term}}} ->
        {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end

  defp application_ensure({:ok, :prepend_compiled_apps}, app, :force_update) do
    Application.stop(app)

    with {:unload, :ok} <- {:unload, Application.unload(app)},
         {:load, :ok} <- {:load, Application.load(app)},
         {:sure_all_started, {:ok, _apps}} <-
           {:sure_all_started, Application.ensure_all_started(app)} do
      {:ok, :application_ensure}
    else
      {:unload, {:error, term}} ->
        {:error, :application_ensure, :unload, term}

      {:load, {:error, term}} ->
        {:error, :application_ensure, :load, term}

      {:sure_all_started, {:error, {app, term}}} ->
        {:error, :application_ensure, :sure_all_started, {app, term}}
    end
  end

  defp application_ensure(error, _app, _status), do: error

  defp loop(port, command) do
    receive do
      {^port, {:data, {:eol, msg}}} when is_binary(msg) ->
        update_exec_satet([msg])
        notify_subscribers(msg)
        loop(port, command)

      {^port, {:data, data}} ->
        update_exec_satet([data])
        notify_subscribers(data)
        loop(port, command)

      {^port, {:exit_status, exit_status}} ->
        output = get_exec_state()
        stop_exec_state()
        %{operation: command, output: output, status: exit_status}
    end
  end

  defp start_exec_satet(initial_value),
    do: Agent.start_link(fn -> initial_value end, name: __MODULE__)

  defp update_exec_satet(new_value),
    do: Agent.get_and_update(__MODULE__, fn state -> {state, state ++ new_value} end)

  defp get_exec_state(), do: Agent.get(__MODULE__, & &1)

  defp stop_exec_state(), do: Agent.stop(__MODULE__)

  defp notify_subscribers(answer) do
    Phoenix.PubSub.broadcast(MishkaInstaller.PubSub, @module, {String.to_atom(@module), answer})
  end

  defp delete_app_dir(false), do: {:error, :prepend_compiled_apps, :no_directory, []}

  defp delete_app_dir(dir) do
    Path.join(get_build_path(), ["#{dir}"])
    |> File.rm_rf()
    |> case do
      {:ok, files_and_directories} -> {:ok, :delete_app_dir, files_and_directories}
      {:error, reason, file} -> {:error, :delete_app_dir, reason, file}
    end
  end

  defp change_dir(deps_path, app) do
    with {:error, _posix} <- File.cd(deps_path) do
      {:error, :do_deps_compile, app, operation: "File.cd", output: "Wrong path"}
    end
  end
end
