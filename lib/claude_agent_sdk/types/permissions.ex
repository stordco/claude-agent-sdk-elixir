defmodule ClaudeAgentSdk.Types.Permissions do
  @moduledoc """
  Permission-related type definitions for Claude SDK.

  This module defines types for tool permissions, permission callbacks,
  and permission updates used by the control protocol.

  ## Permission Modes

  - `:default` - CLI prompts for dangerous tools
  - `:accept_edits` - Auto-accept file edits
  - `:plan` - Planning mode
  - `:bypass_permissions` - Allow all tools (use with caution)

  ## Permission Results

  Permission callbacks return either:

  - `PermissionResultAllow` - Allow the tool use, optionally with modified input
  - `PermissionResultDeny` - Deny the tool use with a message

  ## Examples

      # Allow with modified input
      %PermissionResultAllow{
        updated_input: %{"command" => "echo 'sanitized'"},
        updated_permissions: []
      }

      # Deny with message
      %PermissionResultDeny{
        message: "This command is not allowed",
        interrupt: false
      }
  """

  @type permission_mode :: :default | :accept_edits | :plan | :bypass_permissions
  @type permission_behavior :: :allow | :deny | :ask
  @type permission_destination :: :user_settings | :project_settings | :local_settings | :session

  defmodule PermissionRuleValue do
    @moduledoc "Permission rule value."

    @type t :: %__MODULE__{
            tool_name: String.t(),
            rule_content: String.t() | nil
          }

    @enforce_keys [:tool_name]
    defstruct [:tool_name, :rule_content]

    @spec new(String.t(), String.t() | nil) :: t()
    def new(tool_name, rule_content \\ nil) when is_binary(tool_name) do
      %__MODULE__{tool_name: tool_name, rule_content: rule_content}
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{tool_name: name, rule_content: content}) do
      %{"toolName" => name, "ruleContent" => content}
    end
  end

  defmodule PermissionUpdate do
    @moduledoc """
    Permission update configuration.

    Used to update permission rules during a session.
    """

    alias ClaudeAgentSdk.Types.Permissions.PermissionRuleValue

    @type update_type ::
            :add_rules
            | :replace_rules
            | :remove_rules
            | :set_mode
            | :add_directories
            | :remove_directories

    @type t :: %__MODULE__{
            type: update_type(),
            rules: [PermissionRuleValue.t()] | nil,
            behavior: ClaudeAgentSdk.Types.Permissions.permission_behavior() | nil,
            mode: ClaudeAgentSdk.Types.Permissions.permission_mode() | nil,
            directories: [String.t()] | nil,
            destination: ClaudeAgentSdk.Types.Permissions.permission_destination() | nil
          }

    @enforce_keys [:type]
    defstruct [:type, :rules, :behavior, :mode, :directories, :destination]

    @doc "Create a new PermissionUpdate."
    @spec new(update_type(), keyword()) :: t()
    def new(type, opts \\ []) do
      %__MODULE__{
        type: type,
        rules: Keyword.get(opts, :rules),
        behavior: Keyword.get(opts, :behavior),
        mode: Keyword.get(opts, :mode),
        directories: Keyword.get(opts, :directories),
        destination: Keyword.get(opts, :destination)
      }
    end

    @doc "Convert PermissionUpdate to map for control protocol."
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = update) do
      result = %{"type" => type_to_string(update.type)}

      result =
        if update.destination do
          Map.put(result, "destination", destination_to_string(update.destination))
        else
          result
        end

      result =
        case update.type do
          type when type in [:add_rules, :replace_rules, :remove_rules] ->
            result
            |> maybe_put(
              "rules",
              update.rules,
              &Enum.map(&1, fn r -> PermissionRuleValue.to_map(r) end)
            )
            |> maybe_put("behavior", update.behavior, &behavior_to_string/1)

          :set_mode ->
            maybe_put(result, "mode", update.mode, &mode_to_string/1)

          type when type in [:add_directories, :remove_directories] ->
            maybe_put(result, "directories", update.directories, & &1)

          _ ->
            result
        end

      result
    end

    defp maybe_put(map, _key, nil, _transform), do: map
    defp maybe_put(map, key, value, transform), do: Map.put(map, key, transform.(value))

    defp type_to_string(:add_rules), do: "addRules"
    defp type_to_string(:replace_rules), do: "replaceRules"
    defp type_to_string(:remove_rules), do: "removeRules"
    defp type_to_string(:set_mode), do: "setMode"
    defp type_to_string(:add_directories), do: "addDirectories"
    defp type_to_string(:remove_directories), do: "removeDirectories"

    defp destination_to_string(:user_settings), do: "userSettings"
    defp destination_to_string(:project_settings), do: "projectSettings"
    defp destination_to_string(:local_settings), do: "localSettings"
    defp destination_to_string(:session), do: "session"

    defp behavior_to_string(:allow), do: "allow"
    defp behavior_to_string(:deny), do: "deny"
    defp behavior_to_string(:ask), do: "ask"

    defp mode_to_string(:default), do: "default"
    defp mode_to_string(:accept_edits), do: "acceptEdits"
    defp mode_to_string(:plan), do: "plan"
    defp mode_to_string(:bypass_permissions), do: "bypassPermissions"
  end

  defmodule ToolPermissionContext do
    @moduledoc """
    Context information for tool permission callbacks.

    Provides additional context when a permission decision is needed.
    """

    @type t :: %__MODULE__{
            signal: term(),
            suggestions: [PermissionUpdate.t()]
          }

    defstruct signal: nil, suggestions: []

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        signal: Keyword.get(opts, :signal),
        suggestions: Keyword.get(opts, :suggestions, [])
      }
    end
  end

  defmodule PermissionResultAllow do
    @moduledoc """
    Allow permission result.

    Indicates that the tool use is allowed, optionally with
    modified input or updated permissions.
    """

    @type t :: %__MODULE__{
            behavior: :allow,
            updated_input: map() | nil,
            updated_permissions: [PermissionUpdate.t()] | nil
          }

    defstruct behavior: :allow, updated_input: nil, updated_permissions: nil

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        behavior: :allow,
        updated_input: Keyword.get(opts, :updated_input),
        updated_permissions: Keyword.get(opts, :updated_permissions)
      }
    end

    @doc "Convert to map for control protocol response."
    @spec to_response_map(t(), map()) :: map()
    def to_response_map(%__MODULE__{} = result, original_input) do
      response = %{
        "behavior" => "allow",
        "updatedInput" => result.updated_input || original_input
      }

      if result.updated_permissions do
        Map.put(
          response,
          "updatedPermissions",
          Enum.map(result.updated_permissions, &PermissionUpdate.to_map/1)
        )
      else
        response
      end
    end
  end

  defmodule PermissionResultDeny do
    @moduledoc """
    Deny permission result.

    Indicates that the tool use is denied with an optional message.
    """

    @type t :: %__MODULE__{
            behavior: :deny,
            message: String.t(),
            interrupt: boolean()
          }

    defstruct behavior: :deny, message: "", interrupt: false

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        behavior: :deny,
        message: Keyword.get(opts, :message, ""),
        interrupt: Keyword.get(opts, :interrupt, false)
      }
    end

    @doc "Convert to map for control protocol response."
    @spec to_response_map(t()) :: map()
    def to_response_map(%__MODULE__{} = result) do
      response = %{"behavior" => "deny", "message" => result.message}

      if result.interrupt do
        Map.put(response, "interrupt", true)
      else
        response
      end
    end
  end

  @type permission_result :: PermissionResultAllow.t() | PermissionResultDeny.t()

  @type can_use_tool_callback ::
          (String.t(), map(), ToolPermissionContext.t() -> permission_result())
end
