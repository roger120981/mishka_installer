defmodule MishkaInstaller do
  alias MishkaInstaller.PluginState

  @spec plugin_activity(String.t(), PluginState.t(), String.t(), String.t()) ::
          :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def plugin_activity(action, %PluginState{} = plugin, priority, status \\ "info") do
    MishkaInstaller.Activity.create_activity_by_start_child(%{
      type: "plugin",
      section: "other",
      section_id: nil,
      action: action,
      priority: priority,
      status: status,
      user_id: nil
    },
      Map.from_struct(plugin)
      |> Map.drop([:parent_pid])
    )
  end

  def ip(user_ip), do: is_bitstring(user_ip) && user_ip || Enum.join(Tuple.to_list(user_ip), ".")

  def get_config(item, section \\ :basic) do
    case Application.fetch_env(:mishke_installer_developer, section) do
      :error -> nil
      {:ok, list} -> Keyword.fetch!(list, item)
    end
  end

  def repo() do
    case MishkaInstaller.get_config(:repo) do
      nil -> Ecto.Integration.TestRepo
      value -> value
    end
  end
end
