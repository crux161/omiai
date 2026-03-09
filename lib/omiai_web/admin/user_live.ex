defmodule OmiaiWeb.AdminLive.Users do
  use OmiaiWeb, :live_view

  alias Omiai.Accounts
  alias Omiai.Accounts.User

  # ---------------------------------------------------------------------------
  # Mount & Params
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Accounts.list_users())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: "Users", user: nil, form: nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = User.registration_changeset(%User{}, %{})
    assign(socket, page_title: "New User", user: %User{}, form: to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil ->
        socket
        |> put_flash(:error, "User not found")
        |> push_navigate(to: "/admin/users")

      user ->
        changeset = User.profile_changeset(user, %{})
        assign(socket, page_title: "Edit User", user: user, form: to_form(changeset))
    end
  end

  defp apply_action(socket, :reset_password, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil ->
        socket
        |> put_flash(:error, "User not found")
        |> push_navigate(to: "/admin/users")

      user ->
        changeset = User.reset_password_changeset(user, %{})
        assign(socket, page_title: "Reset Password", user: user, form: to_form(changeset))
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      case socket.assigns.live_action do
        :new -> User.registration_changeset(%User{}, params)
        :edit -> User.profile_changeset(socket.assigns.user, params)
        :reset_password -> User.reset_password_changeset(socket.assigns.user, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_user", %{"user" => params}, %{assigns: %{live_action: :new}} = socket) do
    case Accounts.register_user(atomize_keys(params)) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created")
         |> push_navigate(to: "/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save_user", %{"user" => params}, %{assigns: %{live_action: :edit}} = socket) do
    case Accounts.admin_update_user(socket.assigns.user, atomize_keys(params)) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated")
         |> push_navigate(to: "/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save_password", %{"user" => params}, socket) do
    case Accounts.admin_reset_password(socket.assigns.user, atomize_keys(params)) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully")
         |> push_navigate(to: "/admin/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Accounts.get_user(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found")}

      user ->
        {:ok, _} = Accounts.delete_user(user)

        {:noreply,
         socket
         |> put_flash(:info, "User deleted")
         |> assign(users: Accounts.list_users())}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :index -> render_index(assigns)
      :new -> render_form(assigns)
      :edit -> render_form(assigns)
      :reset_password -> render_reset_password(assigns)
    end
  end

  defp render_index(assigns) do
    ~H"""
    <div class="page-header">
      <h1>Users (<%= length(@users) %>)</h1>
      <.link navigate="/admin/users/new" class="btn btn-primary">New User</.link>
    </div>
    <table>
      <thead>
        <tr>
          <th>Quicdial ID</th>
          <th>Display Name</th>
          <th>Avatar</th>
          <th>Created</th>
          <th>Last Login</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= for user <- @users do %>
          <tr>
            <td class="mono"><%= user.quicdial_id %></td>
            <td><%= user.display_name %></td>
            <td><%= user.avatar_id %></td>
            <td class="text-muted"><%= format_datetime(user.inserted_at) %></td>
            <td class="text-muted"><%= format_datetime(user.last_login_at) %></td>
            <td>
              <.link navigate={"/admin/users/#{user.id}/edit"} class="btn btn-secondary">Edit</.link>
              <.link navigate={"/admin/users/#{user.id}/reset-password"} class="btn btn-secondary">Reset PW</.link>
              <button class="btn btn-danger" phx-click="delete" phx-value-id={user.id} data-confirm="Delete this user? This cannot be undone.">Delete</button>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <div class="page-header">
      <h1><%= @page_title %></h1>
    </div>
    <div class="form-card">
      <.form for={@form} phx-change="validate" phx-submit="save_user">
        <%= if @live_action == :new do %>
          <div class="form-group">
            <label>Quicdial ID (leave blank to auto-generate)</label>
            <input type="text" name={@form[:quicdial_id].name} value={@form[:quicdial_id].value} />
            <.field_errors field={@form[:quicdial_id]} />
          </div>
          <div class="form-group">
            <label>Password</label>
            <input type="password" name={@form[:password].name} value={@form[:password].value} />
            <.field_errors field={@form[:password]} />
          </div>
        <% else %>
          <div class="form-group">
            <label>Quicdial ID</label>
            <input type="text" value={@user.quicdial_id} disabled />
          </div>
        <% end %>
        <div class="form-group">
          <label>Display Name</label>
          <input type="text" name={@form[:display_name].name} value={@form[:display_name].value} />
          <.field_errors field={@form[:display_name]} />
        </div>
        <div class="form-group">
          <label>Avatar ID</label>
          <input type="text" name={@form[:avatar_id].name} value={@form[:avatar_id].value} />
          <.field_errors field={@form[:avatar_id]} />
        </div>
        <div style="display:flex;gap:0.5rem;margin-top:1rem;">
          <button type="submit" class="btn btn-primary">Save</button>
          <.link navigate="/admin/users" class="btn btn-secondary">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  defp render_reset_password(assigns) do
    ~H"""
    <div class="page-header">
      <h1>Reset Password — <%= @user.display_name %></h1>
    </div>
    <div class="form-card">
      <p class="text-muted" style="margin-top:0;">Quicdial ID: <span class="mono"><%= @user.quicdial_id %></span></p>
      <.form for={@form} phx-change="validate" phx-submit="save_password">
        <div class="form-group">
          <label>New Password</label>
          <input type="password" name={@form[:password].name} value={@form[:password].value} />
          <.field_errors field={@form[:password]} />
        </div>
        <div style="display:flex;gap:0.5rem;margin-top:1rem;">
          <button type="submit" class="btn btn-primary">Reset Password</button>
          <.link navigate="/admin/users" class="btn btn-secondary">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp field_errors(assigns) do
    ~H"""
    <%= for error <- @field.errors do %>
      <div class="field-error"><%= translate_error(error) %></div>
    <% end %>
    """
  end

  defp translate_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
